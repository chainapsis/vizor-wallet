import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test('ZEC to external maps external address to recipient', () {
    final plan = SwapAddressPlan.fromUserInput(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrecipient',
      walletTransparentAddress: 't1walletstaging',
    );

    expect(plan.oneClickRecipient, '0xrecipient');
    expect(plan.oneClickRefundTo, 't1walletstaging');
    expect(
      plan.zecStagingAddressPolicy,
      SwapZecStagingAddressPolicy.currentWalletTransparentAddress,
    );
    expect(plan.zecShieldingPolicy, SwapZecShieldingPolicy.promptAfterArrival);
    expect(plan.userInputLabel, 'Destination');
    expect(plan.userInputHint, 'External USDC address or account');
    expect(plan.zecDeliveryUsesWalletStaging, isFalse);
    expect(plan.toQuoteRequest(sellAmount: 1.5).destination, '0xrecipient');
    expect(
      plan.toQuoteRequest(sellAmount: 1.5).refundAddress,
      't1walletstaging',
    );
  });

  test('external to ZEC maps wallet staging address to recipient', () {
    final plan = SwapAddressPlan.fromUserInput(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrefund',
      walletTransparentAddress: 't1walletstaging',
    );

    expect(plan.oneClickRecipient, 't1walletstaging');
    expect(plan.oneClickRefundTo, '0xrefund');
    expect(plan.userInputLabel, 'USDC refund address');
    expect(plan.userInputHint, 'Refund address on the USDC source chain');
    expect(plan.zecDeliveryUsesWalletStaging, isTrue);
    expect(
      plan.deliverySummary,
      'ZEC arrives at the wallet receive address; shield prompt follows',
    );
    expect(
      plan.reviewDeliveryValue,
      'wallet receive address; shield prompt follows',
    );
    expect(
      plan.toQuoteRequest(sellAmount: 140.35).destination,
      't1walletstaging',
    );
    expect(plan.toQuoteRequest(sellAmount: 140.35).refundAddress, '0xrefund');
  });

  test('external to ZEC can model future rotating auto-shield delivery', () {
    final plan = SwapAddressPlan.fromUserInput(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      userExternalAddress: '0xrefund',
      walletTransparentAddress: 't1rotating',
      zecStagingAddressPolicy:
          SwapZecStagingAddressPolicy.rotatingWalletTransparentAddress,
      zecShieldingPolicy: SwapZecShieldingPolicy.automaticAfterArrival,
    );

    expect(plan.zecStagingIsRotating, isTrue);
    expect(plan.zecShieldingIsAutomatic, isTrue);
    expect(
      plan.reviewDeliveryValue,
      'reserved wallet receive address; auto-shield follows',
    );
  });

  test('rejects empty user or wallet addresses', () {
    expect(
      () => SwapAddressPlan.fromUserInput(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '',
        walletTransparentAddress: 't1walletstaging',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => SwapAddressPlan.fromUserInput(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0xrefund',
        walletTransparentAddress: ' ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
