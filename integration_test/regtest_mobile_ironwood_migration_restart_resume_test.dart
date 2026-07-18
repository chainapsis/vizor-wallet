import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'reschedules overdue children and completes after a mobile process restart',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);

      final activeChain = await getDriver('/status');
      expect(activeChain['ironwoodActive'], isTrue);

      await restoreWalletDbFromDriver();
      final accountUuid = await accountUuidAtOrder(0);
      final persisted = await mobileRegtestMigrationStatus(accountUuid);
      final runId = persisted.activeRunId;
      final originalTxids = persisted.scheduledBroadcasts
          .map((entry) => entry.txidHex)
          .toSet();
      final expectedIronwood = persisted.targetValuesZatoshi.fold<BigInt>(
        BigInt.zero,
        (total, value) => total + value,
      );
      final submittedBeforeRestart =
          persisted.broadcastedTxCount + persisted.confirmedTxCount;

      expect(runId, isNotNull);
      expect(persisted.totalCount, greaterThanOrEqualTo(3));
      expect(submittedBeforeRestart, 1);
      expect(originalTxids, hasLength(persisted.totalCount));

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

      await tapWidget(
        tester,
        const ValueKey('mobile_home_ironwood_migration_required_pill'),
        timeout: const Duration(minutes: 2),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_migration_status_migrating'),
          ),
        ),
        description: 'persisted mobile migration screen after restart',
        timeout: const Duration(minutes: 2),
      );

      final recovered = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.broadcastedTxCount + status.confirmedTxCount >
                submittedBeforeRestart,
        description: 'one overdue child to submit after restart',
        timeout: const Duration(minutes: 5),
      );
      expect(
        recovered.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        originalTxids,
      );
      expect(recovered.totalCount, persisted.totalCount);

      final chainAfterRecovery = await getDriver('/status');
      final currentHeight = (chainAfterRecovery['zcashdHeight'] as num).toInt();
      final remaining = recovered.scheduledBroadcasts
          .where((entry) => entry.status == 'scheduled')
          .toList();
      expect(remaining, isNotEmpty);
      expect(
        remaining.every((entry) => entry.scheduledHeight > currentHeight),
        isTrue,
      );

      final allSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(allSubmitted.activeRunId, runId);
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );
      expect(
        allSubmitted.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        originalTxids,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description: 'mobile migration completion after restart',
        timeout: const Duration(minutes: 5),
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(balance.ironwood, expectedIronwood);
      await waitForHome(tester);
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
    description: 'mobile wallet sync after process restart',
    timeout: const Duration(minutes: 5),
  );
}
