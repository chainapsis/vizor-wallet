import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/crypto/base58check.dart';

void main() {
  group('base58CheckDecode', () {
    test('decodes the genesis P2PKH address (version 0x00)', () {
      final payload = base58CheckDecode('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa');
      expect(payload, isNotNull);
      expect(payload!.first, 0x00); // mainnet P2PKH version byte
      expect(payload, hasLength(21)); // 1 version + 20 hash160
    });

    test('decodes a P2SH address (version 0x05)', () {
      final payload = base58CheckDecode('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy');
      expect(payload, isNotNull);
      expect(payload!.first, 0x05); // mainnet P2SH version byte
    });

    test('rejects a tampered checksum', () {
      // Genesis address with the last character changed.
      expect(
        base58CheckDecode('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb'),
        isNull,
      );
    });

    test('rejects non-base58 characters', () {
      expect(base58CheckDecode('1A1zP10OIl'), isNull);
    });

    test('rejects too-short input', () {
      expect(base58CheckDecode('1111'), isNull);
    });
  });
}
