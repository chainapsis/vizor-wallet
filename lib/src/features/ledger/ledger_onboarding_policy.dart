import 'ledger_capability.dart';

/// Temporary product limit for user-selected Ledger onboarding accounts.
/// Existing accounts retain the full protocol derivation range.
const kMaxLedgerOnboardingAccountIndex = 100;
const kLedgerOnboardingAccountIndexLabel = 'Ledger account index (0–100)';
const kLedgerOnboardingAccountIndexError =
    'Account index must be between 0 and 100.';

bool isLedgerOnboardingAccountIndexValid(int? index) =>
    index != null && index >= 0 && index <= kMaxLedgerOnboardingAccountIndex;

int? parseLedgerOnboardingAccountIndex(String text) {
  final index = int.tryParse(text);
  return isLedgerOnboardingAccountIndexValid(index) ? index : null;
}

/// Names the account the way the device does, so the two screens agree.
String ledgerViewingKeyApprovalMessage(int accountIndex, String? appVersion) {
  final number = ledgerDeviceAccountNumber(accountIndex, appVersion);
  return number == null
      ? 'Approve sharing your viewing key with Vizor.'
      : 'Approve sharing the viewing key for Account #$number.';
}
