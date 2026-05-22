import 'dart:convert';

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
  }) : _baseUrl = baseUrl,
       _httpClient = httpClient,
       _timeout = timeout;

  final Uri _baseUrl;
  final VotingHttpClient _httpClient;
  final Duration _timeout;

  /// Lists rounds from the vote server.
  ///
  /// The backend has returned both a bare list and `{ "rounds": [...] }` during
  /// development, so this accepts both shapes while still rejecting anything
  /// that does not contain a list of round objects.
  Future<List<VotingRoundSummary>> listRounds() async {
    final decoded = await _getJson(_endpoint(['rounds']));
    final values = decoded is List
        ? decoded
        : decoded is Map
        ? decoded['rounds']
        : null;
    if (values == null) {
      // vote-sdk proto3 JSON omits empty repeated fields, so a chain with no
      // stored rounds returns `{}` rather than `{"rounds":[]}`.
      if (decoded is Map) return const [];
      throw const FormatException(
        'listRounds expected a JSON list or rounds field',
      );
    }
    if (values is! List) {
      throw const FormatException(
        'listRounds expected a JSON list or rounds field',
      );
    }
    return values
        .map(_objectFromValue)
        .map(VotingRoundSummary.fromJson)
        .toList(growable: false);
  }

  /// Fetches one round and unwraps the ZODL-style `{ "round": ... }` envelope.
  Future<VotingRoundStatus> getRoundStatus(String roundId) async {
    final decoded = await _getJson(
      _endpoint(['round', normalizeVotingRoundId(roundId)]),
    );
    return VotingRoundStatus.fromJson(_unwrapNestedObject(decoded, 'round'));
  }

  Future<VotingRoundTally> getRoundTally(String roundId) async {
    final decoded = await _getJson(
      _endpoint(['tally-results', normalizeVotingRoundId(roundId)]),
    );
    return VotingRoundTally.fromJson(_objectFromValue(decoded));
  }

  Future<VotingTxResult> submitDelegation({
    required Map<String, dynamic> submission,
  }) async {
    final decoded = await _postJson(
      _endpoint(['delegate-vote']),
      submission,
      allowStatusCodes: const {422},
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  Future<VotingTxResult> submitVoteCommitment({
    required Map<String, dynamic> commitment,
  }) async {
    final decoded = await _postJson(
      _endpoint(['cast-vote']),
      commitment,
      allowStatusCodes: const {422},
    );
    return VotingTxResult.fromJson(_objectFromValue(decoded));
  }

  Future<VotingTxConfirmation?> getTxConfirmation(String txHash) async {
    final uri = _endpoint(['tx', txHash]);
    final response = await _httpClient.get(uri, timeout: _timeout);
    if (response.statusCode == 404) return null;
    _throwIfNotSuccess(uri, response, allowStatusCodes: const {422});
    return VotingTxConfirmation.fromJson(_objectFromValue(jsonDecode(response.bodyText)));
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
    final body = {'vote_round_id': roundId, ...share};
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      body,
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
    final body = {'vote_round_id': roundId, ...share};
    final decoded = await _postJson(
      _endpoint(['shares'], baseUrl: serverUrl),
      body,
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

  Future<Object?> _getJson(Uri uri) async {
    final response = await _httpClient.get(uri, timeout: _timeout);
    _throwIfNotSuccess(uri, response);
    return jsonDecode(response.bodyText);
  }

  Future<Object?> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Set<int> allowStatusCodes = const {},
  }) async {
    final response = await _httpClient.postJson(uri, body, timeout: _timeout);
    _throwIfNotSuccess(uri, response, allowStatusCodes: allowStatusCodes);
    return jsonDecode(response.bodyText);
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

Map<String, dynamic> _unwrapNestedObject(Object? value, String key) {
  final object = _objectFromValue(value);
  final nested = object[key];
  return nested == null ? object : _objectFromValue(nested);
}
