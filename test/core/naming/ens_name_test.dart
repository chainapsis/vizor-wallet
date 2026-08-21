import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_name.dart';

void main() {
  group('isEnsName', () {
    test('accepts second-level and deeper .eth names', () {
      expect(isEnsName('vitalik.eth'), isTrue);
      expect(isEnsName('pay.vitalik.eth'), isTrue);
      expect(isEnsName('VITALIK.ETH'), isTrue); // case-insensitive detection
      expect(isEnsName('  vitalik.eth  '), isTrue); // trimmed
    });
    test('rejects non-names', () {
      expect(isEnsName('0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045'), isFalse);
      expect(isEnsName('eth'), isFalse); // bare TLD
      expect(isEnsName('vitalik.near'), isFalse);
      expect(isEnsName(''), isFalse);
    });
  });

  group('normalizeEnsName', () {
    test('lowercases and trims', () {
      expect(normalizeEnsName(' Vitalik.ETH '), 'vitalik.eth');
    });
    test('rejects empty labels, bad chars, hyphen edges', () {
      expect(() => normalizeEnsName('vi..talik.eth'), throwsA(isA<EnsNameException>()));
      expect(() => normalizeEnsName('vita lik.eth'), throwsA(isA<EnsNameException>()));
      expect(() => normalizeEnsName('vitälik.eth'), throwsA(isA<EnsNameException>()));
      expect(() => normalizeEnsName('-vitalik.eth'), throwsA(isA<EnsNameException>()));
      expect(() => normalizeEnsName('vitalik-.eth'), throwsA(isA<EnsNameException>()));
    });
  });
}
