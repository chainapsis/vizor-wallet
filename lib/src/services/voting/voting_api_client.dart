import 'dart:convert';
import 'dart:typed_data';

import 'voting_retry.dart';
import 'voting_http.dart';
import 'voting_models.dart';

/// Minimal REST client for vote-sdk's `/shielded-vote/v1` API surface.
///
/// Chain-facing calls use the configured vote server base URL with optional
/// failover endpoints. Helper-share traffic is owned by `zcash_voting` through
/// Vizor's Rust route-aware transport, not this client.
class VotingApiClient {
  VotingApiClient({
    required Uri baseUrl,
    required VotingHttpClient httpClient,
    List<Uri> fallbackBaseUrls = const [],
    Duration timeout = const Duration(seconds: 10),
    VotingRetryPolicy? readRetryPolicy,
    Future<void> Function(Duration delay)? delay,
  }) : _baseUrl = baseUrl,
       _httpClient = httpClient,
       _fallbackBaseUrls = _dedupeBaseUrls(fallbackBaseUrls, baseUrl: baseUrl),
       _timeout = timeout,
       _readRetryPolicy =
           readRetryPolicy ??
           VotingRetryPolicy.transientHttp(
             name: 'voting-api-read',
             delays: const [Duration(milliseconds: 300), Duration(seconds: 1)],
           ),
       _delay = delay ?? Future<void>.delayed;

  final Uri _baseUrl;
  final List<Uri> _fallbackBaseUrls;
  final VotingHttpClient _httpClient;
  final Duration _timeout;
  final VotingRetryPolicy _readRetryPolicy;
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

  /// The body of `GET /protocol-capabilities`, unread: zcash_voting's proxy
  /// availability reads it.
  Future<Uint8List> getProtocolCapabilitiesBody() async =>
      (await _getBody(['protocol-capabilities']))!;

  /// The body of `GET /round/{roundId}`, unread: zcash_voting's proxy
  /// availability reads it.
  Future<Uint8List> getRoundBody(String roundId) async =>
      (await _getBody(['round', normalizeVotingRoundId(roundId)]))!;

  /// The body of `GET /proxy-delegation-params`, or null when the chain
  /// answers 404 because it has no proxy delegation.
  Future<Uint8List?> getProxyDelegationParamsBody() =>
      _getBody(['proxy-delegation-params'], allowNotFound: true);

  /// One page of the round's whole delegate ballot list,
  /// `GET /delegate-ballots/{roundId}?start_after=&limit=`, unread:
  /// zcash_voting checks and chains the pages.
  Future<Uint8List> getDelegateBallotsPageBody(
    String roundId, {
    required int startAfter,
    int limit = 1000,
  }) async => (await _getBody(
    ['delegate-ballots', normalizeVotingRoundId(roundId)],
    queryParameters: {'start_after': '$startAfter', 'limit': '$limit'},
  ))!;

  /// The vote chain's answer to `GET` [path], a path under a vote server's
  /// base URL that zcash_voting names, such as
  /// `/shielded-vote/v1/delegates/by-key/{hex}`, with its query. It asks
  /// for the codespace ([kVotingCodespaceHeaders]).
  ///
  /// Every answer below HTTP 500 other than 429 is returned unread, so a
  /// 404 reaches zcash_voting, which tells an enabled node's not-found from
  /// a dormant one. A transport failure or a transient status is retried,
  /// then the next vote server is tried; the last failure is thrown.
  Future<VotingChainAnswer> getChainAnswer(String path) async {
    final target = Uri.parse(path);
    final response = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) {
        final uri = _endpointForPath(target, baseUrl);
        return _runRequestWithRetry(
          retryPolicy: _readRetryPolicy,
          operation: () async {
            final response = await _get(
              uri,
              headers: kVotingCodespaceHeaders,
              timeout: _timeout,
            );
            if (response.statusCode == 429 || response.statusCode >= 500) {
              _throwIfNotSuccess(uri, response);
            }
            return response;
          },
        );
      },
    );
    return VotingChainAnswer(response.statusCode, response.bodyBytes);
  }

  /// Posts [body], a JSON body zcash_voting built, to [path] under each vote
  /// server in turn, and returns the first verdict: HTTP 200, 400 or 422.
  /// It asks for the codespace ([kVotingCodespaceHeaders]).
  ///
  /// The body goes out byte for byte: one that would not survive a JSON
  /// round trip unchanged is refused before anything is sent. Every body
  /// posted this way is safe to resend, so an answer without a verdict, or
  /// a transport failure, moves on to the next server; the last answer
  /// comes back when none gives a verdict, and the last failure is thrown
  /// when none answered.
  Future<VotingChainAnswer> postChainBody(String path, Uint8List body) async {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic> ||
        !_sameBytes(utf8.encode(jsonEncode(decoded)), body)) {
      throw ArgumentError('the body would not be posted byte for byte');
    }
    final target = Uri.parse(path);
    VotingChainAnswer? last;
    Object? lastError;
    StackTrace? lastStack;
    for (final baseUrl in [_baseUrl, ..._fallbackBaseUrls]) {
      try {
        final response = await _httpClient.postJson(
          _endpointForPath(target, baseUrl),
          decoded,
          headers: kVotingCodespaceHeaders,
          timeout: _timeout,
        );
        last = VotingChainAnswer(response.statusCode, response.bodyBytes);
        if (const {200, 400, 422}.contains(response.statusCode)) return last;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
      }
    }
    if (last != null) return last;
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  /// [target]'s path and query under [baseUrl], whose own path is kept.
  Uri _endpointForPath(Uri target, Uri baseUrl) {
    final baseSegments = baseUrl.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    return baseUrl.replace(
      pathSegments: [
        ...baseSegments,
        ...target.pathSegments.where((segment) => segment.isNotEmpty),
      ],
      queryParameters: target.queryParameters.isEmpty
          ? null
          : target.queryParameters,
    );
  }

  /// The body of a `GET` on [pathSegments] with vote-server failover and the
  /// read retry policy; null for a 404 when [allowNotFound].
  Future<Uint8List?> _getBody(
    List<String> pathSegments, {
    Map<String, String>? queryParameters,
    bool allowNotFound = false,
  }) async {
    final response = await _withVoteServerFailover(
      policy: _readRetryPolicy,
      operation: (baseUrl) {
        final uri = _endpoint(
          pathSegments,
          queryParameters: queryParameters,
          baseUrl: baseUrl,
        );
        return _runRequestWithRetry(
          retryPolicy: _readRetryPolicy,
          operation: () async {
            final response = await _get(uri, timeout: _timeout);
            if (!(allowNotFound && response.statusCode == 404)) {
              _throwIfNotSuccess(uri, response);
            }
            return response;
          },
        );
      },
    );
    if (response.statusCode == 404) return null;
    return response.bodyBytes;
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

  Future<VotingHttpResponse> _get(
    Uri uri, {
    Map<String, String>? headers,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) {
    return _httpClient.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
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

  static void _throwIfNotSuccess(Uri uri, VotingHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
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

/// Whether [a] and [b] hold the same bytes.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Opts a vote-chain submission or lookup into the answer's `codespace`
/// (contracts-v1 §0), which zcash_voting classifies every rejection
/// by, paired with its code. A node that ignores it answers as before.
const kVotingCodespaceHeaders = {'x-svote-codespace': '1'};

/// A vote chain answer passed on unread: its HTTP status and body, which
/// zcash_voting parses.
class VotingChainAnswer {
  /// Creates the answer.
  const VotingChainAnswer(this.statusCode, this.body);

  /// The HTTP status.
  final int statusCode;

  /// The body.
  final Uint8List body;
}
