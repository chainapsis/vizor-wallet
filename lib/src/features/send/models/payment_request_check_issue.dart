import '../../../core/l10n/l10n.dart';

/// Why the payment-request card's check ended in a specific sentence.
///
/// The flow state carries the code and the card resolves it with [text] in the
/// locale it is shown in.
///
/// [wrongNetworkAddress] has its own sentence because "Invalid address" reads
/// as a typo, and this is not one: the address is real, it just is not payable
/// from this build. Before validation was network-aware the wallet accepted
/// these and only refused them at proposal time, as an opaque "Bad address:
/// IncorrectNetwork".
///
/// The card is a pre-send consent surface: nothing has been broadcast, it
/// holds an unconsumed proposal, and offers Check again or Edit.
/// [friendlyProposeSendError] is written for a screen that actually sent, so
/// its wording ("Send failed", "Some parts of this transaction were sent")
/// would assert an event that never happened here. Follows the card's
/// status-line convention: one line, no trailing period.
enum PaymentRequestCheckIssue {
  wrongNetworkAddress,
  networkUpgradeHold,
  networkUpgradeScheduleChanged,
  network,
  generic,
  noPayableAmount,
  noActiveAccount;

  String text(AppLocalizations l10n) => switch (this) {
    wrongNetworkAddress => l10n.sendRecipientWrongNetwork,
    networkUpgradeHold => l10n.sendPaymentRequestCheckUpgradeHold,
    networkUpgradeScheduleChanged =>
      l10n.sendPaymentRequestCheckUpgradeScheduleChanged,
    network => l10n.sendPaymentRequestCheckNetwork,
    generic => l10n.sendPaymentRequestCheckGeneric,
    noPayableAmount => l10n.sendPaymentRequestCheckNoAmount,
    noActiveAccount => l10n.sendPaymentRequestCheckNoAccount,
  };
}
