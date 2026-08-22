import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart' show desktopRegtestMnemonic;
import 'support/mobile_regtest_flow.dart';

const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');

/// Mobile counterpart of `regtest_voting_test.dart`: re-imports the wallet
/// the setup invocation migrated (the iOS test runner reinstalls the app
/// between invocations, so the wallet DB never survives — the Ironwood notes
/// are rediscovered from the regtest chain), then completes a real-proof
/// vote through the mobile voting flow.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'imports the Ironwood wallet and completes a real mobile regtest vote',
    (tester) async {
      if (_roundId.length != 64) {
        fail('ZCASH_E2E_VOTE_ROUND_ID must be a 64-character round id.');
      }
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);
      await cleanupE2eWalletState();

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: desktopRegtestMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      final account = container.read(accountProvider).value!.accounts.single;
      final dbPath = await getWalletDbPath();

      logE2e('waiting for the migrated Ironwood balance to sync');
      rust_sync.WalletBalance? balance;
      final syncDeadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(syncDeadline)) {
        await tester.pump(const Duration(seconds: 1));
        balance = await rust_sync.getBalance(
          dbPath: dbPath,
          network: 'regtest',
          accountUuid: account.uuid,
        );
        if (balance.ironwood > BigInt.zero) break;
      }
      expect(
        balance?.ironwood,
        greaterThan(BigInt.zero),
        reason: 'the setup invocation must have created Ironwood notes',
      );

      logE2e('opening signed regtest voting round $_roundId');
      await tapWidget(tester, const ValueKey('mobile_home_voting_entry'));
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
        description: 'voting session round to load',
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
        description: 'Ironwood voting eligibility to confirm',
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
      logE2e(
        'eligibility confirmed at '
        '${eligibleSession.eligibleWeightZatoshi} zatoshi',
      );

      final accountUuid = eligibleSession.accountUuid;
      expect(accountUuid, isNotNull);
      final draftKey = VotingSessionKey(
        roundId: _roundId,
        accountUuid: accountUuid!,
      );

      for (var proposalId = 1; proposalId <= 4; proposalId++) {
        await _scrollUntilVisible(
          tester,
          ValueKey('voting_proposal_${proposalId}_option_0'),
        );
        await tapWidget(
          tester,
          ValueKey('voting_proposal_${proposalId}_option_0'),
          timeout: const Duration(minutes: 10),
        );
        await pumpUntil(
          tester,
          () =>
              container
                  .read(votingDraftProvider(draftKey))
                  .choices[proposalId] ==
              0,
          description: 'proposal $proposalId selection to persist',
        );
        logE2e('selected proposal $proposalId');
      }
      expect(container.read(votingDraftProvider(draftKey)).choices, {
        1: 0,
        2: 0,
        3: 0,
        4: 0,
      });
      await tapAppButton(
        tester,
        const ValueKey('voting_review_answers_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('voting_confirm_submit_button'),
      );

      logE2e('waiting for real delegation, commitment, and share proofs');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('voting_submission_done_button')),
        ),
        description: 'confirmed voting receipt',
        timeout: const Duration(minutes: 40),
      );
      final done = find.byKey(const ValueKey('voting_submission_done_button'));
      final button = tester.widget<AppButton>(done);
      expect(button.onPressed, isNotNull);
      logE2e('vote completed and confirmation receipt is actionable');
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
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
    description: 'poll detail list for $key',
  );
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  await tester.pump(const Duration(milliseconds: 250));
}
