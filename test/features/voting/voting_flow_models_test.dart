import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

void main() {
  test('proposal parser preserves explicit service proposal ids', () {
    final proposals = proposalsFromJson({
      'proposals': [
        {
          'proposal_id': 1,
          'title': 'First',
          'options': ['Yes', 'No'],
        },
        {
          'proposalId': 2,
          'title': 'Second',
          'choices': [
            {'id': 0, 'label': 'Abstain'},
            {'id': 1, 'label': 'Support'},
          ],
        },
      ],
    });

    expect(proposals.map((proposal) => proposal.id), [1, 2]);
    expect(proposals.first.options.map((option) => option.index), [0, 1]);
    expect(proposals.last.options.map((option) => option.label), [
      'Abstain',
      'Support',
    ]);
  });

  test('proposal parser rejects missing proposal ids', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'title': 'Missing id'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: proposal_id',
        ),
      ),
    );
  });

  test('proposal parser rejects ids outside Rust vote protocol range', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'proposal_id': 0, 'title': 'Zero'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'proposal_id must be 1..15, got 0',
        ),
      ),
    );
  });

  test('proposal parser rejects fractional proposal ids', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'proposal_id': 1.9, 'title': 'Fractional'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'proposal_id must be an integer',
        ),
      ),
    );
  });

  test('draft choices can be cleared by proposal id', () {
    final draft = const VotingDraftState()
        .setChoice(1, 0)
        .setChoice(2, 1)
        .clearChoice(1);

    expect(draft.choices, {2: 1});
    expect(draft.isEmpty, false);
    expect(draft.clearChoice(2).isEmpty, true);
  });
}
