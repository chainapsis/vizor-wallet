import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/config/swap_feature_config.dart';
import '../core/formatting/zec_amount.dart';
import '../features/swap/models/swap_fiat_value_formatting.dart';

const kVizorCoinGeckoPriceBaseUrlEnvKey = 'VIZOR_COINGECKO_PRICE_BASE_URL';
const kVizorCoinGeckoDefaultPriceBaseUrl = 'https://api.coingecko.com/api/v3';
const kVizorCoinGeckoPriceBaseUrl = String.fromEnvironment(
  kVizorCoinGeckoPriceBaseUrlEnvKey,
  defaultValue: kVizorCoinGeckoDefaultPriceBaseUrl,
);

class ZecMarketData {
  const ZecMarketData({required this.usdPrice, this.change24hPct});

  final double usdPrice;
  final double? change24hPct;
}

/// Home ZEC market data source. Swap keeps using its provider-specific pricing
/// snapshot; this source is only for the home balance fiat label and 24h badge.
abstract interface class ZecMarketDataSource {
  /// Returns the current ZEC/USD price plus optional 24h change percentage
  /// points (e.g. `-0.26` for -0.26%), or null when unavailable.
  Future<ZecMarketData?> fetchMarketData();
}

class CoinGeckoZecMarketDataSource implements ZecMarketDataSource {
  CoinGeckoZecMarketDataSource({
    HttpClient? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? HttpClient(),
       _baseUri = baseUri ?? Uri.parse(kVizorCoinGeckoPriceBaseUrl);

  final HttpClient _client;
  final Uri _baseUri;
  final Duration timeout;

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    final endpoint = coinGeckoSimplePriceUri(_baseUri);
    try {
      final request = await _client.getUrl(endpoint).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        log('zecMarketData: CoinGecko returned ${response.statusCode}');
        return null;
      }
      return parseZecMarketData(body);
    } catch (e) {
      log('zecMarketData: fetch failed: $e');
      return null;
    }
  }
}

Uri coinGeckoSimplePriceUri(Uri baseUri) {
  final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
  return baseUri.replace(
    path: '$basePath/simple/price',
    queryParameters: const {
      'ids': 'zcash',
      'names': 'Zcash',
      'symbols': 'zec',
      'vs_currencies': 'usd',
      'include_24hr_change': 'true',
    },
  );
}

/// Parses CoinGecko `/simple/price` into the home market data model.
/// Returns null when the required ZEC/USD price is missing or unusable.
ZecMarketData? parseZecMarketData(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final zcash = decoded['zcash'];
    if (zcash is! Map<String, dynamic>) return null;

    final usdRaw = zcash['usd'];
    if (usdRaw is! num) return null;
    final usdPrice = usdRaw.toDouble();
    if (!usdPrice.isFinite || usdPrice <= 0) return null;

    final changeRaw = zcash['usd_24h_change'];
    final change24hPct = changeRaw is num && changeRaw.toDouble().isFinite
        ? changeRaw.toDouble()
        : null;

    return ZecMarketData(usdPrice: usdPrice, change24hPct: change24hPct);
  } catch (_) {
    return null;
  }
}

double? parseZecPriceChange24hPct(String body) {
  return parseZecMarketData(body)?.change24hPct;
}

const zecMarketDataRefreshInterval = Duration(minutes: 3);

final zecMarketDataSourceProvider = Provider<ZecMarketDataSource>((ref) {
  return CoinGeckoZecMarketDataSource();
});

/// Latest known home ZEC market data, or null until the first successful fetch.
/// Stays on the last known value across transient fetch failures. Null while
/// market-price UI is disabled on non-mainnet builds.
final zecHomeMarketDataProvider =
    NotifierProvider.autoDispose<ZecHomeMarketDataNotifier, ZecMarketData?>(
      ZecHomeMarketDataNotifier.new,
    );

class ZecHomeMarketDataNotifier extends Notifier<ZecMarketData?> {
  Timer? _timer;
  int _epoch = 0;

  @override
  ZecMarketData? build() {
    _timer?.cancel();
    final epoch = ++_epoch;
    if (!ref.watch(swapFeatureEnabledProvider)) return null;
    final source = ref.watch(zecMarketDataSourceProvider);

    ref.onDispose(() {
      _epoch++;
      _timer?.cancel();
    });

    Future<void> tick() async {
      final data = await source.fetchMarketData();
      if (epoch != _epoch) return;
      if (data != null) state = data;
      _timer = Timer(zecMarketDataRefreshInterval, () => unawaited(tick()));
    }

    scheduleMicrotask(() {
      if (epoch == _epoch) unawaited(tick());
    });
    return null;
  }
}

final zecHomeUsdUnitPriceProvider = Provider.autoDispose<double?>((ref) {
  return ref.watch(zecHomeMarketDataProvider)?.usdPrice;
});

final zecPriceChange24hPctProvider = Provider.autoDispose<double?>((ref) {
  return ref.watch(zecHomeMarketDataProvider)?.change24hPct;
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

/// Rounds to the displayed 2-decimal precision so text and color agree —
/// e.g. -0.004 renders as a neutral "0.00%", not a red zero.
double roundZecPriceChange24hPct(double pct) {
  return double.parse(pct.toStringAsFixed(2));
}

/// "+ 1.25% (24h)" / "- 0.26% (24h)" / "0.00% (24h)" badge text for a 24h
/// change percentage. The space between the sign and the number follows the
/// Figma Home Card spec ("+ 13.12% (24h)").
String formatZecPriceChange24hPct(double pct) {
  final rounded = roundZecPriceChange24hPct(pct);
  if (rounded == 0) return '0.00% (24h)';
  return rounded > 0
      ? '+ ${rounded.toStringAsFixed(2)}% (24h)'
      : '- ${rounded.abs().toStringAsFixed(2)}% (24h)';
}
