import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';

void main() {
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

  group('parseZecAmount', () {
    test('parses canonical period-separated amounts', () {
      expect(parseZecAmount('0.01'), BigInt.from(1000000));
      expect(parseZecAmount('.01'), BigInt.from(1000000));
      expect(parseZecAmount('1.'), BigInt.from(100000000));
      expect(parseZecAmount('0.00000001'), BigInt.one);
    });

    test('rejects commas and non-canonical decimals', () {
      expect(parseZecAmount('0,01'), isNull);
      expect(parseZecAmount('1,2.3'), isNull);
      expect(parseZecAmount('1.2.3'), isNull);
      expect(parseZecAmount('0.000000001'), isNull);
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
      expect(parseZecAmount(value.text), BigInt.from(1000000));
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
