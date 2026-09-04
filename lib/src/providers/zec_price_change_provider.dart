import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show log;
import '../core/config/swap_feature_config.dart';
import '../core/formatting/zec_amount.dart';
import '../core/layout/app_process_work_policy.dart';
import '../core/network/network_http_client.dart';
import '../features/swap/models/swap_fiat_value_formatting.dart';

const kVizorCoinGeckoPriceBaseUrlEnvKey = 'VIZOR_COINGECKO_PRICE_BASE_URL';
const kVizorCoinGeckoDefaultPriceBaseUrl = 'https://api.coingecko.com/api/v3';
const kVizorCoinGeckoPriceBaseUrl = String.fromEnvironment(
  kVizorCoinGeckoPriceBaseUrlEnvKey,
  defaultValue: kVizorCoinGeckoDefaultPriceBaseUrl,
);
const zecMarketDataRequestTimeout = Duration(seconds: 60);
const zecMarketDataRefreshInterval = Duration(minutes: 3);
const zecMarketDataRetryDelays = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
];
const zecMarketDataCacheTtl = Duration(hours: 1);
const zecMarketDataCacheStorageKey = 'vizor_zec_market_data_v1';

class ZecMarketData {
  const ZecMarketData({required this.usdPrice, this.change24hPct});

  final double usdPrice;
  final double? change24hPct;
}

class CachedZecMarketData {
  const CachedZecMarketData({required this.data, required this.fetchedAt});

  final ZecMarketData data;
  final DateTime fetchedAt;

  bool isFreshAt(DateTime now) {
    final age = now.toUtc().difference(fetchedAt.toUtc());
    return !age.isNegative && age < zecMarketDataCacheTtl;
  }
}

abstract interface class ZecMarketDataCache {
  Future<CachedZecMarketData?> read();

  Future<void> write(CachedZecMarketData value);
}

class SharedPreferencesZecMarketDataCache implements ZecMarketDataCache {
  const SharedPreferencesZecMarketDataCache();

  @override
  Future<CachedZecMarketData?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(zecMarketDataCacheStorageKey);
    if (raw == null || raw.isEmpty) return null;
    return decodeCachedZecMarketData(raw);
  }

  @override
  Future<void> write(CachedZecMarketData value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      zecMarketDataCacheStorageKey,
      encodeCachedZecMarketData(value),
    );
    if (!saved) throw StateError('Could not persist ZEC market data.');
  }
}

String encodeCachedZecMarketData(CachedZecMarketData value) {
  return jsonEncode({
    'version': 1,
    'usdPrice': value.data.usdPrice,
    'change24hPct': value.data.change24hPct,
    'fetchedAtMs': value.fetchedAt.toUtc().millisecondsSinceEpoch,
  });
}

CachedZecMarketData? decodeCachedZecMarketData(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      return null;
    }
    final usdRaw = decoded['usdPrice'];
    final changeRaw = decoded['change24hPct'];
    final fetchedAtRaw = decoded['fetchedAtMs'];
    if (usdRaw is! num || fetchedAtRaw is! int) return null;
    final usdPrice = usdRaw.toDouble();
    if (!usdPrice.isFinite || usdPrice <= 0) return null;
    if (changeRaw != null && changeRaw is! num) return null;
    final change24hPct = (changeRaw as num?)?.toDouble();
    if (change24hPct != null && !change24hPct.isFinite) return null;
    return CachedZecMarketData(
      data: ZecMarketData(usdPrice: usdPrice, change24hPct: change24hPct),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtRaw, isUtc: true),
    );
  } catch (_) {
    return null;
  }
}

/// Non-swap ZEC market data source. Swap keeps using its provider-specific
/// pricing snapshot; this source feeds home and mobile wallet-native ZEC
/// displays.
abstract interface class ZecMarketDataSource {
  /// Returns the current ZEC/USD price plus optional 24h change percentage
  /// points (e.g. `-0.26` for -0.26%), or null when unavailable.
  Future<ZecMarketData?> fetchMarketData();
}

