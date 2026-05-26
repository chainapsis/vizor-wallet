import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_fiat_amount.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';

void main() {
  test('converts ZEC token amount to fiat display text', () {
    final state = _stateWithUsdRate(70);

    expect(
      swapFiatDisplayText(state, asset: SwapAsset.zec, tokenAmountText: '1.5'),
      r'$105',
    );
    expect(
      swapFiatInputTextFromTokenText(
        state,
        asset: SwapAsset.zec,
        tokenAmountText: '0.01',
      ),
      '0.7',
    );
    expect(
      swapFiatDisplayText(
        state,
        asset: SwapAsset.zec,
        tokenAmountText: '1.4999',
      ),
      r'$104',
    );
  });

  test('converts fiat text back into token amount text', () {
    final state = _stateWithUsdRate(70);

    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.zec,
        fiatAmountText: '105',
      ),
      '1.5000',
    );
    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.usdc,
        fiatAmountText: '105.26',
      ),
      '105.26',
    );
  });

  test('fiat conversion never rounds executable token amount up', () {
    final state = _stateWithUsdRate(70);

    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.zec,
        fiatAmountText: '100',
      ),
      '1.4285',
    );
    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.usdc,
        fiatAmountText: '105.269',
      ),
      '105.26',
    );
  });

  test('returns null when fiat conversion is unavailable for the asset', () {
    final state = _stateWithUsdRate(70);

    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.eth,
        fiatAmountText: '25',
      ),
      isNull,
    );
  });
}

SwapPrototypeState _stateWithUsdRate(double usdcPerZec) {
  return SwapPrototypeState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    externalRequests: const [],
    requestImportText: '',
    indicativeExternalPerZec: {SwapAsset.usdc: usdcPerZec},
  );
}
