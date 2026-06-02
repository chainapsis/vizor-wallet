import 'dart:convert';

import 'voting_http.dart';
import 'voting_models.dart';

/// Reads an optional off-chain endorsed round set.
///
/// Endorsements are a UX signal, not the source of round validity. Network,
/// HTTP, and parsing failures therefore soft-fail to an empty set so the app can
/// still show valid rounds without endorsement badges instead of hiding voting.
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

  /// Returns normalized round ids when available, or an empty set on failure.
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
      Map<String, dynamic>() => decoded['vote_round_ids'],
      Map() => decoded['vote_round_ids'],
      _ => null,
    };
    if (values is! List) {
      return const {};
    }

    return values
        .whereType<String>()
        .map(normalizeVotingRoundId)
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
