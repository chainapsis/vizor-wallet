import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39085',
);
const _expectedFundingZatoshiText = String.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
);
const _liveHoldMs = int.fromEnvironment(
  'ZCASH_E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS',
  defaultValue: 0,
);
const _autoStart = bool.fromEnvironment(
  'ZCASH_E2E_CUSTOM_MIGRATION_AUTO_START',
);
const _paceMs = int.fromEnvironment(
  'ZCASH_E2E_CUSTOM_MIGRATION_PACE_MS',
  defaultValue: 1500,
);
const _completionHoldMs = int.fromEnvironment(
  'ZCASH_E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'submits and observes a synthetic 10,000,000 ZEC Custom migration',
    (tester) async {
      expect(_expectedFundingZatoshiText, isNotEmpty);
      final expectedFunding = BigInt.parse(_expectedFundingZatoshiText);
      rust_sync.OrchardMigrationPrivatePlan? reviewedPlan;

      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            ironwoodMigrationCustomPlanProvider.overrideWith((
              ref,
              custom,
            ) async {
              final request = ref.watch(
                ironwoodMigrationInputsProvider.select(
                  (inputs) => inputs.statusRequest,
                ),
              );
              if (request == null) return null;

              final plan = await ref
                  .watch(ironwoodMigrationServiceProvider)
                  .customPlan(
                    network: request.network,
                    accountUuid: request.accountUuid,
                    amountGroupCount: custom.amountGroupCount,
                    parallelScheduleCount: custom.parallelScheduleCount,
                    planSeed: custom.planSeed,
                  );
              if (plan != null) reviewedPlan = plan;
              return plan;
            }),
          ],
        ),
      );
      await importDesktopRegtestWallet(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
      );
      final fundedBalance = await _waitForOrchardBalance(
        tester,
        accountUuid,
        expectedFunding,
      );
      expect(fundedBalance.ironwood, BigInt.zero);

      e2eLog('activating Ironwood for the real Custom migration');
      await ironwoodDriverPost(_driverUrl, '/activate');
      await _waitForIronwoodSync(tester, container);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'real Custom migration announcement',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      await openCustomMigrationReview(tester);
      await pumpUntil(
        tester,
        () =>
            tester.any(
              find.byKey(const ValueKey('custom_migration_histogram')),
            ) &&
            tester.any(find.byKey(const ValueKey('custom_migration_timeline'))),
        description: 'real Custom migration plan',
        timeout: const Duration(minutes: 10),
      );
      final continueFinder = find.byKey(
        const ValueKey('custom_migration_continue_button'),
      );
      final continueButton = tester.widget<AppButton>(continueFinder);
      expect(continueButton.onPressed, isNotNull);

      if (_autoStart) {
        e2eLog('automated preflight is accepting the real Custom plan');
        await tapAppButton(
          tester,
          const ValueKey('custom_migration_continue_button'),
        );
      } else {
        expect(_liveHoldMs, greaterThan(0));
        e2eLog(
          'manual handoff ready: adjust the Custom controls and select '
          'Continue to signing when satisfied',
        );
        binding.shouldPropagateDevicePointerEvents = true;
        try {
          await _waitForManualStart(
            tester,
            accountUuid,
            Duration(milliseconds: _liveHoldMs),
          );
        } finally {
          binding.shouldPropagateDevicePointerEvents = false;
        }
      }

      expect(reviewedPlan, isNotNull);
      final approvedPlan = reviewedPlan!;
      final approvedTargets = approvedPlan.targetValuesZatoshi.toList();
      expect(approvedPlan.totalInputZatoshi, expectedFunding);
      expect(_sum(approvedTargets), approvedPlan.totalMigratableZatoshi);
      expect(
        approvedPlan.totalInputZatoshi -
            approvedPlan.totalMigratableZatoshi -
            (approvedPlan.orchardChangeZatoshi ?? BigInt.zero),
        approvedPlan.estimatedTotalFeeZatoshi,
      );

      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null && status.targetValuesZatoshi.isNotEmpty,
        description: 'real Custom migration run to start',
        timeout: const Duration(minutes: 15),
      );
      final runId = started.activeRunId!;
      expect(started.totalCount, approvedTargets.length);
      _expectTargetOrder(started, approvedTargets);
      e2eLog(
        'Custom run $runId accepted ${approvedTargets.length} exact targets; '
        'driving the real chain at the persisted heights',
      );

      final scheduled = await _drivePreparation(
        tester,
        accountUuid,
        runId,
        approvedTargets,
      );
      _expectPersistedSchedule(
        scheduled,
        approvedTargets,
        approvedSchedule: approvedPlan.scheduledTransfers,
        requireAllHeights: false,
        requireOriginalMatchesEffective: true,
      );
      final scheduleHeights = scheduled.parts
          .map((part) => part.effectiveScheduledHeight)
          .whereType<int>()
          .toList();
      e2eLog(
        'first persisted schedule cohort has ${scheduleHeights.length} '
        'transaction(s) spanning block ${scheduleHeights.reduce(math.min)} '
        'through ${scheduleHeights.reduce(math.max)}',
      );

      final submitted = await _driveScheduledBroadcasts(
        tester,
        container,
        accountUuid,
        runId,
        approvedTargets,
      );
      expect(
        submitted.broadcastedTxCount + submitted.confirmedTxCount,
        submitted.totalCount,
      );
      _expectTargetOrder(submitted, approvedTargets);
      _expectPersistedSchedule(
        submitted,
        approvedTargets,
        approvedSchedule: approvedPlan.scheduledTransfers,
        requireAllHeights: true,
      );

      e2eLog('mining trusted confirmations for every Custom migration note');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final complete = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'real Custom migration completion',
        timeout: const Duration(minutes: 15),
      );
      expect(complete.totalCount, approvedTargets.length);
      expect(complete.confirmedTxCount, complete.totalCount);
      _expectTargetOrder(complete, approvedTargets);

      final finalBalance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(
        finalBalance.orchard,
        approvedPlan.orchardChangeZatoshi ?? BigInt.zero,
      );
      expect(finalBalance.ironwood, approvedPlan.totalMigratableZatoshi);
      expect(
        expectedFunding - finalBalance.orchard - finalBalance.ironwood,
        approvedPlan.estimatedTotalFeeZatoshi,
      );
      e2eLog(
        'real Custom migration complete: ${approvedTargets.length} Ironwood '
        'notes totaling ${finalBalance.ironwood} zatoshi',
      );

      if (_completionHoldMs > 0) {
        await _hold(tester, Duration(milliseconds: _completionHoldMs));
      }
    },
    timeout: Timeout(
      Duration(milliseconds: _liveHoldMs + _completionHoldMs + 90 * 60 * 1000),
    ),
  );
}

