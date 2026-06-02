import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_poll_ordering.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

void main() {
  test('prioritizes in-progress polls before normal active polls', () {
    final rounds = [
      _round('closed-old', status: 'finalized', end: '2026-01-01T00:00:00Z'),
      _round('active-later', status: 'active', end: '2026-03-01T00:00:00Z'),
      _round(
        'in-progress',
        status: 'active',
        end: '2026-05-01T00:00:00Z',
        inProgress: true,
      ),
      _round(
        'voted',
        status: 'active',
        end: '2026-01-15T00:00:00Z',
        voted: true,
      ),
      _round('tallying', status: 'tallying', end: '2026-03-15T00:00:00Z'),
      _round('active-sooner', status: 'active', end: '2026-02-01T00:00:00Z'),
      _round('closed-recent', status: 'closed', end: '2026-04-01T00:00:00Z'),
    ];

    final sorted = sortVotingRoundsForPollList(rounds);

    expect(sorted.map((round) => round.roundId), [
      'in-progress',
      'active-sooner',
      'active-later',
      'voted',
      'closed-recent',
      'tallying',
      'closed-old',
    ]);
  });

  test('keeps backend order when sort keys are tied', () {
    final rounds = [
      _round('first', status: 'active', end: '2026-02-01T00:00:00Z'),
      _round('second', status: 'active', end: '2026-02-01T00:00:00Z'),
    ];

    final sorted = sortVotingRoundsForPollList(rounds);

    expect(sorted.map((round) => round.roundId), ['first', 'second']);
  });
}

VotingRoundView _round(
  String id, {
  required String status,
  required String end,
  bool voted = false,
  bool inProgress = false,
}) {
  return VotingRoundView(
    roundId: id,
    title: id,
    status: status,
    voted: voted,
    inProgress: inProgress,
    rawJson: {'vote_end_time': end},
  );
}
