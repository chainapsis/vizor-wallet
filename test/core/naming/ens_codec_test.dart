import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_codec.dart';

void main() {
  test('namehash matches ENSIP-1 vectors', () {
    expect(hexEncode(namehash('')),
        '0x0000000000000000000000000000000000000000000000000000000000000000');
    expect(hexEncode(namehash('eth')),
        '0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae');
    expect(hexEncode(namehash('foo.eth')),
        '0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f');
  });

  test('dnsEncodeName length-prefixes labels and null-terminates', () {
    expect(dnsEncodeName('foo.eth'),
        [3, 0x66, 0x6f, 0x6f, 3, 0x65, 0x74, 0x68, 0]);
  });

  test('hex round trip', () {
    expect(hexDecode('0x00ff10'), [0, 255, 16]);
    expect(hexEncode([0, 255, 16]), '0x00ff10');
  });

  test('encodeAddrCoinCall builds selector + node + coinType words', () {
    final node = List<int>.filled(32, 0x11);
    final data = encodeAddrCoinCall(node, BigInt.from(133));
    expect(hexEncode(data.sublist(0, 4)), '0xf1cb7e06');
    expect(data.sublist(4, 36), node);
    expect(data.length, 4 + 32 + 32);
    expect(data.last, 133);
  });

  test('encodeUniversalResolve places two dynamic bytes args', () {
    final name = dnsEncodeName('foo.eth');
    final call = encodeAddrCall(namehash('foo.eth'));
    final data = encodeUniversalResolve(name, call);
    expect(hexEncode(data.sublist(0, 4)), '0x9061b923');
    // head: offset1 = 0x40, offset2 = 0x40 + 32 + pad32(name.length)
    expect(data[4 + 31], 0x40);
  });

  test('decodeUniversalResolveResult unwraps (bytes,address)', () {
    // Hand-built return blob: offset 0x40, resolver addr word, len 32, word.
    final inner = List<int>.filled(32, 0x22);
    final blob = <int>[
      ...List.filled(31, 0), 0x40,
      ...List.filled(12, 0), ...List.filled(20, 0xaa),
      ...List.filled(31, 0), 32,
      ...inner,
    ];
    expect(decodeUniversalResolveResult(blob), inner);
  });

  test('decodeAddressWord returns checksummed address', () {
    final word = [...List.filled(12, 0), ...hexDecode('d8da6bf26964af9d7eed9e03e53415d37aa96045')];
    expect(decodeAddressWord(word), '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045');
  });
}
