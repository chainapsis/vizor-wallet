import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart' show desktopRegtestMnemonic;
import 'support/mobile_regtest_flow.dart';

const _fundingZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 13000000,
);
const _lightwalletdUrl = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
  defaultValue: 'http://127.0.0.1:19067',
);

/// Mobile mirror of `regtest_voting_ironwood_setup_test.dart`: imports the
/// deterministic regtest wallet through the mobile onboarding UI and creates
/// confirmed Ironwood voting power via the immediate migration. The voting
/// invocation that follows re-imports the same mnemonic (the iOS test runner
/// reinstalls the app between invocations, so the wallet DB does not
/// survive; the chain state does).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'prepares a confirmed Ironwood note for the mobile voting E2E',
    (tester) async {
      tolerateRenderOverflows();
      await cleanupE2eWalletState();
      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: desktopRegtestMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      final account = container.read(accountProvider).value!.accounts.single;
      final dbPath = await getWalletDbPath();

      logE2e('waiting for the funded Orchard balance to sync');
      rust_sync.WalletBalance? funded;
      final fundingDeadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(fundingDeadline)) {
        await tester.pump(const Duration(seconds: 1));
        funded = await rust_sync.getBalance(
          dbPath: dbPath,
          network: 'regtest',
          accountUuid: account.uuid,
        );
        if (funded.orchard >= BigInt.from(_fundingZatoshi)) break;
      }
      expect(
        funded?.orchard,
        greaterThanOrEqualTo(BigInt.from(_fundingZatoshi)),
        reason: 'funding manifest must have funded the deterministic wallet',
      );

      await postDriver('/activate', const {});
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

      await postDriver('/mine', const {'blocks': 10});
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
      logE2e('mobile voting setup complete; ironwood=${balance?.ironwood}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
