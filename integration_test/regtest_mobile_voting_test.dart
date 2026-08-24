import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import 'support/mobile_regtest_flow.dart';

const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'imports an Ironwood wallet and completes a real mobile regtest vote',
    (tester) async {
      tolerateRenderOverflows();
      if (_roundId.length != 64) {
        fail('ZCASH_E2E_VOTE_ROUND_ID must be a 64-character round id.');
      }
      addTearDown(cleanupE2eWalletState);
      await cleanupE2eWalletState();

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );

      logE2e('waiting for the confirmed Ironwood voting balance');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_home_coinholder_voting')),
        ),
        description: 'mobile voting entry point',
        timeout: const Duration(minutes: 5),
      );
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_coinholder_voting')),
        ),
      );

      await tapWidget(tester, const ValueKey('mobile_home_coinholder_voting'));
      await tapAppButton(
        tester,
        ValueKey('voting_poll_action_$_roundId'),
        timeout: const Duration(minutes: 2),
      );

      await pumpUntil(
        tester,
        () {
          final session = container.read(votingSessionProvider(_roundId));
          return session.hasError || session.value?.round != null;
        },
        description: 'mobile voting session round to load',
        timeout: const Duration(minutes: 2),
      );
      var session = container.read(votingSessionProvider(_roundId));
      if (session.hasError) {
        fail('Voting session failed to load: ${session.error}');
      }
      await pumpUntil(
        tester,
        () {
          session = container.read(votingSessionProvider(_roundId));
          final value = session.value;
          return session.hasError ||
              value?.error != null ||
              value?.hasConfirmedVotingEligibility == true;
        },
        description: 'mobile Ironwood voting eligibility to confirm',
        timeout: const Duration(minutes: 10),
      );
      if (session.hasError) {
        fail('Voting eligibility failed: ${session.error}');
      }
      final eligibleSession = session.value!;
      if (!eligibleSession.hasConfirmedVotingEligibility) {
        fail(
          'Voting eligibility was rejected: '
          '${eligibleSession.error?.message ?? 'unknown error'}',
        );
      }

      final accountUuid = eligibleSession.accountUuid;
      expect(accountUuid, isNotNull);
      final draftKey = VotingSessionKey(
        roundId: _roundId,
        accountUuid: accountUuid!,
      );
      for (var proposalId = 1; proposalId <= 4; proposalId++) {
        final optionKey = ValueKey('voting_proposal_${proposalId}_option_0');
        await _scrollUntilVisible(tester, optionKey);
        await _tapVotingOption(
          tester,
          optionKey,
          timeout: const Duration(minutes: 2),
        );
        await pumpUntil(
          tester,
          () =>
              container
                  .read(votingDraftProvider(draftKey))
                  .choices[proposalId] ==
              0,
          description: 'mobile proposal $proposalId selection to persist',
        );
      }

      await _scrollUntilVisible(
        tester,
        const ValueKey('voting_review_answers_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('voting_review_answers_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('voting_confirm_submit_button'),
      );

      await pumpUntil(
        tester,
        () {
          final job = container.read(votingSubmissionJobProvider(draftKey));
          return job.isInFlight ||
              job.status == VotingSubmissionJobStatus.error ||
              job.status == VotingSubmissionJobStatus.complete;
        },
        description: 'mobile voting submission job to start',
        timeout: const Duration(minutes: 2),
      );
      var job = container.read(votingSubmissionJobProvider(draftKey));
      if (!job.isInFlight) {
        fail('Voting submission did not start: ${job.errorMessage}');
      }

      logE2e('waiting on the voting progress screen for submission');
      await pumpUntil(tester, () {
        job = container.read(votingSubmissionJobProvider(draftKey));
        return tester.any(
              find.byKey(
                const ValueKey('mobile_voting_submission_progress_content'),
              ),
            ) ||
            job.status == VotingSubmissionJobStatus.complete ||
            job.status == VotingSubmissionJobStatus.error;
      }, description: 'mobile voting submission progress screen');

      logE2e('waiting for real mobile vote proofs and receipt');
      await pumpUntil(
        tester,
        () {
          job = container.read(votingSubmissionJobProvider(draftKey));
          return job.status == VotingSubmissionJobStatus.complete ||
              job.status == VotingSubmissionJobStatus.error;
        },
        description: 'mobile voting submission to finish',
        timeout: const Duration(minutes: 40),
      );
      if (job.status == VotingSubmissionJobStatus.error) {
        fail('Voting submission failed: ${job.errorMessage}');
      }
      expect(job.status, VotingSubmissionJobStatus.complete);

      const submittedTitleKey = ValueKey('mobile_voting_submitted_title');
      const submittedHomeButtonKey = ValueKey(
        'mobile_voting_submitted_home_button',
      );
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(submittedHomeButtonKey)),
        description: 'mobile voted confirmation screen',
        timeout: const Duration(minutes: 2),
      );
      expect(find.byKey(submittedTitleKey), findsOneWidget);
      await tapAppButton(tester, submittedHomeButtonKey);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_home_coinholder_voting')),
        ),
        description: 'mobile home after completed voting submission',
      );
      expect(
        find.byKey(const ValueKey('mobile_home_coinholder_voting')),
        findsOneWidget,
      );
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<void> _tapVotingOption(
  WidgetTester tester,
  Key key, {
  required Duration timeout,
}) async {
  final row = find.byKey(key);
  final inkWell = find.descendant(of: row, matching: find.byType(InkWell));
  await pumpUntil(
    tester,
    () => tester.any(inkWell) && tester.widget<InkWell>(inkWell).onTap != null,
    description: '$key voting option to become enabled',
    timeout: timeout,
  );
  final hitTestable = inkWell.hitTestable();
  if (tester.any(hitTestable)) {
    await tester.tap(hitTestable);
  } else {
    tester.widget<InkWell>(inkWell).onTap!.call();
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollUntilVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (tester.any(finder)) {
    await tester.ensureVisible(finder);
    return;
  }
  final scrollable = find.byType(Scrollable).last;
  await pumpUntil(
    tester,
    () => tester.any(scrollable),
    description: 'mobile poll list for $key',
  );
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  await tester.pump(const Duration(milliseconds: 250));
}
