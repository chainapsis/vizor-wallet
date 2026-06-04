import 'package:flutter/foundation.dart';

import '../../rust/third_party/zcash_voting/config.dart';
import 'voting_models.dart';

@immutable
class VotingApiServerSet {
  const VotingApiServerSet({required this.primary, required this.failovers});

  final Uri primary;
  final List<Uri> failovers;

  List<Uri> get all => [primary, ...failovers];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VotingApiServerSet &&
        other.primary == primary &&
        listEquals(other.failovers, failovers);
  }

  @override
  int get hashCode {
    return Object.hash(primary, Object.hashAll(failovers));
  }
}

extension ResolvedVotingConfigX on ResolvedVotingConfig {
  VotingApiServerSet get apiServers {
    if (voteServers.isEmpty) {
      throw StateError('Resolved voting config has no vote servers.');
    }
    final all = <Uri>[];
    final seen = <String>{};
    for (final endpoint in voteServers) {
      final uri = Uri.parse(endpoint.url);
      final key = uri.toString();
      if (seen.add(key)) {
        all.add(uri);
      }
    }
    return VotingApiServerSet(
      primary: all.first,
      failovers: all.skip(1).toList(growable: false),
    );
  }

  Uri get apiBaseUrl => apiServers.primary;

  List<Uri> get apiFailoverBaseUrls => apiServers.failovers;

  Set<String> get authenticatedRoundIdSet => authenticatedRounds
      .map((round) => _normalizeRoundIdForConfig(round.roundId))
      .toSet();

  List<Uri> get pirEndpointUrls => pirEndpoints
      .map((endpoint) => Uri.parse(endpoint.url))
      .toList(growable: false);

  bool isRoundAuthenticated(String roundId) {
    return authenticatedRoundIdSet.contains(
      _normalizeRoundIdForConfig(roundId),
    );
  }

  bool isRoundExplicitlySkipped(String roundId) {
    final normalizedRoundId = _normalizeRoundIdForConfig(roundId);
    return skippedRoundIds
        .map(_normalizeRoundIdForConfig)
        .contains(normalizedRoundId);
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

String _normalizeRoundIdForConfig(String roundId) {
  try {
    return normalizeVotingRoundId(roundId);
  } on FormatException {
    return roundId;
  }
}
