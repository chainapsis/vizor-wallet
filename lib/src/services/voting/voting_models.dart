import 'dart:convert';

import '../../core/formatting/hex_codec.dart';

/// Result returned by chain-facing submit endpoints.
///
/// A 2xx or accepted deterministic rejection can both carry this shape. Callers
/// must check [code] before treating [txHash] as a submitted transaction.
class VotingTxResult {
  final String txHash;
  final int code;
  final String log;

  const VotingTxResult({
    required this.txHash,
    required this.code,
    required this.log,
  });

  factory VotingTxResult.fromJson(Map<String, dynamic> json) {
    final code = _intFromJson(json, const ['code']);
    final txHash = _optionalStringFromJson(json, const ['tx_hash']) ?? '';
    if (code == 0 && txHash.trim().isEmpty) {
      throw const FormatException('Missing required string: tx_hash');
    }
    return VotingTxResult(
      txHash: txHash,
      code: code,
      log: _optionalStringFromJson(json, const ['log']) ?? '',
    );
  }
}

/// Confirmation query result for a submitted voting transaction.
class VotingTxConfirmation {
  final int height;
  final int code;
  final String log;
  final List<Map<String, dynamic>> events;

  const VotingTxConfirmation({
    required this.height,
    required this.code,
    required this.log,
    required this.events,
  });

  factory VotingTxConfirmation.fromJson(Map<String, dynamic> json) {
    return VotingTxConfirmation(
      height: _intFromJson(json, const ['height']),
      code: _intFromJson(json, const ['code']),
      log: _optionalStringFromJson(json, const ['log']) ?? '',
      events: _optionalListFromJson(json, const [
        'events',
      ]).map(_objectFromValue).map(_txEventJsonFromApi).toList(growable: false),
    );
  }

  String get eventsJson => jsonEncode(events);
}

// Validate tx-event fields once and keep only the wire keys Rust consumes.
Map<String, dynamic> _txEventJsonFromApi(Map<String, dynamic> event) {
  return <String, dynamic>{
    'type': _stringFromJson(event, const ['type']),
    'attributes': _optionalListFromJson(event, const ['attributes'])
        .map(_objectFromValue)
        .map(_txEventAttributeJsonFromApi)
        .toList(growable: false),
  };
}

Map<String, dynamic> _txEventAttributeJsonFromApi(
  Map<String, dynamic> attribute,
) {
  return <String, dynamic>{
    'key': _stringFromJson(attribute, const ['key']),
    'value': _stringFromJson(attribute, const ['value']),
  };
}

/// Lightweight round summary returned by list endpoints.
///
/// The raw object is kept so later provider/UI work can use newly added service
/// fields without forcing this low-level client model to change first.
class VotingRoundSummary {
  final String roundId;
  final String title;
  final String status;
  final Map<String, dynamic> rawJson;

  const VotingRoundSummary({
    required this.roundId,
    required this.title,
    required this.status,
    required this.rawJson,
  });

  factory VotingRoundSummary.fromJson(Map<String, dynamic> json) {
    return VotingRoundSummary(
      roundId: _roundIdFromJson(json),
      title: _optionalStringFromJson(json, const ['title']) ?? '',
      status: _optionalStringFromJson(json, const ['status']) ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Current service-side status for a single round.
class VotingRoundStatus {
  final String roundId;
  final String status;
  final Map<String, dynamic> rawJson;

  const VotingRoundStatus({
    required this.roundId,
    required this.status,
    required this.rawJson,
  });

  factory VotingRoundStatus.fromJson(Map<String, dynamic> json) {
    return VotingRoundStatus(
      roundId: _roundIdFromJson(json),
      status: _stringFromJson(json, const ['status']),
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Raw tally payload for a finalized or tallying round.
class VotingRoundTally {
  final String roundId;
  final Map<String, dynamic> rawJson;

  const VotingRoundTally({required this.roundId, required this.rawJson});

  factory VotingRoundTally.fromJson(
    Map<String, dynamic> json, {
    String? fallbackRoundId,
  }) {
    return VotingRoundTally(
      roundId: _optionalRoundIdFromJson(json) ?? fallbackRoundId ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Response from a helper-server share submission.
class VotingShareSubmissionResult {
  static const _acceptedStatuses = {'queued', 'duplicate'};

  final String status;
  final Map<String, dynamic> rawJson;

  const VotingShareSubmissionResult({
    required this.status,
    required this.rawJson,
  });

  factory VotingShareSubmissionResult.fromJson(Map<String, dynamic> json) {
    final status = _stringFromJson(json, const ['status']);
    if (!_acceptedStatuses.contains(status)) {
      throw FormatException('Unexpected helper share submit status: $status');
    }
    return VotingShareSubmissionResult(
      status: status,
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Confirmation status for one helper-server share.
class VotingShareStatus {
  static const _acceptedStatuses = {'pending', 'confirmed'};

  final String status;
  final Map<String, dynamic> rawJson;

  const VotingShareStatus({required this.status, required this.rawJson});

  factory VotingShareStatus.fromJson(Map<String, dynamic> json) {
    final status = _stringFromJson(json, const ['status']);
    if (!_acceptedStatuses.contains(status)) {
      throw FormatException('Unexpected helper share status: $status');
    }
    return VotingShareStatus(status: status, rawJson: Map.unmodifiable(json));
  }
}

/// Normalizes a vote round id to the lowercase hex form used in service routes.
///
/// Accepts either 64 hex characters or a 32-byte base64 string. Throws a
/// [FormatException] when the input is not one of those encodings.
String normalizeVotingRoundId(String value) => _normalizeRoundId(value);

/// HTTP status error that preserves the response body for diagnostics.
class VotingHttpException implements Exception {
  final Uri uri;
  final int statusCode;
  final String body;

  const VotingHttpException({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() => 'VotingHttpException($statusCode $uri): $body';
}

Map<String, dynamic> decodeVotingJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

String _stringFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalStringFromJson(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required string: ${keys.first}');
  }
  return value;
}

String? _optionalStringFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    return value.toString();
  }
  return null;
}

String _roundIdFromJson(Map<String, dynamic> json) {
  final value = _optionalRoundIdFromJson(json);
  if (value == null || value.isEmpty) {
    throw const FormatException('Missing required string: vote_round_id');
  }
  return value;
}

String? _optionalRoundIdFromJson(Map<String, dynamic> json) {
  final value = _optionalStringFromJson(json, const ['vote_round_id']);
  final raw = value?.trim();
  return raw == null || raw.isEmpty ? null : _normalizeRoundId(raw);
}

String _normalizeRoundId(String value) {
  final trimmed = value.trim();
  if (_isHexRoundId(trimmed)) return trimmed.toLowerCase();
  try {
    final bytes = base64Decode(trimmed);
    if (bytes.length == 32) return bytesToHex(bytes);
  } on FormatException {
    // Fall through to a field-specific error below.
  }
  throw const FormatException(
    'Invalid vote_round_id: expected 64 hex chars or 32-byte base64',
  );
}

int _intFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalIntFromJson(json, keys);
  if (value == null) {
    throw FormatException('Missing required int: ${keys.first}');
  }
  return value;
}

int? _optionalIntFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      throw FormatException('$key must be an integer');
    }
    return int.parse(value.toString());
  }
  return null;
}

List<Object?> _optionalListFromJson(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is List) return value;
    throw FormatException('Expected list: $key');
  }
  return const [];
}

Map<String, dynamic> _objectFromValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

bool _isHexRoundId(String value) {
  if (value.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
}
