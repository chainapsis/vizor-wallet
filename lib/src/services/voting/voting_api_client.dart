import 'dart:async';
import 'dart:convert';

import 'voting_retry.dart';
import 'voting_http.dart';
import 'voting_models.dart';

/// Minimal REST client for vote-sdk's `/shielded-vote/v1` API surface.
///
/// Chain-facing calls use the configured vote server base URL with optional
/// failover endpoints. Helper-server share calls take an explicit [serverUrl]
/// because foreground submission and recovery may target different helper
/// subsets over time.
class VotingApiClient {
  VotingApiClient({
    required Uri baseUrl,
    required VotingHttpClient httpClient,
    List<Uri> fallbackBaseUrls = const [],
    Duration timeout = const Duration(seconds: 10),
    Duration helperTimeout = const Duration(seconds: 5),
    Duration helperPreflightTimeout = const Duration(seconds: 2),
    Duration helperPreflightTtl = const Duration(seconds: 10),
    VotingRetryPolicy? readRetryPolicy,
    VotingRetryPolicy? helperRetryPolicy,
    VotingRetryPolicy? broadcastRetryPolicy,
    Future<void> Function(Duration delay)? delay,
  }) : _baseUrl = baseUrl,
       _httpClient = httpClient,
       _fallbackBaseUrls = _dedupeBaseUrls(fallbackBaseUrls, baseUrl: baseUrl),
       _timeout = timeout,
       _helperTimeout = helperTimeout,
       _helperPreflightTimeout = helperPreflightTimeout,
       _helperPreflightTtl = helperPreflightTtl,
       _readRetryPolicy =
           readRetryPolicy ??
           VotingRetryPolicy.transientHttp(
             name: 'voting-api-read',
             delays: const [Duration(milliseconds: 300), Duration(seconds: 1)],
           ),
       _helperRetryPolicy =
           helperRetryPolicy ??
           VotingRetryPolicy.transientHttp(
             name: 'voting-api-helper',
             delays: const [
               Duration(milliseconds: 200),
               Duration(milliseconds: 600),
             ],
           ),
       _broadcastRetryPolicy =
           broadcastRetryPolicy ??
           VotingRetryPolicy.transientHttp(
             name: 'voting-api-broadcast',
             delays: const [Duration(seconds: 2), Duration(seconds: 4)],
           ),
       _delay = delay ?? Future<void>.delayed;

  final Uri _baseUrl;
  final List<Uri> _fallbackBaseUrls;
  final VotingHttpClient _httpClient;
  final Duration _timeout;
  final Duration _helperTimeout;
  final Duration _helperPreflightTimeout;
  final Duration _helperPreflightTtl;
  final VotingRetryPolicy _readRetryPolicy;
  final VotingRetryPolicy _helperRetryPolicy;
  final VotingRetryPolicy _broadcastRetryPolicy;
  final Future<void> Function(Duration delay) _delay;
  final Map<String, _CachedHelperPreflight> _helperPreflightCache = {};
  final Map<String, Future<bool>> _helperPreflightInFlight = {};

