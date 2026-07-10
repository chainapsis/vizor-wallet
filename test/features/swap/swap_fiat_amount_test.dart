import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/fiat_currencies.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_fiat_amount.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

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

  test('uses token price instead of assuming stablecoins are one dollar', () {
    final state = _stateWithUsdRate(70, usdcUsdPrice: 0.98);

    expect(
      swapFiatDisplayText(state, asset: SwapAsset.usdc, tokenAmountText: '10'),
      r'$9.8',
    );
    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.usdc,
        fiatAmountText: '98',
      ),
      '100.00',
    );
  });

  test('does not derive fiat values from route rates without unit prices', () {
    final state = _stateWithUsdRate(70, zecUsdPrice: null, usdcUsdPrice: null);

    expect(
      swapFiatDisplayText(state, asset: SwapAsset.zec, tokenAmountText: '1'),
      r'$--',
    );
    expect(
      swapFiatDisplayText(state, asset: SwapAsset.usdc, tokenAmountText: '70'),
      r'$--',
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
      swapFiatDisplayText(state, asset: SwapAsset.eth, tokenAmountText: '1'),
      r'$--',
    );
    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: SwapAsset.eth,
        fiatAmountText: '25',
      ),
      isNull,
    );
  });

  test('formats compact fiat display values', () {
    expect(formatCompactFiatValueFor(kUsdFiatCurrency, 0), r'$0.00');
    expect(formatCompactFiatValueFor(kUsdFiatCurrency, 1234.5), r'$1.23K');
    expect(formatCompactFiatValueFor(kUsdFiatCurrency, 1234567), r'$1.235M');
  });

  test('caps swap fiat digits for low-decimal display currencies', () {
    const krwDisplay = FiatDisplay(
      currency: FiatCurrency(code: 'krw', symbol: '₩', maxDecimals: 0),
      usdToCurrencyRate: 1,
    );
    const inrDisplay = FiatDisplay(
      currency: FiatCurrency(code: 'inr', symbol: '₹', maxDecimals: 1),
      usdToCurrencyRate: 1,
    );
    final state = _stateWithUsdRate(1, zecUsdPrice: 50.25);

    // Zero-decimal currency: no fractional units.
    expect(
      swapFiatDisplayText(
        state,
        asset: SwapAsset.zec,
        tokenAmountText: '1',
        fiatDisplay: krwDisplay,
      ),
      '₩50',
    );
    // One-decimal currency: a single fraction digit at most.
    expect(
      swapFiatDisplayText(
        state,
        asset: SwapAsset.zec,
        tokenAmountText: '1',
        fiatDisplay: inrDisplay,
      ),
      '₹50.2',
    );
    // Two-decimal currencies keep the pre-existing magnitude-based digits.
    expect(
      swapFiatDisplayText(state, asset: SwapAsset.zec, tokenAmountText: '1'),
      r'$50.25',
    );
  });
}

SwapState _stateWithUsdRate(
  double usdcPerZec, {
  double? zecUsdPrice = 70,
  double? usdcUsdPrice = 1,
}) {
  final usdPrices = <SwapAsset, double>{};
  if (zecUsdPrice != null) {
    usdPrices[SwapAsset.zec] = zecUsdPrice;
  }
  if (usdcUsdPrice != null) {
    usdPrices[SwapAsset.usdc] = usdcUsdPrice;
  }
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: {SwapAsset.usdc: usdcPerZec},
    indicativeUsdPrices: usdPrices,
  );
}
