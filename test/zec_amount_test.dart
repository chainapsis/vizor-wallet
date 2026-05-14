import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';

void main() {
  group('ZecAmount.tryParse', () {
    test('parses canonical period-separated amounts', () {
      expect(ZecAmount.tryParse('0.01')?.zatoshi, BigInt.from(1000000));
      expect(ZecAmount.tryParse('.01')?.zatoshi, BigInt.from(1000000));
      expect(ZecAmount.tryParse('1.')?.zatoshi, BigInt.from(100000000));
      expect(ZecAmount.tryParse('0.00000001')?.zatoshi, BigInt.one);
    });

    test('rejects commas and non-canonical decimals', () {
      expect(ZecAmount.tryParse('0,01'), isNull);
      expect(ZecAmount.tryParse('1,2.3'), isNull);
      expect(ZecAmount.tryParse('1.2.3'), isNull);
      expect(ZecAmount.tryParse('0.000000001'), isNull);
    });
  });

  group('formatZecAmount', () {
    test('uses a period as the decimal separator', () {
      expect(
        formatZecAmount(BigInt.from(1000000), minFractionDigits: 2),
        '0.01',
      );
      expect(
        formatZecAmount(BigInt.from(100000000), minFractionDigits: 2),
        '1.00',
      );
    });

    test('preserves exact zatoshi precision when needed', () {
      expect(formatZecAmount(BigInt.one, minFractionDigits: 2), '0.00000001');
      expect(formatZecAmount(BigInt.from(123450000)), '1.2345');
    });
  });

  group('ZecAmountPretty', () {
    test('formats balance and receipt presets with existing precision', () {
      final defaultTickerLower = kZcashDefaultCurrencyTicker.toLowerCase();

      expect(
        ZecAmount.fromZatoshi(BigInt.from(100000000)).balance.amountText,
        '1.00',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.from(100000000)).receipt.toString(),
        '1.00 $defaultTickerLower',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.one).balance.amountText,
        '0.00000001',
      );
    });

    test('formats fee preset with upper-case denom', () {
      expect(
        ZecAmount.fromZatoshi(BigInt.from(10000)).fee.toString(),
        '0.0001 $kZcashDefaultCurrencyTicker',
      );
    });

    test('formats activity rows with compact precision', () {
      expect(
        ZecAmount.fromZatoshi(BigInt.from(123450000)).activity.toString(),
        '1.2345 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.from(123400000)).activity.toString(),
        '1.234 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.from(10000)).activity.toString(),
        '0.0001 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.zero).activity.toString(),
        '0 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(-BigInt.from(100000000)).activity.toString(),
        '1 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(
          -BigInt.from(100000000),
        ).signedActivity.toString(),
        '-1 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.zero).signedActivity.toString(),
        '0 $kZcashDefaultCurrencyTicker',
      );
    });

    test('formats activity details with full precision', () {
      expect(
        ZecAmount.fromZatoshi(BigInt.from(123450000)).activityDetail.toString(),
        '1.2345 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.one).activityDetail.toString(),
        '0.00000001 $kZcashDefaultCurrencyTicker',
      );
      expect(
        ZecAmount.fromZatoshi(BigInt.from(100000000)).activityDetail.toString(),
        '1.00 $kZcashDefaultCurrencyTicker',
      );
    });

    test('can render testnet amounts with TAZ denomination', () {
      final ticker = ZcashNetwork.testnet.currencyTicker;

      expect(
        ZecAmount.fromZatoshi(
          BigInt.from(100000000),
        ).receiptPretty(denomination: ticker).toString(),
        '1.00 taz',
      );
      expect(
        ZecAmount.fromZatoshi(
          BigInt.from(10000),
        ).feePretty(denomination: ticker).toString(),
        '0.0001 TAZ',
      );
    });
  });

  group('ZecAmountInputFormatter', () {
    const formatter = ZecAmountInputFormatter();

    test('normalizes comma input to period before parsing', () {
      final value = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: '0,01',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );

      expect(value.text, '0.01');
      expect(ZecAmount.tryParse(value.text)?.zatoshi, BigInt.from(1000000));
    });

    test('rejects invalid characters and ambiguous separators', () {
      const oldValue = TextEditingValue(text: '1.2');

      expect(
        formatter
            .formatEditUpdate(oldValue, const TextEditingValue(text: '1.2a'))
            .text,
        oldValue.text,
      );
      expect(
        formatter
            .formatEditUpdate(oldValue, const TextEditingValue(text: '1,2.3'))
            .text,
        oldValue.text,
      );
      expect(
        formatter
            .formatEditUpdate(
              oldValue,
              const TextEditingValue(text: '1.123456789'),
            )
            .text,
        oldValue.text,
      );
    });
  });
}
