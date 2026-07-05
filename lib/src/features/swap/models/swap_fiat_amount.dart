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
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return r'$0';
  final usdValue = swapUsdValueForAsset(state, asset: asset, amount: amount);
  if (usdValue == null) return r'$--';
  return '\$${swapFormatFiatValue(usdValue)}';
}

String swapFiatInputTextFromTokenText(
  SwapState state, {
  required SwapAsset asset,
  required String tokenAmountText,
}) {
  final amount = double.tryParse(tokenAmountText.trim());
  if (amount == null || amount <= 0) return '';
  final usdValue = swapUsdValueForAsset(state, asset: asset, amount: amount);
  if (usdValue == null) return '';
  return swapFormatFiatValue(usdValue);
}

String? swapTokenAmountTextFromFiatText(
  SwapState state, {
  required SwapAsset asset,
  required String fiatAmountText,
}) {
  final fiatAmount = double.tryParse(fiatAmountText.trim());
  if (fiatAmount == null || fiatAmount <= 0) return '';
  final usdUnitPrice = swapUsdUnitPriceForAsset(state, asset: asset);
  if (usdUnitPrice == null || usdUnitPrice <= 0) return null;
  return asset.formatAmountDown(fiatAmount / usdUnitPrice);
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

/// Derive a per-asset USD unit-price map from the app's single ZEC/USD price.
///
/// The zwap backend does not ship its own price oracle the way the NEAR
/// aggregator does, so it reuses the wallet's own ZEC/USD spot price (the same
/// source the home balance is priced with). The external legs are priced by
/// dividing through `externalPerZec` (external-asset units per ZEC): if
/// 1 ZEC = X external units and 1 ZEC = $Z, then one external unit is $Z/X.
///
/// Only entries with a usable (finite, positive) price are included. Returns an
/// empty map when the ZEC price is unusable so callers can treat "no prices" and
/// "empty prices" the same way.
Map<SwapAsset, double> swapUsdPricesFromZecPrice({
  required double? zecUsdUnitPrice,
  Map<SwapAsset, double> externalPerZec = const {},
}) {
  final zecPrice = _usableUnitPrice(zecUsdUnitPrice);
  if (zecPrice == null) return const {};
  final prices = <SwapAsset, double>{SwapAsset.zec: zecPrice};
  for (final entry in externalPerZec.entries) {
    final perZec = _usableUnitPrice(entry.value);
    if (perZec == null) continue;
    final usd = _usableUnitPrice(zecPrice / perZec);
    if (usd != null) prices[entry.key] = usd;
  }
  return prices;
}

/// Build a [SwapFiatValueBasis] for a quote whose sell/receive assets are known,
/// pricing each side off a per-asset USD unit-price map (see
/// [swapUsdPricesFromZecPrice]). Returns null when neither side can be priced,
/// so the caller leaves `fiatValueBasis` null (renders `$--`) exactly as before.
SwapFiatValueBasis? swapFiatValueBasisFromUsdPrices({
  required Map<SwapAsset, double> usdPrices,
  required SwapAsset sellAsset,
  required SwapAsset receiveAsset,
  DateTime? capturedAt,
}) {
  if (usdPrices.isEmpty) return null;
  final basis = SwapFiatValueBasis(
    capturedAt: capturedAt ?? DateTime.now().toUtc(),
    sellUsdUnitPrice: swapUsdUnitPriceFromPrices(usdPrices, sellAsset),
    receiveUsdUnitPrice: swapUsdUnitPriceFromPrices(usdPrices, receiveAsset),
  );
  return basis.isUsable ? basis : null;
}
