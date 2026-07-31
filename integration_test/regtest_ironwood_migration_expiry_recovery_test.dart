import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    're-signs multiple expired migration parts in the existing approved run',
    (tester) async {
      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            ironwoodMigrationCoordinatorProvider.overrideWith(
              _ControlledMigrationCoordinator.new,
            ),
          ],
        ),
      );
      await importDesktopRegtestWallet(tester);
      await pumpUntil(
        tester,
        () =>
            textForKey(
              tester,
              const ValueKey('home_desktop_balance_amount_text'),
            ) ==
            '0.0412',
        description: 'pre-Ironwood Orchard balance to render',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      final coordinator =
          container.read(ironwoodMigrationCoordinatorProvider.notifier)
              as _ControlledMigrationCoordinator;
      await pumpUntil(
        tester,
        () {
          final chain = container.read(chainUpgradeStatusProvider).value;
          final sync = container.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >= 500;
        },
        description: 'active Ironwood chain and completed wallet sync',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood announcement after activation',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: await firstDesktopRegtestAccountUuid(),
        spacePreparationBroadcasts: true,
      );
      expect(plan, isNotNull);
      expect(plan!.plannedBatchCount, 2);
      expect(plan.targetValuesZatoshi, hasLength(2));
      await openPrivateMigrationReview(tester);
      await startPrivateMigrationFromReview(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.phase == 'waiting_denom_confirmations',
        description: 'persisted denomination confirmation phase',
        timeout: const Duration(minutes: 2),
      );
      final navigator = find.byType(Navigator).first;
      GoRouter.of(tester.element(navigator)).go('/migration/private/status');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_active_status')),
        ),
        description: 'denomination confirmation status',
        timeout: const Duration(minutes: 5),
      );

      final original = await desktopRegtestMigrationStatus(accountUuid);
      final originalRunId = original.activeRunId!;
      final originalTargets = original.targetValuesZatoshi.toList();
      final dbPath = await getWalletDbPath();

      GoRouter.of(tester.element(navigator)).go('/home');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
        description: 'home while denomination preparation continues',
      );

      final preparationHeight = int.parse(
        (await _runSqlite(
          dbPath,
          "SELECT COALESCE(MIN(scheduled_height), 0) "
          "FROM vizor_migration_denomination_stages "
          "WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          "AND status = 'pending';",
        )).trim(),
      );
      final preparationChain = await ironwoodDriverGet(_driverUrl, '/status');
      final preparationChainHeight = (preparationChain['zcashdHeight'] as num)
          .toInt();
      if (preparationHeight > preparationChainHeight) {
        await ironwoodDriverPost(
          _driverUrl,
          '/mine',
          payload: {'blocks': preparationHeight - preparationChainHeight},
        );
      }
      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == false &&
              (sync?.scannedHeight ?? 0) >= preparationHeight;
        },
        description: 'wallet sync at denomination broadcast height',
        timeout: const Duration(minutes: 5),
      );
      await container
          .read(ironwoodMigrationServiceProvider)
          .continueSoftwarePrivateMigration(accountUuid: accountUuid);
      await _waitForNoPendingDenominationStages(tester, dbPath, originalRunId);
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.phase == 'ready_to_migrate',
        description: 'migration denomination readiness',
        timeout: const Duration(minutes: 10),
      );
      final recoveryChain = await ironwoodDriverGet(_driverUrl, '/status');
      final recoveryChainHeight = (recoveryChain['zcashdHeight'] as num)
          .toInt();
      await ironwoodDriverPost(_driverUrl, '/lightwalletd/stop');
      try {
        await container
            .read(ironwoodMigrationServiceProvider)
            .continueSoftwarePrivateMigration(accountUuid: accountUuid);
      } catch (error) {
        expect(error.toString(), contains('transport error'));
        e2eLog('initial migration submission unavailable as expected: $error');
      }
      final scheduled = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.scheduledBroadcasts.length == originalTargets.length &&
            status.scheduledBroadcasts.every(
              (broadcast) => broadcast.status == 'scheduled',
            ),
        description: 'persisted two-part migration broadcast schedule',
        timeout: const Duration(minutes: 10),
      );
      GoRouter.of(tester.element(navigator)).go('/migration/private/status');
      await tester.pump(const Duration(milliseconds: 500));
      expect(scheduled.activeRunId, originalRunId);
      expect(scheduled.scheduledBroadcasts, hasLength(2));
      final originalTxids = scheduled.scheduledBroadcasts
          .map((broadcast) => broadcast.txidHex)
          .toSet();
      expect(originalTxids, hasLength(2));

      final syncNotifier = container.read(syncProvider.notifier);
      final syncPause = await syncNotifier.pauseForWalletMutation();
      late rust_sync.MigrationStatus replacement;
      try {
        await _runSqlite(
          dbPath,
          "UPDATE vizor_migration_pending_txs "
          "SET expiry_height = $recoveryChainHeight "
          "WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          "AND status = 'scheduled';",
        );
        expect(
          (await _runSqlite(
            dbPath,
            "SELECT COUNT(*) FROM vizor_migration_pending_txs "
            "WHERE run_id = '${_sqlLiteral(originalRunId)}' "
            "AND status = 'scheduled' "
            "AND expiry_height = $recoveryChainHeight;",
          )).trim(),
          '2',
        );
        e2eLog(
          'forced both parts of run $originalRunId to expire at tip '
          '$recoveryChainHeight',
        );

        try {
          await container
              .read(ironwoodMigrationServiceProvider)
              .continueSoftwarePrivateMigration(accountUuid: accountUuid);
        } catch (error) {
          expect(error.toString(), contains('transport error'));
          e2eLog('replacement submission unavailable as expected: $error');
        }

        replacement = await waitForDesktopRegtestMigrationStatus(
          tester,
          accountUuid,
          (status) =>
              status.activeRunId == originalRunId &&
              status.scheduledBroadcasts.length == originalTxids.length &&
              status.scheduledBroadcasts.every(
                (broadcast) => broadcast.status == 'scheduled',
              ) &&
              status.scheduledBroadcasts
                      .map((broadcast) => broadcast.txidHex)
                      .toSet()
                      .difference(originalTxids)
                      .length ==
                  originalTxids.length,
          description: 'same-run replacement migration transactions',
          timeout: const Duration(minutes: 3),
        );
        expect(replacement.targetValuesZatoshi, orderedEquals(originalTargets));
        expect(replacement.scheduledBroadcasts, hasLength(2));

        final recovered = await _runSqlite(
          dbPath,
          "SELECT "
          "(SELECT COUNT(*) FROM vizor_migration_prepared_notes "
          " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          " AND lock_state = 'locked') || ':' || "
          "(SELECT COUNT(*) FROM vizor_migration_pending_txs "
          " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          " AND status = 'needs_resign') || ':' || "
          "(SELECT COUNT(*) FROM vizor_migration_pending_txs "
          " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          " AND status = 'scheduled') || ':' || "
          "(SELECT COUNT(DISTINCT schedule_start_height) "
          " FROM vizor_migration_pending_txs "
          " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
          " AND status = 'scheduled') || ':' || "
          "(SELECT COUNT(*) FROM vizor_migration_pending_txs AS pending "
          " JOIN vizor_migration_runs AS run USING (run_id) "
          " WHERE pending.run_id = '${_sqlLiteral(originalRunId)}' "
          " AND pending.status = 'scheduled' "
          " AND pending.schedule_start_height = "
          "     run.recovery_schedule_origin_height "
          " AND run.recovery_schedule_max_block_offset = "
          "     (SELECT MAX(scheduled_height - schedule_start_height) "
          "      FROM vizor_migration_pending_txs "
          "      WHERE run_id = '${_sqlLiteral(originalRunId)}'));",
        );
        expect(recovered.trim(), '2:0:2:1:2');
      } finally {
        try {
          await ironwoodDriverPost(
            _driverUrl,
            '/node/restart',
            timeout: const Duration(minutes: 5),
          );
        } finally {
          syncNotifier.resumeAfterWalletMutation(syncPause);
        }
      }

      await syncNotifier.startSyncAnyway();
      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == false &&
              (sync?.scannedHeight ?? 0) >= recoveryChainHeight;
        },
        description: 'wallet sync after forced migration expiry',
        timeout: const Duration(minutes: 5),
      );
      coordinator.enableAutomaticAdvances();
      await coordinator.refreshNow(forceAdvance: true);

      final submitted = await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
      );
      expect(submitted.activeRunId, originalRunId);
      expect(
        submitted.broadcastedTxCount + submitted.confirmedTxCount,
        submitted.totalCount,
      );
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'completed migration after same-run expiry recovery',
        timeout: const Duration(minutes: 5),
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

