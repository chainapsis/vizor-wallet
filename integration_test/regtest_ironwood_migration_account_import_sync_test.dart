import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _migrationImportPhase = String.fromEnvironment(
  'ZCASH_E2E_ACCOUNT_IMPORT_MIGRATION_PHASE',
  defaultValue: 'denomination',
);
const _childSchedulePhase = 'child_schedule';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'preserves active $_migrationImportPhase migration state during old-account import sync',
    (tester) async {
      expect(_migrationImportPhase, anyOf('denomination', _childSchedulePhase));
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
            (_migrationImportPhase == _childSchedulePhase
                ? '10.0002'
                : '0.011'),
        description: 'funded first-account Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final firstAccount = (await desktopRegtestAccounts()).single;
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
        description: 'idle funded-account sync before Ironwood',
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      final activeChain = await ironwoodDriverGet(_driverUrl, '/status');
      final activeHeight = (activeChain['zcashdHeight'] as num).toInt();
      await pumpUntil(
        tester,
        () {
          final chain = container.read(chainUpgradeStatusProvider).value;
          final sync = container.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >= activeHeight;
        },
        description: 'active Ironwood sync before migration',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood announcement before migration',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);

      final migrationPlan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: firstAccount.uuid,
        spacePreparationBroadcasts: true,
      );
      expect(migrationPlan, isNotNull);
      await openPrivateMigrationReview(tester);
      await startPrivateMigrationFromReview(tester);

      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        firstAccount.uuid,
        (status) =>
            status.phase == 'waiting_denom_confirmations' &&
            status.pendingSplitStageCount > 0,
        description: 'durable denomination migration before account import',
        timeout: const Duration(minutes: 5),
      );
      final baseline = _migrationImportPhase == _childSchedulePhase
          ? await _advanceToChildSchedule(
              tester,
              container,
              firstAccount.uuid,
              started,
            )
          : started;
      final runId = baseline.activeRunId;
      expect(runId, isNotNull);
      final targetValues = baseline.targetValuesZatoshi.toList();
      final preparationIdentities = _preparationIdentities(baseline);
      final partCoreIdentities = _partCoreIdentities(baseline);
      final partScheduleHeights = _partScheduleHeights(baseline);
      final scheduledBroadcastCoreIdentities =
          _scheduledBroadcastCoreIdentities(baseline);
      final scheduledBroadcastHeights = _scheduledBroadcastHeights(baseline);
      expect(preparationIdentities, isNotEmpty);
      if (_migrationImportPhase == _childSchedulePhase) {
        expect(partCoreIdentities, isNotEmpty);
        expect(
          scheduledBroadcastCoreIdentities.length,
          greaterThan(1),
          reason:
              'The child-schedule scenario must exercise multiple scheduled '
              'migration transactions.',
        );
      }

      final beforeImportSync = container.read(syncProvider).value;
      expect(beforeImportSync, isNotNull);
      expect(beforeImportSync!.isSyncComplete, isTrue);
      expect(beforeImportSync.isSyncing, isFalse);
      final beforeImportHeight = beforeImportSync.scannedHeight;
      expect(beforeImportHeight, greaterThanOrEqualTo(activeHeight));

      final beforeImportProjection = _projectionByStage(baseline);
      e2eLog(
        'before old-account import ($_migrationImportPhase): '
        '${_observationText(beforeImportSync, baseline, beforeImportHeight)}',
      );

      // Desktop currently redirects /add-account back to the active private
      // migration status route. Exercise the shared account mutation path
      // directly so this regression still covers the mobile-reachable case
      // and the account/sync/Rust behavior shared by both form factors.
      await container
          .read(accountProvider.notifier)
          .importAccount(mnemonic: secondDesktopRegtestMnemonic);
      await tester.pump();
      final accounts = await desktopRegtestAccounts();
      expect(accounts, hasLength(2));

      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == true &&
              sync?.isSyncComplete == false &&
              (sync?.scannedHeight ?? beforeImportHeight) < beforeImportHeight;
        },
        description: 'historic rescan after old-account import',
        timeout: const Duration(minutes: 2),
      );

      var observationCount = 0;
      var minimumDartScannedHeight = beforeImportHeight;
      var minimumRustScannedHeight = beforeImportHeight;
      var previousConfirmationCount = baseline.denominationConfirmationCount;
      var previousEstimatedCompletionHeight =
          baseline.estimatedCompletionHeight;
      var previousNextActionHeight = baseline.nextActionHeight;
      var previousProofReady = baseline.proofReady;
      var previousProjection = beforeImportProjection;
      final projectionRegressions = <String>[];
      final proofReadinessRegressions = <String>[];
      final phaseChanges = <String>[];
      String? lastObservation;

      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        final sync = container.read(syncProvider).value;
        expect(sync, isNotNull);
        final status = await desktopRegtestMigrationStatus(firstAccount.uuid);
        final rustProgress = await rust_sync.getSyncStatus(
          dbPath: await getWalletDbPath(),
          network: 'regtest',
        );
        observationCount++;

        expect(status.activeRunId, runId);
        expect(status.targetValuesZatoshi, orderedEquals(targetValues));
        expect(
          _preparationIdentities(status),
          preparationIdentities,
          reason: 'The persisted denomination plan must not be rewritten.',
        );
        if (_migrationImportPhase == _childSchedulePhase) {
          _expectStableIdentities(
            actual: _partCoreIdentities(status),
            expected: partCoreIdentities,
            label: 'migration part core',
          );
          _expectNonRegressingHeights(
            actual: _partScheduleHeights(status),
            previous: partScheduleHeights,
            label: 'migration part schedule',
          );
          // A broadcast operation that started before account growth took the
          // gate may finish and remove an item from the due queue. That is a
          // forward lifecycle transition; remaining persisted schedules must
          // still retain identity and never move backward.
          _expectStableIdentities(
            actual: _scheduledBroadcastCoreIdentities(status),
            expected: scheduledBroadcastCoreIdentities,
            label: 'scheduled broadcast core',
            allowMissing: true,
          );
          _expectNonRegressingHeights(
            actual: _scheduledBroadcastHeights(status),
            previous: scheduledBroadcastHeights,
            label: 'scheduled broadcast height',
            allowMissing: true,
          );
        }

        if (status.phase != baseline.phase &&
            !phaseChanges.contains(status.phase)) {
          phaseChanges.add(status.phase);
        }
        if (status.denominationConfirmationCount < previousConfirmationCount) {
          projectionRegressions.add(
            'confirmation count $previousConfirmationCount'
            ' -> ${status.denominationConfirmationCount}',
          );
        }
        previousConfirmationCount = status.denominationConfirmationCount;

        final estimatedCompletionHeight = status.estimatedCompletionHeight;
        if (estimatedCompletionHeight != null &&
            previousEstimatedCompletionHeight != null &&
            estimatedCompletionHeight < previousEstimatedCompletionHeight) {
          projectionRegressions.add(
            'estimated completion $previousEstimatedCompletionHeight'
            ' -> $estimatedCompletionHeight',
          );
        }
        previousEstimatedCompletionHeight = estimatedCompletionHeight;

        final nextActionHeight = status.nextActionHeight;
        if (nextActionHeight != null &&
            previousNextActionHeight != null &&
            nextActionHeight < previousNextActionHeight) {
          projectionRegressions.add(
            'next action $previousNextActionHeight -> $nextActionHeight',
          );
        }
        previousNextActionHeight = nextActionHeight;

        if (previousProofReady == true && status.proofReady == false) {
          proofReadinessRegressions.add(
            'proof readiness true -> false at '
            'dart=${sync!.scannedHeight}, '
            'rust=${rustProgress.scannedHeight}',
          );
        }
        previousProofReady = status.proofReady;

        final projection = _projectionByStage(status);
        for (final entry in projection.entries) {
          final previous = previousProjection[entry.key];
          if (previous == null) continue;
          if (entry.value.$1 < previous.$1) {
            projectionRegressions.add(
              'stage ${entry.key} projected height '
              '${previous.$1} -> ${entry.value.$1}',
            );
          }
          if (entry.value.$2 < previous.$2) {
            projectionRegressions.add(
              'stage ${entry.key} projected completion '
              '${previous.$2} -> ${entry.value.$2}',
            );
          }
        }
        previousProjection = projection;

        minimumDartScannedHeight =
            minimumDartScannedHeight < sync!.scannedHeight
            ? minimumDartScannedHeight
            : sync.scannedHeight;
        final rustScannedHeight = rustProgress.scannedHeight.toInt();
        minimumRustScannedHeight = minimumRustScannedHeight < rustScannedHeight
            ? minimumRustScannedHeight
            : rustScannedHeight;

        final observation = _observationText(sync, status, rustScannedHeight);
        if (observation != lastObservation) {
          e2eLog('old-account catchup: $observation');
          lastObservation = observation;
        }

        if (!sync.isSyncing && sync.isSyncComplete) break;
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      final completedSync = container.read(syncProvider).value;
      expect(completedSync, isNotNull);
      expect(completedSync!.isSyncing, isFalse);
      expect(completedSync.isSyncComplete, isTrue);
      expect(completedSync.scannedHeight, greaterThanOrEqualTo(activeHeight));
      expect(observationCount, greaterThan(1));
      expect(minimumDartScannedHeight, lessThan(beforeImportHeight));

      final completedStatus = await desktopRegtestMigrationStatus(
        firstAccount.uuid,
      );
      expect(completedStatus.activeRunId, runId);
      expect(completedStatus.targetValuesZatoshi, orderedEquals(targetValues));
      expect(_preparationIdentities(completedStatus), preparationIdentities);
      if (_migrationImportPhase == _childSchedulePhase) {
        _expectStableIdentities(
          actual: _partCoreIdentities(completedStatus),
          expected: partCoreIdentities,
          label: 'completed migration part core',
        );
        _expectNonRegressingHeights(
          actual: _partScheduleHeights(completedStatus),
          previous: partScheduleHeights,
          label: 'completed migration part schedule',
        );
        _expectStableIdentities(
          actual: _scheduledBroadcastCoreIdentities(completedStatus),
          expected: scheduledBroadcastCoreIdentities,
          label: 'completed scheduled broadcast core',
          allowMissing: true,
        );
        _expectNonRegressingHeights(
          actual: _scheduledBroadcastHeights(completedStatus),
          previous: scheduledBroadcastHeights,
          label: 'completed scheduled broadcast height',
          allowMissing: true,
        );
      }
      expect(
        projectionRegressions,
        isEmpty,
        reason:
            'An unrelated account catchup must not make active migration '
            'confirmations or projections move backward.',
      );
      expect(
        proofReadinessRegressions,
        isEmpty,
        reason:
            'An unrelated account catchup must not revoke an already-ready '
            'migration proof window.',
      );

      e2eLog(
        'old-account catchup complete ($_migrationImportPhase): '
        'observations=$observationCount '
        'dartHeight=$beforeImportHeight->$minimumDartScannedHeight'
        '->${completedSync.scannedHeight} '
        'rustMinHeight=$minimumRustScannedHeight '
        'phaseChanges=${phaseChanges.isEmpty ? 'none' : phaseChanges.join(',')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<rust_sync.MigrationStatus> _advanceToChildSchedule(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
  rust_sync.MigrationStatus started,
) async {
  var status = started;
  final deadline = DateTime.now().add(const Duration(minutes: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (status.scheduledBroadcasts.isNotEmpty) {
      e2eLog(
        'child schedule ready: phase=${status.phase} '
        'proof=${status.proofReady} '
        'signed=${status.signedChildPcztCount} '
        'scheduled=${status.scheduledBroadcasts.length}',
      );
      return status;
    }

    if (status.phase != 'waiting_denom_confirmations') {
      status = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (next) => next.scheduledBroadcasts.isNotEmpty,
        description: 'child migration schedule after denomination readiness',
        timeout: const Duration(minutes: 5),
      );
      continue;
    }

    // Hidden-window E2E runs should not depend on the periodic coordinator
    // timer happening to fire while an expensive denomination proof is being
    // generated. Await the same public coordinator path the app uses so the
    // test receives either a completed advance or an explicit error.
    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow(forceAdvance: true);
    await _waitForMempool(tester);
    final completedBefore = status.denominationSplitCompletedCount;
    await ironwoodDriverPost(
      _driverUrl,
      '/mine',
      payload: {
        'blocks': status.denominationConfirmationTarget > 0
            ? status.denominationConfirmationTarget
            : 10,
      },
    );
    status = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (next) =>
          next.scheduledBroadcasts.isNotEmpty ||
          next.phase != 'waiting_denom_confirmations' ||
          next.denominationSplitCompletedCount > completedBefore,
      description: 'next denomination stage or child migration schedule',
      timeout: const Duration(minutes: 5),
    );
  }
  fail('Timed out preparing child migration schedule.');
}

