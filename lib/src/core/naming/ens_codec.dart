import 'dart:convert';
import '../crypto/keccak256.dart';

/// ENSIP-1 namehash. [name] must already be normalized (Task 1).
List<int> namehash(String name) {
  var node = List<int>.filled(32, 0);
  if (name.isEmpty) return node;
  for (final label in name.split('.').reversed) {
    node = keccak256([...node, ...keccak256(utf8.encode(label))]);
  }
  return node;
}

/// DNS wire-format encoding used by UniversalResolver.resolve(bytes,bytes).
List<int> dnsEncodeName(String name) {
  final out = <int>[];
  for (final label in name.split('.')) {
    final bytes = utf8.encode(label);
    assert(bytes.length < 64, 'label too long for DNS encoding');
    out..add(bytes.length)..addAll(bytes);
  }
  return out..add(0);
}

const _hexDigits = '0123456789abcdef';

String hexEncode(List<int> bytes) {
  final sb = StringBuffer('0x');
  for (final b in bytes) {
    sb..write(_hexDigits[(b >> 4) & 0xf])..write(_hexDigits[b & 0xf]);
  }
  return sb.toString();
}

List<int> hexDecode(String hex) {
  var h = hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;
  if (h.length.isOdd) h = '0$h';
  return [
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ];
}

// ABI encoding/decoding helpers

List<int> _word(BigInt v) {
  final out = List<int>.filled(32, 0);
  var x = v;
  for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

List<int> _padRight32(List<int> b) =>
    [...b, ...List.filled((32 - b.length % 32) % 32, 0)];

BigInt _readWord(List<int> d, int offset) {
  var v = BigInt.zero;
  for (var i = 0; i < 32; i++) {
    v = (v << 8) | BigInt.from(d[offset + i]);
  }
  return v;
}

/// EIP-55 checksum address from 20 bytes.
String _toChecksumAddress(List<int> raw) {
  final hex = hexEncode(raw).substring(2); // lowercase 40-char hex
  final hash = keccak256(ascii.encode(hex));
  final chars = <String>[];
  for (var i = 0; i < 40; i++) {
    final ch = hex[i];
    final hashByte = hash[i >> 1];
    final nibble = (i & 1) == 0 ? (hashByte >> 4) : (hashByte & 0x0f);
    chars.add(nibble >= 8 ? ch.toUpperCase() : ch);
  }
  return '0x' + chars.join();
}

/// `addr(bytes32)` selector `3b3b57de`
List<int> encodeAddrCall(List<int> node) =>
    [...hexDecode('3b3b57de'), ...node];

/// `addr(bytes32,uint256)` selector `f1cb7e06`
List<int> encodeAddrCoinCall(List<int> node, BigInt coinType) =>
    [...hexDecode('f1cb7e06'), ...node, ..._word(coinType)];

/// `resolve(bytes,bytes)` selector `9061b923`, two dynamic `bytes` args
List<int> encodeUniversalResolve(List<int> dnsName, List<int> callData) {
  final head1 = _word(BigInt.from(0x40));
  final tail1 = [..._word(BigInt.from(dnsName.length)), ..._padRight32(dnsName)];
  final head2 = _word(BigInt.from(0x40 + tail1.length));
  final tail2 = [..._word(BigInt.from(callData.length)), ..._padRight32(callData)];
  return [...hexDecode('9061b923'), ...head1, ...head2, ...tail1, ...tail2];
}

/// Decodes `(bytes result, address resolver)` return from UniversalResolver
/// and returns the inner `result` bytes.
List<int> decodeUniversalResolveResult(List<int> data) {
  final offset = _readWord(data, 0).toInt();
  final len = _readWord(data, offset).toInt();
  return data.sublist(offset + 32, offset + 32 + len);
}

/// Decodes a single dynamic `bytes` return value (offset + length + payload).
List<int> decodeBytesResult(List<int> data) => decodeUniversalResolveResult(data);

/// Decodes the last 20 bytes of a 32-byte word to EIP-55-checksummed address.
String decodeAddressWord(List<int> word) {
  final raw = word.sublist(word.length - 20);
  return _toChecksumAddress(raw);
}

/// EVM coin type per ENSIP-11: ETH is 60, others use 0x80000000 | chainId
BigInt evmCoinType(int chainId) => chainId == 1
    ? BigInt.from(60)
    : BigInt.from(0x80000000 | chainId);
