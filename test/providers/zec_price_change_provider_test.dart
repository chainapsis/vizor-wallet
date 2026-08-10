import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

class _FakeSource implements ZecMarketDataSource {
  _FakeSource(this.data);

  final ZecMarketData? data;
  int fetchCount = 0;

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    fetchCount += 1;
    return data;
  }
}

class _CompleterSource implements ZecMarketDataSource {
  final completer = Completer<ZecMarketData?>();
  int fetchCount = 0;

  @override
  Future<ZecMarketData?> fetchMarketData() {
    fetchCount += 1;
    return completer.future;
  }
}

class _FakeCache implements ZecMarketDataCache {
  _FakeCache({this.value, this.readError, this.writeError});

  CachedZecMarketData? value;
  final Object? readError;
  final Object? writeError;
  int readCount = 0;
  final writes = <CachedZecMarketData>[];

  @override
  Future<CachedZecMarketData?> read() async {
    readCount += 1;
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> write(CachedZecMarketData next) async {
    if (writeError != null) throw writeError!;
    value = next;
    writes.add(next);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseZecMarketData', () {
    test('reads ZEC price and 24h change from a CoinGecko response', () {
      final data = parseZecMarketData(
        '{"zcash":{"usd":33.45,"usd_24h_change":-0.25852}}',
      );

      expect(data?.usdPrice, 33.45);
      expect(data?.change24hPct, -0.25852);
    });

    test('allows a missing or null 24h change when price is usable', () {
      expect(
        parseZecMarketData('{"zcash":{"usd":33.45}}')?.change24hPct,
        isNull,
      );
      expect(
        parseZecMarketData(
          '{"zcash":{"usd":33.45,"usd_24h_change":null}}',
        )?.usdPrice,
        33.45,
      );
    });

    test('returns null for malformed and unusable price bodies', () {
      expect(parseZecMarketData('{}'), isNull);
      expect(parseZecMarketData('{"cosmos":{"usd":1.2}}'), isNull);
      expect(parseZecMarketData('{"zcash":"fast"}'), isNull);
      expect(parseZecMarketData('{"zcash":null}'), isNull);
      expect(parseZecMarketData('{"zcash":{"usd":"33.45"}}'), isNull);
      expect(parseZecMarketData('{"zcash":{"usd":0}}'), isNull);
      expect(parseZecMarketData('[]'), isNull);
      expect(parseZecMarketData('not json'), isNull);
    });

    test('builds the CoinGecko simple price URL from a base URL', () {
      final uri = coinGeckoSimplePriceUri(
        Uri.parse('https://api.coingecko.com/api/v3/'),
      );

      expect(
        uri.toString(),
        'https://api.coingecko.com/api/v3/simple/price?'
        'ids=zcash&names=Zcash&symbols=zec&vs_currencies=usd&'
        'include_24hr_change=true',
      );
    });
  });

  group('formatZecPriceChange24hPct', () {
    test('signs and rounds to two decimals with a 24h label', () {
      expect(formatZecPriceChange24hPct(1.253), '+ 1.25% (24h)');
      expect(formatZecPriceChange24hPct(-0.25852), '- 0.26% (24h)');
      expect(formatZecPriceChange24hPct(12.0), '+ 12.00% (24h)');
    });

    test('normalizes near-zero values to an unsigned zero', () {
      expect(formatZecPriceChange24hPct(0), '0.00% (24h)');
      expect(formatZecPriceChange24hPct(0.004), '0.00% (24h)');
      expect(formatZecPriceChange24hPct(-0.004), '0.00% (24h)');
    });
  });

