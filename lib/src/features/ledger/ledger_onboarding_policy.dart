import '../../core/l10n/l10n.dart' show AppLocalizations;
import 'ledger_capability.dart';

/// Temporary product limit for user-selected Ledger onboarding accounts.
/// Existing accounts retain the full protocol derivation range.
const kMaxLedgerOnboardingAccountIndex = 100;

/// Thrown (not shown) when the index is out of range; screens show
/// `ledgerAccountIndexOutOfRange` instead.
const kLedgerOnboardingAccountIndexError =
    'Account index must be between 0 and 100.'; // l10n-ignore: exception text

bool isLedgerOnboardingAccountIndexValid(int? index) =>
    index != null && index >= 0 && index <= kMaxLedgerOnboardingAccountIndex;

int? parseLedgerOnboardingAccountIndex(String text) {
  final index = int.tryParse(text);
  return isLedgerOnboardingAccountIndexValid(index) ? index : null;
}

/// Names the account the way the device does, so the two screens agree.
String ledgerViewingKeyApprovalMessage(
  AppLocalizations l10n,
  int accountIndex,
  String? appVersion,
) {
  final number = ledgerDeviceAccountNumber(accountIndex, appVersion);
  return number == null
      ? l10n.ledgerApproveShareViewingKey
      : l10n.ledgerApproveShareViewingKeyForAccount('$number');
}
