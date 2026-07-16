import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _network = 'regtest';
final _fundedAmount = BigInt.from(100020000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'runs the desktop app from Orchard through a complete Ironwood migration',
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

      expect(
        find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('home_desktop_ironwood_migration_cta_button'),
        ),
        findsNothing,
      );

      e2eLog('activating Ironwood while the Flutter app is running');
      await ironwoodDriverPost(_driverUrl, '/activate');
      final activeChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(activeChain['ironwoodActive'], isTrue);
      expect(activeChain['consensusBranchId'], '37a5165b');

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final chain = providerContainer
              .read(chainUpgradeStatusProvider)
              .value;
          final sync = providerContainer.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >= 500;
        },
        description: 'active Ironwood chain and completed wallet sync',
        timeout: const Duration(minutes: 5),
      );
      final inputs = providerContainer.read(ironwoodMigrationInputsProvider);
      final accountUuid = await _firstAccountUuid();
      final initialMigration = await _migrationStatus(accountUuid);
      e2eLog(
        'migration inputs: active=${inputs.ironwoodActiveAtTip}, '
        'scoped=${inputs.hasAccountScopedData}, syncing=${inputs.isSyncing}, '
        'orchard=${inputs.orchardBalance}; phase=${initialMigration.phase}',
      );
      final request = inputs.statusRequest!;
      final cachedMigration = await providerContainer.read(
        ironwoodMigrationStatusProvider(request).future,
      );
      final announcement = await providerContainer.read(
        ironwoodMigrationAnnouncementProvider.future,
      );
      e2eLog(
        'provider state: cachedPhase=${cachedMigration.phase}, '
        'announcementVisible=${announcement.visible}',
      );

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood announcement after activation',
        timeout: const Duration(minutes: 5),
      );

      final announcementOverlay = find.byKey(
        const ValueKey('ironwood_migration_announcement_overlay'),
      );
      final overlayOrigin = tester.getTopLeft(announcementOverlay);
      await tester.tapAt(overlayOrigin + const Offset(16, 16));
      await tester.pump(const Duration(milliseconds: 250));
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'dismissed announcement to disappear',
      );
      await tapAppButton(
        tester,
        const ValueKey('home_desktop_ironwood_migration_cta_button'),
      );

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
        const ValueKey('ironwood_migration_fast_option'),
      );
      final selectButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('ironwood_migration_select_review_button')),
      );
      expect(selectButton.onPressed, isNull);
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

      final started = await _migrationStatus(accountUuid);
      expect(started.activeRunId, isNotNull);
      expect(started.denominationSplitTotalCount, greaterThan(0));
      expect(started.denominationSplitCompletedCount, 0);

      e2eLog('locking and restoring the wallet with an active migration run');
      providerContainer.read(appSecurityProvider.notifier).lock();
      await enterAppText(
        tester,
        const ValueKey('unlock_password_field'),
        desktopRegtestPassword,
      );
      await tapAppButton(tester, const ValueKey('unlock_submit_button'));
      await tapAppButton(
        tester,
        const ValueKey('home_desktop_ironwood_migration_cta_button'),
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
        description: 'active migration status after unlock',
      );
      final resumed = await _migrationStatus(accountUuid);
      expect(resumed.activeRunId, started.activeRunId);

      e2eLog('confirming denomination split');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );

      await pumpUntil(
        tester,
        () =>
            tester.any(
              find.byKey(
                const ValueKey('ironwood_migration_status_broadcast_scheduled'),
              ),
            ) ||
            tester.any(
              find.byKey(
                const ValueKey(
                  'ironwood_migration_status_waiting_migration_confirmations',
                ),
              ),
            ),
        description: 'migration broadcast scheduling',
        timeout: const Duration(minutes: 5),
      );

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey(
              'ironwood_migration_status_waiting_migration_confirmations',
            ),
          ),
        ),
        description: 'migration transaction broadcast',
        timeout: const Duration(minutes: 5),
      );

      final broadcast = await _migrationStatus(accountUuid);
      expect(broadcast.broadcastedTxCount, greaterThan(0));
      expect(broadcast.totalCount, greaterThan(0));

      e2eLog('confirming Ironwood migration transaction');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_status_complete')),
        ),
        description: 'completed migration status',
        timeout: const Duration(minutes: 5),
      );

      final complete = await _migrationStatus(accountUuid);
      expect(complete.phase, 'complete');
      expect(complete.confirmedTxCount, complete.totalCount);

      final dbPath = await getWalletDbPath();
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
      );
      expect(
        balance.ironwood,
        greaterThan(_fundedAmount - BigInt.from(1000000)),
      );
      expect(balance.ironwood, lessThan(_fundedAmount));
      expect(balance.orchard, BigInt.zero);

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_status_action_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
        description: 'home after completed migration',
      );
      expect(
        find.byKey(
          const ValueKey('home_desktop_ironwood_migration_cta_button'),
        ),
        findsNothing,
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<String> _firstAccountUuid() async {
  final dbPath = await getWalletDbPath();
  final accounts = await rust_wallet.listAccounts(
    dbPath: dbPath,
    network: _network,
  );
  expect(accounts, hasLength(1));
  return accounts.single.uuid;
}

Future<rust_sync.MigrationStatus> _migrationStatus(String accountUuid) async {
  return rust_sync.getOrchardMigrationStatus(
    dbPath: await getWalletDbPath(),
    network: _network,
    accountUuid: accountUuid,
  );
}
