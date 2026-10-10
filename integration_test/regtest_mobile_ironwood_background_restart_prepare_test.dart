import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/mobile_background_migration_flow.dart';
import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists foreground-approved signed proofs without broadcasting before process restart',
    (tester) async {
      tolerateRenderOverflows();
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await revokeAllBackgroundMigrationAuthorization();
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.23 $mobileE2eTicker');

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
      await openMobilePrivateMigrationOptions(tester);
      await startMobilePrivateMigration(tester);

      final accountUuid = await accountUuidAtOrder(0);
      final initialPreparationDeadline = DateTime.now().add(
        const Duration(minutes: 5),
      );
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'proof-restart denomination run',
        timeout: initialPreparationDeadline.difference(DateTime.now()),
      );
      expect(started.activeRunId, isNotNull);
      expect(started.pendingTxCount, 0);
      expect(started.signedChildPcztCount, greaterThanOrEqualTo(2));

      final preparationReceipt = await waitForMobileInitialPreparationReceipt(
        tester,
        accountUuid,
        started.activeRunId!,
        deadline: initialPreparationDeadline,
      );
      await pauseFlutterAndQuiesceMigrationForNativeOutboxTicks(
        tester,
        container,
      );
      final paused = await mobileRegtestMigrationStatus(accountUuid);
      expect(paused.pendingTxCount, started.pendingTxCount);
      expect(paused.signedChildPcztCount, started.signedChildPcztCount);
      expect(
        paused.broadcastedTxCount + paused.confirmedTxCount,
        started.broadcastedTxCount + started.confirmedTxCount,
      );
      await mineMobileInitialPreparationReceipt(
        preparationReceipt,
        blocks: 50,
        deadline: initialPreparationDeadline,
      );
      final unpreparedTick = await runNativeMigrationOutboxTick();
      expect(unpreparedTick['outcome'], anyOf('noWork', 'waiting'));
      expectNativeOutboxTickDidNotCreateProofs(
        paused,
        await mobileRegtestMigrationStatus(accountUuid),
      );
      final proofed = await prepareForegroundProofsForNativeOutboxTicks(
        tester,
        container,
        accountUuid,
      );

      expect(proofed.activeRunId, paused.activeRunId);
      expect(proofed.pendingTxCount, greaterThanOrEqualTo(1));
      expect(
        proofed.signedChildPcztCount,
        paused.signedChildPcztCount - proofed.pendingTxCount,
      );
      expect(proofed.broadcastedTxCount + proofed.confirmedTxCount, 0);
      expect(proofed.scheduledBroadcasts, hasLength(proofed.pendingTxCount));
      final chain = await getDriver('/status');
      final firstDue = proofed.scheduledBroadcasts
          .map((part) => part.scheduledHeight)
          .reduce((a, b) => a < b ? a : b);
      final tip = (chain['zcashdHeight'] as num).toInt();
      if (firstDue > tip) {
        await postDriver('/mine', {'blocks': firstDue - tip});
      }
      expectNativeOutboxTickDidNotCreateProofs(
        proofed,
        await mobileRegtestMigrationStatus(accountUuid),
      );
      await waitForNativeBackgroundMempoolSize(0);

      await snapshotWalletDbToDriver();
      markMobileE2eAssertionsCompleted();
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
    description: 'idle mobile wallet sync before proof restart',
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
    description: 'active Ironwood chain before proof restart',
    timeout: const Duration(minutes: 5),
  );
}
