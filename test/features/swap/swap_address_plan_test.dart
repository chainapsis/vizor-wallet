import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test(
    'ZEC to external maps external address to recipient and UA to refund',
    () {
      final plan = SwapAddressPlan.fromUserInput(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0xrecipient',
        walletZecAddress: 'u1wallet-refund',
      );

      expect(plan.oneClickRecipient, '0xrecipient');
      expect(plan.oneClickRefundTo, 'u1wallet-refund');
      expect(plan.toQuoteRequest(sellAmount: 1.5).destination, '0xrecipient');
      expect(
        plan.toQuoteRequest(sellAmount: 1.5).refundAddress,
        'u1wallet-refund',
      );
      final exactOutput = plan.toQuoteRequest(
        mode: SwapQuoteMode.exactOutput,
        amount: 105.25,
        amountText: '105.25',
      );
      expect(exactOutput.mode, SwapQuoteMode.exactOutput);
      expect(exactOutput.amountAsset, SwapAsset.usdc);
      expect(exactOutput.amount, 105.25);
    },
  );

  test('external to ZEC maps wallet UA to recipient', () {
    final plan = SwapAddressPlan.fromUserInput(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrefund',
      walletZecAddress: 'u1wallet-recipient',
    );

    expect(plan.oneClickRecipient, 'u1wallet-recipient');
    expect(plan.oneClickRefundTo, '0xrefund');
    expect(
      plan.toQuoteRequest(sellAmount: 140.35).destination,
      'u1wallet-recipient',
    );
    expect(plan.toQuoteRequest(sellAmount: 140.35).refundAddress, '0xrefund');
  });

  test('rejects empty user or wallet addresses', () {
    expect(
      () => SwapAddressPlan.fromUserInput(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '',
        walletZecAddress: 'u1wallet-recipient',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => SwapAddressPlan.fromUserInput(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0xrefund',
        walletZecAddress: ' ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
