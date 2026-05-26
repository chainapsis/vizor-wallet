import 'swap_prototype_models.dart';

double? swapUsdUnitPriceForAsset(
  SwapPrototypeState state, {
  required SwapAsset asset,
}) {
  if (_isUsdStable(asset)) return 1;
  if (asset != SwapAsset.zec || !_isUsdStable(state.externalAsset)) {
    return null;
  }
  return state.indicativeExternalPerZec[state.externalAsset] ??
      state.externalAsset.fallbackExternalPerZec;
}

String swapFiatDisplayText(
  SwapPrototypeState state, {
  required SwapAsset asset,
  required String tokenAmountText,
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return r'$0';
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  if (usdUnitPrice == null) return r'$0';
  return '\$${swapFormatFiatValue(amount * usdUnitPrice)}';
}

String swapFiatInputTextFromTokenText(
  SwapPrototypeState state, {
  required SwapAsset asset,
  required String tokenAmountText,
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return '';
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  if (usdUnitPrice == null) return '';
  return swapFormatFiatValue(amount * usdUnitPrice);
}

String? swapTokenAmountTextFromFiatText(
  SwapPrototypeState state, {
  required SwapAsset asset,
  required String fiatAmountText,
}) {
  final fiatAmount = double.tryParse(fiatAmountText.trim());
  if (fiatAmount == null || fiatAmount <= 0) return '';
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  if (usdUnitPrice == null || usdUnitPrice <= 0) return null;
  return swapFormatTokenAmountDown(asset, fiatAmount / usdUnitPrice);
}

String swapTokenAmountDisplayText({
  required SwapAsset asset,
  required String tokenAmountText,
}) {
  final amount = tokenAmountText.trim();
  if (amount.isEmpty) return '0 ${asset.symbol}';
  return '$amount ${asset.symbol}';
}

String swapFormatFiatValue(double value) {
  if (value <= 0) return '0';
  final digits = value >= 100
      ? 0
      : value >= 1
      ? 2
      : 4;
  var text = _truncateToFractionDigits(value, digits).toStringAsFixed(digits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

String swapFormatTokenAmountDown(SwapAsset asset, double value) {
  if (value <= 0) return asset.formatAmount(0);
  final digits = _displayFractionDigitsForAsset(asset);
  return _truncateToFractionDigits(value, digits).toStringAsFixed(digits);
}

double _truncateToFractionDigits(double value, int fractionDigits) {
  if (!value.isFinite || value <= 0) return 0;
  var factor = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    factor *= 10;
  }
  return (value * factor).truncateToDouble() / factor;
}

int _displayFractionDigitsForAsset(SwapAsset asset) {
  final normalized = asset.symbol.toUpperCase();
  if (normalized == 'ZEC') return 4;
  if (normalized == 'BTC' || normalized == 'WBTC' || asset.decimals == 8) {
    return 8;
  }
  if (normalized == 'ETH' || normalized == 'SOL' || normalized == 'NEAR') {
    return 4;
  }
  return 2;
}

bool _isUsdStable(SwapAsset asset) {
  return switch (asset.symbol.toUpperCase()) {
    'USDC' || 'USDT' || 'DAI' => true,
    _ => false,
  };
}