Future<void> _waitForMempool(WidgetTester tester) async {
  // A padded denomination plan can spend several minutes generating proofs on
  // a loaded debug host before the first transaction reaches zcashd.
  // Keep this below the enclosing child-schedule deadline so a genuinely
  // stalled coordinator still fails with a bounded timeout.
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await ironwoodDriverGet(_driverUrl, '/mempool');
    final size = (last['size'] as num?)?.toInt() ?? 0;
    if (size > 0) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out waiting for a denomination transaction. Last: $last');
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  int minimumHeight, {
  required String description,
}) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= minimumHeight;
    },
    description: description,
    timeout: const Duration(minutes: 5),
  );
}

Map<int, String> _preparationIdentities(rust_sync.MigrationStatus status) {
  return {
    for (final transaction
        in status.preparationTransactions ??
            const <rust_sync.MigrationPreparationTransactionStatus>[])
      transaction.stageIndex:
          '${transaction.round}:'
          '${transaction.approximateValueZatoshi}:'
          '${transaction.feeZatoshi}:'
          '${transaction.plannedHeight}:'
          '${transaction.scheduledHeight}',
  };
}

Map<int, (int, int)> _projectionByStage(rust_sync.MigrationStatus status) {
  return {
    for (final transaction
        in status.preparationTransactions ??
            const <rust_sync.MigrationPreparationTransactionStatus>[])
      transaction.stageIndex: (
        transaction.projectedHeight,
        transaction.projectedCompletionHeight,
      ),
  };
}

