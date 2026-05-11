import 'dart:convert';

import 'voting_http.dart';

/// Reads an optional off-chain endorsed-round set.
///
/// Endorsements are a UX signal, not the source of round authenticity. Network,
/// HTTP, and parsing failures therefore soft-fail to an empty set so the app can
/// still show authenticated rounds as unendorsed instead of hiding voting.
class VotingEndorserClient {
  VotingEndorserClient({
    required Uri endorsedSetUrl,
    required VotingHttpClient httpClient,
    Duration timeout = const Duration(seconds: 10),
  }) : _endorsedSetUrl = endorsedSetUrl,
       _httpClient = httpClient,
       _timeout = timeout;

  final Uri _endorsedSetUrl;
  final VotingHttpClient _httpClient;
  final Duration _timeout;

  /// Returns lowercase round ids when available, or an empty set on failure.
  Future<Set<String>> getEndorsedSet() async {
    try {
      final response = await _httpClient.get(
        _endorsedSetUrl,
        timeout: _timeout,
      );
      if (response.statusCode != 200) {
        return const {};
      }
      return _parseEndorsedSet(jsonDecode(response.bodyText));
    } catch (_) {
      return const {};
    }
  }

  static Set<String> _parseEndorsedSet(Object? decoded) {
    final values = switch (decoded) {
      List() => decoded,
      Map<String, dynamic>() =>
        decoded['endorsed_round_ids'] ??
            decoded['endorsedRoundIds'] ??
            decoded['endorsedRounds'] ??
            decoded['rounds'],
      Map() =>
        decoded['endorsed_round_ids'] ??
            decoded['endorsedRoundIds'] ??
            decoded['endorsedRounds'] ??
            decoded['rounds'],
      _ => null,
    };
    if (values is! List) {
      return const {};
    }

    return values
        .map((value) {
          if (value is String) return value;
          if (value is Map<String, dynamic>) {
            return value['round_id'] ?? value['roundId'] ?? value['id'];
          }
          if (value is Map) {
            return value['round_id'] ?? value['roundId'] ?? value['id'];
          }
          return null;
        })
        .whereType<Object>()
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
