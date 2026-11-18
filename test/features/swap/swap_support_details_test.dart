import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_support_details.dart';

import '../../support/test_l10n.dart';

SwapIntent _intent({String? originTx = 'origin-tx'}) => SwapIntent(
  id: 'local-only-id',
  pair: 'USDC -> ZEC',
  sellAmount: '113000 USDC',
  receiveEstimate: '116 ZEC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.failed,
  nextAction: 'Failed',
  providerStatusRaw: 'FAILED',
  depositAddress: '0xdeposit',
  originChainTxHash: originTx,
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

  test('failed support requires a confirmed or provider-observed deposit', () {
    final unfunded = _intent(originTx: null);
    expect(swapNeedsSupportNotice(unfunded), isFalse);
    final deposit = unfunded.copyWith(depositTxHash: 'local-deposit-tx');
    expect(swapNeedsSupportNotice(deposit), isTrue);
    expect(
      swapNeedsSupportNotice(
        deposit.copyWith(
          broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
        ),
      ),
      isFalse,
    );
    expect(
      swapNeedsSupportNotice(
        unfunded.copyWith(
          providerRefundInfo: const SwapProviderRefundInfo(
            depositedAmountText: '100 USDC',
          ),
        ),
      ),
      isTrue,
    );
    expect(
      swapNeedsSupportNotice(
        unfunded.copyWith(status: SwapIntentStatus.expired),
      ),
      isTrue,
    );
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

  test(
    'confidential support identifies the route without an explorer link',
    () {
      for (final status in [
        SwapIntentStatus.failed,
        SwapIntentStatus.expired,
      ]) {
        final body = swapSupportDetails(
          testL10n,
          _intent().copyWith(status: status, confidential: true),
        );
        expect(body, contains('Route: Confidential'));
        expect(body, contains('Deposit transaction: origin-tx'));
        expect(body, isNot(contains('Explorer:')));
        expect(body, isNot(contains('explorer.near-intents.org')));
      }
    },
  );

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
