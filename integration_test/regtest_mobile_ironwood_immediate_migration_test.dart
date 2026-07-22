import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

final _fundedAmount = BigInt.from(1095000);

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
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'Immediate migration broadcast run',
        timeout: const Duration(minutes: 5),
      );
      expect(started.activeRunId, isNotNull);
      await waitForMobileRegtestMempoolSize(
        tester,
        1,
        timeout: const Duration(minutes: 5),
      );

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.scheduledBroadcasts.isNotEmpty,
        description: 'Immediate migration scheduled transfers',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.totalCount, greaterThan(0));
      final submitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(
        submitted.broadcastedTxCount + submitted.confirmedTxCount,
        submitted.totalCount,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.activeRunId == null,
        description: 'completed Immediate migration',
        timeout: const Duration(minutes: 5),
      );
      expect(complete.confirmedTxCount, complete.totalCount);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(balance.ironwood, BigInt.from(1000000));
      expect(
        _fundedAmount - balance.ironwood - orchardResidual,
        BigInt.from(95000),
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
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
