import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    're-signs expired migration parts in the existing approved run',
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
            '0.011',
        description: 'pre-Ironwood Orchard balance to render',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
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
      await openPrivateMigrationReview(tester);
      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_authorize_start_button'),
      );
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
          find.byKey(
            const ValueKey(
              'ironwood_migration_status_waiting_denom_confirmations',
            ),
          ),
        ),
        description: 'denomination confirmation status',
        timeout: const Duration(minutes: 5),
      );

      final original = await desktopRegtestMigrationStatus(accountUuid);
      final originalRunId = original.activeRunId;
      final originalTargets = original.targetValuesZatoshi.toList();
      expect(originalRunId, isNotNull);

      GoRouter.of(tester.element(navigator)).go('/home');
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
        description: 'home while denomination preparation continues',
      );

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 12},
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.phase == 'ready_to_migrate',
        description: 'migration denomination readiness',
        timeout: const Duration(minutes: 10),
      );
      await container
          .read(ironwoodMigrationServiceProvider)
          .continueSoftwarePrivateMigration(accountUuid: accountUuid);
      final scheduled = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.scheduledBroadcasts.isNotEmpty,
        description: 'persisted migration broadcast schedule',
        timeout: const Duration(minutes: 10),
      );
      GoRouter.of(tester.element(navigator)).go('/migration/private/status');
      await tester.pump(const Duration(milliseconds: 500));
      expect(scheduled.activeRunId, originalRunId);
      expect(scheduled.scheduledBroadcasts, isNotEmpty);
      final originalTxids = scheduled.scheduledBroadcasts
          .map((broadcast) => broadcast.txidHex)
          .toSet();
      final expiringTxid =
          (scheduled.scheduledBroadcasts.toList()..sort(
                (left, right) =>
                    left.scheduledHeight.compareTo(right.scheduledHeight),
              ))
              .first
              .txidHex;

      await stopRustWorkForCleanup();
      final chain = await ironwoodDriverGet(_driverUrl, '/status');
      final chainHeight = (chain['zcashdHeight'] as num).toInt();
      final dbPath = await getWalletDbPath();
      await _runSqlite(
        dbPath,
        "UPDATE vizor_migration_pending_txs "
        "SET expiry_height = $chainHeight "
        "WHERE run_id = '${_sqlLiteral(originalRunId!)}' "
        "AND txid_hex = '${_sqlLiteral(expiringTxid)}';"
        "UPDATE transactions SET expiry_height = $chainHeight "
        "WHERE lower(hex(txid)) = '${_walletDbTxidHex(expiringTxid)}';",
      );
      e2eLog(
        'forced one part of run $originalRunId to expire at tip $chainHeight',
      );

      final statusRequest = IronwoodMigrationStatusRequest(
        network: 'regtest',
        accountUuid: accountUuid,
      );
      container.invalidate(ironwoodMigrationStatusProvider(statusRequest));
      await container.read(
        ironwoodMigrationStatusProvider(statusRequest).future,
      );
      await tester.pump();

      final replacement = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == originalRunId &&
            status.scheduledBroadcasts.isNotEmpty &&
            status.scheduledBroadcasts
                    .map((broadcast) => broadcast.txidHex)
                    .toSet()
                    .difference(originalTxids)
                    .length ==
                1,
        description: 'same-run replacement migration transactions',
        timeout: const Duration(minutes: 3),
      );
      expect(replacement.targetValuesZatoshi, orderedEquals(originalTargets));
      expect(replacement.phase, 'broadcast_scheduled');

      final recovered = await _runSqlite(
        dbPath,
        "SELECT phase || ':' || "
        "(SELECT COUNT(*) FROM vizor_migration_prepared_notes "
        " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
        " AND lock_state = 'locked') || ':' || "
        "(SELECT COUNT(*) FROM vizor_migration_pending_txs "
        " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
        " AND status = 'needs_resign') "
        "FROM vizor_migration_runs "
        "WHERE run_id = '${_sqlLiteral(originalRunId)}';",
      );
      expect(
        recovered.trim(),
        'broadcast_scheduled:${originalTargets.length}:0',
      );

      await ironwoodDriverPost(
        _driverUrl,
        '/node/restart',
        timeout: const Duration(minutes: 5),
      );

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

Future<String> _runSqlite(String dbPath, String sql) async {
  final result = await Process.run('sqlite3', [dbPath, sql]);
  if (result.exitCode != 0) {
    throw StateError('sqlite3 failed: ${result.stderr}');
  }
  return result.stdout as String;
}

String _sqlLiteral(String value) => value.replaceAll("'", "''");

String _walletDbTxidHex(String displayTxid) {
  final bytePairs = RegExp(
    '..',
  ).allMatches(displayTxid).map((match) => match.group(0)!).toList();
  return bytePairs.reversed.join();
}
