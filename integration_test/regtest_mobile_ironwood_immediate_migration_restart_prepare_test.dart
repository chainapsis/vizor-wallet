import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists a signed immediate migration while lightwalletd is unavailable',
    (tester) async {
      tolerateRenderOverflows();
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
      await openMobileImmediateMigrationReview(tester);
      await tapWidget(
        tester,
        const ValueKey('mobile_ironwood_fast_acknowledgement'),
      );

      logE2e('stopping lightwalletd before immediate migration broadcast');
      await postDriver('/lightwalletd/stop', const {});
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_immediate_start_button'),
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final interrupted = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.totalCount > 0 &&
            status.scheduledBroadcasts.length == status.totalCount,
        description: 'persisted signed immediate migration',
        timeout: const Duration(minutes: 5),
      );
      expect(interrupted.broadcastedTxCount, 0);
      expect(interrupted.confirmedTxCount, 0);
      expect(
        interrupted.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        hasLength(interrupted.totalCount),
      );
      await waitForMobileRegtestMempoolSize(tester, 0);
      await snapshotWalletDbToDriver();
    },
    timeout: const Timeout(Duration(minutes: 20)),
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
    description: 'idle mobile wallet sync at $targetHeight',
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
    description: 'active Ironwood chain and completed mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
