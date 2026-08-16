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
