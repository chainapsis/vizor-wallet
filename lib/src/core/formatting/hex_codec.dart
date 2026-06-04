import 'dart:typed_data';

/// Decodes a hex string into bytes, tolerating an optional `0x` prefix.
///
/// Assumes [hex] is well-formed (even length, hex digits only); callers that
/// accept untrusted input should validate before calling.
Uint8List hexToBytes(String hex) {
  final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
  return Uint8List.fromList([
    for (var i = 0; i < normalized.length; i += 2)
      int.parse(normalized.substring(i, i + 2), radix: 16),
  ]);
}

/// Encodes bytes into a lowercase hex string with no prefix.
String bytesToHex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
