import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/core/config/fiat_currencies.dart';

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

void main() {
  group('parseZecMarketData', () {
    test('reads ZEC price and 24h change from a CoinGecko response', () {
      final data = parseZecMarketData(
        '{"zcash":{"usd":33.45,"usd_24h_change":-0.25852}}',
      );

      expect(data?.usdPrice, 33.45);
      expect(data?.change24hPctFor(kUsdFiatCurrency), -0.25852);
    });

    test('allows a missing or null 24h change when price is usable', () {
      expect(
        parseZecMarketData(
          '{"zcash":{"usd":33.45}}',
        )?.change24hPctFor(kUsdFiatCurrency),
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

      final expectedCodes = kSupportedFiatCurrencies
          .map((currency) => currency.code)
          .join(',');
      expect(
        uri.toString(),
        'https://api.coingecko.com/api/v3/simple/price?'
        'ids=zcash&names=Zcash&symbols=zec&'
        'vs_currencies=${Uri.encodeQueryComponent(expectedCodes)}&'
        'include_24hr_change=true',
      );
    });

    test('reads every supported currency from a batched response', () {
      final data = parseZecMarketData(
        '{"zcash":{"usd":33.45,"usd_24h_change":-0.25852,'
        '"krw":45600.7,"krw_24h_change":-0.31}}',
      );
      final krw = fiatCurrencyForCode('krw');

      expect(data?.usdPrice, 33.45);
      expect(data?.priceFor(krw), 45600.7);
      expect(data?.change24hPctFor(krw), -0.31);
    });

    test('falls back to the USD 24h change for currencies missing one', () {
      final data = parseZecMarketData(
        '{"zcash":{"usd":33.45,"usd_24h_change":-0.25852,"krw":45600.7}}',
      );
      final krw = fiatCurrencyForCode('krw');

      expect(data?.priceFor(krw), 45600.7);
      expect(data?.change24hPctFor(krw), -0.25852);
    });

    test('returns null for a currency absent from the response', () {
      final data = parseZecMarketData('{"zcash":{"usd":33.45}}');

      expect(data?.priceFor(fiatCurrencyForCode('krw')), isNull);
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

  group('zecHomeMarketDataProvider', () {
    ProviderContainer makeContainer({
      required bool swapEnabled,
      required ZecMarketDataSource source,
    }) {
      final container = ProviderContainer(
        overrides: [
          swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
          zecMarketDataSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('exposes the fetched market data after the first tick', () async {
      final source = _FakeSource(
        const ZecMarketData(
          pricesByCurrency: {'usd': 33.45},
          change24hPctByCurrency: {'usd': -0.26},
        ),
      );
      final container = makeContainer(swapEnabled: true, source: source);
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      expect(sub.read(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read()?.usdPrice, 33.45);
      expect(container.read(zecHomeFiatUnitPriceProvider), 33.45);
      expect(container.read(zecPriceChange24hPctProvider), -0.26);
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
        const ZecMarketData(
          pricesByCurrency: {'usd': 33.45},
          change24hPctByCurrency: {'usd': 5.0},
        ),
      );
      final container = makeContainer(swapEnabled: false, source: source);
      final sub = container.listen(zecHomeMarketDataProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
      expect(source.fetchCount, 0);
    });
  });
}
