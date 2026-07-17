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

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39082',
);
final _fundedAmount = BigInt.from(1000020000);
final _expectedSplitFee = BigInt.from(160000);
final _expectedMigrationFee = BigInt.from(135000);
final _expectedTotalFee = _expectedSplitFee + _expectedMigrationFee;
final _expectedOrchardChange = BigInt.from(725000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates twenty Orchard notes through a chained denomination split',
    (tester) async {
      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      await pumpUntil(
        tester,
        () =>
            textForKey(
              tester,
              const ValueKey('home_desktop_balance_amount_text'),
            ) ==
            '10.0002',
        description: 'twenty-note pre-Ironwood Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await firstDesktopRegtestAccountUuid();
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        initialChain['zcashdHeight'] as num,
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      await _waitForIronwoodSync(tester, container);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'many-note Ironwood announcement',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);

      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(plan, isNotNull);
      final migrationPlan = plan!;
      _expectManyNotePlan(migrationPlan);

      await openPrivateMigrationReview(tester);
      expect(
        find.text('${migrationPlan.plannedBatchCount} Planned batches'),
        findsOneWidget,
      );
      expect(find.text('Total, ~0.0029 ZEC'), findsOneWidget);

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_authorize_start_button'),
      );
      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == 'waiting_denom_confirmations' &&
            status.denominationSplitTotalCount == 2 &&
            status.denominationSplitCompletedCount == 0 &&
            status.pendingSplitStageCount == 2,
        description: 'first many-note denomination stage',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);
      expect(started.totalCount, migrationPlan.plannedBatchCount);
      expect(started.preparedNoteCount, migrationPlan.plannedBatchCount);
      expect((await _waitForMempool(tester, (size) => size == 1))['size'], 1);

      e2eLog('confirming many-note denomination stage 1/2');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final firstStageConfirmed = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.phase == 'waiting_denom_confirmations' &&
            status.denominationSplitCompletedCount == 1 &&
            status.denominationSplitTotalCount == 2,
        description: 'many-note denomination progress 1/2',
      );
      expect(firstStageConfirmed.pendingSplitStageCount, 2);
      expect((await _waitForMempool(tester, (size) => size == 1))['size'], 1);

      e2eLog('confirming many-note denomination stage 2/2');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final scheduled = await prepareDesktopRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(scheduled.activeRunId, runId);
      expect(scheduled.denominationSplitCompletedCount, 2);
      expect(scheduled.pendingSplitStageCount, 0);
      expect(scheduled.scheduledBroadcasts, hasLength(9));

      final allSubmitted = await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
        timeout: const Duration(minutes: 6),
      );
      expect(allSubmitted.activeRunId, runId);
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );
      expect(allSubmitted.totalCount, 9);
      expect(
        allSubmitted.scheduledBroadcasts.where(
          (broadcast) => broadcast.status == 'scheduled',
        ),
        isEmpty,
      );

      e2eLog('confirming all many-note migration transactions');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'completed many-note migration',
      );
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_status_complete')),
        ),
        description: 'many-note completion UI',
        timeout: const Duration(minutes: 5),
      );

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(
        balance.orchard,
        migrationPlan.orchardChangeZatoshi ?? BigInt.zero,
      );
      expect(balance.ironwood, migrationPlan.totalMigratableZatoshi);
      expect(
        _fundedAmount - balance.orchard - balance.ironwood,
        _expectedTotalFee,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

void _expectManyNotePlan(rust_sync.OrchardMigrationPrivatePlan plan) {
  expect(plan.totalInputZatoshi, _fundedAmount);
  expect(plan.plannedBatchCount, 9);
  expect(plan.targetValuesZatoshi, hasLength(plan.plannedBatchCount));
  expect(plan.denominationSplitStageCount, 2);
  expect(plan.denominationSplitFeeZatoshi, _expectedSplitFee);
  expect(plan.migrationFeeZatoshi, _expectedMigrationFee);
  expect(plan.estimatedTotalFeeZatoshi, _expectedTotalFee);
  expect(plan.orchardChangeZatoshi, _expectedOrchardChange);
  expect(_sumTargets(plan.targetValuesZatoshi), plan.totalMigratableZatoshi);
  expect(
    plan.totalInputZatoshi -
        plan.totalMigratableZatoshi -
        plan.orchardChangeZatoshi!,
    plan.estimatedTotalFeeZatoshi,
  );
}

Future<void> _refreshMigrationStatusUi(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
) async {
  final request = IronwoodMigrationStatusRequest(
    network: 'regtest',
    accountUuid: accountUuid,
  );
  container.invalidate(ironwoodMigrationStatusProvider(request));
  await container.read(ironwoodMigrationStatusProvider(request).future);
  await tester.pump();
}

Future<Map<String, Object?>> _waitForMempool(
  WidgetTester tester,
  bool Function(int size) condition,
) async {
  final end = DateTime.now().add(const Duration(minutes: 2));
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(end)) {
    last = await ironwoodDriverGet(_driverUrl, '/mempool');
    if (condition(last['size'] as int)) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for migration mempool condition. Last: $last');
}

BigInt _sumTargets(Iterable<BigInt> values) {
  return values.fold(BigInt.zero, (sum, value) => sum + value);
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  num targetHeight,
) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= targetHeight;
    },
    description: 'idle many-note wallet sync at $targetHeight',
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
    description: 'active Ironwood many-note sync',
    timeout: const Duration(minutes: 5),
  );
}