class _ControlledMigrationCoordinator extends IronwoodMigrationCoordinator {
  var _automaticAdvancesEnabled = false;

  void enableAutomaticAdvances() => _automaticAdvancesEnabled = true;

  @override
  Future<void> refreshNow({bool forceAdvance = false}) {
    if (!_automaticAdvancesEnabled) return Future.value();
    return super.refreshNow(forceAdvance: forceAdvance);
  }

  @override
  Future<void> resumeBackgroundPreparations() {
    if (!_automaticAdvancesEnabled) return Future.value();
    return super.resumeBackgroundPreparations();
  }
}

Future<void> _waitForNoPendingDenominationStages(
  WidgetTester tester,
  String dbPath,
  String runId,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final pending = await _runSqlite(
      dbPath,
      "SELECT COUNT(*) FROM vizor_migration_denomination_stages "
      "WHERE run_id = '${_sqlLiteral(runId)}' AND status = 'pending';",
    );
    if (pending.trim() == '0') return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out waiting for the scheduled denomination broadcast.');
}

Future<String> _runSqlite(String dbPath, String sql) async {
  final result = await Process.run('sqlite3', [dbPath, sql]);
  if (result.exitCode != 0) {
    throw StateError('sqlite3 failed: ${result.stderr}');
  }
  return result.stdout as String;
}

String _sqlLiteral(String value) => value.replaceAll("'", "''");
