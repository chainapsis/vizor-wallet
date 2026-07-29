import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';

/// Mobile regtest E2E: an externally funded unmined tx must appear in
/// the mobile activity as a pending receive and confirm after mining —
/// the steady-mode counterpart of regtest_mempool_receive_history_test.
/// The runner script starts the python driver that performs the
/// host-side funding/mining.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'shows mempool receives in the mobile activity before mining',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await importWalletViaPaste(
        tester,
        mnemonic: _mnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
      await waitForMempoolObserver();

      logE2e('copying first account shielded address');
      final address = await copyShieldedAddress(tester);
      expect(address, startsWith('uregtest1'));
      final accountUuid = await accountUuidAtOrder(0);

      final txid = await fundUnmined(address, '0.25');
      logE2e('external unmined funding txid=$txid');
      await waitForHistoryTx(
        tester,
        accountUuid: accountUuid,
        txidHex: txid,
        txKind: 'receiving',
        displayAmount: BigInt.from(25_000_000),
      );
      // The activity tab fetches fresh history on open; assert the
      // pending receive there first, then the home recent row (which
      // updates via the mempool refresh follow-ups).
      await openActivityTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_activity_row_0'),
        title: 'Receiving...',
        amount: '+0.25 $mobileE2eTicker',
      );
      await openHomeTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Receiving...',
        amount: '+0.25 $mobileE2eTicker',
      );

      await mineRegtestBlocks(10);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Received',
        amount: '+0.25 $mobileE2eTicker',
      );
      expectNoActivityRow(
        tester,
        rowKeyPrefix: 'mobile_home_activity',
        title: 'Receiving...',
        amount: '+0.25 $mobileE2eTicker',
      );
      await openActivityTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_activity_row_0'),
        title: 'Received',
        amount: '+0.25 $mobileE2eTicker',
      );
      await waitForShieldedBalance2(tester, '1.50 $mobileE2eTicker');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Balance check that first returns to the home tab.
Future<void> waitForShieldedBalance2(
  WidgetTester tester,
  String expected,
) async {
  await openHomeTab(tester);
  await waitForShieldedBalance(tester, expected);
}
