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

    test('formats compact balances with adaptive precision', () {
      String compact(String value) =>
          ZecAmount.tryParse(value)!.compactBalance.amountText;

      expect(compact('0'), '0');
      expect(compact('0.00000001'), '<0.000001');
      expect(compact('0.00000099'), '<0.000001');
      expect(compact('0.000001'), '0.000001');
      expect(compact('0.00000123'), '0.000001');
      expect(compact('0.00012345'), '0.000123');
      expect(compact('0.00123456'), '0.001234');
      expect(compact('0.01'), '0.01');
      expect(compact('0.01000001'), '0.01');
      expect(compact('0.12345678'), '0.123456');
      expect(compact('0.99999999'), '0.999999');
      expect(compact('1'), '1');
      expect(compact('1.00000001'), '1');
      expect(compact('1.00000123'), '1.000001');
      expect(compact('1.20000000'), '1.20');
      expect(compact('1.23450000'), '1.2345');
      expect(compact('1.23456789'), '1.234567');
      expect(compact('9.99999999'), '9.999999');
      expect(compact('10.12345678'), '10.12345');
      expect(compact('99.99999999'), '99.99999');
      expect(compact('100.12345678'), '100.1234');
      expect(compact('999.99999999'), '999.9999');
      expect(compact('1000.12345678'), '1000.123');
      expect(compact('1000.00012345'), '1000');
      expect(compact('9999.99999999'), '9999.999');
      expect(compact('10000.12345678'), '10000.12');
      expect(compact('99999.99999999'), '99999.99');
      expect(compact('123456.12345678'), '123456.12');
      expect(compact('1234567.12345678'), '1234567.12');
      expect(compact('123456789123'), '123456789123');
      expect(
        ZecAmount.tryParse(
          '1',
        )!.compactBalancePretty(hideZeroFraction: false).amountText,
        '1.00',
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
