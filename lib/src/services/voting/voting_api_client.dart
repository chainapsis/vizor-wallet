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
    Duration helperPostTimeout = const Duration(seconds: 30),
    VotingRetryPolicy? readRetryPolicy,
    VotingRetryPolicy? helperRetryPolicy,
    VotingRetryPolicy? broadcastRetryPolicy,
    Future<void> Function(Duration delay)? delay,
  }) : _baseUrl = baseUrl,
       _httpClient = httpClient,
       _fallbackBaseUrls = _dedupeBaseUrls(fallbackBaseUrls, baseUrl: baseUrl),
       _timeout = timeout,
       _helperTimeout = helperTimeout,
       _helperPostTimeout = helperPostTimeout,
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
  final Duration _helperPostTimeout;
  final VotingRetryPolicy _readRetryPolicy;
  final VotingRetryPolicy _helperRetryPolicy;
  final VotingRetryPolicy _broadcastRetryPolicy;
  final Future<void> Function(Duration delay) _delay;

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
    final VotingHttpResponse response;
    try {
      response = await _withVoteServerFailover(
        policy: _readRetryPolicy,
        operation: (baseUrl) async {
          final requestUri = _endpoint(['tx', txHash], baseUrl: baseUrl);
          // Confirmation polling retries the complete lookup. Trying each
          // server once per pass keeps one offline fallback from consuming the
          // request timeout repeatedly before the next server gets a chance.
          final response = await _get(requestUri, timeout: _timeout);
          if (response.statusCode != 404 && response.statusCode != 422) {
            _throwIfNotSuccess(requestUri, response);
          }
          return response;
        },
        shouldTryNextCandidate: (response) => response.statusCode == 404,
      );
    } catch (error) {
      if (_readRetryPolicy.shouldRetry(error)) return null;
      rethrow;
    }
    if (response.statusCode == 404) return null;
    return VotingTxConfirmation.fromJson(
      _objectFromValue(jsonDecode(response.bodyText)),
    );
  }

  /// Ranks ready helpers using the shared progressive timeout policy.
  ///
  /// All probes start together. The first decision happens after [softTimeout];
  /// if fewer than [readyTargetCount] helpers are ready, slower responses keep
  /// racing until enough arrive or [hardTimeout] expires. A helper is ready only
  /// when its public status endpoint returns `{"status":"ok"}` successfully.
  /// Completing [cancelSignal] stops the wait and returns the responses already
  /// collected so callers can abandon the preflight promptly.
  Future<VotingHelperPreflightResult> preflightHelpers(
    Iterable<Uri> serverUrls, {
    required int readyTargetCount,
    required Duration softTimeout,
    required Duration hardTimeout,
    Future<void>? cancelSignal,
  }) async {
    if (softTimeout.isNegative || hardTimeout <= softTimeout) {
      throw ArgumentError(
        'helper preflight requires 0 <= softTimeout < hardTimeout',
      );
    }

    final seen = <String>{};
    final servers = [
      for (final serverUrl in serverUrls)
        if (seen.add(serverUrl.toString())) serverUrl,
    ];
    if (servers.isEmpty) {
      return VotingHelperPreflightResult(
        rankedServerUrls: const [],
        readiness: const {},
      );
    }

    final targetCount = readyTargetCount.clamp(1, servers.length).toInt();
    final readyServers = <String>[];
    var completedServerCount = 0;
    var acceptingResults = true;
    final targetOrAllCompleted = Completer<void>();
    for (final serverUrl in servers) {
      unawaited(
        _probeHelper(serverUrl, timeout: hardTimeout).then((isReady) {
          if (!acceptingResults) return;
          completedServerCount++;
          if (isReady) readyServers.add(serverUrl.toString());
          if (!targetOrAllCompleted.isCompleted &&
              (readyServers.length >= targetCount ||
                  completedServerCount == servers.length)) {
            targetOrAllCompleted.complete();
          }
        }),
      );
    }

    final softDeadline = Completer<void>();
    final softTimer = Timer(softTimeout, softDeadline.complete);
    late final bool cancelledDuringSoftWait;
    try {
      cancelledDuringSoftWait = await Future.any([
        softDeadline.future.then((_) => false),
        if (cancelSignal != null) cancelSignal.then((_) => true),
      ]);
    } finally {
      softTimer.cancel();
    }
    if (cancelledDuringSoftWait) {
      acceptingResults = false;
      return _helperPreflightResult(servers, readyServers);
    }

    if (readyServers.length < targetCount &&
        completedServerCount < servers.length) {
      final hardDeadline = Completer<void>();
      final remainingTimeout = hardTimeout - softTimeout;
      final hardTimer = Timer(remainingTimeout, hardDeadline.complete);
      try {
        await Future.any([
          targetOrAllCompleted.future,
          hardDeadline.future,
          ?cancelSignal,
        ]);
      } finally {
        hardTimer.cancel();
      }
    }

    acceptingResults = false;
    return _helperPreflightResult(servers, readyServers);
  }

  /// Posts one encrypted share directly to a helper server.
  ///
  /// The share map is expected to be the complete service JSON body produced
  /// by the voting pipeline. Fast transient failures retain the helper retry
  /// policy. An ambiguous timeout is never retried against the same helper so
  /// the caller can promptly move to another candidate. [timeout] bounds each
  /// transport attempt; [overallTimeout] also bounds retries and their delays.
  Future<VotingShareSubmissionResult> submitShare({
    required Uri serverUrl,
    required Map<String, dynamic> share,
    Duration? timeout,
    Duration? overallTimeout,
  }) async {
    final decoded = await _postInitialShareJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      share,
      timeout: timeout,
      overallTimeout: overallTimeout,
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
  /// [timeout] overrides the default helper POST timeout.
  Future<VotingShareSubmissionResult> resubmitShare({
    required Uri serverUrl,
    required String shareId,
    required Map<String, dynamic> share,
    Duration? timeout,
  }) async {
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      share,
      timeout: timeout ?? _helperPostTimeout,
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

  Future<bool> _probeHelper(Uri serverUrl, {required Duration timeout}) async {
    final uri = _endpoint(['status'], baseUrl: serverUrl);
    try {
      final response = await _get(uri, timeout: timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final status = _objectFromValue(jsonDecode(response.bodyText))['status'];
      return status?.toString().trim().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Object?> _postInitialShareJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
    Duration? overallTimeout,
  }) async {
    final requestTimeout = timeout ?? _helperPostTimeout;
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'timeout', 'must be positive');
    }
    if (overallTimeout != null && overallTimeout <= Duration.zero) {
      throw ArgumentError.value(
        overallTimeout,
        'overallTimeout',
        'must be positive',
      );
    }
    final stopwatch = Stopwatch()..start();
    var budgetExpired = false;
    final retryPolicy = VotingRetryPolicy(
      name: '${_helperRetryPolicy.name}-initial',
      delays: _helperRetryPolicy.delays,
      shouldRetry: (error) =>
          error is! TimeoutException && _helperRetryPolicy.shouldRetry(error),
    );
    final request = _runRequestWithRetry(
      retryPolicy: retryPolicy,
      isCancelled: () => budgetExpired,
      operation: () async {
        var attemptTimeout = requestTimeout;
        if (overallTimeout != null) {
          final remaining = overallTimeout - stopwatch.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException(
              'Initial helper delivery attempt exceeded its overall timeout',
              overallTimeout,
            );
          }
          if (remaining < attemptTimeout) attemptTimeout = remaining;
        }
        final response = await _post(
          uri,
          body,
          timeout: attemptTimeout,
        ).timeout(attemptTimeout);
        _throwIfNotSuccess(uri, response);
        return response;
      },
    );
    final response = overallTimeout == null
        ? await request
        : await request.timeout(
            overallTimeout,
            onTimeout: () {
              budgetExpired = true;
              throw TimeoutException(
                'Initial helper delivery attempt exceeded its overall timeout',
                overallTimeout,
              );
            },
          );
    return jsonDecode(response.bodyText);
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

VotingHelperPreflightResult _helperPreflightResult(
  List<Uri> servers,
  List<String> readyServers,
) {
  final readySet = readyServers.toSet();
  final configuredServers = servers.map((server) => server.toString()).toList();
  return VotingHelperPreflightResult(
    rankedServerUrls: [
      ...readyServers,
      for (final server in configuredServers)
        if (!readySet.contains(server)) server,
    ],
    readiness: {
      for (final server in configuredServers) server: readySet.contains(server),
    },
  );
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
