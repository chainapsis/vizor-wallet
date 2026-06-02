import 'dart:async';
import 'dart:convert';

import 'voting_retry.dart';
import 'voting_http.dart';
import 'voting_models.dart';

/// Minimal REST client for vote-sdk's `/shielded-vote/v1` API surface.
///
/// Chain-facing calls use the configured vote server base URL. Helper-server
/// share calls take an explicit [serverUrl] because foreground submission and
/// recovery may target different helper subsets over time.
class VotingApiClient {
  VotingApiClient({
    required Uri baseUrl,
    required VotingHttpClient httpClient,
    Duration timeout = const Duration(seconds: 10),
    Duration helperTimeout = const Duration(seconds: 5),
    List<Duration> broadcastRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    Future<void> Function(Duration delay)? delay,
  }) : _baseUrl = baseUrl,
       _httpClient = httpClient,
       _timeout = timeout,
       _helperTimeout = helperTimeout,
       _broadcastRetryDelays = List.unmodifiable(broadcastRetryDelays),
       _delay = delay ?? Future<void>.delayed;

  final Uri _baseUrl;
  final VotingHttpClient _httpClient;
  final Duration _timeout;
  final Duration _helperTimeout;
  final List<Duration> _broadcastRetryDelays;
  final Future<void> Function(Duration delay) _delay;

  /// Lists rounds from the vote server.
  ///
  /// Current vote-sdk returns `{ "rounds": [...] }`. An empty `{}` is accepted
  /// because proto3 JSON omits empty repeated fields.
  Future<List<VotingRoundSummary>> listRounds() async {
    final decoded = await _getJson(_endpoint(['rounds']));
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
    final uri = _endpoint(['rounds', 'active']);
    final response = await _httpClient.get(uri, timeout: _timeout);
    if (response.statusCode == 404) return null;
    _throwIfNotSuccess(uri, response);
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
    final decoded = await _getJson(_endpoint(['round', normalizedRoundId]));
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
    final decoded = await _getJson(
      _endpoint(['tally-results', normalizedRoundId]),
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
    final decoded = await _getJson(
      _endpoint(['tally', normalizedRoundId, proposalId.toString()]),
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
  /// are retried according to [_broadcastRetryDelays].
  Future<VotingTxResult> submitDelegation({
    required Map<String, dynamic> submission,
  }) async {
    final decoded = await _withBroadcastRetry(
      () => _postJson(
        _endpoint(['delegate-vote']),
        submission,
        allowStatusCodes: const {422},
      ),
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  /// Broadcasts a vote commitment transaction to the vote chain.
  ///
  /// Deterministic vote-chain rejections are returned as [VotingTxResult] when
  /// the service responds with HTTP 422. Transient gateway or network failures
  /// are retried according to [_broadcastRetryDelays].
  Future<VotingTxResult> submitVoteCommitment({
    required Map<String, dynamic> commitment,
  }) async {
    final decoded = await _withBroadcastRetry(
      () => _postJson(
        _endpoint(['cast-vote']),
        commitment,
        allowStatusCodes: const {422},
      ),
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  Future<VotingTxConfirmation?> getTxConfirmation(String txHash) async {
    final uri = _endpoint(['tx', txHash]);
    final response = await _httpClient.get(uri, timeout: _timeout);
    if (response.statusCode == 404) return null;
    _throwIfNotSuccess(uri, response, allowStatusCodes: const {422});
    return VotingTxConfirmation.fromJson(
      _objectFromValue(jsonDecode(response.bodyText)),
    );
  }

  /// Posts one encrypted share directly to a helper server.
  ///
  /// The share map is expected to already use the service JSON field names
  /// produced by the voting pipeline. We only add the round id required by the
  /// helper API.
  Future<VotingShareSubmissionResult> submitShare({
    required String roundId,
    required Uri serverUrl,
    required Map<String, dynamic> share,
  }) async {
    final body = {...share, 'vote_round_id': normalizeVotingRoundId(roundId)};
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      body,
      timeout: _helperTimeout,
    );
    return VotingShareSubmissionResult.fromJson(_objectFromValue(decoded));
  }

  /// Checks whether a helper has confirmed a share identified by its nullifier.
  Future<VotingShareStatus> getShareStatus({
    required String roundId,
    required Uri serverUrl,
    required String shareId,
  }) async {
    final decoded = await _getJson(
      _endpoint([
        'share-status',
        normalizeVotingRoundId(roundId),
        shareId,
      ], baseUrl: serverUrl),
      timeout: _helperTimeout,
    );
    return VotingShareStatus.fromJson(_objectFromValue(decoded));
  }

  /// Resends a previously generated share to a specific helper server.
  ///
  /// [shareId] is retained in the signature so call sites can keep the recovery
  /// key nearby, but the current helper endpoint accepts the same body as the
  /// initial submission.
  Future<VotingShareSubmissionResult> resubmitShare({
    required String roundId,
    required Uri serverUrl,
    required String shareId,
    required Map<String, dynamic> share,
  }) async {
    final body = {...share, 'vote_round_id': normalizeVotingRoundId(roundId)};
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      body,
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

  Future<Object?> _getJson(Uri uri, {Duration? timeout}) async {
    final response = await _httpClient.get(uri, timeout: timeout ?? _timeout);
    _throwIfNotSuccess(uri, response);
    return jsonDecode(response.bodyText);
  }

  Future<Object?> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Set<int> allowStatusCodes = const {},
    Duration? timeout,
  }) async {
    final response = await _httpClient.postJson(
      uri,
      body,
      timeout: timeout ?? _timeout,
    );
    _throwIfNotSuccess(uri, response, allowStatusCodes: allowStatusCodes);
    return jsonDecode(response.bodyText);
  }

  Future<T> _withBroadcastRetry<T>(Future<T> Function() operation) async {
    return retryVotingOperation(
      operation: operation,
      delays: _broadcastRetryDelays,
      label: 'broadcast',
      delay: _delay,
    );
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
    if (object.isEmpty) return;
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

void _requireMatchingRoundId({
  required String actual,
  required String expected,
  required String context,
}) {
  if (actual != expected) {
    throw FormatException('$context response round id mismatch');
  }
}
