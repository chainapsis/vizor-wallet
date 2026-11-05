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

  String get label => switch (this) {
    SwapIntentStatus.awaitingDeposit => 'Awaiting deposit',
    SwapIntentStatus.awaitingExternalDeposit => 'Awaiting external deposit',
    SwapIntentStatus.depositObserved => 'Deposit observed',
    SwapIntentStatus.processing => 'Processing',
    SwapIntentStatus.providerStatusUnknown => 'Checking status',
    SwapIntentStatus.incompleteDeposit => 'Incomplete deposit',
    SwapIntentStatus.complete => 'Complete',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}