Map<int, String> _partCoreIdentities(rust_sync.MigrationStatus status) {
  return {
    for (final part in status.parts)
      part.partIndex:
          '${part.scheduleOrder}:'
          '${part.valueZatoshi}:'
          '${part.txidHex}:'
          '${part.originalScheduledHeight}',
  };
}

Map<int, (int?, int?)> _partScheduleHeights(rust_sync.MigrationStatus status) {
  return {
    for (final part in status.parts)
      part.partIndex: (part.scheduleStartHeight, part.effectiveScheduledHeight),
  };
}

Map<String, String> _scheduledBroadcastCoreIdentities(
  rust_sync.MigrationStatus status,
) {
  return {
    for (final broadcast in status.scheduledBroadcasts)
      broadcast.txidHex: '${broadcast.valueZatoshi}',
  };
}

Map<String, (int?, int?)> _scheduledBroadcastHeights(
  rust_sync.MigrationStatus status,
) {
  return {
    for (final broadcast in status.scheduledBroadcasts)
      broadcast.txidHex: (
        broadcast.scheduleStartHeight,
        broadcast.scheduledHeight,
      ),
  };
}

void _expectStableIdentities<K>({
  required Map<K, String> actual,
  required Map<K, String> expected,
  required String label,
  bool allowMissing = false,
}) {
  for (final entry in expected.entries) {
    if (allowMissing && !actual.containsKey(entry.key)) continue;
    expect(
      actual[entry.key],
      entry.value,
      reason: 'Persisted $label ${entry.key} must remain stable.',
    );
  }
}