  /// Lists rounds from the vote server.
  ///
  /// Current vote-sdk returns `{ "rounds": [...] }`. An empty `{}` is accepted
  /// because proto3 JSON omits empty repeated fields.
  Future<List<VotingRoundSummary>> listRounds() async {
    final decoded = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) => _getJson(
        _endpoint(['rounds'], baseUrl: baseUrl),
        retryPolicy: _readRetryPolicy,
      ),
    );
    final object = _objectFromValue(decoded);
    final values = object['rounds'];
    if (values == null) {
      // vote-sdk proto3 JSON omits empty repeated fields, so a chain with no
      // stored rounds returns `{}` rather than `{"rounds":[]}`.
      if (object.isEmpty) return const [];
      throw const FormatException('listRounds expected a rounds field');
    }
    if (values is! List) {
      throw const FormatException('listRounds expected a rounds list');
    }
    return values
        .map(_objectFromValue)
        .map(VotingRoundSummary.fromJson)
        .toList(growable: false);
  }

  /// Fetches the currently active round, returning null when the chain has none.
  Future<VotingRoundStatus?> getActiveRoundStatus() async {
    final response = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) {
        final requestUri = _endpoint(['rounds', 'active'], baseUrl: baseUrl);
        return _runRequestWithRetry(
          retryPolicy: _readRetryPolicy,
          operation: () async {
            final response = await _get(requestUri, timeout: _timeout);
            if (response.statusCode != 404) {
              _throwIfNotSuccess(requestUri, response);
            }
            return response;
          },
        );
      },
    );
    if (response.statusCode == 404) return null;
    final decoded = jsonDecode(response.bodyText);
    final object = _objectFromValue(decoded);
    if (!object.containsKey('round')) {
      throw const FormatException('getActiveRoundStatus expected round field');
    }
    final round = object['round'];
    if (round == null) return null;
    return VotingRoundStatus.fromJson(_objectFromValue(round));
  }

  /// Fetches one round and unwraps the ZODL-style `{ "round": ... }` envelope.
  Future<VotingRoundStatus> getRoundStatus(String roundId) async {
    final normalizedRoundId = normalizeVotingRoundId(roundId);
    final decoded = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) => _getJson(
        _endpoint(['round', normalizedRoundId], baseUrl: baseUrl),
        retryPolicy: _readRetryPolicy,
      ),
    );
    final status = VotingRoundStatus.fromJson(
      _requiredNestedObject(decoded, 'round'),
    );
    _requireMatchingRoundId(
      actual: status.roundId,
      expected: normalizedRoundId,
      context: 'getRoundStatus',
    );
    return status;
  }

  Future<VotingRoundTally> getRoundTally(String roundId) async {
    final normalizedRoundId = normalizeVotingRoundId(roundId);
    final decoded = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) => _getJson(
        _endpoint(['tally-results', normalizedRoundId], baseUrl: baseUrl),
        retryPolicy: _readRetryPolicy,
      ),
    );
    final object = _objectFromValue(decoded);
    _validateTallyResultsEnvelope(object, expectedRoundId: normalizedRoundId);
    return VotingRoundTally.fromJson(
      object,
      fallbackRoundId: normalizedRoundId,
    );
  }

  Future<VotingRoundTally> getProposalTally(
    String roundId,
    int proposalId,
  ) async {
    final normalizedRoundId = normalizeVotingRoundId(roundId);
    final decoded = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) => _getJson(
        _endpoint([
          'tally',
          normalizedRoundId,
          proposalId.toString(),
        ], baseUrl: baseUrl),
        retryPolicy: _readRetryPolicy,
      ),
    );
    final tally = VotingRoundTally.fromJson(
      _objectFromValue(decoded),
      fallbackRoundId: normalizedRoundId,
    );
    _requireMatchingRoundId(
      actual: tally.roundId,
      expected: normalizedRoundId,
      context: 'getProposalTally',
    );
    return tally;
  }

  /// Broadcasts a delegation transaction to the vote chain.
  ///
  /// Deterministic vote-chain rejections are returned as [VotingTxResult] when
  /// the service responds with HTTP 422. Transient gateway or network failures
  /// are retried according to [_broadcastRetryPolicy].
  Future<VotingTxResult> submitDelegation({
    required Map<String, dynamic> submission,
  }) async {
    final decoded = await _withVoteServerFailover(
      policy: _broadcastRetryPolicy,
      operation: (baseUrl) => _postJson(
        _endpoint(['delegate-vote'], baseUrl: baseUrl),
        submission,
        allowStatusCodes: const {422},
        retryPolicy: _broadcastRetryPolicy,
      ),
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  /// Broadcasts a vote commitment transaction to the vote chain.
  ///
  /// Deterministic vote-chain rejections are returned as [VotingTxResult] when
  /// the service responds with HTTP 422. Transient gateway or network failures
  /// are retried according to [_broadcastRetryPolicy].
  Future<VotingTxResult> submitVoteCommitment({
    required Map<String, dynamic> commitment,
  }) async {
    final decoded = await _withVoteServerFailover(
      policy: _broadcastRetryPolicy,
      operation: (baseUrl) => _postJson(
        _endpoint(['cast-vote'], baseUrl: baseUrl),
        commitment,
        allowStatusCodes: const {422},
        retryPolicy: _broadcastRetryPolicy,
      ),
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  Future<VotingTxConfirmation?> getTxConfirmation(String txHash) async {
    final response = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) async {
        final requestUri = _endpoint(['tx', txHash], baseUrl: baseUrl);
        // Confirmation polling retries the complete lookup. Trying each server
        // once per pass keeps one offline fallback from consuming the request
        // timeout repeatedly before the next server gets a chance to answer.
        final response = await _get(requestUri, timeout: _timeout);
        if (response.statusCode != 404 && response.statusCode != 422) {
          _throwIfNotSuccess(requestUri, response);
        }
        return response;
      },
      shouldTryNextCandidate: (response) => response.statusCode == 404,
    );
    if (response.statusCode == 404) return null;
    return VotingTxConfirmation.fromJson(
      _objectFromValue(jsonDecode(response.bodyText)),
    );
  }

  /// Checks helper readiness concurrently without failing the voting flow.
  ///
  /// A helper is ready only when its public status endpoint returns a
  /// successful `{"status":"ok"}` response. Results are cached briefly so
  /// concurrent share batches do not repeatedly probe the same helpers.
  Future<Map<String, bool>> preflightHelpers(Iterable<Uri> serverUrls) async {
    final uniqueServers = <String, Uri>{};
    for (final serverUrl in serverUrls) {
      uniqueServers.putIfAbsent(serverUrl.toString(), () => serverUrl);
    }
    final entries = await Future.wait([
      for (final entry in uniqueServers.entries)
        _preflightHelper(
          entry.key,
          entry.value,
        ).then((isReady) => MapEntry(entry.key, isReady)),
    ]);
    return Map<String, bool>.unmodifiable(Map.fromEntries(entries));
  }

  /// Posts one encrypted share directly to a helper server.
  ///
  /// The share map is expected to be the complete service JSON body produced
  /// by the voting pipeline. Fast transient failures retain the helper retry
  /// policy, but every attempt and backoff shares one [_helperTimeout] budget.
  /// An ambiguous timeout is never retried against the same helper so the
  /// caller can promptly move to another candidate.
  Future<VotingShareSubmissionResult> submitShare({
    required Uri serverUrl,
    required Map<String, dynamic> share,
  }) async {
    final decoded = await _postInitialShareJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      share,
    );
    return VotingShareSubmissionResult.fromJson(_objectFromValue(decoded));
  }

  /// Checks whether a helper has confirmed a share identified by its nullifier.
  ///
  /// [isCancelled] is checked before each retry so lifecycle-owned polling can
  /// stop without starting another request.
  Future<VotingShareStatus> getShareStatus({
    required String roundId,
    required Uri serverUrl,
    required String shareId,
    bool Function()? isCancelled,
  }) async {
    final decoded = await _getJson(
      _endpoint([
        'share-status',
        normalizeVotingRoundId(roundId),
        shareId,
      ], baseUrl: serverUrl),
      timeout: _helperTimeout,
      retryPolicy: _helperRetryPolicy,
      isCancelled: isCancelled,
    );
    return VotingShareStatus.fromJson(_objectFromValue(decoded));
  }

  /// Resends a previously generated share to a specific helper server.
  ///
  /// [shareId] is retained in the signature so call sites can keep the recovery
  /// key nearby, but the current helper endpoint accepts the same body as the
  /// initial submission. This makes one transport attempt because a timeout is
  /// ambiguous; the caller decides whether to try another helper or wait.
  Future<VotingShareSubmissionResult> resubmitShare({
    required Uri serverUrl,
    required String shareId,
    required Map<String, dynamic> share,
  }) async {
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      share,
      timeout: _helperTimeout,
    );
    return VotingShareSubmissionResult.fromJson(_objectFromValue(decoded));
  }

  Uri _endpoint(
    List<String> pathSegments, {
    Map<String, String>? queryParameters,
    Uri? baseUrl,
  }) {
    final base = baseUrl ?? _baseUrl;
    final baseSegments = base.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    return base.replace(
      pathSegments: [...baseSegments, 'shielded-vote', 'v1', ...pathSegments],
      queryParameters: queryParameters,
    );
  }

  Future<Object?> _getJson(
    Uri uri, {
    Duration? timeout,
    VotingRetryPolicy? retryPolicy,
    bool Function()? isCancelled,
  }) async {
    final response = await _runRequestWithRetry(
      retryPolicy: retryPolicy,
      isCancelled: isCancelled,
      operation: () async {
        final response = await _get(uri, timeout: timeout ?? _timeout);
        _throwIfNotSuccess(uri, response);
        return response;
      },
    );
    return jsonDecode(response.bodyText);
  }

  Future<Object?> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Set<int> allowStatusCodes = const {},
    Duration? timeout,
    VotingRetryPolicy? retryPolicy,
  }) async {
    final response = await _runRequestWithRetry(
      retryPolicy: retryPolicy,
      operation: () async {
        final response = await _post(uri, body, timeout: timeout ?? _timeout);
        _throwIfNotSuccess(uri, response, allowStatusCodes: allowStatusCodes);
        return response;
      },
    );
    return jsonDecode(response.bodyText);
  }

  Future<bool> _preflightHelper(String key, Uri serverUrl) async {
    final current = DateTime.now();
    final cached = _helperPreflightCache[key];
    if (cached != null && current.isBefore(cached.expiresAt)) {
      return cached.isReady;
    }

    final existing = _helperPreflightInFlight[key];
    if (existing != null) return existing;

    final probe = _probeHelper(serverUrl);
    _helperPreflightInFlight[key] = probe;
    try {
      final isReady = await probe;
      _helperPreflightCache[key] = _CachedHelperPreflight(
        isReady: isReady,
        expiresAt: DateTime.now().add(_helperPreflightTtl),
      );
      return isReady;
    } finally {
      if (identical(_helperPreflightInFlight[key], probe)) {
        _helperPreflightInFlight.remove(key);
      }
    }
  }

  Future<bool> _probeHelper(Uri serverUrl) async {
    final uri = _endpoint(['status'], baseUrl: serverUrl);
    try {
      final response = await _get(
        uri,
        timeout: _helperPreflightTimeout,
      ).timeout(_helperPreflightTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final status = _objectFromValue(jsonDecode(response.bodyText))['status'];
      return status?.toString().trim().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Object?> _postInitialShareJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final budget = Stopwatch()..start();
    Object? lastError;
    StackTrace? lastStackTrace;
    for (
      var attempt = 0;
      attempt <= _helperRetryPolicy.delays.length;
      attempt++
    ) {
      final remaining = attempt == 0
          ? _helperTimeout
          : _helperTimeout - budget.elapsed;
      if (remaining <= Duration.zero) {
        if (lastError != null && lastStackTrace != null) {
          Error.throwWithStackTrace(lastError, lastStackTrace);
        }
        throw TimeoutException(
          'Helper submission budget exhausted for $uri',
          _helperTimeout,
        );
      }
      try {
        final response = await _post(
          uri,
          body,
          timeout: remaining,
        ).timeout(remaining);
        _throwIfNotSuccess(uri, response);
        return jsonDecode(response.bodyText);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (error is TimeoutException ||
            attempt == _helperRetryPolicy.delays.length ||
            !_helperRetryPolicy.shouldRetry(error)) {
          rethrow;
        }
        final retryDelay = _helperRetryPolicy.delays[attempt];
        final remainingAfterAttempt = _helperTimeout - budget.elapsed;
        if (remainingAfterAttempt <= retryDelay) rethrow;
        await _delay(retryDelay).timeout(remainingAfterAttempt);
      }
    }
    throw StateError(
      '${_helperRetryPolicy.name} retry exited unexpectedly: $lastError',
    );
  }

  Future<VotingHttpResponse> _get(Uri uri, {required Duration timeout}) {
    return _httpClient.get(uri, timeout: timeout);
  }

  Future<VotingHttpResponse> _post(
    Uri uri,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) {
    return _httpClient.postJson(uri, body, timeout: timeout);
  }

  Future<T> _runRequestWithRetry<T>({
    required Future<T> Function() operation,
    VotingRetryPolicy? retryPolicy,
    bool Function()? isCancelled,
  }) {
    if (retryPolicy == null) {
      return operation();
    }
    return withVotingRetry(
      policy: retryPolicy,
      operation: operation,
      delay: _delay,
      isCancelled: isCancelled,
    );
  }

  Future<T> _withVoteServerFailover<T>({
    required VotingRetryPolicy policy,
    required Future<T> Function(Uri baseUrl) operation,
    bool Function(T result)? shouldTryNextCandidate,
  }) async {
    final candidates = [_baseUrl, ..._fallbackBaseUrls];
    Object? lastError;
    late T fallbackResult;
    var hasFallbackResult = false;
    for (var attempt = 0; attempt < candidates.length; attempt++) {
      final baseUrl = candidates[attempt];
      try {
        final result = await operation(baseUrl);
        if (attempt < candidates.length - 1 &&
            (shouldTryNextCandidate?.call(result) ?? false)) {
          fallbackResult = result;
          hasFallbackResult = true;
          continue;
        }
        return result;
      } catch (error) {
        lastError = error;
        final retryable = policy.shouldRetry(error);
        if (attempt == candidates.length - 1 || !retryable) {
          if (hasFallbackResult && retryable) {
            return fallbackResult;
          }
          rethrow;
        }
      }
    }
    throw StateError('vote-server failover exited unexpectedly: $lastError');
  }

  static void _throwIfNotSuccess(
    Uri uri,
    VotingHttpResponse response, {
    Set<int> allowStatusCodes = const {},
  }) {
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        !allowStatusCodes.contains(response.statusCode)) {
      throw VotingHttpException(
        uri: uri,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
  }

  static List<Uri> _dedupeBaseUrls(
    List<Uri> fallbackBaseUrls, {
    required Uri baseUrl,
  }) {
    final keys = <String>{baseUrl.toString()};
    final deduped = <Uri>[];
    for (final uri in fallbackBaseUrls) {
      if (keys.add(uri.toString())) {
        deduped.add(uri);
      }
    }
    return List<Uri>.unmodifiable(deduped);
  }
}

class _CachedHelperPreflight {
  const _CachedHelperPreflight({
    required this.isReady,
    required this.expiresAt,
  });

  final bool isReady;
  final DateTime expiresAt;
}

Map<String, dynamic> _objectFromValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

Map<String, dynamic> _requiredNestedObject(Object? value, String key) {
  final object = _objectFromValue(value);
  final nested = object[key];
  if (nested == null) {
    throw FormatException('Expected $key field');
  }
  return _objectFromValue(nested);
}

void _validateTallyResultsEnvelope(
  Map<String, dynamic> object, {
  required String expectedRoundId,
}) {
  final envelopeRoundId = VotingRoundTally.fromJson(object).roundId;
  if (envelopeRoundId.isNotEmpty) {
    _requireMatchingRoundId(
      actual: envelopeRoundId,
      expected: expectedRoundId,
      context: 'getRoundTally',
    );
  }

  final results = object['results'];
  if (results == null) {
    if (object.isEmpty || _isPendingTallyEnvelope(object)) return;
    throw const FormatException('getRoundTally expected results field');
  }
  if (results is! List) {
    throw const FormatException('getRoundTally expected results list');
  }
  for (final value in results) {
    final result = _objectFromValue(value);
    final roundId = VotingRoundTally.fromJson(result).roundId;
    if (roundId.isEmpty) continue;
    _requireMatchingRoundId(
      actual: roundId,
      expected: expectedRoundId,
      context: 'getRoundTally',
    );
  }
}

bool _isPendingTallyEnvelope(Map<String, dynamic> object) {
  final status = (object['status'] ?? object['phase'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return status == '2' || status == 'tallying' || status == 'pending';
}

void _requireMatchingRoundId({
  required String actual,
  required String expected,
  required String context,
}) {
  if (actual != expected) {
    throw FormatException('$context response round id mismatch');
  }
}
