import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../providers/zec_price_change_provider.dart';

/// Best-effort price for the entry screen only. Account setup and claiming
/// never await this provider. Reuse a fresh cache, otherwise fetch once;
/// unlike Home, this screen does not start a periodic refresh loop.
final giftCardEntryPriceProvider = FutureProvider.autoDispose<double?>((
  ref,
) async {
  if (!ref.watch(swapFeatureEnabledProvider)) return null;
  final cache = ref.watch(zecMarketDataCacheProvider);
  final source = ref.watch(zecMarketDataSourceProvider);
  final now = ref.watch(zecMarketDataNowProvider);
  try {
    final saved = await cache.read();
    if (saved != null && saved.isFreshAt(now())) return saved.data.usdPrice;
  } catch (_) {
    // A failed cache read must not prevent either price lookup or claiming.
  }
  if (!ref.mounted) return null;
  try {
    final data = await source.fetchMarketData();
    if (data == null) return null;
    try {
      await cache.write(
        CachedZecMarketData(data: data, fetchedAt: now().toUtc()),
      );
    } catch (_) {
      // The fetched price is still usable when cache persistence fails.
    }
    return data.usdPrice;
  } catch (_) {
    return null;
  }
});
