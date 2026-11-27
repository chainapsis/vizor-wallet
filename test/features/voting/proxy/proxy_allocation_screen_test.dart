import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_ballot_review.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

/// Opens the directory, chooses [shares] (handle to basis points), then
/// pushes the editor and, with [review], the vote review with [answers].
Future<ProxyTestHarness> _pumpDraft(
  WidgetTester tester,
  Map<String, int?> shares, {
  ProxyMockScenario? scenario,
  DateTime? now,
  bool review = false,
  VotingDraftState answers = const VotingDraftState(),
  ProxyDelegationRepository? backing,
  Size size = const Size(1000, 2400),
  double textScale = 1,
}) async {
  final round = scenario ?? proxyTestScenario();
  final harness = await pumpProxyRoute(
    tester,
    proxyDelegateDirectoryRoute(kProxyTestRoundId),
    scenario: round,
    now: now,
    backing: backing,
    size: size,
    textScale: textScale,
    answers: answers,
  );
  final notifier = harness.container.read(
    proxyAllocationDraftProvider(kProxyTestKey).notifier,
  );
  for (final (i, MapEntry(key: handle, value: bps)) in shares.entries.indexed) {
    notifier.toggle(proxyEntry(round, handle));
    notifier.setPercent(i, bps);
  }
  harness.router.push(proxyAllocationRoute(kProxyTestRoundId));
  await settleProxy(tester);
  if (review) {
    harness.router.go(votingReviewRoute(kProxyTestRoundId));
    await settleProxy(tester);
  }
  return harness;
}

/// The editable share field of delegate [index].
Finder _percentField(int index) => find.descendant(
  of: find.byKey(ValueKey('proxy_allocation_percent_$index')),
  matching: find.byType(EditableText),
);

/// The mock repository, except that every commit is refused as [kind], as
/// zcash_voting refuses a bundle whose proxy batch could never be proved.
class _RefusingCommits extends MockProxyDelegationRepository {
  _RefusingCommits(super.scenario, this.kind);

  /// The kind each commit is refused with.
  final ProxyDelegationErrorKind kind;

  @override
  Future<void> commit(
    ProxyAllocationRequest request, {
    required ProxyAllocationPreview confirmed,
  }) async => throw ProxyDelegationError(kind: kind);
}

/// The [AppButton] keyed [key].
AppButton _button(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key)));

