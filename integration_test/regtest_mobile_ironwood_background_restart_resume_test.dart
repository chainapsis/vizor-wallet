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
    'broadcasts the persisted proof after process restart without replacing it',
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
      expect(persisted.pendingTxCount, 1);
      expect(persisted.signedChildPcztCount, greaterThanOrEqualTo(1));
      expect(persisted.broadcastedTxCount + persisted.confirmedTxCount, 0);
      expect(persisted.scheduledBroadcasts, hasLength(1));
      final persistedTxid = persisted.scheduledBroadcasts.single.txidHex;

      final wake = await runNativeBackgroundMigrationWake();
      final broadcasted = await mobileRegtestMigrationStatus(accountUuid);
      expect(wake['outcome'], 'advanced');
      expect(broadcasted.activeRunId, runId);
      expect(broadcasted.pendingTxCount, 1);
      expect(broadcasted.signedChildPcztCount, persisted.signedChildPcztCount);
      expect(broadcasted.broadcastedTxCount + broadcasted.confirmedTxCount, 1);
      expect(
        broadcasted.scheduledBroadcasts
            .where((entry) => entry.txidHex == persistedTxid)
            .single
            .status,
        'broadcasted',
      );
      await waitForNativeBackgroundMempoolTxid(persistedTxid);

      await runNativeBackgroundMigrationWake();
      final afterAnotherWake = await mobileRegtestMigrationStatus(accountUuid);
      expect(afterAnotherWake.activeRunId, runId);
      expect(
        afterAnotherWake.broadcastedTxCount + afterAnotherWake.confirmedTxCount,
        1,
      );
      expect(
        afterAnotherWake.scheduledBroadcasts.any(
          (entry) =>
              entry.txidHex == persistedTxid && entry.status == 'broadcasted',
        ),
        isTrue,
      );
      await waitForNativeBackgroundMempoolTxid(persistedTxid);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await enterPasscode(tester, mobileE2ePasscode);
      await waitForHome(tester);
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (activeChain['zcashdHeight'] as num).toInt(),
      );

      await pauseFlutterAndQuiesceMigrationForNativeWakes(tester, container);
      final beforeRemainingWakes = await mobileRegtestMigrationStatus(
        accountUuid,
      );
      final allSubmitted = await runNativeDueWakesUntilSubmitted(
        accountUuid: accountUuid,
        initialStatus: beforeRemainingWakes,
        submittedTarget: beforeRemainingWakes.totalCount,
      );
      expect(allSubmitted.activeRunId, runId);
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );
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
