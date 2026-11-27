import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_step_row.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_test_harness.dart';
import 'support/mock_delegate_mode_repository.dart';
import 'support/proxy_values.dart';

/// The development round's options per question: 2, 3 and 2.
const _answers = {1: 1, 2: 2, 3: 0};

/// Opens DG-9 for the test round.
Future<DelegateTestHarness> _pumpBallot(
  WidgetTester tester, {
  DelegateModeMockScenario? scenario,
  DateTime? now,
}) => pumpDelegateRoute(
  tester,
  delegateBallotRoute(kDelegateTestRoundId),
  scenario: scenario ?? delegateRegisteredScenario(),
  now: now,
);

/// Picks [option] on question [proposalId].
Future<void> _choose(WidgetTester tester, int proposalId, int option) =>
    tapDelegateKey(tester, 'voting_proposal_${proposalId}_option_$option');

/// Answers every question with [_answers].
Future<void> _answerAll(WidgetTester tester) async {
  for (final MapEntry(key: id, value: option) in _answers.entries) {
    await _choose(tester, id, option);
  }
}

/// The Submit button's handler, null while disabled.
VoidCallback? _submit(WidgetTester tester) => tester
    .widget<AppButton>(find.byKey(const ValueKey('delegate_ballot_submit')))
    .onPressed;

/// Answers everything and opens DG-10.
Future<void> _openConfirm(WidgetTester tester) async {
  await _answerAll(tester);
  await tapDelegateKey(tester, 'delegate_ballot_submit');
}

/// Lets the background resend run once.
Future<void> _resendTick(WidgetTester tester) async {
  await tester.pump(kDelegateBallotResendInterval);
  await settleProxy(tester);
}

/// A submitted ballot offers no way to submit it, or another, again; at
/// most Done.
void _expectNoResubmit(WidgetTester tester) {
  expect(find.byKey(const ValueKey('delegate_ballot_submit')), findsNothing);
  expect(find.byKey(const ValueKey('delegate_ballot_resubmit')), findsNothing);
  expect(find.textContaining('Submit again'), findsNothing);
  expect(
    find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.key != _done,
    ),
    findsNothing,
  );
}

const _done = ValueKey('delegate_ballot_done');

/// The processing view's rows, as `label: mark`.
List<String> _steps(WidgetTester tester) => [
  for (final row in tester.widgetList<VotingStepRow>(
    find.byType(VotingStepRow),
  ))
    '${row.label}: ${row.complete
        ? 'done'
        : row.active
        ? 'active'
        : 'todo'}',
];

/// The processing view waits for the chain, with no Done yet.
void _expectConfirming(WidgetTester tester) {
  expect(_steps(tester), [
    '${testL10n.delegateStepSigning}: done',
    '${testL10n.delegateStepSubmitting}: done',
    '${testL10n.delegateStepConfirming}: active',
  ]);
  expect(find.text(testL10n.delegateBallotProgressTitle), findsOne);
  expect(find.byKey(_done), findsNothing);
  _expectNoResubmit(tester);
}

/// The processing view shows [_answers] as submitted, with Done.
void _expectConfirmed(WidgetTester tester) {
  final success = find.byKey(const ValueKey('delegate_ballot_success'));
  expect(success, findsOne);
  expect(find.text(testL10n.delegateBallotSubmittedTitle), findsOne);
  expect(find.text(testL10n.delegateBallotOnChain), findsOne);
  for (final label in const ['No', "Don't fund", 'Yes']) {
    expect(find.descendant(of: success, matching: find.text(label)), findsOne);
  }
  expect(find.text(testL10n.delegateBallotCounted), findsNothing);
  expect(find.byKey(_done), findsOne);
  _expectNoResubmit(tester);
}

