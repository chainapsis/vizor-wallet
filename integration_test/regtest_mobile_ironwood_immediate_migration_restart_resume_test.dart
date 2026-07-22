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
    'broadcasts the same immediate migration after network and process recovery',
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

      expect(runId, isNotNull);
      expect(persisted.broadcastedTxCount, 0);
      expect(persisted.confirmedTxCount, 0);
      expect(originalTxids, hasLength(persisted.totalCount));

      await postDriver(
        '/lightwalletd/start',
        const {},
        timeout: const Duration(minutes: 5),
      );
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await enterPasscode(tester, mobileE2ePasscode);
      await waitForHome(tester);

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      final chain = await getDriver('/status');
      await _waitForIdleSync(
        tester,
        container,
        (chain['zcashdHeight'] as num).toInt(),
      );

      final submitted = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.broadcastedTxCount + status.confirmedTxCount ==
                status.totalCount,
        description: 'automatic immediate migration broadcast after restart',
        timeout: const Duration(minutes: 5),
      );
      expect(submitted.totalCount, persisted.totalCount);
      expect(
        submitted.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        originalTxids,
      );
      await waitForMobileRegtestMempoolSize(tester, submitted.totalCount);

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == persisted.totalCount &&
            status.activeRunId == null,
        description: 'immediate migration completion after restart',
        timeout: const Duration(minutes: 5),
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(balance.ironwood, expectedIronwood);
      expect(balance.orchard + balance.uneconomicValue, BigInt.zero);
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
    description: 'mobile wallet sync after immediate migration restart',
    timeout: const Duration(minutes: 5),
  );
}
