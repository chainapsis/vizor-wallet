import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

class _FakeSource implements ZecPriceChange24hSource {
  _FakeSource(this.pct);

  final double? pct;
  int fetchCount = 0;

  @override
  Future<double?> fetchChangePct() async {
    fetchCount += 1;
    return pct;
  }
}

void main() {
  group('parseZecPriceChange24hPct', () {
    test('reads the zcash percentage from a satellite response', () {
      expect(parseZecPriceChange24hPct('{"zcash":-0.25852}'), -0.25852);
      expect(parseZecPriceChange24hPct('{"zcash":7.5,"cosmos":1.2}'), 7.5);
      expect(parseZecPriceChange24hPct('{"zcash":0}'), 0);
    });

    test('returns null for warm-up, malformed, and non-numeric bodies', () {
      expect(parseZecPriceChange24hPct('{}'), isNull);
      expect(parseZecPriceChange24hPct('{"cosmos":1.2}'), isNull);
      expect(parseZecPriceChange24hPct('{"zcash":"fast"}'), isNull);
      expect(parseZecPriceChange24hPct('{"zcash":null}'), isNull);
      expect(parseZecPriceChange24hPct('[]'), isNull);
      expect(parseZecPriceChange24hPct('not json'), isNull);
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

  group('zecPriceChange24hPctProvider', () {
    ProviderContainer makeContainer({
      required bool swapEnabled,
      required ZecPriceChange24hSource source,
    }) {
      final container = ProviderContainer(
        overrides: [
          swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
          zecPriceChange24hSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('exposes the fetched percentage after the first tick', () async {
      final source = _FakeSource(-0.26);
      final container = makeContainer(swapEnabled: true, source: source);
      final sub = container.listen(zecPriceChange24hPctProvider, (_, _) {});

      expect(sub.read(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), -0.26);
      expect(source.fetchCount, 1);
    });

    test('stays null when the source has no value yet', () async {
      final source = _FakeSource(null);
      final container = makeContainer(swapEnabled: true, source: source);
      final sub = container.listen(zecPriceChange24hPctProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
      expect(source.fetchCount, 1);
    });

    test('does not fetch while the swap feature is disabled', () async {
      final source = _FakeSource(5.0);
      final container = makeContainer(swapEnabled: false, source: source);
      final sub = container.listen(zecPriceChange24hPctProvider, (_, _) {});

      await Future<void>.delayed(Duration.zero);
      expect(sub.read(), isNull);
      expect(source.fetchCount, 0);
    });
  });
}
