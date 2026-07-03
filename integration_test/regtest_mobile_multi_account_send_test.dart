import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

const _firstMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';

/// Mobile regtest E2E: import two wallets, send shielded funds from the
/// first to the second through the send wizard, and watch the pending
/// receive confirm — the mobile counterpart of
/// regtest_multi_account_send_test.dart.
///
/// Mobile activity rows carry the Receiving/Received/Sent titles from
/// the shared mappers; the desktop status texts are asserted only via
/// the title transition here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'sends shielded funds between two imported accounts on mobile',
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
        mnemonic: _firstMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');

      await openAddAccountFlow(tester);
      await importWalletViaPaste(
        tester,
        mnemonic: _secondMnemonic,
        birthdayHeight: 1,
        isFirstWallet: false,
      );

      logE2e('copying second account shielded address');
      final secondAddress = await copyShieldedAddress(tester);
      expect(secondAddress, startsWith('uregtest1'));
      final firstUuid = await accountUuidAtOrder(0);
      final secondUuid = await accountUuidAtOrder(1);

      await switchAccountTo(tester, firstUuid);
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
      await waitForMempoolObserver();

      await sendViaWizard(
        tester,
        address: secondAddress,
        amountDigits: '0.25',
      );

      await switchAccountTo(tester, secondUuid);
      await waitForHistoryEntry(
        tester,
        accountUuid: secondUuid,
        txKind: 'receiving',
        displayAmount: BigInt.from(25_000_000),
        pending: true,
      );
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Receiving',
        amount: '+0.25 $mobileE2eTicker',
      );
      await openActivityTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_activity_row_0'),
        title: 'Receiving',
        amount: '+0.25 $mobileE2eTicker',
      );

      await mineRegtestBlocks(10);

      await openHomeTab(tester);
      await waitForShieldedBalance(tester, '0.25 $mobileE2eTicker');
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Received',
        amount: '+0.25 $mobileE2eTicker',
      );
      expectNoActivityRow(
        tester,
        rowKeyPrefix: 'mobile_home_activity',
        title: 'Receiving',
        amount: '+0.25 $mobileE2eTicker',
      );
      await openActivityTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_activity_row_0'),
        title: 'Received',
        amount: '+0.25 $mobileE2eTicker',
      );
      expectNoActivityRow(
        tester,
        rowKeyPrefix: 'mobile_activity',
        title: 'Receiving',
        amount: '+0.25 $mobileE2eTicker',
      );
      logE2e('second account received shielded funds');

      await openHomeTab(tester);
      await switchAccountTo(tester, firstUuid);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Sent',
        amount: '-0.25 $mobileE2eTicker',
      );
      await openActivityTab(tester);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_activity_row_0'),
        title: 'Sent',
        amount: '-0.25 $mobileE2eTicker',
      );
      logE2e('first account sent activity matched');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
