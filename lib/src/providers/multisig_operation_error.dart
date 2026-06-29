import 'dart:convert';

const _multisigErrorMarker = 'zcash_wallet_multisig_error_v1';

class MultisigOperationException implements Exception {
  const MultisigOperationException({
    required this.kind,
    required this.message,
    required this.rawMessage,
    this.httpStatus,
    this.retryAfterSeconds,
    this.retryable = false,
  });

  final String kind;
  final String message;
  final String rawMessage;
  final int? httpStatus;
  final int? retryAfterSeconds;
  final bool retryable;

  bool get isUnauthorized => kind == 'unauthorized' || httpStatus == 401;
  bool get isConflict => kind == 'conflict' || httpStatus == 409;
  bool get isRateLimited => kind == 'rate_limited' || httpStatus == 429;
  bool get isIdempotencyInProgress =>
      isConflict && multisigErrorLooksIdempotencyInProgress(rawMessage);
  bool get isDuplicateSigningRequestId =>
      isConflict && _lowerRaw.contains('signing_request_id already exists');

  String get _lowerRaw => rawMessage.toLowerCase();

  static MultisigOperationException from(Object error) {
    if (error is MultisigOperationException) return error;
    final raw = multisigRawErrorText(error);
    final structured = _tryParseStructuredError(raw);
    if (structured != null) return structured;
    return _fromRaw(raw);
  }

  @override
  String toString() => message;
}

bool multisigErrorLooksIdempotencyInProgress(Object error) {
  return multisigRawErrorText(
    error,
  ).toLowerCase().contains('idempotency-key request is still in progress');
}

String normalizeMultisigProgressDetail(String detail) {
  if (!multisigErrorLooksIdempotencyInProgress(detail)) return detail;
  return 'Previous request is still being processed. Try again in a moment.';
}

String friendlyMultisigError(Object error) {
  final parsed = MultisigOperationException.from(error);
  final lower = parsed.rawMessage.toLowerCase();

  if (lower.contains('proposal not found') ||
      lower.contains('send flow mismatch')) {
    return 'Transaction expired before the request could be created.';
  }
  if (lower.contains('session is not ready')) {
    return 'This multisig account is not ready for signing requests.';
  }
  if (lower.contains('waiting for round 1')) {
    return 'Waiting for every selected signer to submit Round 1.';
  }
  if (lower.contains('waiting for round 2')) {
    return 'Waiting for every selected signer to submit Round 2.';
  }
  if (lower.contains('local participant is not selected')) {
    return 'This account is not one of the requested signers.';
  }
  if (lower.contains('broadcast status is unknown')) {
    return 'Broadcast status is unknown. Refresh before trying again.';
  }
  if (lower.contains('confirm the local multisig backup')) {
    return 'Confirm the local multisig backup before signing.';
  }

  return switch (parsed.kind) {
    'unauthorized' =>
      'Session expired. The app tried to reconnect; refresh and try again.',
    'forbidden' => 'This account is not allowed to perform that action.',
    'conflict' => 'Coordinator state changed. Refresh and try again.',
    'rate_limited' =>
      parsed.retryAfterSeconds == null
          ? 'Too many requests. Wait a moment and try again.'
          : 'Too many requests. Try again in ${parsed.retryAfterSeconds} seconds.',
    'network' => 'Network connection lost. Progress was saved; try again.',
    'server' => 'Multisig coordinator failed. Progress was saved; try again.',
    _ => parsed.message,
  };
}

String multisigRawErrorText(Object error) {
  var raw = error.toString();
  const prefixes = ['Exception: ', 'StateError: ', 'Invalid argument(s): '];
  var changed = true;
  while (changed) {
    changed = false;
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        raw = raw.substring(prefix.length);
        changed = true;
      }
    }
  }
  return raw;
}

MultisigOperationException? _tryParseStructuredError(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    if (json['marker'] != _multisigErrorMarker) return null;
    final message = json['message']?.toString() ?? raw;
    return MultisigOperationException(
      kind: json['kind']?.toString() ?? 'unknown',
      message: message,
      rawMessage: raw,
      httpStatus: _readInt(json['httpStatus']),
      retryAfterSeconds: _readInt(json['retryAfterSeconds']),
      retryable: json['retryable'] as bool? ?? false,
    );
  } catch (_) {
    return null;
  }
}

MultisigOperationException _fromRaw(String raw) {
  final lower = raw.toLowerCase();
  final httpStatus = _readStatusCode(lower);
  final kind = _kindFromRawStatus(httpStatus, lower);
  return MultisigOperationException(
    kind: kind,
    message: raw,
    rawMessage: raw,
    httpStatus: httpStatus,
    retryable: _rawLooksRetryable(kind),
  );
}

String _kindFromRawStatus(int? httpStatus, String lower) {
  if (httpStatus == 401) return 'unauthorized';
  if (httpStatus == 403) return 'forbidden';
  if (httpStatus == 409) return 'conflict';
  if (httpStatus == 429) return 'rate_limited';
  if (httpStatus != null && httpStatus >= 500 && httpStatus <= 599) {
    return 'server';
  }
  return _classifyRawKind(lower);
}

String _classifyRawKind(String lower) {
  if (lower.contains('unauthorized')) return 'unauthorized';
  if (lower.contains('forbidden')) return 'forbidden';
  if (lower.contains('conflict')) return 'conflict';
  if (lower.contains('rate limit') || lower.contains('too many requests')) {
    return 'rate_limited';
  }
  if (lower.contains('http request failed') ||
      lower.contains('network') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('connection refused') ||
      lower.contains('failed to connect')) {
    return 'network';
  }
  return 'local_invalid_state';
}

bool _rawLooksRetryable(String kind) {
  return kind == 'unauthorized' ||
      kind == 'conflict' ||
      kind == 'rate_limited' ||
      kind == 'network' ||
      kind == 'server';
}

int? _readStatusCode(String lower) {
  final match = RegExp(r'\b(4\d\d|5\d\d)\b').firstMatch(lower);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
