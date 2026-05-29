import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/crypto/bech32.dart';

void main() {
  group('decodeSegwitAddress (mainnet bc)', () {
    test('accepts a valid P2WPKH (bech32, v0)', () {
      final r = decodeSegwitAddress(
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
      );
      expect(r, isNotNull);
      expect(r!.version, 0);
      expect(r.program, hasLength(20));
    });

    test('accepts a valid P2WSH (bech32, v0, 32-byte program)', () {
      final r = decodeSegwitAddress(
        'bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3',
      );
      expect(r, isNotNull);
      expect(r!.version, 0);
      expect(r.program, hasLength(32));
    });

    test('accepts the all-uppercase form', () {
      expect(
        decodeSegwitAddress('BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4'),
        isNotNull,
      );
    });

    test('rejects a tampered checksum', () {
      expect(
        decodeSegwitAddress(
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5',
        ),
        isNull,
      );
    });

    test('rejects mixed case', () {
      expect(
        decodeSegwitAddress(
          'bc1qw508d6qejxtdg4y5r3zarvarY0c5xw7kv8f3t4',
        ),
        isNull,
      );
    });

    test('rejects the wrong human-readable prefix (tb = testnet)', () {
      expect(
        decodeSegwitAddress(
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        ),
        isNull,
      );
    });

    test('honours an explicit hrp override', () {
      expect(
        decodeSegwitAddress(
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
          hrp: 'tb',
        ),
        isNotNull,
      );
    });
  });
}
