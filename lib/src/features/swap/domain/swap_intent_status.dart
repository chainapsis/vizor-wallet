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
}

/// The next step of a swap, stored by name in a swap record's `nextAction`.
/// No screen shows it, so it has no copy.
enum SwapNextAction {
  sendDeposit,
  depositDetected,
  processing,
  unrecognizedStatus,
  incompleteDeposit,
  complete,
  refundSent,
  startFreshQuote,
  failed,
  signLedgerDeposit,
  signKeystoneDeposit;

  /// The value to keep for a stored `nextAction`: a name, or the English an
  /// earlier build wrote, becomes the name; other text stays as stored.
  static String normalizeStored(String stored) {
    for (final action in values) {
      if (action.name == stored) return stored;
    }
    if (_legacySendDeposit.hasMatch(stored)) return sendDeposit.name;
    return _legacyNextActions[stored]?.name ?? stored;
  }
}

final _legacySendDeposit = RegExp(
  r'^Send .+ to the one-time deposit address$', // l10n-ignore: legacy persisted text
);

const _legacyNextActions = <String, SwapNextAction>{
  'Deposit detected': // l10n-ignore: legacy persisted text
      SwapNextAction.depositDetected,
  'Swap is processing': // l10n-ignore: legacy persisted text
      SwapNextAction.processing,
  'Provider returned a status this wallet does not recognize': // l10n-ignore: legacy persisted text
      SwapNextAction.unrecognizedStatus,
  'Deposit is below the quoted amount': // l10n-ignore: legacy persisted text
      SwapNextAction.incompleteDeposit,
  'Swap complete': // l10n-ignore: legacy persisted text
      SwapNextAction.complete,
  'Refund sent to your refund address': // l10n-ignore: legacy persisted text
      SwapNextAction.refundSent,
  'Start a fresh quote': // l10n-ignore: legacy persisted text
      SwapNextAction.startFreshQuote,
  'Swap failed': // l10n-ignore: legacy persisted text
      SwapNextAction.failed,
  'Sign and send the ZEC deposit with Ledger.': // l10n-ignore: legacy persisted text
      SwapNextAction.signLedgerDeposit,
  'Sign and send the ZEC deposit with Keystone.': // l10n-ignore: legacy persisted text
      SwapNextAction.signKeystoneDeposit,
};
