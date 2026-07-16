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
  defaultValue: 'http://127.0.0.1:39083',
);
const _fundingTxCount = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_TX_COUNT',
  defaultValue: 4,
);
final _fundedAmount = BigInt.from(1000020000);
final _expectedReceiveAmounts = [
  BigInt.from(100002000),
  BigInt.from(200004000),
  BigInt.from(300006000),
  BigInt.from(400008000),
];
final _expectedSplitFee = BigInt.from(160000);
final _expectedMigrationFee = BigInt.from(150000);
final _expectedTotalFee = _expectedSplitFee + _expectedMigrationFee;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates uneven Orchard notes received across four transactions',
    (tester) async {
      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();
      expect(_fundingTxCount, 4);

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
        description: 'mixed-note pre-Ironwood Orchard balance',
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
      await _expectFundingHistory(tester, accountUuid);
      final initialBalance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(initialBalance.sapling, BigInt.zero);
      expect(initialBalance.orchard, _fundedAmount);
      expect(initialBalance.ironwood, BigInt.zero);

      await ironwoodDriverPost(_driverUrl, '/activate');
      await _waitForIronwoodSync(tester, container);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'mixed-note Ironwood announcement',
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
      _expectMixedNotePlan(migrationPlan);

      await openPrivateMigrationReview(tester);
      expect(
        find.text('${migrationPlan.plannedBatchCount} Planned batches'),
        findsOneWidget,
      );
      expect(find.text('Total, ~0.0031 ZEC'), findsOneWidget);

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
        description: 'first mixed-note denomination stage',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);
      expect(started.totalCount, migrationPlan.plannedBatchCount);
      expect(started.preparedNoteCount, migrationPlan.plannedBatchCount);
      expect((await _waitForMempool(tester, (size) => size == 1))['size'], 1);

      e2eLog('confirming mixed-note denomination stage 1/2');
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
        description: 'mixed-note denomination progress 1/2',
      );
      expect(firstStageConfirmed.pendingSplitStageCount, 2);
      expect((await _waitForMempool(tester, (size) => size == 1))['size'], 1);

      e2eLog('confirming mixed-note denomination stage 2/2');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final migrationStarted = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.denominationSplitCompletedCount == 2 &&
            status.totalCount == migrationPlan.plannedBatchCount &&
            status.broadcastedTxCount > 0,
        description: 'mixed-note migration broadcasts',
        timeout: const Duration(minutes: 5),
      );
      expect(migrationStarted.pendingSplitStageCount, 0);

      final allSubmitted = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.broadcastedTxCount + status.confirmedTxCount ==
                status.totalCount,
        description: 'all mixed-note migration broadcasts',
        timeout: const Duration(minutes: 6),
      );
      expect(allSubmitted.totalCount, 10);
      expect(
        allSubmitted.scheduledBroadcasts.where(
          (broadcast) => broadcast.status == 'scheduled',
        ),
        isEmpty,
      );

      e2eLog('confirming all mixed-note migration transactions');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'completed mixed-note migration',
      );
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_status_complete')),
        ),
        description: 'mixed-note completion UI',
        timeout: const Duration(minutes: 5),
      );

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(balance.orchard, BigInt.zero);
      expect(
        balance.ironwood,
        migrationPlan.totalMigratableZatoshi -
            migrationPlan.migrationFeeZatoshi,
      );
      expect(_fundedAmount - balance.ironwood, _expectedTotalFee);
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}

Future<void> _expectFundingHistory(
  WidgetTester tester,
  String accountUuid,
) async {
  final dbPath = await getWalletDbPath();
  final end = DateTime.now().add(const Duration(minutes: 2));
  List<rust_sync.TransactionInfo> received = const [];
  while (DateTime.now().isBefore(end)) {
    final history = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: 'regtest',
      limit: 20,
      accountUuid: accountUuid,
    );
    received = history.where((tx) => tx.txKind == 'received').toList();
    if (received.length == _fundingTxCount) break;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  expect(received, hasLength(_fundingTxCount));
  expect(received.map((tx) => tx.txidHex).toSet(), hasLength(_fundingTxCount));
  expect(
    received.map((tx) => tx.displayAmount),
    unorderedEquals(_expectedReceiveAmounts),
  );
  expect(
    received.map((tx) => tx.minedHeight),
    everyElement(greaterThan(BigInt.zero)),
  );
}

void _expectMixedNotePlan(rust_sync.OrchardMigrationPrivatePlan plan) {
  expect(plan.totalInputZatoshi, _fundedAmount);
  expect(plan.plannedBatchCount, 10);
  expect(plan.targetValuesZatoshi, hasLength(plan.plannedBatchCount));
  expect(plan.denominationSplitStageCount, 2);
  expect(plan.denominationSplitFeeZatoshi, _expectedSplitFee);
  expect(plan.migrationFeeZatoshi, _expectedMigrationFee);
  expect(plan.estimatedTotalFeeZatoshi, _expectedTotalFee);
  expect(plan.orchardChangeZatoshi, isNull);
  expect(_sumTargets(plan.targetValuesZatoshi), plan.totalMigratableZatoshi);
  expect(
    plan.totalInputZatoshi - plan.totalMigratableZatoshi,
    plan.denominationSplitFeeZatoshi,
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
    description: 'idle mixed-note wallet sync at $targetHeight',
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
    description: 'active Ironwood mixed-note sync',
    timeout: const Duration(minutes: 5),
  );
}
