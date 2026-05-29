/// Bech32 / Bech32m decoding with checksum verification, for validating
/// Bitcoin native SegWit addresses (BIP-173 for witness v0, BIP-350 for v1+).
///
/// Faithful in-tree port of the BIP-173 / BIP-350 reference `bech32` /
/// `segwit_addr` implementations, kept dependency-free and verified against the
/// BIP test vectors in `test/core/crypto/bech32_test.dart`. The polymod works
/// on values below 2^30, so it is safe on both the native and web int models.
///
/// References:
///   - BIP-173 — https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
///   - BIP-350 — https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki
library;

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const _bech32Const = 1;
const _bech32mConst = 0x2bc830a3;

int _polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final b = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((b >> i) & 1) != 0) chk ^= gen[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) {
  final high = <int>[];
  final low = <int>[];
  for (final c in hrp.codeUnits) {
    high.add(c >> 5);
    low.add(c & 31);
  }
  return [...high, 0, ...low];
}

/// Returns the matched constant (bech32 or bech32m) or null on a bad checksum.
int? _verifyChecksum(String hrp, List<int> data) {
  final m = _polymod([..._hrpExpand(hrp), ...data]);
  if (m == _bech32Const) return _bech32Const;
  if (m == _bech32mConst) return _bech32mConst;
  return null;
}

({String hrp, List<int> data, int spec})? _bech32Decode(String bech) {
  for (final c in bech.codeUnits) {
    if (c < 33 || c > 126) return null;
  }
  final lower = bech.toLowerCase();
  final upper = bech.toUpperCase();
  if (bech != lower && bech != upper) return null; // mixed case
  final s = lower;
  if (s.length > 90) return null;
  final pos = s.lastIndexOf('1');
  if (pos < 1 || pos + 7 > s.length) return null;
  final hrp = s.substring(0, pos);
  final data = <int>[];
  for (final ch in s.substring(pos + 1).split('')) {
    final v = _charset.indexOf(ch);
    if (v == -1) return null;
    data.add(v);
  }
  final spec = _verifyChecksum(hrp, data);
  if (spec == null) return null;
  return (hrp: hrp, data: data.sublist(0, data.length - 6), spec: spec);
}

List<int>? _convertBits(List<int> data, int from, int to, {required bool pad}) {
  var acc = 0;
  var bits = 0;
  final ret = <int>[];
  final maxv = (1 << to) - 1;
  final maxAcc = (1 << (from + to - 1)) - 1;
  for (final value in data) {
    if (value < 0 || (value >> from) != 0) return null;
    acc = ((acc << from) | value) & maxAcc;
    bits += from;
    while (bits >= to) {
      bits -= to;
      ret.add((acc >> bits) & maxv);
    }
  }
  if (pad) {
    if (bits > 0) ret.add((acc << (to - bits)) & maxv);
  } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
    return null;
  }
  return ret;
}

/// Decodes and checksum-validates a SegWit address for [hrp] (default `bc`,
/// Bitcoin mainnet). Returns the witness version (0-16) and decoded program
/// bytes, or `null` if the address is not a valid SegWit address for [hrp].
({int version, List<int> program})? decodeSegwitAddress(
  String address, {
  String hrp = 'bc',
}) {
  final decoded = _bech32Decode(address);
  if (decoded == null || decoded.hrp != hrp || decoded.data.isEmpty) {
    return null;
  }
  final version = decoded.data[0];
  if (version > 16) return null;
  final program = _convertBits(decoded.data.sublist(1), 5, 8, pad: false);
  if (program == null || program.length < 2 || program.length > 40) {
    return null;
  }
  // v0 must be 20 (P2WPKH) or 32 (P2WSH) bytes.
  if (version == 0 && program.length != 20 && program.length != 32) {
    return null;
  }
  // v0 uses bech32; v1+ uses bech32m.
  final expected = version == 0 ? _bech32Const : _bech32mConst;
  if (decoded.spec != expected) return null;
  return (version: version, program: program);
}
