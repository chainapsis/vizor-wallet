import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/models/send_amount_currency.dart';

void main() {
  group('send amount currency helpers', () {
    test('converts USD input to canonical zatoshi', () {
      expect(sendZatoshiFromUsdText('105', 70), BigInt.from(150000000));
      expect(sendZatoshiFromUsdText('.70', 70), BigInt.from(1000000));
    });

    test('converts USD input without floating-point zatoshi drift', () {
      expect(sendZatoshiFromUsdText('0.63', 70), BigInt.from(900000));
      expect(sendZatoshiFromUsdText('122.71', 70.12), BigInt.from(175000000));
    });

    test('rejects invalid or unavailable USD conversion inputs', () {
      expect(sendZatoshiFromUsdText('', 70), isNull);
      expect(sendZatoshiFromUsdText('.', 70), isNull);
      expect(sendZatoshiFromUsdText('0.', 70), isNull);
      expect(sendZatoshiFromUsdText('10', null), isNull);
      expect(sendZatoshiFromUsdText('10', 0), isNull);
      expect(sendZatoshiFromUsdText('abc', 70), isNull);
    });

    test('formats USD input and display values from zatoshi', () {
      final zatoshi = BigInt.from(123456789);

      expect(sendUsdInputTextForZatoshi(zatoshi, 70), '86.42');
      expect(sendableUsdInputTextForZatoshi(zatoshi, 70), '86.42');
      expect(sendUsdDisplayTextForZatoshi(zatoshi, 1234), '1,523.46');
    });

    test('keeps sub-cent values out of sendable USD inputs', () {
      expect(sendUsdInputTextForZatoshi(BigInt.one, 70), '0.00');
      expect(sendableUsdInputTextForZatoshi(BigInt.one, 70), isEmpty);
      expect(sendUsdDisplayTextForZatoshi(BigInt.zero, 70), '0.00');
    });
  });
}
