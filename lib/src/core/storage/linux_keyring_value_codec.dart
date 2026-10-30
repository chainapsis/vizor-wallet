import 'dart:convert';

const _encodedValuePrefix = 'vizor-b64:';

/// Returns a stored form of [value] whose JSON string encoding contains no
/// backslash.
///
/// `flutter_secure_storage_linux` keeps every key in one libsecret item that
/// holds a JSON object. gnome-keyring saves a passwordless collection as a
/// plaintext file without escaping the secret, then reloads it with GKeyFile
/// unescaping, which rejects sequences such as `\"` and leaves the item with an
/// empty secret. A single quote in any value therefore made every key read back
/// as missing. Values that JSON would escape, and values that already start
/// with the encoding prefix, are base64-encoded. Other values are stored
/// unchanged so builds without this codec still read them.
String encodeLinuxKeyringValue(String value) {
  if (!linuxKeyringValueNeedsEncoding(value) &&
      !value.startsWith(_encodedValuePrefix)) {
    return value;
  }
  return '$_encodedValuePrefix${base64.encode(utf8.encode(value))}';
}

/// Reverses [encodeLinuxKeyringValue]. A value without the encoding prefix is
/// returned unchanged, which covers values written before the codec existed.
String decodeLinuxKeyringValue(String stored) {
  if (!stored.startsWith(_encodedValuePrefix)) return stored;
  return utf8.decode(
    base64.decode(stored.substring(_encodedValuePrefix.length)),
  );
}

/// Whether JSON would escape [value] with a backslash, meaning it contains a
/// quote, a backslash, or a control character.
bool linuxKeyringValueNeedsEncoding(String value) {
  for (final unit in value.codeUnits) {
    if (unit == 0x22 || unit == 0x5C || unit < 0x20) return true;
  }
  return false;
}
