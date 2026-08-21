import 'dart:convert';

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
  defaultValue: 'http://127.0.0.1:39078',
);
const _lightwalletdUrl = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
  defaultValue: 'http://127.0.0.1:19067',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'prepares a confirmed Ironwood note for the voting E2E',
    (tester) async {
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
            '0.13',
        description: 'funded Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
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
        description: 'wallet sync through NU6.3 activation',
        timeout: const Duration(minutes: 5),
      );

      final account = (await desktopRegtestAccounts()).single;
      final dbPath = await getWalletDbPath();
      final plan = await rust_sync.getOrchardMigrationImmediatePlan(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: account.uuid,
      );
      expect(plan, isNotNull);
      final approved = plan!;
      final result = await rust_sync.migrateOrchardToIronwoodImmediately(
        dbPath: dbPath,
        lightwalletdUrl: _lightwalletdUrl,
        network: 'regtest',
        accountUuid: account.uuid,
        mnemonicBytes: utf8.encode(desktopRegtestMnemonic),
        approvedTotalInputZatoshi: approved.totalInputZatoshi,
        approvedFeeZatoshi: approved.feeZatoshi,
        approvedMigratedZatoshi: approved.migratedZatoshi,
        approvedInputNoteCount: approved.inputNoteCount,
      );
      expect(result.broadcastedCount, 1);

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await container.read(syncProvider.notifier).startSyncAnyway();
      rust_sync.WalletBalance? balance;
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(seconds: 1));
        balance = await rust_sync.getBalance(
          dbPath: dbPath,
          network: 'regtest',
          accountUuid: account.uuid,
        );
        if (balance.ironwood > BigInt.zero) {
          break;
        }
      }
      expect(
        balance?.ironwood,
        greaterThan(BigInt.zero),
        reason: 'immediate migration must create confirmed voting power',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
