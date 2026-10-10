import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_background_migration_flow.dart';
import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'paused native outbox transports persisted signed bytes after process restart',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        resumeFlutterAfterNativeBackgroundMigration(tester);
        await revokeAllBackgroundMigrationAuthorization(ignoreErrors: true);
        await cleanupE2eWalletState();
      });

      final activeChain = await getDriver('/status');
      expect(activeChain['ironwoodActive'], isTrue);

      await restoreWalletDbFromDriver();
      final accountUuid = await accountUuidAtOrder(0);
      final persisted = await mobileRegtestMigrationStatus(accountUuid);
      final runId = persisted.activeRunId;
      final expectedIronwood = persisted.targetValuesZatoshi.fold<BigInt>(
        BigInt.zero,
        (total, value) => total + value,
      );

      expect(runId, isNotNull);
      expect(persisted.pendingTxCount, greaterThanOrEqualTo(1));
      expect(persisted.signedChildPcztCount, greaterThanOrEqualTo(0));
      expect(persisted.broadcastedTxCount + persisted.confirmedTxCount, 0);
      expect(
        persisted.scheduledBroadcasts,
        hasLength(persisted.pendingTxCount),
      );
      final persistedTxids = persisted.scheduledBroadcasts
          .map((part) => part.txidHex)
          .toSet();

      pauseFlutterForNativeBackgroundMigration(tester);
      final tick = await runNativeMigrationOutboxTick();
      final broadcasted = await mobileRegtestMigrationStatus(accountUuid);
      expect(tick['outcome'], 'accepted');
      final receipts = await nativeMigrationReceipts(accountUuid, runId!);
      expect(receipts, hasLength(1));
      await expectAcceptedNativeMigrationReceipt(
        receipts.single,
        persistedTxids,
      );
      final persistedTxid = receipts.single['txidHex']! as String;
      expectNativeOutboxTickDidNotCreateProofs(persisted, broadcasted);
      expect(broadcasted.activeRunId, runId);
      expect(broadcasted.pendingTxCount, persisted.pendingTxCount);
      expect(broadcasted.signedChildPcztCount, persisted.signedChildPcztCount);
      expect(broadcasted.broadcastedTxCount + broadcasted.confirmedTxCount, 0);
      expect(
        broadcasted.scheduledBroadcasts
            .where((entry) => entry.txidHex == persistedTxid)
            .single
            .status,
        'scheduled',
      );
      await waitForNativeBackgroundMempoolTxid(persistedTxid);

      late ProviderContainer container;
      // Bootstrap under an independently owned native admission hold: neither
      // a foreground transport retry nor an OS task can take SendTx credit.
      await withNativeMigrationTransportHeld(() async {
        resumeFlutterAfterNativeBackgroundMigration(tester);
        await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
        await enterPasscode(tester, mobileE2ePasscode);
        await waitForHome(tester);
        container = ProviderScope.containerOf(
          tester.element(
            find.byKey(const ValueKey('mobile_home_shielded_balance')),
          ),
        );
        await _waitForIdleSync(
          tester,
          container,
          (activeChain['zcashdHeight'] as num).toInt(),
        );
        pauseFlutterForNativeBackgroundMigration(tester);
      });
      final beforeRemainingTicks = await reconcileNativeMigrationReceipts(
        tester,
        container,
        accountUuid,
      );
      expectNativeOutboxTickDidNotCreateProofs(persisted, beforeRemainingTicks);
      expect(
        beforeRemainingTicks.broadcastedTxCount +
            beforeRemainingTicks.confirmedTxCount,
        1,
      );
      expect(
        beforeRemainingTicks.scheduledBroadcasts
            .where((part) => part.txidHex == persistedTxid)
            .single
            .status,
        'broadcasted',
      );
      final allSubmitted = await runNativeDueOutboxTicksUntilSubmitted(
        tester: tester,
        container: container,
        accountUuid: accountUuid,
        initialStatus: beforeRemainingTicks,
        submittedTarget: beforeRemainingTicks.totalCount,
      );
      expect(allSubmitted.activeRunId, runId);
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );
      final duplicateTick = await runNativeMigrationOutboxTick();
      expect(duplicateTick['outcome'], anyOf('noWork', 'waiting'));
      final afterDuplicate = await mobileRegtestMigrationStatus(accountUuid);
      expectNativeOutboxTickDidNotCreateProofs(allSubmitted, afterDuplicate);
      expect(
        afterDuplicate.broadcastedTxCount + afterDuplicate.confirmedTxCount,
        allSubmitted.totalCount,
      );
      expect(await nativeMigrationReceipts(accountUuid, runId), isEmpty);
      resumeFlutterAfterNativeBackgroundMigration(tester);

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description: 'migration completion after proof restart',
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(balance.ironwood, expectedIronwood);
      markMobileE2eAssertionsCompleted();
    },
    timeout: const Timeout(Duration(minutes: 20)),
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
    description: 'mobile wallet sync after proof restart',
    timeout: const Duration(minutes: 5),
  );
}
