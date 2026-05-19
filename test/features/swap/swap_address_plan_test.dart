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
      expect(
        plan.zecStagingAddressPolicy,
        SwapZecStagingAddressPolicy.rotatingWalletUnifiedAddress,
      );
      expect(plan.zecShieldingPolicy, SwapZecShieldingPolicy.notRequired);
      expect(plan.userInputLabel, 'Destination');
      expect(plan.userInputHint, 'External USDC address or account');
      expect(
        plan.deliverySummary,
        'USDC is delivered to the external destination',
      );
      expect(plan.toQuoteRequest(sellAmount: 1.5).destination, '0xrecipient');
      expect(
        plan.toQuoteRequest(sellAmount: 1.5).refundAddress,
        'u1wallet-refund',
      );
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
    expect(plan.userInputLabel, 'USDC refund address');
    expect(plan.userInputHint, 'Refund address on the USDC source chain');
    expect(plan.zecDeliveryIsDirectShielded, isTrue);
    expect(
      plan.deliverySummary,
      'ZEC arrives directly at the shielded wallet address',
    );
    expect(plan.reviewDeliveryValue, 'shielded wallet address');
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
