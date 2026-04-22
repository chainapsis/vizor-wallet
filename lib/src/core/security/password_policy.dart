const kWalletPasswordMinLength = 8;
const kWalletPasswordMinLengthMessage =
    'Password must be at least 8 characters.';
const kWalletPasswordAsciiMessage =
    'Use only English letters, numbers, and symbols.';

bool isWalletPasswordAsciiOnly(String value) {
  return value.runes.every((rune) => rune >= 0x21 && rune <= 0x7E);
}

String? validateWalletPassword(String value) {
  if (value.isEmpty) return null;
  if (!isWalletPasswordAsciiOnly(value)) {
    return kWalletPasswordAsciiMessage;
  }
  if (value.length < kWalletPasswordMinLength) {
    return kWalletPasswordMinLengthMessage;
  }
  return null;
}

bool isWalletPasswordValid(String value) {
  return value.isNotEmpty && validateWalletPassword(value) == null;
}
