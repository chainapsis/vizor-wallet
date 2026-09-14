import 'dart:convert';

import '../../../core/crypto/base58check.dart';
import '../../../core/crypto/bech32.dart';
import 'address_book_contact.dart';

/// Mainnet checks for address encodings that carry network information.
/// No network inference is possible for raw TON account identifiers.
bool isMainnetExternalAddress(AddressBookNetwork network, String value) =>
    switch (network) {
      // Version bytes: each project's src/chainparams.cpp. Litecoin retains
      // the original Bitcoin-compatible P2SH version 5 as well as version 50.
      AddressBookNetwork.litecoin =>
        _legacy(value, const [48, 5, 50]) ||
            decodeSegwitAddress(value, hrp: 'ltc') != null ||
            isLitecoinMainnetMwebAddress(value),
      AddressBookNetwork.dogecoin => _legacy(value, const [30, 22]),
      AddressBookNetwork.dash => _legacy(value, const [76, 16]),
      AddressBookNetwork.bitcoinCash =>
        _legacy(value, const [0, 5]) || _cashAddress(value),
      AddressBookNetwork.ton => _tonAddress(value),
      AddressBookNetwork.cardano => _cardanoAddress(value),
      _ => false,
    };

bool _legacy(String value, List<int> versions) {
  if (value.length < 26 || value.length > 35) return false;
  final decoded = base58CheckDecode(value);
  return decoded != null &&
      decoded.length == 21 &&
      versions.contains(decoded.first);
}

// https://github.com/bitcoincashorg/bitcoincash.org/blob/master/spec/cashaddr.md
bool _cashAddress(String value) {
  if (value != value.toLowerCase() && value != value.toUpperCase()) {
    return false;
  }
  final lower = value.toLowerCase();
  final parts = lower.split(':');
  if (parts.length > 2 || (parts.length == 2 && parts.first != 'bitcoincash')) {
    return false;
  }
  final body = parts.last;
  if (body.length < 8 || body.length > 120) return false;
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final data = body.split('').map(alphabet.indexOf).toList();
  if (data.any((v) => v < 0)) return false;
  // BigInt keeps the 40-bit polymod exact on Dart's JavaScript target too.
  final generators = [
    0x98f2bc8e61,
    0x79b76d99e2,
    0xf33e5fb3c4,
    0xae2eabe2a8,
    0x1e4f43e470,
  ].map(BigInt.from).toList();
  var checksum = BigInt.one;
  for (final v in [...'bitcoincash'.codeUnits.map((c) => c & 31), 0, ...data]) {
    final top = (checksum >> 35).toInt();
    checksum = ((checksum & BigInt.from(0x07ffffffff)) << 5) ^ BigInt.from(v);
    for (var i = 0; i < 5; i++) {
      if ((top & (1 << i)) != 0) checksum ^= generators[i];
    }
  }
  if (checksum != BigInt.one) return false;
  final payload = _fromFiveBits(data.sublist(0, data.length - 8));
  if (payload == null || payload.isEmpty) return false;
  final version = payload.first;
  if ((version & 0x80) != 0) return false;
  // P2PKH, P2SH, and their CashTokens-aware forms.
  if (![0, 1, 2, 3].contains(version >> 3)) return false;
  const sizes = [20, 24, 28, 32, 40, 48, 56, 64];
  return payload.length == sizes[version & 7] + 1;
}

List<int>? _fromFiveBits(List<int> data) {
  var accumulator = 0;
  var bits = 0;
  final bytes = <int>[];
  for (final value in data) {
    accumulator = ((accumulator << 5) | value) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((accumulator >> bits) & 255);
    }
  }
  if (bits >= 5 || ((accumulator << (8 - bits)) & 255) != 0) return null;
  return bytes;
}

// https://docs.ton.org/foundations/addresses/formats
bool _tonAddress(String value) {
  if (RegExp(r'^-?[0-9]+:[0-9a-fA-F]{64}$').hasMatch(value)) {
    final workchain = int.tryParse(value.split(':').first);
    return workchain != null && workchain >= -128 && workchain <= 127;
  }
  if (value.length != 48) return false;
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != 36 || ![0x11, 0x51].contains(bytes.first)) return false;
    var crc = 0;
    for (final byte in bytes.take(34)) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = ((crc << 1) ^ ((crc & 0x8000) != 0 ? 0x1021 : 0)) & 0xffff;
      }
    }
    return bytes[34] == crc >> 8 && bytes[35] == (crc & 255);
  } on FormatException {
    return false;
  }
}

// https://cips.cardano.org/cip/CIP-19
bool _cardanoAddress(String value) {
  if (value.toLowerCase().startsWith('addr1')) {
    final bytes = decodeBech32Payload(value, hrp: 'addr');
    if (bytes == null || bytes.isEmpty || (bytes.first & 15) != 1) return false;
    final type = bytes.first >> 4;
    if (type <= 3) return bytes.length == 57;
    if (type == 6 || type == 7) return bytes.length == 29;
    if (type == 4 || type == 5) {
      // Slot, transaction and certificate indices are bounded to 32/16/16
      // bits. Keep accepting non-minimal encodings of values within range.
      var cursor = 29;
      for (final maximum in [0xffffffff, 0xffff, 0xffff]) {
        var value = 0;
        int byte;
        do {
          if (cursor >= bytes.length) return false;
          byte = bytes[cursor++];
          value = value * 128 + (byte & 0x7f);
          if (value > maximum) return false;
        } while ((byte & 0x80) != 0);
      }
      return cursor == bytes.length;
    }
    return false;
  }
  if (value.length > 256) return false;
  final bytes = base58Decode(value);
  if (bytes == null) return false;
  try {
    final outer = _AddressCbor(bytes);
    if (outer.head(4) != 2 || outer.head(6) != 24) return false;
    final body = outer.byteString();
    final checksum = outer.head(0);
    if (!outer.done || _crc32(body) != checksum) return false;
    final inner = _AddressCbor(body);
    if (inner.head(4) != 3 || inner.byteString().length != 28) return false;
    final attributes = inner.head(5);
    final keys = <int>{};
    for (var i = 0; i < attributes; i++) {
      final key = inner.head(0);
      if (!keys.add(key)) return false;
      // Byron network magic is present only on testnets (attribute key 2).
      if (key == 2) return false;
      inner.byteString();
    }
    return const [0, 2].contains(inner.head(0)) && inner.done;
  } on FormatException {
    return false;
  }
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// Only the definite-length CBOR primitives in CIP-19 Byron addresses.
class _AddressCbor {
  _AddressCbor(this.bytes);
  final List<int> bytes;
  int cursor = 0;
  bool get done => cursor == bytes.length;

  int head(int major) {
    if (cursor >= bytes.length) throw const FormatException();
    final byte = bytes[cursor++];
    if (byte >> 5 != major) throw const FormatException();
    final additional = byte & 31;
    if (additional < 24) return additional;
    final count = switch (additional) {
      24 => 1,
      25 => 2,
      26 => 4,
      _ => 0,
    };
    if (count == 0 || cursor + count > bytes.length) {
      throw const FormatException();
    }
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = value * 256 + bytes[cursor++];
    }
    return value;
  }

  List<int> byteString() {
    final length = head(2);
    if (cursor + length > bytes.length) throw const FormatException();
    final value = bytes.sublist(cursor, cursor + length);
    cursor += length;
    return value;
  }
}
