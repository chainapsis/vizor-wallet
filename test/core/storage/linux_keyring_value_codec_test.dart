import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_value_codec.dart';

/// flutter_secure_storage_linux stores every entry in one JSON object. A
/// passwordless gnome-keyring collection cannot read that object back once its
/// JSON contains a backslash.
bool _keyringItemHasEscapes(Map<String, String> entries) =>
    jsonEncode(entries).contains(r'\');

void main() {
  test('leaves values without JSON escapes unchanged', () {
    for (final value in [
      'zcash_wallet_0123456789abcdef01234567.db',
      'true',
      'q2v3+/Zm9vYmFy==',
      'https://zec.rocks:443',
      'Konto über',
      '',
    ]) {
      expect(encodeLinuxKeyringValue(value), value);
      expect(decodeLinuxKeyringValue(value), value);
    }
  });

  test('encodes values JSON would escape and round-trips them', () {
    for (final value in [
      '[{"uuid":"550e8400-e29b-41d4-a716-446655440000","name":"Account 1"}]',
      r'C:\wallets\zcash',
      'line one\nline two',
      'tab\tand\u0001control',
      'Konto "über"',
    ]) {
      expect(linuxKeyringValueNeedsEncoding(value), isTrue);
      final stored = encodeLinuxKeyringValue(value);
      expect(_keyringItemHasEscapes({'key': stored}), isFalse);
      expect(decodeLinuxKeyringValue(stored), value);
    }
  });

  test('encodes a value that already looks encoded', () {
    const value = 'vizor-b64:not-really-encoded';
    final stored = encodeLinuxKeyringValue(value);

    expect(stored, isNot(value));
    expect(decodeLinuxKeyringValue(stored), value);
  });

  test('an encoded value never needs encoding again', () {
    final stored = encodeLinuxKeyringValue('{"v":1}');

    expect(linuxKeyringValueNeedsEncoding(stored), isFalse);
  });

  test('a malformed encoded value fails instead of reading as empty', () {
    expect(
      () => decodeLinuxKeyringValue('vizor-b64:%%%'),
      throwsA(isA<FormatException>()),
    );
  });
}
