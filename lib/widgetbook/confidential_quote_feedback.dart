// Widgetbook-only quote feedback states for the confidential prototypes.
/// Presentation only. Provider failures must be classified before reaching UI.
enum SwapQuoteFeedbackKind {
  liquidityUnavailable,
  amountTooLow,
  quoteUnavailable,
  networkUnavailable,
  confidentialUnavailable,
}

extension SwapQuoteFeedbackCopy on SwapQuoteFeedbackKind {
  /// Shown above the primary action while no quote exists.
  String status(bool confidential) => switch (this) {
    SwapQuoteFeedbackKind.liquidityUnavailable =>
      confidential
          ? 'No confidential quote for this amount'
          : 'No quote for this amount',
    SwapQuoteFeedbackKind.amountTooLow => 'Amount below minimum',
    SwapQuoteFeedbackKind.quoteUnavailable => 'Quote unavailable',
    SwapQuoteFeedbackKind.networkUnavailable => 'Unable to connect',
    SwapQuoteFeedbackKind.confidentialUnavailable =>
      'Confidential quotes unavailable',
  };

  bool offersConfidential(bool confidential) =>
      this == SwapQuoteFeedbackKind.liquidityUnavailable && !confidential;

  String recoveryLabel(bool confidential) => offersConfidential(confidential)
      ? 'Get confidential quote'
      : this == SwapQuoteFeedbackKind.amountTooLow
      ? 'Edit amount'
      : 'Try again';
}
