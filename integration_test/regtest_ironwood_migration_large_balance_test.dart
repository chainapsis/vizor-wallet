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
  defaultValue: 'http://127.0.0.1:39081',
);
final _fundedAmount = BigInt.from(9900020000);
final _expectedSplitFee = BigInt.from(80000);
final _expectedMigrationFee = BigInt.from(180000);
final _expectedTotalFee = _expectedSplitFee + _expectedMigrationFee;
final _expectedOrchardChange = BigInt.from(760000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'batches a large Orchard balance across split and migration transactions',
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
            '99.0002',
        description: 'large pre-Ironwood Orchard balance',
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
        description: 'large-balance Ironwood announcement',
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
      _expectLargePlan(migrationPlan);

      await openPrivateMigrationReview(tester);
      expect(
        find.text('${migrationPlan.plannedBatchCount} Planned batches'),
        findsOneWidget,
      );
      expect(find.text('Total, ~0.0026 ZEC'), findsOneWidget);
      expect(find.text('~0.0076 ZEC'), findsOneWidget);

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_authorize_start_button'),
      );
      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == 'waiting_denom_confirmations' &&
            status.denominationSplitTotalCount == 1 &&
            status.denominationSplitCompletedCount == 0 &&
            status.pendingSplitStageCount == 1,
        description: 'large-balance denomination stage',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);
      _expectRunMatchesPlan(started, migrationPlan);
      expect((await _waitForMempool(tester, (size) => size == 1))['size'], 1);

      e2eLog('confirming large-balance denomination stage');
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
      expect(scheduled.denominationSplitCompletedCount, 1);
      expect(scheduled.totalCount, migrationPlan.plannedBatchCount);
      expect(scheduled.pendingSplitStageCount, 0);
      expect(scheduled.scheduledBroadcasts, hasLength(12));

      final firstChild = await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
        submittedTarget: 1,
      );
      expect(firstChild.broadcastedTxCount, 1);
      expect(firstChild.confirmedTxCount, 0);
      expect(firstChild.broadcastedTxCount, lessThan(firstChild.totalCount));
      expect(firstChild.pendingSplitStageCount, 0);
      expect(firstChild.pendingTxCount, migrationPlan.plannedBatchCount);
      expect(firstChild.signedChildPcztCount, 0);
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await _expectIntermediateProgressUi(tester, migrationPlan, firstChild);

      e2eLog('mining a partial large-balance migration batch');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 1},
      );
      final partiallyConfirmed = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.confirmedTxCount > 0 &&
            status.confirmedTxCount < status.totalCount,
        description: 'partial large-balance migration confirmation',
      );
      expect(
        partiallyConfirmed.broadcastedTxCount +
            partiallyConfirmed.confirmedTxCount,
        lessThanOrEqualTo(partiallyConfirmed.totalCount),
      );
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await _expectIntermediateProgressUi(
        tester,
        migrationPlan,
        partiallyConfirmed,
      );

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
      expect(allSubmitted.totalCount, 12);
      expect(
        allSubmitted.scheduledBroadcasts.where(
          (broadcast) => broadcast.status == 'scheduled',
        ),
        isEmpty,
      );
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await _expectIntermediateProgressUi(tester, migrationPlan, allSubmitted);

      e2eLog('confirming all large-balance migration transactions');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'completed large-balance migration',
      );
      await _refreshMigrationStatusUi(tester, container, accountUuid);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_status_complete')),
        ),
        description: 'large-balance completion UI',
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

void _expectLargePlan(rust_sync.OrchardMigrationPrivatePlan plan) {
  expect(plan.totalInputZatoshi, _fundedAmount);
  expect(plan.plannedBatchCount, 12);
  expect(plan.targetValuesZatoshi, hasLength(plan.plannedBatchCount));
  expect(plan.denominationSplitStageCount, 1);
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

void _expectRunMatchesPlan(
  rust_sync.MigrationStatus status,
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  expect(status.preparedNoteCount, plan.plannedBatchCount);
  expect(status.totalCount, plan.plannedBatchCount);
  expect(status.signedChildPcztCount, plan.plannedBatchCount);
  expect(status.denominationSplitTotalCount, plan.denominationSplitStageCount);
  expect(_sumTargets(status.targetValuesZatoshi), plan.totalMigratableZatoshi);
}

Future<void> _expectIntermediateProgressUi(
  WidgetTester tester,
  rust_sync.OrchardMigrationPrivatePlan plan,
  rust_sync.MigrationStatus status,
) async {
  if (status.phase == kIronwoodMigrationBroadcastScheduledPhase) {
    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(
          const ValueKey('ironwood_migration_status_broadcast_scheduled'),
        ),
      ),
      description: 'large-balance scheduled broadcast progress UI',
    );
    expect(find.text('Broadcast Scheduled'), findsOneWidget);
    expect(
      find.text(
        '${status.denominationSplitCompletedCount}/'
        '${status.denominationSplitTotalCount}',
      ),
      findsOneWidget,
    );
    expect(find.text('${status.pendingTxCount}'), findsOneWidget);
    expect(find.text('${status.broadcastedTxCount}'), findsOneWidget);
    expect(
      find.text('${status.confirmedTxCount}/${status.totalCount}'),
      findsOneWidget,
    );
    return;
  }

  await pumpUntil(
    tester,
    () => tester.any(find.text('${plan.plannedBatchCount} Planned batches')),
    description: 'large-balance transfer progress UI',
  );
  final percentages = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .where((text) => RegExp(r'^\d+%$').hasMatch(text))
      .map((text) => int.parse(text.substring(0, text.length - 1)))
      .toList();
  expect(percentages, hasLength(1));
  expect(percentages.single, inInclusiveRange(1, 99));
  expect(find.textContaining('Left to transfer:'), findsOneWidget);
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
    description: 'idle large-balance wallet sync at $targetHeight',
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
    description: 'active Ironwood large-balance sync',
    timeout: const Duration(minutes: 5),
  );
}
