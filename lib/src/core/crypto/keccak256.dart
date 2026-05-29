/// Keccak-256 (the original Keccak with 0x01 domain padding used by Ethereum —
/// NOT the standardized SHA3-256, which pads with 0x06).
///
/// This is a faithful in-tree port of the canonical Keccak-f[1600] sponge
/// reference (Keccak Team reference / FIPS-202 PUB 202 specification), with the
/// same round constants, rho rotation offsets, and rate=136 sponge as
/// pointycastle's `KeccakDigest(256)`. It is kept dependency-free and verified
/// against the official Keccak test vectors and the EIP-55 reference addresses
/// in `test/core/crypto/keccak256_test.dart` /
/// `test/features/address_book/address_format_validator_test.dart`.
///
/// References:
///   - FIPS-202 (SHA-3 / Keccak) — https://doi.org/10.6028/NIST.FIPS.202
///   - Keccak Team reference — https://keccak.team/keccak_specs_summary.html
///
/// Used for EIP-55 address checksum verification. Targets the native 64-bit int
/// VM (iOS/Android/macOS); not safe on the web int model.
library;

const List<int> _roundConstants = [
  0x0000000000000001, 0x0000000000008082,
  0x800000000000808a, 0x8000000080008000,
  0x000000000000808b, 0x0000000080000001,
  0x8000000080008081, 0x8000000000008009,
  0x000000000000008a, 0x0000000000000088,
  0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b,
  0x8000000000008089, 0x8000000000008003,
  0x8000000000008002, 0x8000000000000080,
  0x000000000000800a, 0x800000008000000a,
  0x8000000080008081, 0x8000000000008080,
  0x0000000080000001, 0x8000000080008008,
];

const List<int> _rotationOffsets = [
  0, 1, 62, 28, 27, //
  36, 44, 6, 55, 20, //
  3, 10, 43, 25, 39, //
  41, 45, 15, 21, 8, //
  18, 2, 61, 56, 14, //
];

int _rotl(int x, int n) {
  if (n == 0) return x;
  return (x << n) | (x >>> (64 - n));
}

void _keccakF1600(List<int> a) {
  final c = List<int>.filled(5, 0);
  final d = List<int>.filled(5, 0);
  final b = List<int>.filled(25, 0);

  for (var round = 0; round < 24; round++) {
    for (var x = 0; x < 5; x++) {
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
    }
    for (var x = 0; x < 5; x++) {
      d[x] = c[(x + 4) % 5] ^ _rotl(c[(x + 1) % 5], 1);
    }
    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 25; y += 5) {
        a[x + y] ^= d[x];
      }
    }

    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 5; y++) {
        final idx = x + 5 * y;
        final newIdx = y + 5 * ((2 * x + 3 * y) % 5);
        b[newIdx] = _rotl(a[idx], _rotationOffsets[idx]);
      }
    }

    for (var y = 0; y < 25; y += 5) {
      for (var x = 0; x < 5; x++) {
        a[x + y] = b[x + y] ^ ((~b[(x + 1) % 5 + y]) & b[(x + 2) % 5 + y]);
      }
    }

    a[0] ^= _roundConstants[round];
  }
}

/// Computes the Keccak-256 digest (32 bytes) of [input].
List<int> keccak256(List<int> input) {
  const rate = 136; // 1088-bit rate, 512-bit capacity
  final state = List<int>.filled(25, 0);

  final padLen = rate - (input.length % rate);
  final padded = List<int>.from(input)..addAll(List<int>.filled(padLen, 0));
  padded[input.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;

  for (var off = 0; off < padded.length; off += rate) {
    for (var i = 0; i < rate; i++) {
      final lane = i ~/ 8;
      final shift = 8 * (i % 8);
      state[lane] ^= (padded[off + i] & 0xff) << shift;
    }
    _keccakF1600(state);
  }

  final out = List<int>.filled(32, 0);
  for (var i = 0; i < 32; i++) {
    final lane = i ~/ 8;
    final shift = 8 * (i % 8);
    out[i] = (state[lane] >>> shift) & 0xff;
  }
  return out;
}
