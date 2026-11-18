import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_support_details.dart';

import '../../support/test_l10n.dart';

SwapIntent _intent() => SwapIntent(
  id: 'local-only-id',
  pair: 'USDC -> ZEC',
  sellAmount: '113000 USDC',
  receiveEstimate: '116 ZEC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.failed,
  nextAction: 'Failed',
  providerStatusRaw: 'FAILED',
  depositAddress: '0xdeposit',
  originChainTxHash: 'origin-tx',
  oneClickRecipient: 'private-recipient',
  oneClickRefundTo: 'private-refund-address',
);

void main() {
  test('only failed and expired unrefunded intents offer support', () {
    for (final status in SwapIntentStatus.values) {
      expect(
        swapNeedsSupportNotice(_intent().copyWith(status: status)),
        status == SwapIntentStatus.failed || status == SwapIntentStatus.expired,
        reason: status.name,
      );
    }
    expect(
      swapNeedsSupportNotice(_intent().copyWith(startPending: true)),
      isFalse,
    );
    for (final refund in [null, '0 USDC', '0.0000 USDC', '2.3 USDC']) {
      expect(
        swapNeedsSupportNotice(
          _intent().copyWith(
            providerRefundInfo: SwapProviderRefundInfo(
              refundedAmountText: refund,
            ),
          ),
        ),
        refund != '2.3 USDC',
      );
    }
  });

  test('copied support details exclude unrelated wallet data', () {
    final body = swapSupportDetails(testL10n, _intent());
    expect(body, contains('origin-tx'));
    expect(
      body,
      contains('https://explorer.near-intents.org/transactions/0xdeposit'),
    );
    for (final omitted in [
      '113000',
      '116 ZEC',
      'private-recipient',
      'private-refund-address',
      'local-only-id',
    ]) {
      expect(body, isNot(contains(omitted)));
    }
    expect(body, contains('\n\n'));
  });

  test('known deposit tx takes precedence over the origin fallback', () {
    expect(
      swapSupportDetails(
        testL10n,
        _intent().copyWith(depositTxHash: 'deposit-tx'),
      ),
      contains('Deposit transaction: deposit-tx'),
    );
    expect(
      swapSupportDetails(testL10n, _intent().copyWith(depositTxHash: '   ')),
      contains('Deposit transaction: origin-tx'),
    );
  });
}
