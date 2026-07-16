import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39079',
);
final _fundedAmount = BigInt.from(100020000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'keeps an active Ironwood migration isolated to its account',
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
        description: 'funded first-account Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final firstAccount = (await desktopRegtestAccounts()).single;
      await importAdditionalDesktopRegtestWallet(tester);
      final accounts = await desktopRegtestAccounts();
      expect(accounts, hasLength(2));
      final secondAccount = accounts.singleWhere(
        (account) => account.uuid != firstAccount.uuid,
      );

      await switchDesktopRegtestAccount(tester, firstAccount.uuid);
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['zcashdHeight'] as num);
        },
        description: 'idle pre-Ironwood multi-account sync',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
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
        description: 'active Ironwood multi-account sync',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'first-account Ironwood announcement',
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
        description: 'first-account denomination status',
        timeout: const Duration(minutes: 5),
      );

      final started = await desktopRegtestMigrationStatus(firstAccount.uuid);
      expect(started.activeRunId, isNotNull);

      await switchDesktopRegtestAccount(tester, secondAccount.uuid);
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(
            const ValueKey('home_desktop_ironwood_migration_cta_button'),
          ),
        ),
        description: 'no migration CTA for the unfunded second account',
      );
      final secondStatus = await desktopRegtestMigrationStatus(
        secondAccount.uuid,
      );
      expect(secondStatus.activeRunId, isNull);
      expect(secondStatus.phase, 'no_orchard_funds');
      final firstWhileSecondActive = await desktopRegtestMigrationStatus(
        firstAccount.uuid,
      );
      expect(firstWhileSecondActive.activeRunId, started.activeRunId);

      await switchDesktopRegtestAccount(tester, firstAccount.uuid);
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
        description: 'first-account migration restored after account switch',
      );

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
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
        description: 'first-account migration broadcast',
        timeout: const Duration(minutes: 5),
      );
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
        description: 'first-account migration completion',
        timeout: const Duration(minutes: 5),
      );

      final complete = await desktopRegtestMigrationStatus(firstAccount.uuid);
      expect(complete.phase, 'complete');
      expect(complete.confirmedTxCount, complete.totalCount);

      final dbPath = await getWalletDbPath();
      final firstBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: firstAccount.uuid,
      );
      expect(firstBalance.orchard, BigInt.zero);
      expect(
        firstBalance.ironwood,
        greaterThan(_fundedAmount - BigInt.from(1000000)),
      );
      final secondBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: secondAccount.uuid,
      );
      expect(secondBalance.orchard, BigInt.zero);
      expect(secondBalance.ironwood, BigInt.zero);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
