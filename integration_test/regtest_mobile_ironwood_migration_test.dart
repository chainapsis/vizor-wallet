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

final _fundedAmount = BigInt.from(1095000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates a mobile software wallet from Orchard to Ironwood',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);
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
      await waitForShieldedBalance(tester, '0.01095 $mobileE2eTicker');

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

      logE2e('activating Ironwood while the mobile app is running');
      await postDriver('/activate', const {});
      await _waitForIronwoodSync(tester, container);
      await openMobilePrivateMigrationReview(tester);

      final approvedPlan = await container.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );
      expect(approvedPlan, isNotNull);
      expect(approvedPlan!.denominationSplitStageCount, 1);
      expect(approvedPlan.plannedBatchCount, 1);
      expect(approvedPlan.totalMigratableZatoshi, BigInt.from(1000000));
      expect(approvedPlan.estimatedTotalFeeZatoshi, BigInt.from(95000));

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_migration_status_preparing'),
          ),
        ),
        description: 'mobile migration preparing screen',
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'mobile denomination migration run',
      );
      expect(started.activeRunId, isNotNull);

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.scheduledBroadcasts.isNotEmpty,
        description: 'mobile persisted migration schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.totalCount, approvedPlan.plannedBatchCount);
      expect(
        scheduled.scheduledBroadcasts.map((entry) => entry.valueZatoshi),
        approvedPlan.scheduledTransfers.map((entry) => entry.valueZatoshi),
      );

      final firstSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
        submittedTarget: 1,
      );
      expect(
        firstSubmitted.broadcastedTxCount + firstSubmitted.confirmedTxCount,
        1,
      );

      final allSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description: 'completed mobile Ironwood migration',
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

      await waitForHome(tester);
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(
            const ValueKey('mobile_home_ironwood_migration_required_pill'),
          ),
        ),
        description: 'completed migration CTA to disappear',
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
    description: 'idle mobile wallet sync at $targetHeight',
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
    description: 'active Ironwood chain and completed mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