  group('ZEC market data cache', () {
    test('persists and reads a cache record from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPreferencesZecMarketDataCache();
      final cached = CachedZecMarketData(
        data: const ZecMarketData(usdPrice: 33.45, change24hPct: -0.25),
        fetchedAt: DateTime.utc(2026, 8, 10, 12),
      );

      await store.write(cached);
      final restored = await store.read();

      expect(restored?.data.usdPrice, 33.45);
      expect(restored?.data.change24hPct, -0.25);
      expect(restored?.fetchedAt, DateTime.utc(2026, 8, 10, 12));
    });

    test('round-trips a versioned cache record', () {
      final cached = CachedZecMarketData(
        data: const ZecMarketData(usdPrice: 33.45, change24hPct: -0.25852),
        fetchedAt: DateTime.utc(2026, 8, 10, 12, 34, 56),
      );

      final decoded = decodeCachedZecMarketData(
        encodeCachedZecMarketData(cached),
      );

      expect(decoded?.data.usdPrice, 33.45);
      expect(decoded?.data.change24hPct, -0.25852);
      expect(decoded?.fetchedAt, DateTime.utc(2026, 8, 10, 12, 34, 56));
    });

    test('rejects corrupt and unusable records', () {
      expect(decodeCachedZecMarketData('not json'), isNull);
      expect(
        decodeCachedZecMarketData(
          '{"version":2,"usdPrice":33.45,"fetchedAtMs":0}',
        ),
        isNull,
      );
      expect(
        decodeCachedZecMarketData('{"version":1,"usdPrice":0,"fetchedAtMs":0}'),
        isNull,
      );
      expect(
        decodeCachedZecMarketData(
          '{"version":1,"usdPrice":33.45,'
          '"change24hPct":"fast","fetchedAtMs":0}',
        ),
        isNull,
      );
    });

    test('accepts only timestamps less than one hour old', () {
      final now = DateTime.utc(2026, 8, 10, 12);
      CachedZecMarketData at(DateTime fetchedAt) => CachedZecMarketData(
        data: const ZecMarketData(usdPrice: 33.45),
        fetchedAt: fetchedAt,
      );

      expect(
        at(
          now.subtract(const Duration(minutes: 59, seconds: 59)),
        ).isFreshAt(now),
        isTrue,
      );
      expect(
        at(now.subtract(const Duration(hours: 1))).isFreshAt(now),
        isFalse,
      );
      expect(at(now.add(const Duration(seconds: 1))).isFreshAt(now), isFalse);
    });
  });

  group('zecHomeMarketDataProvider', () {
    ProviderContainer makeContainer({
      required bool swapEnabled,
      required ZecMarketDataSource source,
      ZecMarketDataCache? cache,
      DateTime Function()? now,
      Duration refreshInterval = zecMarketDataRefreshInterval,
    }) {
      final container = ProviderContainer(
        overrides: [
          swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
          zecMarketDataSourceProvider.overrideWithValue(source),
          zecMarketDataCacheProvider.overrideWithValue(cache ?? _FakeCache()),
          if (now != null) zecMarketDataNowProvider.overrideWithValue(now),
          zecMarketDataRefreshIntervalProvider.overrideWithValue(
            refreshInterval,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('exposes the fetched market data after the first tick', () async {
      final source = _FakeSource(
        const ZecMarketData(usdPrice: 33.45, change24hPct: -0.26),
      );
      final container = makeContainer(swapEnabled: true, source: source);
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      expect(sub.read(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.usdPrice, 33.45);
      expect(container.read(zecHomeUsdUnitPriceProvider), 33.45);
      expect(container.read(zecPriceChange24hPctProvider), -0.26);
      expect(source.fetchCount, 1);
    });

    test('shows a fresh cache before replacing it with network data', () async {
      final now = DateTime.utc(2026, 8, 10, 12);
      final source = _CompleterSource();
      final cache = _FakeCache(
        value: CachedZecMarketData(
          data: const ZecMarketData(usdPrice: 30, change24hPct: -1),
          fetchedAt: now.subtract(const Duration(minutes: 30)),
        ),
      );
      final container = makeContainer(
        swapEnabled: true,
        source: source,
        cache: cache,
        now: () => now,
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.usdPrice, 30);
      expect(container.read(zecLiveUsdUnitPriceProvider), isNull);
      expect(source.fetchCount, 1);

      source.completer.complete(
        const ZecMarketData(usdPrice: 33.45, change24hPct: 2),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sub.read()?.usdPrice, 33.45);
      expect(container.read(zecLiveUsdUnitPriceProvider), 33.45);
      expect(cache.writes.single.data.usdPrice, 33.45);
      expect(cache.writes.single.fetchedAt, now);
    });

    test('ignores a cache that is exactly one hour old', () async {
      final now = DateTime.utc(2026, 8, 10, 12);
      final source = _CompleterSource();
      final cache = _FakeCache(
        value: CachedZecMarketData(
          data: const ZecMarketData(usdPrice: 30),
          fetchedAt: now.subtract(const Duration(hours: 1)),
        ),
      );
      final container = makeContainer(
        swapEnabled: true,
        source: source,
        cache: cache,
        now: () => now,
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);

      expect(sub.read(), isNull);
      expect(source.fetchCount, 1);
    });

    test('retains a fresh cache when the network fetch fails', () async {
      final now = DateTime.utc(2026, 8, 10, 12);
      final cache = _FakeCache(
        value: CachedZecMarketData(
          data: const ZecMarketData(usdPrice: 30),
          fetchedAt: now.subtract(const Duration(minutes: 30)),
        ),
      );
      final container = makeContainer(
        swapEnabled: true,
        source: _FakeSource(null),
        cache: cache,
        now: () => now,
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);

      expect(sub.read()?.usdPrice, 30);
      expect(container.read(zecLiveUsdUnitPriceProvider), isNull);
      expect(cache.writes, isEmpty);
    });

    test('removes the last value after its one-hour TTL expires', () async {
      var now = DateTime.utc(2026, 8, 10, 12);
      final cache = _FakeCache(
        value: CachedZecMarketData(
          data: const ZecMarketData(usdPrice: 30),
          fetchedAt: now.subtract(const Duration(minutes: 59)),
        ),
      );
      final container = makeContainer(
        swapEnabled: true,
        source: _FakeSource(null),
        cache: cache,
        now: () => now,
        refreshInterval: const Duration(milliseconds: 5),
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.usdPrice, 30);

      now = now.add(const Duration(minutes: 2));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(sub.read(), isNull);
      expect(container.read(zecLiveUsdUnitPriceProvider), isNull);
    });

    test('keeps live data when cache persistence fails', () async {
      final source = _FakeSource(
        const ZecMarketData(usdPrice: 33.45, change24hPct: -0.26),
      );
      final container = makeContainer(
        swapEnabled: true,
        source: source,
        cache: _FakeCache(writeError: StateError('disk full')),
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);

      expect(sub.read()?.usdPrice, 33.45);
      expect(container.read(zecLiveUsdUnitPriceProvider), 33.45);
    });

    test('continues to fetch when reading the cache fails', () async {
      final source = _FakeSource(const ZecMarketData(usdPrice: 33.45));
      final container = makeContainer(
        swapEnabled: true,
        source: source,
        cache: _FakeCache(readError: StateError('unavailable')),
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);

      expect(sub.read()?.usdPrice, 33.45);
      expect(source.fetchCount, 1);
    });

    test('stays null when the source has no value yet', () async {
      final source = _FakeSource(null);
      final container = makeContainer(swapEnabled: true, source: source);
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
      expect(source.fetchCount, 1);
    });

    test('does not fetch while market-price UI is disabled', () async {
      final source = _FakeSource(
        const ZecMarketData(usdPrice: 33.45, change24hPct: 5.0),
      );
      final cache = _FakeCache(
        value: CachedZecMarketData(
          data: const ZecMarketData(usdPrice: 30),
          fetchedAt: DateTime.now(),
        ),
      );
      final container = makeContainer(
        swapEnabled: false,
        source: source,
        cache: cache,
      );
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
      expect(source.fetchCount, 0);
      expect(cache.readCount, 0);
    });
  });
}
