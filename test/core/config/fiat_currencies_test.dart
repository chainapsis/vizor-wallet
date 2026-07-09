import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/fiat_currencies.dart';

void main() {
  group('fiatCurrencyForCode', () {
    test('resolves supported codes case-insensitively', () {
      expect(fiatCurrencyForCode('krw').code, 'krw');
      expect(fiatCurrencyForCode('KRW').code, 'krw');
      expect(fiatCurrencyForCode(' usd ').code, 'usd');
    });

    test('falls back to USD for unknown or missing codes', () {
      expect(fiatCurrencyForCode('xyz').code, 'usd');
      expect(fiatCurrencyForCode(null).code, 'usd');
      expect(fiatCurrencyForCode('').code, 'usd');
    });

    test('supported list has unique codes and starts with USD', () {
      final codes = kSupportedFiatCurrencies.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes.first, 'usd');
    });
  });

  group('formatCompactFiatValueFor', () {
    const krw = FiatCurrency(code: 'krw', symbol: '₩', maxDecimals: 0);

    test('keeps the pre-existing USD formatting byte-identical', () {
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 0), r'$0.00');
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 12.3), r'$12.30');
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 1234), r'$1.23K');
      expect(
        formatCompactFiatValueFor(kUsdFiatCurrency, 2500000),
        r'$2.5M',
      );
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, double.nan), r'$0.00');
    });

    test('honors zero-decimal currencies for plain values', () {
      expect(formatCompactFiatValueFor(krw, 0), '₩0');
      expect(formatCompactFiatValueFor(krw, 950.4), '₩950');
      expect(formatCompactFiatValueFor(krw, 45600.7), '₩45.6K');
      expect(formatCompactFiatValueFor(krw, 1234567), '₩1.235M');
    });

    test('values that round across a branch threshold compact instead of '
        'rendering ungrouped', () {
      // Plain-branch rounding must not produce the ungrouped "₩1000" the
      // compact contract rules out: 999.6 rounds to 1000 at zero decimals.
      expect(formatCompactFiatValueFor(krw, 999.6), '₩1K');
      expect(formatCompactFiatValueFor(krw, 999.4), '₩999');
      // USD keeps two decimals, so 999.6 stays plain but 999.996 crosses.
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 999.6), r'$999.60');
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 999.996), r'$1K');
      // Same rule at the K→M edge: 999,996 would render as "$1000K".
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 999996), r'$1M');
      expect(formatCompactFiatValueFor(kUsdFiatCurrency, 999940), r'$999.94K');
    });

    test('FiatDisplay converts USD values and falls back to USD', () {
      const inr = FiatCurrency(code: 'inr', symbol: '₹', maxDecimals: 1);
      const display = FiatDisplay(currency: inr, usdToCurrencyRate: 83.2);
      expect(display.displayCurrency.code, 'inr');
      expect(display.formatCompactUsdValue(510), '₹42.43K');
      expect(display.convertUsd(1).toStringAsFixed(1), '83.2');
      expect(display.toUsd(83.2).toStringAsFixed(1), '1.0');
      expect(display.placeholderText, '₹--');
      expect(display.zeroText, '₹0');

      const noRate = FiatDisplay(currency: inr);
      expect(noRate.displayCurrency.code, 'usd');
      expect(noRate.formatCompactUsdValue(510), r'$510.00');
      expect(noRate.placeholderText, r'$--');

      expect(kUsdFiatDisplay.formatCompactUsdValue(510), r'$510.00');
    });

    test('picker label pairs code and symbol', () {
      expect(kUsdFiatCurrency.pickerLabel, r'USD ($)');
      expect(krw.pickerLabel, 'KRW (₩)');
    });
  });
}
