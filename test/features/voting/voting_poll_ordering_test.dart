import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_poll_ordering.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

void main() {
  test('matches zodl-ios poll list ordering', () {
    final rounds = [
      _round('closed-old', status: 'finalized', end: '2026-01-01T00:00:00Z'),
      _round('active-later', status: 'active', end: '2026-03-01T00:00:00Z'),
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
}) {
  return VotingRoundView(
    roundId: id,
    title: id,
    status: status,
    voted: voted,
    rawJson: {'vote_end_time': end},
  );
}
