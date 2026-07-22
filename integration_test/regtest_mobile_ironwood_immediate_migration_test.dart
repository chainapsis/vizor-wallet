import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'broadcasts Immediate migration in the foreground and returns home',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        try {
          await postDriver('/lightwalletd/start', const {});
        } catch (_) {
          // The runner will reset the regtest stack after an unsuccessful run.
        }
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '0.01095 $mobileE2eTicker');

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
      );

      await postDriver('/activate', const {});
      await _waitForIronwoodSync(tester, container);
      await openMobileMigrationOptions(tester);
      await tapWidget(
        tester,
        const ValueKey('mobile_ironwood_immediate_option'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_options_continue_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_immediate_broadcast_button'),
          ),
        ),
        description: 'Immediate migration review',
      );

      logE2e('stopping lightwalletd to hold the Immediate broadcast');
      await postDriver('/lightwalletd/stop', const {});
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_immediate_broadcast_button'),
        timeout: const Duration(minutes: 2),
      );
      await pumpUntil(tester, () {
        final button = find.byKey(
          const ValueKey('mobile_ironwood_immediate_broadcast_button'),
        );
        final appButton = find.descendant(
          of: button,
          matching: find.byType(AppButton),
          matchRoot: true,
        );
        return tester.any(find.byType(CircularProgressIndicator)) &&
            tester.widget<AppButton>(appButton).onPressed == null;
      }, description: 'Immediate broadcast loading state');

      await postDriver('/lightwalletd/start', const {});
      await waitForHome(tester);

      final accountUuid = await accountUuidAtOrder(0);
      await waitForMobileRegtestMempoolSize(
        tester,
        1,
        timeout: const Duration(minutes: 5),
      );

      await postDriver('/mine', const {'blocks': 10});
      final balance = await _waitForImmediateIronwoodBalance(
        tester,
        accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(balance.ironwood, greaterThan(BigInt.zero));
      expect(orchardResidual, BigInt.zero);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<rust_sync.WalletBalance> _waitForImmediateIronwoodBalance(
  WidgetTester tester,
  String accountUuid,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    final balance = await rust_sync.getBalance(
      dbPath: await getWalletDbPath(),
      network: mobileE2eNetwork,
      accountUuid: accountUuid,
    );
    if (balance.ironwood > BigInt.zero && balance.orchard == BigInt.zero) {
      return balance;
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out waiting for Immediate migration to confirm in Ironwood.');
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
    description: 'idle mobile Immediate-migration sync',
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
    description: 'active Ironwood Immediate-migration sync',
    timeout: const Duration(minutes: 5),
  );
}