Future<void> _waitForManualStart(
  WidgetTester tester,
  String accountUuid,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  var polls = 0;
  while (DateTime.now().isBefore(deadline)) {
    final status = await desktopRegtestMigrationStatus(accountUuid);
    if (status.activeRunId != null) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 150 == 0) {
      e2eLog('waiting for manual Custom migration approval');
    }
  }
  fail('Timed out waiting for manual Custom migration approval.');
}

Future<rust_sync.MigrationStatus> _drivePreparation(
  WidgetTester tester,
  String accountUuid,
  String runId,
  List<BigInt> approvedTargets,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 30));
  while (DateTime.now().isBefore(deadline)) {
    final status = await desktopRegtestMigrationStatus(accountUuid);
    expect(status.activeRunId, runId);
    _expectTargetOrder(status, approvedTargets);
    if (status.scheduledBroadcasts.isNotEmpty) return status;

    final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
    if ((mempool['size'] as int) > 0) {
      e2eLog(
        'observed ${(mempool['size'] as int)} denomination transaction(s); '
        'pausing before confirmation',
      );
      await _pace(tester);
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      continue;
    }

    final chain = await ironwoodDriverGet(_driverUrl, '/status');
    final currentHeight = (chain['zcashdHeight'] as num).toInt();
    final nextPreparationHeight = status.preparationTransactions
        ?.where(
          (transaction) =>
              transaction.state ==
              rust_sync.MigrationPreparationTransactionState.scheduled,
        )
        .map((transaction) => transaction.scheduledHeight)
        .whereType<int>()
        .fold<int?>(
          null,
          (value, height) => value == null ? height : math.min(value, height),
        );
    final nextHeight =
        [
              status.nextActionHeight,
              status.nextProofWindowHeight,
              nextPreparationHeight,
            ]
            .whereType<int>()
            .where((height) => height > currentHeight)
            .fold<int?>(
              null,
              (value, height) =>
                  value == null ? height : math.min(value, height),
            );
    if (nextHeight != null) {
      e2eLog(
        'advancing ${nextHeight - currentHeight} block(s) to the next '
        'preparation action at $nextHeight',
      );
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: {'blocks': nextHeight - currentHeight},
      );
      continue;
    }

    await tester.pump(const Duration(milliseconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out preparing the real Custom migration schedule.');
}

Future<rust_sync.MigrationStatus> _driveScheduledBroadcasts(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
  String runId,
  List<BigInt> approvedTargets,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 45));
  while (DateTime.now().isBefore(deadline)) {
    var status = await desktopRegtestMigrationStatus(accountUuid);
    expect(status.activeRunId, runId);
    _expectTargetOrder(status, approvedTargets);
    final submitted = status.broadcastedTxCount + status.confirmedTxCount;
    if (submitted == status.totalCount) return status;

    final scheduled =
        status.scheduledBroadcasts
            .where((entry) => entry.status == 'scheduled')
            .toList()
          ..sort((left, right) {
            final heightOrder = left.scheduledHeight.compareTo(
              right.scheduledHeight,
            );
            return heightOrder != 0
                ? heightOrder
                : left.txidHex.compareTo(right.txidHex);
          });
    if (scheduled.isEmpty) {
      final chain = await ironwoodDriverGet(_driverUrl, '/status');
      final currentHeight = (chain['zcashdHeight'] as num).toInt();
      final nextHeight = [status.nextActionHeight, status.nextProofWindowHeight]
          .whereType<int>()
          .where((height) => height > currentHeight)
          .fold<int?>(
            null,
            (value, height) => value == null ? height : math.min(value, height),
          );
      if (nextHeight != null) {
        await ironwoodDriverPost(
          _driverUrl,
          '/mine',
          payload: {'blocks': nextHeight - currentHeight},
        );
      } else {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      continue;
    }

    final nextScheduled = scheduled.first;
    final nextHeight = nextScheduled.scheduledHeight;
    final chain = await ironwoodDriverGet(_driverUrl, '/status');
    var currentHeight = (chain['zcashdHeight'] as num).toInt();
    if (nextHeight > currentHeight + 1) {
      final beforeDue = nextHeight - currentHeight - 1;
      e2eLog(
        'advancing $beforeDue block(s) to one block before Custom broadcast '
        'height $nextHeight',
      );
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: {'blocks': beforeDue},
      );
      await _waitForIdleSync(tester, container, nextHeight - 1);
      status = await desktopRegtestMigrationStatus(accountUuid);
      expect(
        status.broadcastedTxCount + status.confirmedTxCount,
        submitted,
        reason: 'a Custom migration transaction broadcast before its height',
      );
      expect((await ironwoodDriverGet(_driverUrl, '/mempool'))['size'], 0);
      currentHeight = nextHeight - 1;
      await _pace(tester);
    }

    if (nextHeight > currentHeight) {
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: {'blocks': nextHeight - currentHeight},
      );
    }
    status = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (next) =>
          next.activeRunId == runId &&
          next.broadcastedTxCount + next.confirmedTxCount > submitted,
      description: 'Custom migration cohort at block $nextHeight',
      timeout: const Duration(minutes: 10),
    );
    _expectTargetOrder(status, approvedTargets);
    final newlySubmitted =
        status.broadcastedTxCount + status.confirmedTxCount - submitted;
    expect(newlySubmitted, 1);
    final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
    final mempoolTxids = (mempool['txids'] as List<Object?>)
        .whereType<String>()
        .map((txid) => txid.toLowerCase())
        .toSet();
    expect(mempool['size'], mempoolTxids.length);
    expect(mempoolTxids, {nextScheduled.txidHex.toLowerCase()});
    e2eLog(
      'observed $newlySubmitted due Custom transaction(s) at $nextHeight; '
      'pausing before inclusion',
    );
    await _pace(tester);
    await ironwoodDriverPost(_driverUrl, '/mine', payload: const {'blocks': 1});
  }
  fail('Timed out driving the real Custom migration schedule.');
}

