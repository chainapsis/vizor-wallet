import '../../../../l10n/app_localizations.dart';

enum SwapIntentStatus {
  awaitingDeposit,
  awaitingExternalDeposit,
  depositObserved,
  processing,
  providerStatusUnknown,
  incompleteDeposit,
  complete,
  refunded,
  expired,
  failed,
}

extension SwapIntentStatusLabels on SwapIntentStatus {
  bool get isTerminal => switch (this) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => true,
    _ => false,
  };

  String label(AppLocalizations l10n) => switch (this) {
    SwapIntentStatus.awaitingDeposit => l10n.swapStatusAwaitingDeposit,
    SwapIntentStatus.awaitingExternalDeposit =>
      l10n.swapStatusAwaitingExternalDeposit,
    SwapIntentStatus.depositObserved => l10n.swapStatusDepositObserved,
    SwapIntentStatus.processing => l10n.swapStatusProcessing,
    SwapIntentStatus.providerStatusUnknown => l10n.swapStatusChecking,
    SwapIntentStatus.incompleteDeposit => l10n.swapStatusIncompleteDeposit,
    SwapIntentStatus.complete => l10n.swapStatusComplete,
    SwapIntentStatus.refunded => l10n.swapStatusRefunded,
    SwapIntentStatus.expired => l10n.swapStatusExpired,
    SwapIntentStatus.failed => l10n.swapStatusFailed,
  };
}
