import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_background_migration_flow.dart';
import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'paused native outbox ticks send approved children while BGManager denies notifications',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        resumeFlutterAfterNativeBackgroundMigration(tester);
        try {
          await postDriver('/lightwalletd/start', const {});
        } catch (_) {
          // The runner resets the stack after a failed recovery attempt.
        }
        await revokeAllBackgroundMigrationAuthorization(ignoreErrors: true);
        await cleanupE2eWalletState();
      });
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
        description: 'native outbox denomination run',
        timeout: initialPreparationDeadline.difference(DateTime.now()),
      );
      expect(started.activeRunId, isNotNull);
      expect(started.totalCount, greaterThanOrEqualTo(2));
      expect(started.pendingTxCount, 0);
      expect(started.signedChildPcztCount, greaterThanOrEqualTo(2));

      final submittedBefore =
          started.broadcastedTxCount + started.confirmedTxCount;
      expect(started.totalCount - submittedBefore, greaterThanOrEqualTo(2));

      final preparationReceipt = await waitForMobileInitialPreparationReceipt(
        tester,
        accountUuid,
        started.activeRunId!,
        deadline: initialPreparationDeadline,
      );
      // Pause Flutter before the chain advances so no foreground coordinator
      // work can be mistaken for native outbox transport progress.
      await pauseFlutterAndQuiesceMigrationForNativeOutboxTicks(
        tester,
        container,
      );
      final paused = await mobileRegtestMigrationStatus(accountUuid);
      expect(paused.pendingTxCount, started.pendingTxCount);
      expect(paused.signedChildPcztCount, started.signedChildPcztCount);
      expect(
        paused.broadcastedTxCount + paused.confirmedTxCount,
        submittedBefore,
      );
      // Make the denomination stage trusted and every regtest schedule offset
      // due while only the native outbox runner is allowed to advance.
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
      await waitForNativeBackgroundMempoolSize(0);

      // Proofs require the actual foreground approval UI. Native ticks below
      // receive only already materialized signed transaction bytes.
      final firstProof = await prepareForegroundProofsForNativeOutboxTicks(
        tester,
        container,
        accountUuid,
      );
      final firstProofTxids = firstProof.scheduledBroadcasts
          .map((entry) => entry.txidHex)
          .toSet();
      expect(firstProofTxids, hasLength(firstProof.pendingTxCount));
      expect(firstProofTxids, isNotEmpty);
      final nextDue = firstProof.scheduledBroadcasts
          .map((entry) => entry.scheduledHeight)
          .reduce((a, b) => a < b ? a : b);
      final tip = (await getDriver('/status'))['zcashdHeight'] as num;
      if (nextDue > tip.toInt()) {
        await postDriver('/mine', {'blocks': nextDue - tip.toInt()});
      }

      // Prove denial with runnable signed bytes, not an empty outbox or a hold.
      // Not Now intentionally permits foreground preparation only.
      expect(tester.binding.lifecycleState, AppLifecycleState.paused);
      expect(
        (await getDriver('/status'))['zcashdHeight'] as num,
        greaterThanOrEqualTo(nextDue),
      );
      final beforeManagerDenial = await mobileRegtestMigrationStatus(
        accountUuid,
      );
      expect(beforeManagerDenial.pendingTxCount, greaterThan(0));
      expect(
        beforeManagerDenial.scheduledBroadcasts.any(
          (entry) =>
              entry.status == 'scheduled' && entry.scheduledHeight <= nextDue,
        ),
        isTrue,
      );
      expect(
        await nativeMigrationReceipts(accountUuid, started.activeRunId!),
        isEmpty,
      );
      await waitForNativeBackgroundMempoolSize(0);
      await expectNativeBackgroundManagerDeniedWithoutNotifications();
      final afterManagerDenial = await mobileRegtestMigrationStatus(
        accountUuid,
      );
      expectNativeOutboxTickDidNotCreateProofs(
        beforeManagerDenial,
        afterManagerDenial,
      );
      expect(afterManagerDenial.phase, beforeManagerDenial.phase);
      expect(
        afterManagerDenial.broadcastedTxCount,
        beforeManagerDenial.broadcastedTxCount,
      );
      expect(
        afterManagerDenial.confirmedTxCount,
        beforeManagerDenial.confirmedTxCount,
      );
      expect(
        await nativeMigrationReceipts(accountUuid, started.activeRunId!),
        isEmpty,
      );
      await waitForNativeBackgroundMempoolSize(0);

      await postDriver('/lightwalletd/stop', const {});
      final failedTick = await runNativeMigrationOutboxTick();
      final whileOffline = await mobileRegtestMigrationStatus(accountUuid);
      expect(failedTick['outcome'], 'temporarilyUnavailable');
      expect(whileOffline.activeRunId, firstProof.activeRunId);
      expectNativeOutboxTickDidNotCreateProofs(firstProof, whileOffline);
      expect(whileOffline.pendingTxCount, firstProof.pendingTxCount);
      expect(
        whileOffline.signedChildPcztCount,
        firstProof.signedChildPcztCount,
      );
      expect(
        whileOffline.broadcastedTxCount + whileOffline.confirmedTxCount,
        submittedBefore,
      );
      expect(
        whileOffline.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        firstProofTxids,
      );
      await waitForNativeBackgroundMempoolSize(0);
      expect(
        await nativeMigrationReceipts(accountUuid, started.activeRunId!),
        isEmpty,
      );

      await postDriver(
        '/lightwalletd/start',
        const {},
        timeout: const Duration(minutes: 5),
      );
      final recoveredTick = await runNativeMigrationOutboxTick();
      final afterRecovery = await mobileRegtestMigrationStatus(accountUuid);
      expect(recoveredTick['outcome'], 'accepted');
      final receipts = await nativeMigrationReceipts(
        accountUuid,
        started.activeRunId!,
      );
      expect(receipts, hasLength(1));
      await expectAcceptedNativeMigrationReceipt(
        receipts.single,
        firstProofTxids,
      );
      expectNativeOutboxTickDidNotCreateProofs(firstProof, afterRecovery);
      expect(afterRecovery.pendingTxCount, firstProof.pendingTxCount);
      expect(
        afterRecovery.signedChildPcztCount,
        firstProof.signedChildPcztCount,
      );
      expect(
        afterRecovery.broadcastedTxCount + afterRecovery.confirmedTxCount,
        submittedBefore,
      );
      expect(
        afterRecovery.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        firstProofTxids,
      );
      await waitForNativeBackgroundMempoolTxid(
        receipts.single['txidHex']! as String,
      );
      final reconciled = await reconcileNativeMigrationReceipts(
        tester,
        container,
        accountUuid,
      );
      expectNativeOutboxTickDidNotCreateProofs(firstProof, reconciled);
      expect(
        reconciled.broadcastedTxCount + reconciled.confirmedTxCount,
        submittedBefore + 1,
      );

      final afterSecond = await runNativeDueOutboxTicksUntilSubmitted(
        tester: tester,
        container: container,
        accountUuid: accountUuid,
        initialStatus: reconciled,
        submittedTarget: submittedBefore + 2,
      );

      expect(
        afterSecond.broadcastedTxCount + afterSecond.confirmedTxCount,
        submittedBefore + 2,
      );
      expect(afterSecond.activeRunId, started.activeRunId);
      expect(afterSecond.totalCount, started.totalCount);
      final allSubmitted = await runNativeDueOutboxTicksUntilSubmitted(
        tester: tester,
        container: container,
        accountUuid: accountUuid,
        initialStatus: afterSecond,
        submittedTarget: started.totalCount,
      );
      final duplicateTick = await runNativeMigrationOutboxTick();
      expect(duplicateTick['outcome'], anyOf('noWork', 'waiting'));
      final afterDuplicate = await mobileRegtestMigrationStatus(accountUuid);
      expectNativeOutboxTickDidNotCreateProofs(allSubmitted, afterDuplicate);
      expect(
        afterDuplicate.broadcastedTxCount + afterDuplicate.confirmedTxCount,
        started.totalCount,
      );
      expect(
        await nativeMigrationReceipts(accountUuid, started.activeRunId!),
        isEmpty,
      );
      resumeFlutterAfterNativeBackgroundMigration(tester);
      await postDriver('/mine', const {'blocks': 10});
      final completed = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description:
            'foreground confirmation reconciliation after native transport',
      );
      expect(completed.activeRunId, isNull);
      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(
        balance.ironwood,
        started.targetValuesZatoshi.fold<BigInt>(
          BigInt.zero,
          (total, value) => total + value,
        ),
      );
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
