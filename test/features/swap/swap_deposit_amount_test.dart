import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';

void main() {
  test('software ZEC deposit uses quote base units, not display text', () {
    final quote = _quote(
      sellAmountTextOverride: '0.001 ZEC',
      sellAmountBaseUnits: BigInt.from(150000000),
    );

    expect(zecDepositAmountZatoshiForQuote(quote), BigInt.from(150000000));
  });

  test('software ZEC deposit rejects quotes without base units', () {
    final quote = _quote(sellAmountTextOverride: '1.5 ZEC');

    expect(
      () => zecDepositAmountZatoshiForQuote(quote),
      throwsA(isA<StateError>()),
    );
  });

  test('hardware ZEC deposit uses intent base units, not display text', () {
    final intent = _intent(
      sellAmount: '0.001 ZEC',
      sellAmountBaseUnits: BigInt.from(150000000),
    );

    expect(zecDepositAmountZatoshiForIntent(intent), BigInt.from(150000000));
  });

  test('hardware ZEC deposit rejects intents without base units', () {
    final intent = _intent(sellAmount: '1.5 ZEC');

    expect(
      () => zecDepositAmountZatoshiForIntent(intent),
      throwsA(isA<StateError>()),
    );
  });
}

SwapQuote _quote({
  String? sellAmountTextOverride,
  BigInt? sellAmountBaseUnits,
}) {
  return SwapQuote(
    direction: SwapDirection.zecToExternal,
    sellAsset: SwapAsset.zec,
    receiveAsset: SwapAsset.usdc,
    externalAsset: SwapAsset.usdc,
    sellAmount: 0.001,
    receiveAmount: 0.07,
    minimumReceiveAmount: 0.069,
    providerLabel: 'NEAR Intents',
    feeLabel: 'Included in shown rate',
    expiryLabel: '07:12',
    depositInstruction: const SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: 't1deposit',
      expiresInLabel: '07:12',
      reuseWarning: 'Do not reuse this address',
    ),
    sellAmountTextOverride: sellAmountTextOverride,
    sellAmountBaseUnits: sellAmountBaseUnits,
  );
}

SwapIntent _intent({required String sellAmount, BigInt? sellAmountBaseUnits}) {
  return SwapIntent(
    id: 't1deposit',
    pair: 'ZEC -> USDC',
    sellAmount: sellAmount,
    sellAmountBaseUnits: sellAmountBaseUnits,
    receiveEstimate: '0.07 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingDeposit,
    nextAction: 'Sign deposit',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1deposit',
  );
}
