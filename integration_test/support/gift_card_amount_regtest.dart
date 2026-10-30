import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/features/send/services/send_amount_conversion.dart';

const _amountMode = String.fromEnvironment(
  'GIFT_CARD_E2E_AMOUNT_MODE',
  defaultValue: 'zec',
);
const _usdPrice = 125.5;

/// Only the price is deterministic; funding, mining, and claiming use regtest.
Future<Widget> buildGiftCardAmountRegtestApp() {
  if (!const ['zec', 'usd', 'usd-max'].contains(_amountMode)) {
    throw StateError('Unknown Gift Card E2E amount mode: $_amountMode');
  }
  return buildBootstrappedZcashWalletApp(
    overrides: [
      if (_amountMode != 'zec')
        zecLiveUsdUnitPriceProvider.overrideWithValue(_usdPrice),
    ],
  );
}

Future<BigInt> enterGiftCardRegtestAmount(
  WidgetTester tester, {
  required String sourceAccountUuid,
  required Future<void> Function(Key) tap,
  required Future<void> Function(Key, String) enter,
}) async {
  const editor = ValueKey('payment_link_amount_editor');
  const usd = ValueKey('payment_link_amount_currency_usd');
  const zec = ValueKey('payment_link_amount_currency_zec');
  final amount = BigInt.from(10000000);
  await enter(editor, '0.1');
  if (_amountMode == 'zec') return amount;

  // Check both directions before funding the card in USD.
  await tap(usd);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    tester.widget<EditableText>(find.byKey(editor)).controller.text,
    '12.55',
  );
  await tap(zec);
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    tester.widget<EditableText>(find.byKey(editor)).controller.text,
    '0.1',
  );
  await tap(usd);
  await tester.pump(const Duration(milliseconds: 250));

  if (_amountMode == 'usd') {
    await enter(editor, '12.55');
    return amount;
  }

  final operations = ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  ).read(paymentLinkOperationsProvider);
  final quote = await operations.quoteMaxFunding(
    sourceAccountUuid: sourceAccountUuid,
  );
  await tap(const ValueKey('payment_link_max_button'));
  await tester.pump();
  expect(
    find.text('≈ ${formatZecAmount(quote.recipientAmountZatoshi)} ZEC'),
    findsOneWidget,
  );
  // The fixture deliberately makes the rounded USD field lose precision.
  // The copied link and receiver balance must still use the exact ZEC quote.
  final visibleUsd = tester
      .widget<EditableText>(find.byKey(editor))
      .controller
      .text;
  expect(
    sendZatoshiFromUsdText(visibleUsd, _usdPrice),
    isNot(quote.recipientAmountZatoshi),
  );
  return quote.recipientAmountZatoshi;
}