void main() {
  group('PD-5 editor', () {
    testWidgets('asks for a share per delegate before review', (tester) async {
      await _pumpDraft(tester, {'alice_votes': null, 'bjorn_dev': null});
      expect(find.text(testL10n.proxyVotingPower('50 ZEC')), findsOne);
      expect(find.byKey(const ValueKey('proxy_allocation_row_1')), findsOne);
      expect(find.byKey(const ValueKey('proxy_allocation_row_2')), findsOne);
      expect(find.text(testL10n.proxyPercentRequired), findsOne);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNull);
    });

    testWidgets('previews the exact split and the kept remainder', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      final harness = await _pumpDraft(tester, {
        'alice_votes': null,
      }, scenario: scenario);
      await tester.enterText(_percentField(alice.index), '50');
      await settleProxy(tester);
      expect(
        find.byKey(ValueKey('proxy_allocation_amount_${alice.index}')),
        findsOne,
      );
      expect(find.text('25 ZEC'), findsOne);
      expect(find.text('50% · 25 ZEC'), findsOne);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('proxy_allocation_done')));
      await settleProxy(tester);
      expect(
        harness.location,
        votingPollRoute(kProxyTestRoundId),
        reason: 'the split goes back to the round\'s questions',
      );
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .delegates,
        hasLength(1),
      );
    });

    testWidgets('splits evenly, which delegates everything', (tester) async {
      await _pumpDraft(tester, {
        'alice_votes': null,
        'bjorn_dev': null,
        'chidi_node': null,
      });
      await tester.tap(
        find.byKey(const ValueKey('proxy_allocation_split_evenly')),
      );
      await settleProxy(tester);
      expect(find.text('33.34'), findsOne);
      expect(find.text('33.33'), findsNWidgets(2));
      expect(find.text('0% · 0 ZEC'), findsOne);
    });

    testWidgets('flags shares over 100%', (tester) async {
      await _pumpDraft(tester, {'alice_votes': 6000, 'bjorn_dev': 5000});
      expect(find.text(testL10n.proxyPercentOver), findsOne);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNull);
      await tester.enterText(_percentField(2), '10');
      await settleProxy(tester);
      expect(find.text(testL10n.proxyPercentOver), findsNothing);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNotNull);
    });

    testWidgets('explains a split the voting power cannot cover', (
      tester,
    ) async {
      await _pumpDraft(tester, {
        'alice_votes': 5000,
        'bjorn_dev': 5000,
      }, scenario: proxyTestScenario(eligibleBallots: BigInt.one));
      expect(find.text(testL10n.proxyNotEnoughVotingPower), findsOne);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNull);
    });

    testWidgets('stops adding delegates at 8 and removes rows', (tester) async {
      final scenario = proxyTestScenario();
      final unblocked = scenario.delegates.where((e) => !e.blocked).take(8);
      await _pumpDraft(tester, {
        for (final entry in unblocked) entry.handle: 1250,
      }, scenario: scenario);
      expect(
        _button(tester, 'proxy_allocation_add_delegate').onPressed,
        isNull,
      );
      expect(find.text(testL10n.proxyPickerFull), findsOne);
      final first = unblocked.first;
      await tester.tap(
        find.byKey(ValueKey('proxy_allocation_remove_${first.index}')),
      );
      await settleProxy(tester);
      expect(
        find.byKey(ValueKey('proxy_allocation_row_${first.index}')),
        findsNothing,
      );
      expect(
        _button(tester, 'proxy_allocation_add_delegate').onPressed,
        isNotNull,
      );
    });
  });

  group('the review\'s timing', () {
    testWidgets('names the vote end while the window is open', (tester) async {
      await _pumpDraft(tester, {'alice_votes': 5000}, review: true);
      final end = kProxyTestNow.add(const Duration(days: 3));
      expect(
        find.text(testL10n.proxyVotingEnds(formatProxyVoteEnd(testL10n, end))),
        findsOne,
      );
    });

    testWidgets('keeps the 24 h notice', (tester) async {
      await _pumpDraft(
        tester,
        {'alice_votes': 5000},
        review: true,
        scenario: proxyTestScenario(
          voteEnd: kProxyTestNow.add(const Duration(hours: 9)),
        ),
      );
      expect(find.byKey(const ValueKey('proxy_timing_closing_soon')), findsOne);
      expect(
        find.textContaining(testL10n.proxyClosingSoon('9 hours')),
        findsOne,
      );
    });

    testWidgets('the editor says too late only once voting has ended', (
      tester,
    ) async {
      await _pumpDraft(tester, {
        'alice_votes': 5000,
      }, scenario: proxyTestScenario(voteEnd: kProxyTestNow));
      expect(find.byKey(const ValueKey('proxy_timing_too_late')), findsOne);
      expect(find.text(testL10n.proxyTooLate), findsOne);
      expect(_button(tester, 'proxy_allocation_done').onPressed, isNull);
    });

    testWidgets('the editor names no vote end while the window is open', (
      tester,
    ) async {
      await _pumpDraft(tester, {'alice_votes': 5000});
      expect(find.byKey(const ValueKey('proxy_timing_open')), findsNothing);
    });
  });

  group('the vote review with a delegation', () {
    /// Opens the vote review for [shares] and [answers], by default an
    /// answer for the kept share.
    Future<ProxyTestHarness> pumpConfirm(
      WidgetTester tester, {
      ProxyMockScenario? scenario,
      Map<String, int?> shares = const {
        'alice_votes': 5000,
        'dana_research': 2500,
      },
      Size size = const Size(1000, 2400),
      double textScale = 1,
      VotingDraftState answers = const VotingDraftState(choices: {1: 0}),
    }) => _pumpDraft(
      tester,
      shares,
      scenario: scenario,
      review: true,
      answers: answers,
      size: size,
      textScale: textScale,
    );

    // The desktop minimum windows, large and small. The review does not
    // fit the small one at 200% text, so that case is left to the phone
    // sizes in the mobile lane.
    for (final (size, textScale) in const [
      (Size(1080, 720), 1.0),
      (Size(1080, 720), 2.0),
      (Size(416, 851), 1.0),
    ]) {
      testWidgets('the finality checkbox and its line are pinned above the '
          'button and on screen at $size and ${textScale}x text', (
        tester,
      ) async {
        await pumpConfirm(tester, size: size, textScale: textScale);
        expect(tester.takeException(), isNull);
        final footer = find.byKey(const ValueKey('proxy_confirm_footer'));
        final checkbox = find.byKey(const ValueKey('proxy_finality_checkbox'));
        for (final part in [
          checkbox,
          find.byKey(const ValueKey('proxy_counts_only_with_ballot')),
          find.byKey(const ValueKey('voting_confirm_submit_button')),
        ]) {
          expect(find.descendant(of: footer, matching: part), findsOne);
        }
        final box = tester.getRect(checkbox);
        final cta = tester.getRect(
          find.byKey(const ValueKey('voting_confirm_submit_button')),
        );
        // Whole and above the footer's own scroll area, which only the
        // line may need.
        final area = tester.getRect(
          find.descendant(of: footer, matching: find.byType(Scrollable)),
        );
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(area.top));
        expect(area.bottom, lessThanOrEqualTo(cta.top));
        expect(cta.bottom, lessThanOrEqualTo(size.height));

        // Disabled, the button points at the box, which needs no scroll.
        expect(
          _button(tester, 'voting_confirm_submit_button').onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('proxy_confirm_checkbox_hint')),
          findsOne,
        );
        expect(find.text(testL10n.proxyConfirmCheckboxHint), findsOne);
        await tester.tap(checkbox);
        await settleProxy(tester);
        expect(
          _button(tester, 'voting_confirm_submit_button').onPressed,
          isNotNull,
        );
        expect(find.text(testL10n.proxyConfirmCheckboxHint), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows the split, checks, questions and the final terms', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      await pumpConfirm(tester, scenario: scenario);
      final dana = proxyEntry(scenario, 'dana_research');
      final danaRow = find.byKey(ValueKey('proxy_review_row_${dana.index}'));
      expect(find.text('25 ZEC'), findsOne);
      expect(
        find.descendant(of: danaRow, matching: find.text('12.5 ZEC')),
        findsOne,
      );
      expect(
        find.descendant(of: danaRow, matching: find.text('25%')),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('proxy_review_kept')),
          matching: find.text('12.5 ZEC'),
        ),
        findsOne,
      );
      expect(find.byKey(const ValueKey('proxy_review_kept')), findsOne);
      expect(find.text(testL10n.proxyReviewAnswersTitle), findsOne);
      for (final proposal in scenario.round.proposals) {
        expect(find.text(proposal.title), findsOne);
      }
      for (final copy in [
        testL10n.proxyIntro,
        testL10n.proxyPrivacy,
        testL10n.proxyHelperTiming,
        testL10n.proxyKeepInstalled,
      ]) {
        expect(find.text(copy), findsOne);
      }
      expect(find.text(testL10n.proxyFinality), findsOne);
      expect(find.text(testL10n.proxyCountsOnlyWithBallot), findsOne);
      // Ticked, so no hint sits between the box and its line.
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      final checkbox = tester.getRect(
        find.byKey(const ValueKey('proxy_finality_checkbox')),
      );
      final countsLine = tester.getRect(
        find.byKey(const ValueKey('proxy_counts_only_with_ballot')),
      );
      expect(countsLine.top - checkbox.bottom, lessThan(16));
      expect(find.text('Confirm & submit'), findsOne);
    });

    testWidgets('each delegate shows its provider and any lookalike '
        'warning', (tester) async {
      final scenario = proxyTestScenario();
      await pumpConfirm(
        tester,
        scenario: scenario,
        shares: const {'a1ice_votes': 5000, 'bjorn_dev': 2500},
      );
      Finder inRow(String handle, String text) => find.descendant(
        of: find.byKey(
          ValueKey('proxy_review_row_${proxyEntry(scenario, handle).index}'),
        ),
        matching: find.text(text),
      );
      expect(inRow('a1ice_votes', testL10n.proxyProviderXLabel), findsOne);
      expect(
        inRow('a1ice_votes', testL10n.proxyLookalike('alice_votes')),
        findsOne,
      );
      expect(inRow('bjorn_dev', testL10n.proxyProviderGitHubLabel), findsOne);
    });

    testWidgets('a kept share without answers cannot be submitted', (
      tester,
    ) async {
      final harness = await pumpConfirm(
        tester,
        answers: const VotingDraftState(),
      );
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      expect(find.text(testL10n.proxyAnswerKeptShare), findsOne);
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
      expect(harness.repository.commits, isEmpty);
    });

    testWidgets('commits only after the finality checkbox, recording the '
        'kept share\'s answers first, then sends the delegation and the '
        'votes', (tester) async {
      final harness = await pumpConfirm(tester);
      expect(
        find.byKey(const ValueKey('voting_proposal_1_option_0')),
        findsOne,
      );
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('voting_confirm_submit_button')),
      );
      await settleProxy(tester);
      expect(harness.session.recorded, [
        {1: 0},
      ]);
      expect(harness.repository.commits, hasLength(1));
      expect(
        harness.repository.commits.single.choices.map((c) => c.percentBps),
        [5000, 2500],
      );
      expect(
        harness.location,
        votingStatusRoute(kProxyTestRoundId, accountUuid: kProxyTestAccount),
      );
      expect(harness.jobs.started, [
        kProxyTestRoundId,
      ], reason: 'the vote job sends the delegation first, then the casts');
      expect(harness.jobs.proxyStarted, isEmpty);
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .delegates,
        isEmpty,
      );
    });

    testWidgets('everything delegated asks for no answers and drops any', (
      tester,
    ) async {
      final harness = await pumpConfirm(
        tester,
        shares: const {'alice_votes': 5000, 'dana_research': 5000},
        answers: const VotingDraftState(choices: {1: 0}),
      );
      expect(
        find.text('@alice_votes and @dana_research answer these for you'),
        findsOne,
      );
      expect(find.text(testL10n.proxyReviewAnswersTitle), findsNothing);
      expect(find.byKey(const ValueKey('proxy_review_kept')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('voting_confirm_submit_button')),
      );
      await settleProxy(tester);
      expect(harness.jobs.proxyStarted, [kProxyTestRoundId]);
      expect(harness.jobs.started, isEmpty);
      final key = VotingSessionKey(
        roundId: kProxyTestRoundId,
        accountUuid: kProxyTestAccount,
      );
      expect(harness.container.read(votingDraftProvider(key)).isEmpty, isTrue);
    });

    testWidgets('a pause found right before commit records nothing', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final harness = await pumpConfirm(tester, scenario: scenario);
      scenario.availability = const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.paused,
        usedElsewhere: false,
      );
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('voting_confirm_submit_button')),
      );
      await settleProxy(tester);
      expect(find.byKey(const ValueKey('proxy_confirm_error')), findsOne);
      expect(find.text(testL10n.proxyPaused), findsOne);
      expect(harness.repository.commits, isEmpty);
      expect(harness.location, votingReviewRoute(kProxyTestRoundId));
      expect(harness.jobs.started, isEmpty);
      expect(harness.jobs.proxyStarted, isEmpty);
    });

    for (final (kind, copy) in [
      (
        ProxyDelegationErrorKind.alreadyVoted,
        testL10n.proxyAlreadyStartedVoting,
      ),
      (
        ProxyDelegationErrorKind.registrationUnusable,
        testL10n.proxyRegistrationUnusable,
      ),
    ]) {
      testWidgets('a commit refused as ${kind.name} says why and stays', (
        tester,
      ) async {
        final scenario = proxyTestScenario();
        final harness = await _pumpDraft(
          tester,
          const {'alice_votes': 5000, 'dana_research': 2500},
          scenario: scenario,
          review: true,
          answers: const VotingDraftState(choices: {1: 0}),
          backing: _RefusingCommits(scenario, kind),
        );
        await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
        await settleProxy(tester);
        await tester.tap(
          find.byKey(const ValueKey('voting_confirm_submit_button')),
        );
        await settleProxy(tester);
        expect(find.byKey(const ValueKey('proxy_confirm_error')), findsOne);
        expect(find.text(copy), findsOne);
        expect(harness.location, votingReviewRoute(kProxyTestRoundId));
        expect(harness.jobs.proxyStarted, isEmpty);
        expect(harness.session.cleared, [
          [1, 2, 3],
        ], reason: 'the refused commit leaves no answers behind');
      });
    }

    testWidgets('a delegate suspended after review sends the review back '
        'with the new check', (tester) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      final harness = await _pumpDraft(
        tester,
        const {'alice_votes': 5000, 'dana_research': 2500},
        scenario: scenario,
        review: true,
        answers: const VotingDraftState(choices: {1: 0}),
      );
      expect(
        find.byKey(ValueKey('proxy_review_refused_${alice.index}')),
        findsNothing,
      );
      final checksBefore = harness.repository.checkCalls;
      scenario.checks[alice.index] = DelegateCheck.suspended;
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('voting_confirm_submit_button')),
      );
      await settleProxy(tester);

      expect(find.text(testL10n.proxyReviewChanged), findsOne);
      expect(
        harness.repository.checkCalls,
        checksBefore + 2,
        reason: "the commit's own check, then the review's again",
      );
      expect(harness.repository.commits, isEmpty);
      expect(
        find.byKey(ValueKey('proxy_review_refused_${alice.index}')),
        findsOne,
      );
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
      expect(harness.location, votingReviewRoute(kProxyTestRoundId));
      expect(harness.jobs.started, isEmpty);
      expect(harness.jobs.proxyStarted, isEmpty);
    });

    testWidgets('a refused delegate blocks the commit', (tester) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      scenario.checks[alice.index] = DelegateCheck.suspended;
      await pumpConfirm(tester, scenario: scenario);
      expect(
        find.byKey(ValueKey('proxy_review_refused_${alice.index}')),
        findsOne,
      );
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
    });

    testWidgets('an anchor that no longer verifies offers a retry', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      scenario.checks[alice.index] = DelegateCheck.cannotVerify;
      final harness = await pumpConfirm(tester, scenario: scenario);
      expect(
        find.byKey(const ValueKey('proxy_review_cannot_verify')),
        findsOne,
      );
      expect(find.text(testL10n.proxyCannotVerify), findsOne);
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
      final calls = harness.repository.checkCalls;
      scenario.checks.remove(alice.index);
      await tester.ensureVisible(find.text(testL10n.commonTryAgain));
      await tester.tap(find.text(testL10n.commonTryAgain));
      await settleProxy(tester);
      expect(harness.repository.checkCalls, calls + 1);
      expect(find.text(testL10n.proxyCannotVerify), findsNothing);
      expect(
        _button(tester, 'voting_confirm_submit_button').onPressed,
        isNotNull,
      );
    });

    testWidgets('registry proofs no host verifies offer a retry', (
      tester,
    ) async {
      final scenario = proxyTestScenario()..checkCannotVerify = true;
      final harness = await pumpConfirm(tester, scenario: scenario);
      expect(
        find.byKey(const ValueKey('proxy_review_cannot_verify')),
        findsOne,
      );
      expect(find.text(testL10n.proxyCannotVerify), findsOne);
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);

      scenario.checkCannotVerify = false;
      await tester.ensureVisible(find.text(testL10n.commonTryAgain));
      await tester.tap(find.text(testL10n.commonTryAgain));
      await settleProxy(tester);
      expect(harness.repository.checkCalls, 2);
      expect(find.text(testL10n.proxyCannotVerify), findsNothing);
      expect(
        _button(tester, 'voting_confirm_submit_button').onPressed,
        isNotNull,
      );
    });

    for (final (verdict, line) in [
      (DelegateCheck.retired, '@alice_votes has retired as a delegate.'),
      (
        DelegateCheck.notFound,
        "Vizor couldn't find @alice_votes on the voting chain.",
      ),
    ]) {
      testWidgets('a delegate the check finds ${verdict.name} blocks the '
          'commit with its own line', (tester) async {
        final scenario = proxyTestScenario();
        scenario.checks[proxyEntry(scenario, 'alice_votes').index] = verdict;
        await pumpConfirm(tester, scenario: scenario);
        expect(find.text(line), findsOne);
        await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
        await settleProxy(tester);
        expect(
          _button(tester, 'voting_confirm_submit_button').onPressed,
          isNull,
        );
      });
    }

    testWidgets('a delegate whose proven entry is not the one picked shows '
        'the proven entry and that the details did not match', (tester) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      scenario.checks[alice.index] = DelegateCheck.mismatch;
      scenario.provenListings[alice.index] = proxyListingOf(
        index: alice.index,
        provider: alice.provider,
        handle: 'someone_else',
        dk: 'zvdk1other',
        fingerprint: 'zzzz-yyyy-xxxx-wwww',
        reviewed: false,
      );
      await pumpConfirm(tester, scenario: scenario);
      expect(find.text(testL10n.proxyMismatch('@alice_votes')), findsOne);
      expect(find.text('@someone_else'), findsOne);
      expect(
        find.text(formatProxyDelegateId(alice.index, 'zzzz-yyyy-xxxx-wwww')),
        findsOne,
      );
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      expect(_button(tester, 'voting_confirm_submit_button').onPressed, isNull);
    });
  });

  test('each account keeps its own delegation, and a submit stays with the '
      'account its review confirmed', () async {
    const other = VotingSessionKey(
      roundId: kProxyTestRoundId,
      accountUuid: 'account-2',
    );
    final scenario = proxyTestScenario();
    final repositories = <String, MockProxyDelegationRepository>{};
    final container = ProviderContainer(
      overrides: [
        proxyDelegationFeatureEnabledProvider.overrideWithValue(true),
        proxyClockProvider.overrideWithValue(() => kProxyTestNow),
        proxyDelegationRepositoryProvider.overrideWith(
          (_, key) => repositories.putIfAbsent(
            key.accountUuid,
            () => MockProxyDelegationRepository(scenario),
          ),
        ),
        votingSubmissionSessionProvider(
          kProxyTestKey,
        ).overrideWith(() => ProxyTestSession(proxyTestSession(scenario))),
        votingSubmissionJobsProvider.overrideWith(RecordingSubmissionJobs.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(votingSubmissionSessionProvider(kProxyTestKey), (_, _) {});
    container.read(proxyAllocationDraftProvider(kProxyTestKey).notifier)
      ..toggle(proxyEntry(scenario, 'alice_votes'))
      ..setPercent(0, 5000);
    expect(container.read(proxyAllocationDraftProvider(other)).delegates, []);
    final preview = container.listen(
      proxyAllocationPreviewProvider(kProxyTestKey),
      (_, _) {},
    );
    addTearDown(preview.close);
    await container.read(proxyAllocationPreviewProvider(kProxyTestKey).future);

    expect(
      await submitProxyBallot(
        testL10n,
        container,
        key: kProxyTestKey,
        answers: const [
          VotingDraftVote(proposalId: 1, choice: 0, numOptions: 2),
        ],
        proposalIds: [for (final p in scenario.round.proposals) p.id],
      ),
      isNull,
    );
    expect(repositories[kProxyTestAccount]!.commits, hasLength(1));
    expect(repositories[other.accountUuid]?.commits ?? const [], isEmpty);
    expect(
      (container.read(votingSubmissionSessionProvider(kProxyTestKey).notifier)
              as ProxyTestSession)
          .recorded,
      [
        {1: 0},
      ],
    );
    expect(
      (container.read(votingSubmissionJobsProvider.notifier)
              as RecordingSubmissionJobs)
          .accounts,
      [kProxyTestAccount],
    );
  });
}
