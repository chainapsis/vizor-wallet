import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

final _fundedAmount = BigInt.from(1100000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'resumes the same mobile migration after lightwalletd returns',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        try {
          await postDriver('/lightwalletd/start', const {});
        } catch (_) {
          // The runner resets the stack after a failed recovery attempt.
        }
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '0.011 $mobileE2eTicker');

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
      );

      await postDriver('/activate', const {});
      await _waitForIronwoodSync(tester, container);
      await openMobilePrivateMigrationReview(tester);
      final approvedPlan = await container.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );
      expect(approvedPlan, isNotNull);

      logE2e('stopping lightwalletd before the first migration broadcast');
      await postDriver('/lightwalletd/stop', const {});
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final interrupted = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'persisted migration while lightwalletd is unavailable',
        timeout: const Duration(minutes: 5),
      );
      final runId = interrupted.activeRunId;
      expect(runId, isNotNull);
      await waitForMobileRegtestMempoolSize(tester, 0);

      logE2e('starting lightwalletd and waiting for automatic migration retry');
      await postDriver(
        '/lightwalletd/start',
        const {},
        timeout: const Duration(minutes: 5),
      );
      await waitForMobileRegtestMempoolSize(
        tester,
        1,
        timeout: const Duration(minutes: 5),
      );

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.scheduledBroadcasts.isNotEmpty,
        description: 'migration schedule after network recovery',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.totalCount, approvedPlan!.plannedBatchCount);

      final submitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(submitted.activeRunId, runId);
      expect(
        submitted.broadcastedTxCount + submitted.confirmedTxCount,
        submitted.totalCount,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description: 'completed migration after network recovery',
        timeout: const Duration(minutes: 5),
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(balance.ironwood, approvedPlan.totalMigratableZatoshi);
      expect(orchardResidual, approvedPlan.orchardChangeZatoshi ?? BigInt.zero);
      expect(
        _fundedAmount - balance.ironwood - orchardResidual,
        approvedPlan.estimatedTotalFeeZatoshi,
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  int targetHeight,
) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= targetHeight;
    },
    description: 'idle mobile network-recovery sync at $targetHeight',
    timeout: const Duration(minutes: 5),
  );
}

Future<void> _waitForIronwoodSync(
  WidgetTester tester,
  ProviderContainer container,
) {
  return pumpUntil(
    tester,
    () {
      final chain = container.read(chainUpgradeStatusProvider).value;
      final sync = container.read(syncProvider).value;
      return chain?.ironwoodActiveAtTip == true &&
          sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= 500;
    },
    description: 'active Ironwood network-recovery sync',
    timeout: const Duration(minutes: 5),
  );
}
