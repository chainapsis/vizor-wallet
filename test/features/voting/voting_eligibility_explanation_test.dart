import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_eligibility_explanation.dart';
import 'package:zcash_wallet/src/features/voting/voting_error_messages.dart';

void main() {
  test('no spendable notes maps to the snapshot Ironwood exclusion', () {
    final explanation = VotingEligibilityExplanation.fromMessage(
      friendlyVotingErrorText(
        'Invalid input: no spendable voting notes at snapshot height 3359740',
      ),
      snapshotDate: DateTime.utc(2026, 8, 1),
    );

    expect(
      explanation.reason,
      VotingEligibilityExclusionReason.noNotesAtSnapshot,
    );
    expect(explanation.snapshotHeight, 3359740);
    expect(explanation.snapshotValue, 'Aug 1, 2026');
    expect(explanation.snapshotBlockLabel, 'Block 3,359,740');
    expect(
      explanation.reasonBody,
      contains('Only Ironwood notes this account held at the snapshot'),
    );
    expect(explanation.reasonBody, contains('moved funds or finished Ironwood'));
    expect(explanation.reasonBody, isNot(contains('sending after')));
  });

  test('minimum eligibility keeps the 0.125 ZEC bundle rule', () {
    final explanation = VotingEligibilityExplanation.fromMessage(
      friendlyVotingErrorText(
        'Invalid input: minimum voting eligibility requires at least one '
        'eligible voting bundle with 12500000 zatoshi voting weight; selected '
        '0 persisted bundles with 0 zatoshi eligible bundle weight at '
        'snapshot height 123',
      ),
    );

    expect(explanation.reason, VotingEligibilityExclusionReason.belowMinimum);
    expect(explanation.snapshotHeight, 123);
    expect(explanation.snapshotValue, 'Block 123');
    expect(explanation.reasonBody, contains('0.125 ZEC'));
    expect(explanation.combinedMessage, contains('snapshot block 123'));
    expect(
      explanation.combinedMessage,
      contains(kVotingEligibilityGuidance),
    );
  });

  test('spending after the snapshot is not described as disqualifying', () {
    // zcash_voting selects unspent-at-historical-height Ironwood notes.
    // A later spend of those notes still counts; later receipts do not.
    final body = const VotingEligibilityExplanation(
      reason: VotingEligibilityExclusionReason.noNotesAtSnapshot,
    ).reasonBody;
    expect(body, contains('received or created after'));
    expect(body.toLowerCase(), isNot(contains('spent after')));
    expect(body.toLowerCase(), isNot(contains('sending after')));
  });

  test('friendly text is recognized as an eligibility failure', () {
    final message = friendlyVotingErrorText(
      'no spendable voting notes at snapshot height 10',
    );
    expect(isVotingEligibilityErrorText(message), isTrue);
    expect(message, contains('Ironwood notes'));
    expect(message, contains('snapshot block 10'));
  });
}
