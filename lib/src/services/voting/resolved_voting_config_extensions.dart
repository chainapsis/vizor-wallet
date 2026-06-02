import '../../rust/third_party/zcash_voting/config.dart';

extension ResolvedVotingConfigX on ResolvedVotingConfig {
  Uri get apiBaseUrl => Uri.parse(voteServers.first.url);

  Set<String> get authenticatedRoundIdSet =>
      authenticatedRounds.map((round) => round.roundId).toSet();

  List<Uri> get pirEndpointUrls => pirEndpoints
      .map((endpoint) => Uri.parse(endpoint.url))
      .toList(growable: false);

  bool isRoundAuthenticated(String roundId) {
    return authenticatedRoundIdSet.contains(roundId);
  }

  bool isRoundExplicitlySkipped(String roundId) {
    return skippedRoundIds.contains(roundId);
  }

  void assertRoundAuthenticated(String roundId) {
    if (isRoundAuthenticated(roundId)) {
      return;
    }
    final reason = isRoundExplicitlySkipped(roundId)
        ? 'it is present but failed dynamic-config authentication'
        : 'it is absent from the authenticated round set';
    throw StateError(
      'Round $roundId is not authenticated by voting config: $reason.',
    );
  }
}
