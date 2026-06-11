/// Base58Check decoding with double-SHA256 checksum verification, used to
/// validate legacy (base58) Bitcoin addresses. Pure Dart over the `crypto`
/// package (already a dependency) — no new dependency, web-safe.
///
/// Returns the decoded payload (version byte(s) + data, without the 4-byte
/// checksum) when the checksum is valid, or `null` when the input is not a
/// well-formed Base58Check string.
library;

import 'package:crypto/crypto.dart';

const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

List<int>? _base58Decode(String input) {
  if (input.isEmpty) return null;
  final big58 = BigInt.from(58);
  var num = BigInt.zero;
  for (final unit in input.codeUnits) {
    final idx = _alphabet.indexOf(String.fromCharCode(unit));
    if (idx < 0) return null;
    num = num * big58 + BigInt.from(idx);
  }

  final bytes = <int>[];
  var n = num;
  final mask = BigInt.from(0xff);
  while (n > BigInt.zero) {
    bytes.insert(0, (n & mask).toInt());
    n = n >> 8;
  }

  // Each leading '1' in base58 represents a leading zero byte.
  for (final unit in input.codeUnits) {
    if (unit == 0x31 /* '1' */ ) {
      bytes.insert(0, 0);
    } else {
      break;
    }
  }
  return bytes;
}

/// Decodes [input] as plain Base58 (no checksum). Returns the raw bytes, or
/// `null` when the input is empty or contains non-alphabet characters. Used
/// for formats that are bare Base58 without a Base58Check checksum, such as
/// Solana addresses (Ed25519 public keys, exactly 32 bytes).
List<int>? base58Decode(String input) => _base58Decode(input);

/// Decodes [input] and verifies its 4-byte double-SHA256 checksum.
/// Returns the payload (everything before the checksum) or `null` if invalid.
List<int>? base58CheckDecode(String input) {
  final raw = _base58Decode(input);
  if (raw == null || raw.length < 5) return null;
  final payload = raw.sublist(0, raw.length - 4);
  final checksum = raw.sublist(raw.length - 4);
  final hash = sha256.convert(sha256.convert(payload).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (hash[i] != checksum[i]) return null;
  }
  return payload;
}