void _expectTargetOrder(
  rust_sync.MigrationStatus status,
  List<BigInt> approvedTargets,
) {
  expect(status.targetValuesZatoshi, approvedTargets);
  if (status.parts.isEmpty) return;
  final parts = status.parts.toList()
    ..sort((left, right) => left.partIndex.compareTo(right.partIndex));
  expect(
    parts.map((part) => part.partIndex),
    List.generate(parts.length, (i) => i),
  );
  expect(parts.map((part) => part.valueZatoshi), approvedTargets);
}

void _expectPersistedSchedule(
  rust_sync.MigrationStatus status,
  List<BigInt> approvedTargets, {
  required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  required bool requireAllHeights,
  bool requireOriginalMatchesEffective = false,
}) {
  _expectTargetOrder(status, approvedTargets);
  final parts = status.parts.toList();
  expect(parts, hasLength(approvedTargets.length));
  final approvedOrderByPart = <int, int>{};
  final approvedOffsetByPart = <int, int>{};
  for (
    var scheduleOrder = 0;
    scheduleOrder < approvedSchedule.length;
    scheduleOrder++
  ) {
    final transfer = approvedSchedule[scheduleOrder];
    expect(approvedOrderByPart.containsKey(transfer.partIndex), isFalse);
    approvedOrderByPart[transfer.partIndex] = scheduleOrder;
    approvedOffsetByPart[transfer.partIndex] = transfer.blockOffset;
  }
  expect(approvedOrderByPart, hasLength(parts.length));
  expect(parts.every((part) => part.scheduleOrder != null), isTrue);
  for (final part in parts) {
    expect(approvedOrderByPart, contains(part.partIndex));
    expect(part.scheduleOrder, approvedOrderByPart[part.partIndex]);
  }
  parts.sort(
    (left, right) => left.scheduleOrder!.compareTo(right.scheduleOrder!),
  );
  expect(
    parts.map((part) => part.scheduleOrder),
    List.generate(parts.length, (i) => i),
  );
  final originalHeights = parts
      .map((part) => part.originalScheduledHeight)
      .whereType<int>()
      .toList();
  final effectiveHeights = parts
      .map((part) => part.effectiveScheduledHeight)
      .whereType<int>()
      .toList();
  expect(originalHeights, isNotEmpty);
  expect(originalHeights, hasLength(effectiveHeights.length));
  if (requireAllHeights) {
    expect(originalHeights, hasLength(parts.length));
  }
  final originalScheduleOrigins = <int>[];
  for (final part in parts) {
    final originalHeight = part.originalScheduledHeight;
    if (originalHeight == null) continue;
    final approvedOffset = approvedOffsetByPart[part.partIndex];
    expect(approvedOffset, isNotNull);
    final scheduleOrigin = originalHeight - approvedOffset!;
    expect(scheduleOrigin, greaterThanOrEqualTo(0));
    originalScheduleOrigins.add(scheduleOrigin);
  }
  expect(originalScheduleOrigins, hasLength(originalHeights.length));
  expect(originalScheduleOrigins.toSet(), hasLength(1));
  expect(originalHeights, orderedEquals([...originalHeights]..sort()));
  expect(effectiveHeights, orderedEquals([...effectiveHeights]..sort()));
  if (requireOriginalMatchesEffective) {
    for (final part in parts.where(
      (part) => part.effectiveScheduledHeight != null,
    )) {
      expect(part.originalScheduledHeight, part.effectiveScheduledHeight);
    }
  }
}

Future<rust_sync.WalletBalance> _waitForOrchardBalance(
  WidgetTester tester,
  String accountUuid,
  BigInt expected,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  rust_sync.WalletBalance? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await rust_sync.getBalance(
      dbPath: await getWalletDbPath(),
      network: 'regtest',
      accountUuid: accountUuid,
    );
    if (last.orchard == expected) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Expected Orchard balance $expected, last observed ${last?.orchard}.');
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
    description: 'extreme-value wallet sync at $targetHeight',
    timeout: const Duration(minutes: 10),
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
          (sync?.scannedHeight ?? 0) >= kZcashRegtestIronwoodActivationHeight;
    },
    description: 'active Ironwood extreme-value wallet sync',
    timeout: const Duration(minutes: 10),
  );
}

Future<void> _pace(WidgetTester tester) async {
  if (_paceMs <= 0) return;
  await _hold(tester, const Duration(milliseconds: _paceMs));
}

Future<void> _hold(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

BigInt _sum(Iterable<BigInt> values) {
  return values.fold(BigInt.zero, (sum, value) => sum + value);
}
