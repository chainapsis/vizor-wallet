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

    test('picker label pairs code and symbol', () {
      expect(kUsdFiatCurrency.pickerLabel, r'USD ($)');
      expect(krw.pickerLabel, 'KRW (₩)');
    });
  });
}
