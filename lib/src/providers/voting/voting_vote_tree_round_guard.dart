import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serializes interactive vote-tree sync/witness work per round.
///
/// Fire-and-forget pre-sync must not reset or advance vote-tree cache for a
/// round while [runHeld] is active for that round.
final votingVoteTreeRoundGuardProvider = Provider<VotingVoteTreeRoundGuard>(
  (ref) => VotingVoteTreeRoundGuard(),
);

class VotingVoteTreeRoundGuard {
  final Map<String, int> _holdersByRound = {};

  bool isHeld(String roundId) => (_holdersByRound[roundId] ?? 0) > 0;

  Future<T> runHeld<T>(String roundId, Future<T> Function() action) async {
    _acquire(roundId);
    try {
      return await action();
    } finally {
      _release(roundId);
    }
  }

  void _acquire(String roundId) {
    _holdersByRound[roundId] = (_holdersByRound[roundId] ?? 0) + 1;
  }

  void _release(String roundId) {
    final remaining = (_holdersByRound[roundId] ?? 0) - 1;
    if (remaining <= 0) {
      _holdersByRound.remove(roundId);
    } else {
      _holdersByRound[roundId] = remaining;
    }
  }
}
