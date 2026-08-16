import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_codec.dart';

List<int> _word(int v) {
  final out = List<int>.filled(32, 0);
  var x = BigInt.from(v);
  for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

List<int> _padRight32(List<int> b) =>
    [...b, ...List.filled((32 - b.length % 32) % 32, 0)];

List<int> _addressWord(List<int> addr20) => [...List.filled(12, 0), ...addr20];

List<int> _encodeBytes(List<int> b) =>
    [..._word(b.length), ..._padRight32(b)];

List<int> _encodeStringArray(List<String> items) {
  final utf8Items = items.map(utf8.encode).toList();
  final count = utf8Items.length;
  final headWords = <int>[];
  final tailWords = <int>[];
  var runningOffset = count * 32;
  for (final bytes in utf8Items) {
    headWords.addAll(_word(runningOffset));
    final elemTail = [..._word(bytes.length), ..._padRight32(bytes)];
    tailWords.addAll(elemTail);
    runningOffset += elemTail.length;
  }
  return [..._word(count), ...headWords, ...tailWords];
}

/// Hand-encodes an EIP-3668 `OffchainLookup` revert: selector(4) +
/// `(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData)`.
String encodeOffchainLookupRevert({
  required List<int> sender,
  required List<String> urls,
  required List<int> callData,
  required List<int> callbackSelector,
  required List<int> extraData,
}) {
  final urlsBytes = _encodeStringArray(urls);
  final callDataBytes = _encodeBytes(callData);
  final extraDataBytes = _encodeBytes(extraData);

  const headSize = 5 * 32;
  final urlsOffset = headSize;
  final callDataOffset = urlsOffset + urlsBytes.length;
  final extraDataOffset = callDataOffset + callDataBytes.length;

  final tuple = [
    ..._addressWord(sender),
    ..._word(urlsOffset),
    ..._word(callDataOffset),
    ..._padRight32(callbackSelector),
    ..._word(extraDataOffset),
    ...urlsBytes,
    ...callDataBytes,
    ...extraDataBytes,
  ];
  return hexEncode([...hexDecode('556f1830'), ...tuple]);
}

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

  group('decodeOffchainLookup', () {
    test('round-trips sender/urls/callData/callbackSelector/extraData', () {
      final sender = hexDecode('d8da6bf26964af9d7eed9e03e53415d37aa96045');
      final callData = hexDecode('aabbccdd112233');
      final extraData = hexDecode('deadbeef');
      final callbackSelector = hexDecode('b4a85801');
      final revertHex = encodeOffchainLookupRevert(
        sender: sender,
        urls: [
          'https://gateway.example/{sender}/{data}.json',
          'https://gateway2.example/{sender}/{data}.json',
        ],
        callData: callData,
        callbackSelector: callbackSelector,
        extraData: extraData,
      );

      final decoded = decodeOffchainLookup(hexDecode(revertHex));

      expect(decoded, isNotNull);
      expect(decoded!.sender, '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045');
      expect(decoded.urls, [
        'https://gateway.example/{sender}/{data}.json',
        'https://gateway2.example/{sender}/{data}.json',
      ]);
      expect(decoded.callData, hexEncode(callData));
      expect(decoded.callbackSelector, hexEncode(callbackSelector));
      expect(decoded.extraData, hexEncode(extraData));
    });

    test('round-trips with a single-url array and empty extraData', () {
      final sender = hexDecode('0101010101010101010101010101010101010101');
      final revertHex = encodeOffchainLookupRevert(
        sender: sender,
        urls: ['https://gateway.example'],
        callData: hexDecode('1234'),
        callbackSelector: hexDecode('11223344'),
        extraData: const [],
      );

      final decoded = decodeOffchainLookup(hexDecode(revertHex));

      expect(decoded, isNotNull);
      expect(decoded!.urls, ['https://gateway.example']);
      expect(decoded.extraData, '0x');
    });

    test('returns null when the selector does not match', () {
      final data = [...hexDecode('deadbeef'), ...List.filled(32 * 5, 0)];
      expect(decodeOffchainLookup(data), isNull);
    });

    test('returns null when the revert data is too short', () {
      expect(decodeOffchainLookup(hexDecode('556f1830')), isNull);
    });
  });

  test('encodeCcipCallback places selector + two dynamic bytes args', () {
    final selector = hexDecode('b4a85801');
    final response = hexDecode('aabb');
    final extraData = hexDecode('ccddeeff');
    final data = encodeCcipCallback(selector, response, extraData);

    expect(hexEncode(data.sublist(0, 4)), '0xb4a85801');
    // head1 offset = 0x40
    expect(data[4 + 31], 0x40);
    // tail1: len(response)=2, then 32-byte padded payload
    expect(_readWordAt(data, 4 + 64), BigInt.two);
  });
}

BigInt _readWordAt(List<int> d, int offset) {
  var v = BigInt.zero;
  for (var i = 0; i < 32; i++) {
    v = (v << 8) | BigInt.from(d[offset + i]);
  }
  return v;
}
