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
}