void _expectNonRegressingHeights<K>({
  required Map<K, (int?, int?)> actual,
  required Map<K, (int?, int?)> previous,
  required String label,
  bool allowMissing = false,
}) {
  for (final entry in previous.entries) {
    final current = actual[entry.key];
    if (current == null && allowMissing) continue;
    expect(current, isNotNull, reason: '$label ${entry.key} disappeared.');
    for (final (before, after) in [
      (entry.value.$1, current!.$1),
      (entry.value.$2, current.$2),
    ]) {
      if (before == null) continue;
      expect(
        after,
        isNotNull,
        reason: '$label ${entry.key} lost a persisted height.',
      );
      expect(
        after!,
        greaterThanOrEqualTo(before),
        reason: '$label ${entry.key} must not move backward.',
      );
    }
  }
}

String _observationText(
  SyncState sync,
  rust_sync.MigrationStatus status,
  int rustScannedHeight,
) {
  final projections =
      (status.preparationTransactions ??
              const <rust_sync.MigrationPreparationTransactionStatus>[])
          .map(
            (transaction) =>
                '${transaction.stageIndex}:'
                '${transaction.state.name}:'
                '${transaction.projectedHeight}/'
                '${transaction.projectedCompletionHeight}:'
                '${transaction.confirmationCount}',
          )
          .join(',');
  final parts = status.parts
      .map(
        (part) =>
            '${part.partIndex}:'
            '${part.state.name}:'
            '${part.effectiveScheduledHeight}:'
            '${part.confirmationCount}',
      )
      .join(',');
  return 'sync=${sync.phase}:${sync.scannedHeight}/${sync.chainTipHeight}:'
      '${sync.isSyncing}/${sync.isSyncComplete} '
      'rustScanned=$rustScannedHeight '
      'migration=${status.phase}:${status.activeRunId} '
      'denom=${status.denominationConfirmationCount}/'
      '${status.denominationConfirmationTarget} '
      'proof=${status.proofReady} '
      'next=${status.nextActionHeight} '
      'estimated=${status.estimatedCompletionHeight} '
      'preparation=[$projections] '
      'parts=[$parts]';
}