void main() {
  group('DG-9', () {
    testWidgets('Submit stays disabled until every question has an answer', (
      tester,
    ) async {
      await _pumpBallot(tester);
      expect(find.text(testL10n.proxyBallotRules), findsOne);
      expect(find.text('0 of 3 answered'), findsOne);
      expect(_submit(tester), isNull);
      await _choose(tester, 1, 1);
      await _choose(tester, 2, 2);
      expect(find.text('2 of 3 answered'), findsOne);
      expect(_submit(tester), isNull);
      await _choose(tester, 3, 0);
      expect(find.text('3 of 3 answered'), findsOne);
      expect(_submit(tester), isNotNull);
    });

    testWidgets('offers no per-question abstain', (tester) async {
      final harness = await _pumpBallot(tester);
      final round = harness.scenario.rounds.first;
      for (final proposal in round.proposals) {
        final options = find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'voting_proposal_${proposal.id}_option_',
              ),
        );
        expect(options, findsNWidgets(proposal.options.length));
      }
      expect(find.textContaining('bstain'), findsNothing);
      await _answerAll(tester);
      // Clearing a choice leaves the question unanswered, not abstained.
      await _choose(tester, 2, 2);
      expect(find.text('2 of 3 answered'), findsOne);
      expect(_submit(tester), isNull);
    });

    testWidgets('an existing ballot shows read-only, with no Submit', (
      tester,
    ) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario(
          rounds: [
            delegateTestRound(
              ballot: proxyBallot(ApiDelegateBallotKind.submitted, [0, 1, 0]),
            ),
          ],
        ),
      );
      expect(find.text(testL10n.delegateBallotOnChain), findsOne);
      expect(find.text(testL10n.delegateBallotCounted), findsNothing);
      _expectNoResubmit(tester);
      await _choose(tester, 1, 1);
      expect(harness.repository.submitted, isEmpty);
    });

    testWidgets('preflight blocks a ballot that differs from the stored one', (
      tester,
    ) async {
      final harness = await _pumpBallot(tester);
      await _answerAll(tester);
      // A ballot from another device lands before Submit.
      harness.scenario.rounds.first.ballot = proxyBallot(
        ApiDelegateBallotKind.submitted,
        [0, 1, 0],
      );
      await tapDelegateKey(tester, 'delegate_ballot_submit');
      expect(harness.repository.preflightCalls, 1);
      expect(find.text(testL10n.delegateDifferentBallotOnChain), findsOne);
      expect(
        find.byKey(const ValueKey('delegate_ballot_confirm')),
        findsNothing,
      );
      expect(harness.repository.submitted, isEmpty);
      expect(
        find.byKey(const ValueKey('delegate_ballot_submit')),
        findsNothing,
      );
    });

    testWidgets('preflight finds the identical ballot already on chain', (
      tester,
    ) async {
      final harness = await _pumpBallot(tester);
      await _answerAll(tester);
      harness.scenario.rounds.first.ballot = proxyBallot(
        ApiDelegateBallotKind.submitted,
        [1, 2, 0],
      );
      await tapDelegateKey(tester, 'delegate_ballot_submit');
      expect(find.text(testL10n.delegateAlreadySubmitted), findsWidgets);
      expect(harness.repository.submitted, isEmpty);
    });

    testWidgets('a suspended or retired entry blocks Submit with its reason', (
      tester,
    ) async {
      for (final (status, copy) in [
        (DelegateEntryStatus.suspended, testL10n.delegateSuspended),
        (DelegateEntryStatus.retired, testL10n.delegateRetiredBallot),
      ]) {
        final harness = await _pumpBallot(
          tester,
          scenario: delegateRegisteredScenario(entryStatus: status),
        );
        expect(find.byKey(const ValueKey('delegate_ballot_blocked')), findsOne);
        expect(find.text(copy), findsOne);
        expect(_submit(tester), isNull);
        await _choose(tester, 1, 1);
        expect(find.text('0 of 3 answered'), findsOne);
        expect(harness.repository.submitted, isEmpty);
      }
    });

    testWidgets('after voting ends nothing can be submitted', (tester) async {
      await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario(
          rounds: [
            delegateTestRound(
              voteEnd: kProxyTestNow.subtract(const Duration(seconds: 1)),
            ),
          ],
        ),
      );
      expect(find.text(testL10n.delegateVotingEnded), findsOne);
      expect(_submit(tester), isNull);
    });

    testWidgets('the final 60 seconds ask for a blocking confirm', (
      tester,
    ) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario(
          rounds: [
            delegateTestRound(
              voteEnd: kProxyTestNow.add(const Duration(seconds: 40)),
            ),
          ],
        ),
      );
      expect(find.text(testL10n.delegateFinalMinutes(1)), findsOne);
      await _openConfirm(tester);
      expect(find.text(testL10n.delegateFinalMinute), findsOne);
      await tapDelegateKey(tester, 'delegate_final_minute_cancel');
      expect(harness.repository.preflightCalls, 0);
      await tapDelegateKey(tester, 'delegate_ballot_submit');
      await tapDelegateKey(tester, 'delegate_final_minute_submit');
      expect(harness.repository.preflightCalls, 1);
      expect(find.byKey(const ValueKey('delegate_ballot_confirm')), findsOne);
    });
  });

  group('DG-10 and the processing view', () {
    testWidgets('lists every choice, then signs and submits once on a '
        'processing view that stays until the chain shows the ballot', (
      tester,
    ) async {
      final harness = await _pumpBallot(tester);
      await _openConfirm(tester);
      expect(find.text(testL10n.proxyBallotConfirm(3)), findsOne);
      for (final label in const ['No', "Don't fund", 'Yes']) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('delegate_ballot_confirm')),
            matching: find.text(label),
          ),
          findsOne,
        );
      }
      final hold = Completer<bool>();
      harness.reauth.hold = hold;
      await tester.tap(find.byKey(const ValueKey('delegate_confirm_submit')));
      // A second press while the sheet closes does nothing.
      await tester.tap(
        find.byKey(const ValueKey('delegate_confirm_submit')),
        warnIfMissed: false,
      );
      await settleProxy(tester);
      expect(harness.location, delegateBallotRoute(kDelegateTestRoundId));
      expect(
        find.byKey(const ValueKey('delegate_ballot_confirm')),
        findsNothing,
      );
      expect(harness.reauth.prompts, [DelegateReauthPurpose.signBallot]);
      expect(harness.repository.submitted, isEmpty);
      expect(_steps(tester), [
        '${testL10n.delegateStepSigning}: active',
        '${testL10n.delegateStepSubmitting}: todo',
        '${testL10n.delegateStepConfirming}: todo',
      ]);
      expect(find.byKey(_done), findsNothing);
      expect(
        find.byKey(const ValueKey('voting_proposal_1_option_0')),
        findsNothing,
      );

      hold.complete(true);
      await settleProxy(tester);
      expect(harness.repository.submitted, [
        [1, 2, 0],
      ]);
      _expectConfirmed(tester);
      expectNoDelegateTotals(tester);

      await tapDelegateKey(tester, 'delegate_ballot_done');
      expect(harness.location, kDelegateModePath);
    });

    testWidgets('a cancelled re-auth signs nothing and goes back to the '
        'questions', (tester) async {
      final harness = await _pumpBallot(tester);
      await _openConfirm(tester);
      harness.reauth.allow = false;
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      expect(harness.reauth.prompts, hasLength(1));
      expect(harness.repository.submitted, isEmpty);
      expect(
        find.byKey(const ValueKey('delegate_ballot_progress')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('delegate_ballot_notice')),
        findsNothing,
      );
      expect(find.text('3 of 3 answered'), findsOne);
      expect(_submit(tester), isNotNull);
    });

    testWidgets('Cancel on DG-10 submits nothing', (tester) async {
      final harness = await _pumpBallot(tester);
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_cancel');
      expect(harness.reauth.prompts, isEmpty);
      expect(harness.repository.submitted, isEmpty);
      expect(
        find.byKey(const ValueKey('delegate_ballot_progress')),
        findsNothing,
      );
      expect(_submit(tester), isNotNull);
    });

    testWidgets('AlreadyAccepted counts as success', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario()
          ..submitResults = [ballotSubmit(ApiBallotSubmitKind.alreadyAccepted)],
      );
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      expect(harness.repository.submitted, hasLength(1));
      _expectConfirmed(tester);
      expect(
        find.byKey(const ValueKey('delegate_ballot_rejected')),
        findsNothing,
      );
    });

    testWidgets('a rejection maps to its copy, allows no resubmit and lets '
        'the delegate leave', (tester) async {
      for (final code in [4, 55, 57, 58, 6]) {
        final harness = await _pumpBallot(
          tester,
          scenario: delegateRegisteredScenario()
            ..submitResults = [ballotRejected(code, reason: 'chain log')],
        );
        await _openConfirm(tester);
        await tapDelegateKey(tester, 'delegate_confirm_submit');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('delegate_ballot_rejected')),
            matching: find.text(
              delegateBallotRejectionCopy(testL10n, 'vote', code),
            ),
          ),
          findsOne,
          reason: 'code $code',
        );
        expect(_steps(tester), [
          '${testL10n.delegateStepSigning}: done',
          '${testL10n.delegateStepSubmitting}: done',
          '${testL10n.delegateStepConfirming}: todo',
        ]);
        expect(harness.repository.submitted, hasLength(1));
        expect(find.byKey(_done), findsOne);
        _expectNoResubmit(tester);
        // The chain's word stands, and nothing more is sent.
        await _resendTick(tester);
        expect(harness.repository.resent, isEmpty);
        expect(
          find.byKey(const ValueKey('delegate_ballot_rejected')),
          findsOne,
        );
      }
    });

    testWidgets('a suspension the chain answers shows its copy and is '
        'checked again until the ballot lands', (tester) async {
      for (final code in [54]) {
        final harness = await _pumpBallot(
          tester,
          scenario: delegateRegisteredScenario()
            ..submitResults = [ballotRejected(code, reason: 'chain log')],
        );
        await _openConfirm(tester);
        await tapDelegateKey(tester, 'delegate_confirm_submit');
        expect(
          find.text(delegateBallotRejectionCopy(testL10n, 'vote', code)),
          findsOne,
          reason: 'code $code',
        );
        _expectNoResubmit(tester);

        // Coordinators lifted it; the same ballot goes out again.
        await _resendTick(tester);
        expect(harness.repository.resent, [
          [1, 2, 0],
        ], reason: 'code $code');
        expect(
          find.text(delegateBallotRejectionCopy(testL10n, 'vote', code)),
          findsNothing,
        );
        _expectConfirmed(tester);
      }
    });

    testWidgets('a submit with no answer keeps confirming while it is '
        'resent in the background, then shows it submitted', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario()..submitUnavailable = 1,
      );
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      expect(harness.repository.submitted, [
        [1, 2, 0],
      ]);
      _expectConfirming(tester);
      expect(
        find.byKey(const ValueKey('delegate_ballot_notice')),
        findsNothing,
      );

      await _resendTick(tester);
      expect(harness.repository.resent, [
        [1, 2, 0],
      ]);
      expect(harness.reauth.prompts, hasLength(1), reason: 'no new prompt');
      _expectConfirmed(tester);

      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(1), reason: 'listed');
    });

    testWidgets('an accepted ballot keeps confirming until the list shows '
        'it, never offering to submit again', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario()..acceptedUnlisted = 2,
      );
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      _expectConfirming(tester);

      // The list still lacks it after the first resend.
      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(1));
      _expectConfirming(tester);

      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(2));
      _expectConfirmed(tester);
      expect(harness.repository.submitted, hasLength(1));
      expect(harness.reauth.prompts, hasLength(1));
    });

    testWidgets('after the confirm timeout the delegate may leave while '
        'the resends go on', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario()..acceptedUnlisted = 1000,
      );
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      // The submit's settle already took under a second.
      await tester.pump(
        kDelegateBallotConfirmTimeout - const Duration(seconds: 2),
      );
      _expectConfirming(tester);
      expect(
        find.byKey(const ValueKey('delegate_ballot_still_confirming')),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 2));
      await settleProxy(tester);
      expect(find.text(testL10n.delegateBallotStillConfirming), findsOne);
      expect(find.byKey(_done), findsOne);
      expect(
        _steps(tester).last,
        '${testL10n.delegateStepConfirming}: active',
        reason: 'still trying',
      );
      final resent = harness.repository.resent.length;
      expect(resent, greaterThanOrEqualTo(7));

      harness.scenario.acceptedUnlisted = 0;
      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(resent + 1));
      _expectConfirmed(tester);
    });

    testWidgets('a rejection the chain returns to a resend shows its copy '
        'and ends the resends', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario()
          ..submitUnavailable = 1
          ..submitResults = [ballotRejected(4, reason: 'chain log')],
      );
      await _openConfirm(tester);
      await tapDelegateKey(tester, 'delegate_confirm_submit');
      _expectConfirming(tester);
      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(1));
      expect(
        find.text(delegateBallotRejectionCopy(testL10n, 'vote', 4)),
        findsOne,
      );
      expect(find.byKey(_done), findsOne);
      _expectNoResubmit(tester);
      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(1));
    });

    testWidgets('a later visit shows a stored ballot as confirming, then on '
        'chain', (tester) async {
      final scenario = delegateRegisteredScenario()..submitUnavailable = 1;
      scenario.rounds.first.storedBallot = [1, 2, 0];
      final harness = await _pumpBallot(tester, scenario: scenario);
      expect(find.byKey(const ValueKey('delegate_ballot_pending')), findsOne);
      expect(find.text(testL10n.delegateBallotPendingLabel), findsOne);
      _expectNoResubmit(tester);
      await _resendTick(tester);
      await _resendTick(tester);
      expect(harness.repository.resent, hasLength(2));
      expect(find.text(testL10n.delegateBallotOnChain), findsOne);
      expect(find.text(testL10n.delegateBallotPendingLabel), findsNothing);
    });

    testWidgets('a stored ballot waits while the entry is suspended and is '
        'resent once the suspension lifts', (tester) async {
      final scenario = delegateRegisteredScenario(
        entryStatus: DelegateEntryStatus.suspended,
      )..rounds.first.storedBallot = [1, 2, 0];
      final harness = await _pumpBallot(tester, scenario: scenario);
      expect(find.text(testL10n.delegateSuspended), findsOne);
      _expectNoResubmit(tester);
      await _resendTick(tester);
      expect(harness.repository.resent, isEmpty);

      scenario.status = delegateModeViewWith(
        scenario.status,
        DelegateEntryStatus.active,
      );
      await _resendTick(tester);
      expect(harness.repository.resent, [
        [1, 2, 0],
      ]);
      expect(find.text(testL10n.delegateBallotOnChain), findsOne);
    });

    testWidgets("a retired entry's stored ballot stops and shows why", (
      tester,
    ) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario(
          entryStatus: DelegateEntryStatus.retired,
        )..rounds.first.storedBallot = [1, 2, 0],
      );
      expect(find.text(testL10n.delegateRetiredBallot), findsOne);
      expect(find.text(testL10n.delegateBallotPendingLabel), findsNothing);
      await _resendTick(tester);
      expect(harness.repository.resent, isEmpty);
      _expectNoResubmit(tester);
    });

    testWidgets('resends stop once voting ends', (tester) async {
      final harness = await _pumpBallot(
        tester,
        scenario: delegateRegisteredScenario(
          rounds: [delegateTestRound(voteEnd: kProxyTestNow)],
        )..rounds.first.storedBallot = [1, 2, 0],
      );
      expect(find.text(testL10n.delegateVotingEnded), findsOne);
      expect(find.text(testL10n.delegateBallotPendingLabel), findsNothing);
      await _resendTick(tester);
      expect(harness.repository.resent, isEmpty);
      _expectNoResubmit(tester);
    });
  });

  testWidgets('an unknown round offers a retry', (tester) async {
    await pumpDelegateRoute(
      tester,
      delegateBallotRoute('missing'),
      scenario: delegateRegisteredScenario(),
    );
    expect(find.text(testL10n.delegateLoadError), findsOne);
    expect(find.text(testL10n.commonTryAgain), findsOne);
  });
}
