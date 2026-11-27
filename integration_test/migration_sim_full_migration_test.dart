import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driver = String.fromEnvironment('ZCASH_E2E_DRIVER_URL');
const _funding = int.fromEnvironment('ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(initializeZcashWalletRuntime);

  testWidgets('observe a many-note NU7 migration through Activity', (
    tester,
  ) async {
    await cleanupDesktopRegtestWallet();
    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await importDesktopRegtestWallet(tester);
    final account = await firstDesktopRegtestAccountUuid();
    final db = await getWalletDbPath();
    e2eLog('migration simulation wallet DB: $db');
    final container = ProviderScope.containerOf(
      tester.element(
        find.byKey(const ValueKey('home_desktop_balance_amount_text')),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          container.read(syncProvider).value?.orchardBalance ==
          BigInt.from(_funding),
      description: 'funded Orchard balance before activation',
      timeout: const Duration(minutes: 5),
    );
    await ironwoodDriverPost(_driver, '/activate');
    final chain = await ironwoodDriverGet(_driver, '/status');
    expect(chain['nu7Active'], isTrue);
    final height = chain['zcashdHeight'] as int;
    await pumpUntil(
      tester,
      () {
        final sync = container.read(syncProvider).value;
        return sync?.isSyncComplete == true &&
            (sync?.scannedHeight ?? 0) >= height;
      },
      description: 'wallet synced through NU7',
      timeout: const Duration(minutes: 5),
    );

    await openPrivateMigrationReview(tester);
    final plan = (await container.read(
      ironwoodMigrationPrivatePlanProvider.future,
    ))!;
    expect(plan.totalInputZatoshi, BigInt.from(_funding));
    expect(plan.denominationSplitStageCount, greaterThan(1));
    expect(plan.scheduledTransfers.length, greaterThan(1));
    e2eLog(
      'Reviewed ${plan.denominationSplitStageCount} preparation transactions, '
      '${plan.scheduledTransfers.length} transfers, fee ${plan.estimatedTotalFeeZatoshi} zatoshi',
    );
    await tapAppButton(
      tester,
      const ValueKey('ironwood_migration_authorize_start_button'),
    );
    await waitForDesktopActiveMigrationStatus(tester, preparing: true);
    var status = await waitForDesktopRegtestMigrationStatus(
      tester,
      account,
      (status) => status.activeRunId != null,
      description: 'persisted migration',
    );
    final deadline = DateTime.now().add(const Duration(minutes: 25));
    while (status.phase != kIronwoodMigrationCompletePhase) {
      final chain = await ironwoodDriverGet(_driver, '/status');
      final tip = chain['zcashdHeight'] as int;
      e2eLog(
        'Height $tip: ${status.phase}, prepared '
        '${status.denominationSplitCompletedCount}/${status.denominationSplitTotalCount}, '
        'broadcast ${status.broadcastedTxCount}, confirmed ${status.confirmedTxCount}/${plan.scheduledTransfers.length}',
      );
      if (DateTime.now().isAfter(deadline)) {
        fail('Migration stalled at height $tip in ${status.phase}');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      final next = status.nextActionHeight;
      // Skip empty ranges but keep mining confirmations while the wallet is
      // preparing proofs or waiting for a transaction to become spendable.
      final blocks = next == null || next <= tip ? 1 : next - tip;
      final result = await ironwoodDriverPost(
        _driver,
        '/mine',
        payload: {'blocks': blocks},
      );
      final mined = result['height'] as int;
      await pumpUntil(
        tester,
        () => (container.read(syncProvider).value?.scannedHeight ?? 0) >= mined,
        description: 'wallet sync through block $mined',
        timeout: const Duration(minutes: 2),
      );
      status = await desktopRegtestMigrationStatus(account);
    }
    final complete = status;
    expect(complete.confirmedTxCount, plan.scheduledTransfers.length);
    final balance = await rust_sync.getBalance(
      dbPath: db,
      network: 'regtest',
      accountUuid: account,
    );
    expect(balance.ironwood, plan.totalMigratableZatoshi);
    expect(
      balance.orchard + balance.uneconomicValue,
      plan.orchardChangeZatoshi ?? BigInt.zero,
    );
    expect(
      BigInt.from(_funding) -
          balance.ironwood -
          balance.orchard -
          balance.uneconomicValue,
      plan.estimatedTotalFeeZatoshi,
    );
    e2eLog(
      'Confirmed ${complete.confirmedTxCount} transfers; wallet DB balances in zatoshi: '
      'Orchard ${balance.orchard}, uneconomic ${balance.uneconomicValue}, Ironwood ${balance.ironwood}',
    );
    final request = IronwoodMigrationStatusRequest(
      network: 'regtest',
      accountUuid: account,
    );
    container.invalidate(ironwoodMigrationStatusProvider(request));
    await container.read(ironwoodMigrationStatusProvider(request).future);
    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(const ValueKey('ironwood_migration_status_complete')),
      ),
      description: 'completed migration screen',
    );
    await tapAppButton(
      tester,
      const ValueKey('ironwood_migration_status_action_button'),
    );
    await tapAppWidget(tester, const ValueKey('sidebar_activity_button'));
    await pumpUntil(
      tester,
      () =>
          tester.any(find.text('Migrated to Ironwood')) &&
          tester.any(find.text('Orchard → Ironwood')),
      description: 'confirmed migration in desktop Activity',
    );
    e2eLog(
      'Activity shows the completed migration; Ironwood balance ${balance.ironwood} zatoshi',
    );
    await Future<void>.delayed(const Duration(seconds: 15));
  }, timeout: const Timeout(Duration(minutes: 40)));
}
