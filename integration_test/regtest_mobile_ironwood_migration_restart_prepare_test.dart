import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists a partially broadcast mobile migration for process restart',
    (tester) async {
      tolerateRenderOverflows();
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
      await openMobilePrivateMigrationReview(tester);
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'restart fixture denomination run',
      );
      expect(started.activeRunId, isNotNull);

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.scheduledBroadcasts.length >= 3,
        description: 'multi-transaction restart schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.activeRunId, started.activeRunId);
      expect(scheduled.totalCount, greaterThanOrEqualTo(3));
      expect(
        scheduled.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        hasLength(scheduled.totalCount),
      );

      final firstSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
        submittedTarget: 1,
      );
      expect(firstSubmitted.activeRunId, started.activeRunId);
      expect(
        firstSubmitted.broadcastedTxCount + firstSubmitted.confirmedTxCount,
        1,
      );
      expect(firstSubmitted.totalCount, scheduled.totalCount);
      expect(
        firstSubmitted.scheduledBroadcasts
            .map((entry) => entry.txidHex)
            .toSet(),
        scheduled.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
      );
      await _expectRemainingChildrenWaitForTheirScheduledHeight(
        tester,
        accountUuid,
        firstSubmitted,
      );

      logE2e(
        'stopping after the first scheduled child in run '
        '${started.activeRunId}',
      );
      await snapshotWalletDbToDriver();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _expectRemainingChildrenWaitForTheirScheduledHeight(
  WidgetTester tester,
  String accountUuid,
  rust_sync.MigrationStatus firstSubmitted,
) async {
  final remaining =
      firstSubmitted.scheduledBroadcasts
          .where((entry) => entry.status == 'scheduled')
          .toList()
        ..sort(
          (left, right) =>
              left.scheduledHeight.compareTo(right.scheduledHeight),
        );
  expect(remaining, isNotEmpty);

  final submittedCount =
      firstSubmitted.broadcastedTxCount + firstSubmitted.confirmedTxCount;
  final chain = await getDriver('/status');
  final currentHeight = (chain['zcashdHeight'] as num).toInt();
  final nextHeight = remaining.first.scheduledHeight;
  expect(nextHeight, greaterThan(currentHeight));

  await settle(tester, const Duration(seconds: 2));
  var beforeDue = await mobileRegtestMigrationStatus(accountUuid);
  expect(
    beforeDue.broadcastedTxCount + beforeDue.confirmedTxCount,
    submittedCount,
  );

  final blocksBeforeDue = nextHeight - currentHeight - 1;
  if (blocksBeforeDue > 0) {
    await postDriver('/mine', {'blocks': blocksBeforeDue});
    await settle(tester, const Duration(seconds: 2));
    beforeDue = await mobileRegtestMigrationStatus(accountUuid);
    expect(
      beforeDue.broadcastedTxCount + beforeDue.confirmedTxCount,
      submittedCount,
    );
  }
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
