import '../../../l10n/app_localizations.dart';
import '../layout/app_form_factor.dart';

/// Mobile sets and unlocks the wallet through the 6-digit passcode UI,
/// so the minimum length follows the compiled form factor; desktop
/// typed passwords keep the original 8-character floor.
const kWalletPasswordMinLength = kAppFormFactor == AppFormFactor.mobile ? 6 : 8;
const kWalletPasswordMinLengthMessage =
    'Password must be at least $kWalletPasswordMinLength characters.';
const kWalletPasswordAsciiMessage =
    'Use only English letters, numbers, and symbols.';
const kWalletPasswordMustDifferMessage = 'Use a different password.';

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

String? validateRequiredWalletPassword(String value) {
  if (value.isEmpty) return kWalletPasswordMinLengthMessage;
  return validateWalletPassword(value);
}

bool isWalletPasswordValid(String value) {
  return value.isNotEmpty && validateWalletPassword(value) == null;
}

/// Localized variants for UI validation. The English consts above remain the
/// programmatic layer's copy (provider throws, tests); screens resolve
/// messages through the active [AppLocalizations].
String? validateWalletPasswordLocalized(
  String value,
  AppLocalizations l10n,
) {
  if (value.isEmpty) return null;
  if (!isWalletPasswordAsciiOnly(value)) {
    return l10n.passwordAsciiOnly;
  }
  if (value.length < kWalletPasswordMinLength) {
    return l10n.passwordTooShort(kWalletPasswordMinLength);
  }
  return null;
}

String? validateRequiredWalletPasswordLocalized(
  String value,
  AppLocalizations l10n,
) {
  if (value.isEmpty) return l10n.passwordTooShort(kWalletPasswordMinLength);
  return validateWalletPasswordLocalized(value, l10n);
}
