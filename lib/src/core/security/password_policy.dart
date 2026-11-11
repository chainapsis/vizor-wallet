import '../l10n/l10n.dart';
import '../layout/app_form_factor.dart';

/// Mobile sets and unlocks the wallet through the 6-digit passcode UI,
/// so the minimum length follows the compiled form factor; desktop
/// typed passwords keep the original 8-character floor.
const kWalletPasswordMinLength = kAppFormFactor == AppFormFactor.mobile ? 6 : 8;

/// Which rule a wallet password breaks.
enum PasswordPolicyIssue {
  /// Contains a character outside printable ASCII.
  nonAscii,

  /// Shorter than [kWalletPasswordMinLength].
  tooShort,

  /// Equal to the current password on a change.
  mustDiffer;

  String message(AppLocalizations l10n) => switch (this) {
    PasswordPolicyIssue.nonAscii => l10n.passwordPolicyAscii,
    PasswordPolicyIssue.tooShort => l10n.passwordPolicyMinLength(
      kWalletPasswordMinLength,
    ),
    PasswordPolicyIssue.mustDiffer => l10n.passwordPolicyMustDiffer,
  };
}

/// Thrown by credential writers that refuse a password the UI should already
/// have rejected. Screens turn [issue] into localized text.
class PasswordPolicyViolation extends ArgumentError {
  PasswordPolicyViolation(this.issue) : super(issue.name);

  final PasswordPolicyIssue issue;
}

bool isWalletPasswordAsciiOnly(String value) {
  return value.runes.every((rune) => rune >= 0x21 && rune <= 0x7E);
}

PasswordPolicyIssue? walletPasswordPolicyIssue(String value) {
  if (value.isEmpty) return null;
  if (!isWalletPasswordAsciiOnly(value)) return PasswordPolicyIssue.nonAscii;
  if (value.length < kWalletPasswordMinLength) {
    return PasswordPolicyIssue.tooShort;
  }
  return null;
}

PasswordPolicyIssue? requiredWalletPasswordPolicyIssue(String value) {
  if (value.isEmpty) return PasswordPolicyIssue.tooShort;
  return walletPasswordPolicyIssue(value);
}

String? validateWalletPassword(AppLocalizations l10n, String value) =>
    walletPasswordPolicyIssue(value)?.message(l10n);

String? validateRequiredWalletPassword(AppLocalizations l10n, String value) =>
    requiredWalletPasswordPolicyIssue(value)?.message(l10n);

bool isWalletPasswordValid(String value) {
  return value.isNotEmpty && walletPasswordPolicyIssue(value) == null;
}
