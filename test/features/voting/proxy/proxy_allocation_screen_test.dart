import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
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

/// Opens the directory, chooses [shares] (handle to basis points), then
/// pushes the editor and, with [review], the vote review with [answers].
Future<ProxyTestHarness> _pumpDraft(
  WidgetTester tester,
  Map<String, int?> shares, {
  ProxyMockScenario? scenario,
  bool review = false,
  VotingDraftState answers = const VotingDraftState(),
  ProxyDelegationRepository? backing,
}) async {
  final round = scenario ?? proxyTestScenario();
  final harness = await pumpProxyRoute(
    tester,
    proxyDelegateDirectoryRoute(kProxyTestRoundId),
    scenario: round,
    backing: backing,
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
      VotingDraftState answers = const VotingDraftState(choices: {1: 0}),
    }) => _pumpDraft(
      tester,
      shares,
      scenario: scenario,
      review: true,
      answers: answers,
    );

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

    testWidgets('a commit zcash_voting refuses says why, stays and leaves no '
        'answers behind', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await _pumpDraft(
        tester,
        const {'alice_votes': 5000, 'dana_research': 2500},
        scenario: scenario,
        review: true,
        answers: const VotingDraftState(choices: {1: 0}),
        backing: _RefusingCommits(
          scenario,
          ProxyDelegationErrorKind.alreadyVoted,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('proxy_finality_checkbox')));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('voting_confirm_submit_button')),
      );
      await settleProxy(tester);
      expect(find.byKey(const ValueKey('proxy_confirm_error')), findsOne);
      expect(find.text(testL10n.proxyAlreadyStartedVoting), findsOne);
      expect(harness.location, votingReviewRoute(kProxyTestRoundId));
      expect(harness.jobs.proxyStarted, isEmpty);
      expect(harness.session.cleared, [
        [1, 2, 3],
      ], reason: 'the refused commit leaves no answers behind');
    });

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
