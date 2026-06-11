import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/config/swap_feature_config.dart';
import '../core/formatting/zec_amount.dart';
import '../features/swap/domain/swap_provider_contract.dart';
import '../features/swap/domain/swap_asset.dart';
import '../features/swap/models/swap_fiat_value_formatting.dart';
import '../features/swap/providers/swap_provider_config.dart';

/// Indicative ZEC/USD unit price from the swap provider's pricing snapshot.
///
/// Resolves to null when the swap feature is disabled, the active swap
/// provider exposes no pricing, or the price is unusable — callers hide
/// their fiat sub-label in that case. Shared by the home balance card and
/// the send review/status screens.
final zecUsdUnitPriceProvider = FutureProvider.autoDispose<double?>((
  ref,
) async {
  if (!ref.watch(swapFeatureEnabledProvider)) return null;

  final provider = ref.read(swapIntentProvider);
  final pricingProvider = provider is SwapPricingProvider
      ? provider as SwapPricingProvider
      : null;
  if (pricingProvider == null) return null;

  try {
    final snapshot = await pricingProvider.loadPricingSnapshot();
    final price = snapshot.usdPrices[SwapAsset.zec];
    if (price == null || !price.isFinite || price <= 0) return null;
    return price;
  } catch (e) {
    log('zecUsdUnitPrice: fiat price load failed: $e');
    return null;
  }
});

/// "$250.12"-style fiat text for a zatoshi amount, or null when the amount
/// or [zecUsdUnitPrice] cannot be priced (callers hide the sub-label).
String? fiatTextForZatoshi(BigInt zatoshi, {required double? zecUsdUnitPrice}) {
  if (zatoshi <= BigInt.zero ||
      zecUsdUnitPrice == null ||
      !zecUsdUnitPrice.isFinite ||
      zecUsdUnitPrice <= 0) {
    return null;
  }
  final zec = zatoshi.toDouble() / zatoshiPerZec.toDouble();
  if (!zec.isFinite || zec <= 0) return null;
  return swapFormatCompactFiatValue(zec * zecUsdUnitPrice);
}
