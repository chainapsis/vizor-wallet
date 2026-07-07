import '../../../core/config/fiat_currencies.dart';
import 'swap_models.dart';
import 'swap_fiat_value_formatting.dart';

double? swapUsdUnitPriceForAsset(SwapState state, {required SwapAsset asset}) {
  return swapUsdUnitPriceFromPrices(state.indicativeUsdPrices, asset);
}

double? swapUsdValueForAsset(
  SwapState state, {
  required SwapAsset asset,
  required double amount,
}) {
  if (!amount.isFinite || amount <= 0) return null;
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  return usdUnitPrice == null ? null : amount * usdUnitPrice;
}

double? swapUsdUnitPriceFromPrices(
  Map<SwapAsset, double> usdPrices,
  SwapAsset asset,
) {
  final direct = _usableUnitPrice(usdPrices[asset]);
  if (direct != null) return direct;
  for (final entry in usdPrices.entries) {
    if (entry.key.hasSameMarketAs(asset)) {
      final price = _usableUnitPrice(entry.value);
      if (price != null) return price;
    }
  }
  return null;
}

String swapFiatDisplayText(
  SwapState state, {
  required SwapAsset asset,
  required String tokenAmountText,
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return fiatDisplay.zeroText;
  final usdValue = swapUsdValueForAsset(state, asset: asset, amount: amount);
  if (usdValue == null) return fiatDisplay.placeholderText;
  return '${fiatDisplay.displayCurrency.symbol}'
      '${_formatConvertedFiatValue(fiatDisplay, usdValue)}';
}

String swapFiatInputTextFromTokenText(
  SwapState state, {
  required SwapAsset asset,
  required String tokenAmountText,
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return '';
  final usdValue = swapUsdValueForAsset(state, asset: asset, amount: amount);
  if (usdValue == null) return '';
  return _formatConvertedFiatValue(fiatDisplay, usdValue);
}

String? swapTokenAmountTextFromFiatText(
  SwapState state, {
  required SwapAsset asset,
  required String fiatAmountText,
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  final fiatAmount = double.tryParse(fiatAmountText.trim());
  if (fiatAmount == null || fiatAmount <= 0) return '';
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  if (usdUnitPrice == null || usdUnitPrice <= 0) return null;
  return asset.formatAmountDown(fiatDisplay.toUsd(fiatAmount) / usdUnitPrice);
}

/// Token-equivalent meta line shown while the card is in fiat input mode.
/// The design shows the bare amount with no symbol suffix.
String swapTokenAmountDisplayText({required String tokenAmountText}) {
  final amount = tokenAmountText.trim();
  if (amount.isEmpty) return '0';
  return amount;
}

double? _usableUnitPrice(double? value) {
  return value != null && value.isFinite && value > 0 ? value : null;
}

/// [swapFormatFiatValue] with the fraction digits capped for low-decimal
/// currencies: KRW/JPY (0) never show sub-unit digits and 1-decimal
/// currencies show at most one. Currencies with >= 2 decimals keep the
/// magnitude-based digits unchanged, preserving the pre-existing USD output
/// byte-for-byte (including 4 digits for sub-unit values).
String _formatConvertedFiatValue(FiatDisplay fiatDisplay, double usdValue) {
  final value = fiatDisplay.convertUsd(usdValue);
  final maxDecimals = fiatDisplay.displayCurrency.maxDecimals;
  if (maxDecimals >= 2) return swapFormatFiatValue(value);
  if (value <= 0) return '0';
  return trimTrailingFiatZeros(
    swapTruncateToFractionDigits(value, maxDecimals),
    fractionDigits: maxDecimals,
  );
}