class CoinGeckoZecMarketDataSource implements ZecMarketDataSource {
  CoinGeckoZecMarketDataSource({
    HttpClient? client,
    NetworkHttpClient? networkClient,
    Uri? baseUri,
    this.timeout = zecMarketDataRequestTimeout,
  }) : _client = networkClient ?? NetworkHttpClient(directClient: client),
       _baseUri = baseUri ?? Uri.parse(kVizorCoinGeckoPriceBaseUrl);

  final NetworkHttpClient _client;
  final Uri _baseUri;
  final Duration timeout;

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    final endpoint = coinGeckoSimplePriceUri(_baseUri);
    try {
      final response = await _client.request(
        'GET',
        endpoint,
        headers: const {HttpHeaders.acceptHeader: 'application/json'},
        timeout: timeout,
      );
      final body = utf8.decode(response.bodyBytes);
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

/// Parses CoinGecko `/simple/price` into the market data model. Returns null
/// when the required ZEC/USD price is missing or unusable.
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

final zecMarketDataSourceProvider = Provider<ZecMarketDataSource>((ref) {
  return CoinGeckoZecMarketDataSource();
});

final zecMarketDataCacheProvider = Provider<ZecMarketDataCache>((ref) {
  return const SharedPreferencesZecMarketDataCache();
});

final zecMarketDataNowProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final zecMarketDataRefreshIntervalProvider = Provider<Duration>((ref) {
  return zecMarketDataRefreshInterval;
});

final zecMarketDataRetryDelaysProvider = Provider<List<Duration>>((ref) {
  return zecMarketDataRetryDelays;
});

final zecMarketDataProcessWorkPolicyProvider =
    Provider<bool Function({required bool isInForeground})>(
      (_) => canRunAppProcessWork,
    );

class ZecHomeMarketDataState {
  const ZecHomeMarketDataState({
    this.displayData,
    this.liveData,
    this.fetchedAt,
  });

  final ZecMarketData? displayData;
  final ZecMarketData? liveData;
  final DateTime? fetchedAt;

  bool isFreshAt(DateTime now) {
    final timestamp = fetchedAt;
    if (displayData == null || timestamp == null) return false;
    final age = now.toUtc().difference(timestamp.toUtc());
    return !age.isNegative && age < zecMarketDataCacheTtl;
  }
}

/// Latest usable non-swap ZEC market data. A persisted value less than one
/// hour old is exposed while the first network refresh is in flight; transient
/// failures retain it only until that TTL expires. Null while market-price UI
/// is disabled on non-mainnet builds.
final zecHomeMarketDataStateProvider =
    NotifierProvider.autoDispose<
      ZecHomeMarketDataNotifier,
      ZecHomeMarketDataState
    >(ZecHomeMarketDataNotifier.new);

class ZecHomeMarketDataNotifier extends Notifier<ZecHomeMarketDataState> {
  Timer? _refreshTimer;
  Timer? _expiryTimer;
  int _epoch = 0;
  int _consecutiveFailures = 0;
  AppLifecycleListener? _lifecycle;
  bool _isInForeground = true;
  bool _refreshDeferredToForeground = false;

  bool get _mayRunNow => ref.read(zecMarketDataProcessWorkPolicyProvider)(
    isInForeground: _isInForeground,
  );

  @override
  ZecHomeMarketDataState build() {
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
    final epoch = ++_epoch;
    if (!ref.watch(swapFeatureEnabledProvider)) {
      return const ZecHomeMarketDataState();
    }
    final source = ref.watch(zecMarketDataSourceProvider);
    final cache = ref.watch(zecMarketDataCacheProvider);
    final now = ref.watch(zecMarketDataNowProvider);
    final refreshInterval = ref.watch(zecMarketDataRefreshIntervalProvider);
    final retryDelays = ref.watch(zecMarketDataRetryDelaysProvider);
    _consecutiveFailures = 0;

    ref.onDispose(() {
      _epoch++;
      _refreshTimer?.cancel();
      _expiryTimer?.cancel();
      _lifecycle?.dispose();
      _lifecycle = null;
    });

    void clearMarketData() {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      state = const ZecHomeMarketDataState();
    }

    void scheduleExpiry(DateTime fetchedAt) {
      _expiryTimer?.cancel();
      final remaining = fetchedAt
          .toUtc()
          .add(zecMarketDataCacheTtl)
          .difference(now().toUtc());
      if (remaining <= Duration.zero) {
        clearMarketData();
        return;
      }
      _expiryTimer = Timer(remaining, () {
        if (epoch != _epoch || state.fetchedAt != fetchedAt) return;
        _expiryTimer = null;
        state = const ZecHomeMarketDataState();
      });
    }

    Future<void> persist(CachedZecMarketData value) async {
      try {
        await cache.write(value);
      } catch (e) {
        log('zecMarketData: cache write failed: $e');
      }
    }

    Future<void> tick() async {
      if (!_mayRunNow) {
        _refreshDeferredToForeground = true;
        return;
      }
      if (state.displayData != null && !state.isFreshAt(now())) {
        clearMarketData();
      }
      final data = await source.fetchMarketData();
      if (epoch != _epoch) return;
      if (data != null) {
        _consecutiveFailures = 0;
        final fetchedAt = now().toUtc();
        state = ZecHomeMarketDataState(
          displayData: data,
          liveData: data,
          fetchedAt: fetchedAt,
        );
        scheduleExpiry(fetchedAt);
        unawaited(
          persist(CachedZecMarketData(data: data, fetchedAt: fetchedAt)),
        );
      } else if (state.displayData != null && !state.isFreshAt(now())) {
        clearMarketData();
      }
      final nextDelay = data != null
          ? refreshInterval
          : _consecutiveFailures < retryDelays.length
          ? retryDelays[_consecutiveFailures++]
          : refreshInterval;
      if (_mayRunNow) {
        _refreshTimer = Timer(nextDelay, () => unawaited(tick()));
      } else {
        _refreshDeferredToForeground = true;
      }
    }

    Future<void> initialize() async {
      try {
        final cached = await cache.read();
        if (epoch != _epoch) return;
        if (cached != null && cached.isFreshAt(now())) {
          state = ZecHomeMarketDataState(
            displayData: cached.data,
            fetchedAt: cached.fetchedAt,
          );
          scheduleExpiry(cached.fetchedAt);
        }
      } catch (e) {
        log('zecMarketData: cache read failed: $e');
      }
      if (epoch == _epoch) await tick();
    }

    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _isInForeground = false;
        if (_mayRunNow || _refreshTimer == null) return;
        _refreshTimer?.cancel();
        _refreshTimer = null;
        _refreshDeferredToForeground = true;
      },
      onResume: () {
        _isInForeground = true;
        if (!_refreshDeferredToForeground || epoch != _epoch) return;
        _refreshDeferredToForeground = false;
        unawaited(tick());
      },
    );

    scheduleMicrotask(() {
      if (epoch == _epoch) unawaited(initialize());
    });
    return const ZecHomeMarketDataState();
  }
}

final zecHomeMarketDataProvider = Provider.autoDispose<ZecMarketData?>((ref) {
  return ref.watch(zecHomeMarketDataStateProvider).displayData;
});

final zecHomeUsdUnitPriceProvider = Provider.autoDispose<double?>((ref) {
  return ref.watch(zecHomeMarketDataProvider)?.usdPrice;
});

/// ZEC/USD price fetched successfully during the current provider lifetime.
/// Unlike the Home display price, this never exposes a persisted cache value
/// to USD-denominated send amount calculations.
final zecLiveUsdUnitPriceProvider = Provider.autoDispose<double?>((ref) {
  return ref.watch(zecHomeMarketDataStateProvider).liveData?.usdPrice;
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
