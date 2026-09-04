import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

/// Mobile regtest E2E: the mobile twin of
/// regtest_payment_uri_send_test.dart. A `zcash:` URI delivered over the
/// native `com.zcash.wallet/payment_uri` channel must raise the
/// payment-request card over whatever the mobile shell is showing, and be
/// answered from it — Review hands the card's proposal to the mobile send
/// review, which broadcasts a real regtest transaction.
const _paymentUriChannel = 'com.zcash.wallet/payment_uri';
const _firstMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
const _sendAmount = '0.25';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'opening a zcash: payment URI prefills and sends shielded funds on mobile',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app for the mobile payment-URI send');
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

      // The heart of this test: a zcash: URI must raise the payment-request
      // card and be answered from it, not typed into the composer by hand.
      await _sendViaPaymentUri(tester, secondAddress, _sendAmount);

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
        title: 'Receiving...',
        amount: '+$_sendAmount $mobileE2eTicker',
      );
      logE2e('second account observed the incoming payment-URI transaction');

      await mineRegtestBlocks(10);

      await openHomeTab(tester);
      await waitForShieldedBalance(tester, '$_sendAmount $mobileE2eTicker');
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Received',
        amount: '+$_sendAmount $mobileE2eTicker',
      );
      logE2e('second account received the payment-URI funds');

      await switchAccountTo(tester, firstUuid);
      await expectActivityRow(
        tester,
        const ValueKey('mobile_home_activity_row_0'),
        title: 'Sent',
        amount: '-$_sendAmount $mobileE2eTicker',
      );
      logE2e('first account sent activity matched');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

/// Simulates the native side delivering a `zcash:` deep link, then asserts the
/// payment-request card presents it and drives Review → Confirm to completion.
Future<void> _sendViaPaymentUri(
  WidgetTester tester,
  String address,
  String amount,
) async {
  final uri = 'zcash:$address?amount=$amount';
  logE2e('injecting payment URI: $uri');

  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _paymentUriChannel,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onUris', <String>[uri]),
    ),
    (_) {},
  );

  // The URI is parsed and drained onto the payment-request card, over
  // whatever the wallet was showing — it is not a jump into the composer.
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('payment_request_continue'))) &&
        keyedTextEquals(
          tester,
          const ValueKey('payment_request_amount'),
          '$amount ${mobileE2eTicker.toUpperCase()}',
        ),
    description: 'the payment-request card to show the requested amount',
    timeout: const Duration(minutes: 1),
  );
  logE2e('payment-request card raised from payment URI');

  await tapAppButton(
    tester,
    const ValueKey('payment_request_continue'),
    timeout: const Duration(minutes: 1),
  );
  await pumpUntil(
    tester,
    () => tester.any(find.text('Review payment request')),
    description: 'the mobile payment-request review step',
    timeout: const Duration(minutes: 1),
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_send_confirm'),
    timeout: const Duration(minutes: 1),
  );
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_send_status_succeeded'))),
    description: 'send status to succeed',
    timeout: const Duration(minutes: 4),
  );
  await tapAppButton(tester, const ValueKey('mobile_send_status_button'));
  await waitForHome(tester);
  logE2e('payment-URI send succeeded');
}
