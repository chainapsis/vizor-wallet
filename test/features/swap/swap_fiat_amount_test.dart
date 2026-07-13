import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_fiat_amount.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_fiat_value_formatting.dart';
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

  test('converts fiat through same-market live token variants', () {
    final weth = SwapAsset.live(
      assetId: 'nep141:eth-weth.omft.near',
      symbol: 'WETH',
      blockchain: 'eth',
      decimals: 18,
    );
    final gtUsdc = SwapAsset.live(
      assetId: 'nep141:base-gtusdcp.omft.near',
      symbol: 'gtUSDCp',
      blockchain: 'base',
      decimals: 18,
    );
    final state = _stateWithUsdPrices({
      SwapAsset.zec: 70,
      SwapAsset.eth: 2500,
      SwapAsset.usdc: 1,
    });

    expect(
      swapTokenAmountTextFromFiatText(state, asset: weth, fiatAmountText: '10'),
      '0.0040',
    );
    expect(
      swapTokenAmountTextFromFiatText(
        state,
        asset: gtUsdc,
        fiatAmountText: '25',
      ),
      '25.00',
    );
  });

  test('fiat conversion preserves small high-value token amounts', () {
    final xaut = SwapAsset.live(
      assetId:
          'nep141:eth-0x68749665ff8d2d112fa859aa293f07a622782f38.omft.near',
      symbol: 'XAUT',
      blockchain: 'eth',
      decimals: 6,
    );
    final state = _stateWithUsdPrices({SwapAsset.zec: 70, xaut: 3000});

    expect(
      swapTokenAmountTextFromFiatText(state, asset: xaut, fiatAmountText: '1'),
      '0.000333',
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
    expect(swapFormatCompactFiatValue(0), r'$0.00');
    expect(swapFormatCompactFiatValue(1234.5), r'$1.23K');
    expect(swapFormatCompactFiatValue(1234567), r'$1.235M');
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

SwapState _stateWithUsdPrices(Map<SwapAsset, double> usdPrices) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: const {},
    indicativeUsdPrices: usdPrices,
  );
}
