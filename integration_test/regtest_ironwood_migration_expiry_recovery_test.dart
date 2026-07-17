import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
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
    'retires an expired migration and starts a fresh approved run',
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
            '1.0002',
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

      final accountUuid = await firstDesktopRegtestAccountUuid();
      final original = await desktopRegtestMigrationStatus(accountUuid);
      final originalRunId = original.activeRunId;
      expect(originalRunId, isNotNull);

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 12},
      );
      final scheduled = await prepareDesktopRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(scheduled.activeRunId, originalRunId);
      expect(scheduled.scheduledBroadcasts, isNotEmpty);

      await stopRustWorkForCleanup();
      final chain = await ironwoodDriverGet(_driverUrl, '/status');
      final chainHeight = (chain['zcashdHeight'] as num).toInt();
      final dbPath = await getWalletDbPath();
      await _runSqlite(
        dbPath,
        "UPDATE vizor_migration_pending_txs "
        "SET expiry_height = $chainHeight "
        "WHERE run_id = '${_sqlLiteral(originalRunId!)}';",
      );
      e2eLog('forced run $originalRunId to expire at current tip $chainHeight');

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_status_action_button'),
      );
      await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == null && status.phase == 'ready_to_prepare',
        description: 'expired run retirement',
        timeout: const Duration(minutes: 2),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('ironwood_migration_intro_continue_button'),
          ),
        ),
        description: 'fresh migration intro after expiry',
      );

      final retired = await _runSqlite(
        dbPath,
        "SELECT phase || ':' || "
        "(SELECT COUNT(*) FROM vizor_migration_prepared_notes "
        " WHERE run_id = '${_sqlLiteral(originalRunId)}' "
        " AND lock_state = 'locked') "
        "FROM vizor_migration_runs "
        "WHERE run_id = '${_sqlLiteral(originalRunId)}';",
      );
      expect(retired.trim(), 'failed_terminal:0');

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_intro_continue_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_how_it_works_continue_button'),
      );
      await tapAppWidget(
        tester,
        const ValueKey('ironwood_migration_private_option'),
      );
      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_select_review_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_authorize_start_button'),
      );

      final replacement = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId != null,
        description: 'replacement migration run',
        timeout: const Duration(minutes: 3),
      );
      expect(replacement.activeRunId, isNot(originalRunId));
      expect(replacement.phase, 'waiting_denom_confirmations');
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
