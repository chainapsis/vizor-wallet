import 'swap_asset.dart';
import 'swap_direction.dart';
import 'swap_fiat_value_basis.dart';

class SwapQuoteRequest {
  const SwapQuoteRequest({
    required this.direction,
    required this.externalAsset,
    double? amount,
    double? sellAmount,
    required this.destination,
    this.mode = SwapQuoteMode.exactInput,
    String? amountText,
    String? sellAmountText,
    this.refundAddress,
    this.dryRun = false,
    this.slippageBps,
    this.deadline,
  }) : assert(
         amount != null || sellAmount != null,
         'SwapQuoteRequest amount is required',
       ),
       amount = amount ?? sellAmount ?? 0,
       amountText = amountText ?? sellAmountText;

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final SwapQuoteMode mode;
  final double amount;
  final String? amountText;
  final String destination;
  final String? refundAddress;
  final bool dryRun;
  final int? slippageBps;
  final Duration? deadline;

  SwapAsset get sellAsset => direction.fromAsset(externalAsset);
  SwapAsset get receiveAsset => direction.toAsset(externalAsset);
  SwapAsset get amountAsset => mode.usesInputAmount ? sellAsset : receiveAsset;

  double get sellAmount {
    if (!mode.usesInputAmount) {
      throw StateError('Exact-output quote requests do not carry sellAmount');
    }
    return amount;
  }

  String? get sellAmountText => mode.usesInputAmount ? amountText : null;
}

class SwapDepositInstruction {
  const SwapDepositInstruction({
    required this.asset,
    required this.address,
    required this.expiresInLabel,
    required this.reuseWarning,
    this.memo,
    this.deadline,
  });

  final SwapAsset asset;
  final String address;
  final String expiresInLabel;
  final String reuseWarning;
  final String? memo;
  final DateTime? deadline;
}

class SwapProviderRefundInfo {
  const SwapProviderRefundInfo({
    this.minimumDepositText,
    this.refundFeeText,
    this.depositedAmountText,
    this.refundedAmountText,
    this.refundReason,
  });

  final String? minimumDepositText;
  final String? refundFeeText;
  final String? depositedAmountText;
  final String? refundedAmountText;
  final String? refundReason;

  bool get hasAny =>
      minimumDepositText != null ||
      refundFeeText != null ||
      depositedAmountText != null ||
      refundedAmountText != null ||
      refundReason != null;

  SwapProviderRefundInfo merge(SwapProviderRefundInfo? other) {
    if (other == null) return this;
    return SwapProviderRefundInfo(
      minimumDepositText: other.minimumDepositText ?? minimumDepositText,
      refundFeeText: other.refundFeeText ?? refundFeeText,
      depositedAmountText: other.depositedAmountText ?? depositedAmountText,
      refundedAmountText: other.refundedAmountText ?? refundedAmountText,
      refundReason: other.refundReason ?? refundReason,
    );
  }
}

class SwapQuote {
  const SwapQuote({
    required this.direction,
    required this.sellAsset,
    required this.receiveAsset,
    required this.externalAsset,
    this.mode = SwapQuoteMode.exactInput,
    required this.sellAmount,
    required this.receiveAmount,
    required this.minimumReceiveAmount,
    required this.providerLabel,
    required this.feeLabel,
    this.totalFeesText,
    required this.expiryLabel,
    required this.depositInstruction,
    this.quoteExpiresAt,
    this.providerQuoteId,
    this.sellAmountBaseUnits,
    this.sellAmountTextOverride,
    this.receiveEstimateTextOverride,
    this.minimumReceiveTextOverride,
    this.slippageToleranceTextOverride,
    this.rateTextOverride,
    this.providerRefundInfo,
    this.fiatValueBasis,
  });

  factory SwapQuote.estimate({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    double? amount,
    double? sellAmount,
    SwapQuoteMode mode = SwapQuoteMode.exactInput,
    String providerLabel = 'NEAR Intents',
    String expiryLabel = '07:12',
    DateTime? quoteExpiresAt,
    DateTime? depositDeadline,
    double? externalPerZec,
    int slippageBps = 50,
  }) {
    assert(externalAsset.name != 'zec');
    final quoteAmount = amount ?? sellAmount;
    if (quoteAmount == null) {
      throw ArgumentError('SwapQuote.estimate amount is required');
    }
    final sellAsset = direction.fromAsset(externalAsset);
    final receiveAsset = direction.toAsset(externalAsset);
    final rate = externalPerZec ?? externalAsset.fallbackExternalPerZec;
    final estimatedSellAmount = switch (mode) {
      SwapQuoteMode.exactInput || SwapQuoteMode.flexInput => quoteAmount,
      SwapQuoteMode.exactOutput =>
        direction.sendsZec ? quoteAmount / rate : quoteAmount * rate,
    };
    final receiveAmount = switch (mode) {
      SwapQuoteMode.exactInput || SwapQuoteMode.flexInput =>
        direction.sendsZec ? quoteAmount * rate : quoteAmount / rate,
      SwapQuoteMode.exactOutput => quoteAmount,
    };
    final rateText = direction.sendsZec
        ? '1 ZEC = ${rate.toStringAsFixed(2)} ${externalAsset.symbol}'
        : '1 ${externalAsset.symbol} = ${(1 / rate).toStringAsFixed(4)} ZEC';
    return SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      mode: mode,
      sellAmount: estimatedSellAmount,
      receiveAmount: receiveAmount,
      minimumReceiveAmount: receiveAmount * (1 - slippageBps / 10000),
      providerLabel: providerLabel,
      feeLabel: 'Included in shown rate',
      expiryLabel: expiryLabel,
      quoteExpiresAt: quoteExpiresAt,
      depositInstruction: SwapDepositInstruction(
        asset: sellAsset,
        address:
            'one-time-${sellAsset.symbol.toLowerCase()}-deposit-placeholder',
        expiresInLabel: expiryLabel,
        reuseWarning: 'Do not reuse this address',
        deadline: depositDeadline,
      ),
      rateTextOverride: rateText,
    );
  }

  final SwapDirection direction;
  final SwapAsset sellAsset;
  final SwapAsset receiveAsset;
  final SwapAsset externalAsset;
  final SwapQuoteMode mode;
  final double sellAmount;
  final double receiveAmount;
  final double minimumReceiveAmount;
  final String providerLabel;
  final String feeLabel;
  final String? totalFeesText;
  final String expiryLabel;
  final DateTime? quoteExpiresAt;
  final SwapDepositInstruction depositInstruction;
  final String? providerQuoteId;
  final BigInt? sellAmountBaseUnits;
  final String? sellAmountTextOverride;
  final String? receiveEstimateTextOverride;
  final String? minimumReceiveTextOverride;
  final String? slippageToleranceTextOverride;
  final String? rateTextOverride;
  final SwapProviderRefundInfo? providerRefundInfo;
  final SwapFiatValueBasis? fiatValueBasis;

  String get pairText => '${sellAsset.symbol} -> ${receiveAsset.symbol}';
  String get sellAmountText =>
      sellAmountTextOverride ??
      '${mode == SwapQuoteMode.exactOutput ? sellAsset.formatAmountUp(sellAmount) : sellAsset.formatAmount(sellAmount)} ${sellAsset.symbol}';
  String get receiveEstimateText =>
      receiveEstimateTextOverride ??
      '${mode.usesInputAmount ? receiveAsset.formatAmountDown(receiveAmount) : receiveAsset.formatAmount(receiveAmount)} ${receiveAsset.symbol}';
  String get minimumReceiveText =>
      minimumReceiveTextOverride ??
      '${receiveAsset.formatAmountDown(minimumReceiveAmount)} ${receiveAsset.symbol}';

  String get slippageToleranceText {
    final override = slippageToleranceTextOverride;
    if (override != null) {
      return override;
    }
    final percent = receiveProtectionPercent;
    final sellBuffer = sellAmount * percent / 100;
    return '${formatSwapProtectionAmount(sellAsset, sellBuffer)} '
        '${sellAsset.symbol} (${formatSwapProtectionPercent(percent)})';
  }

  double get receiveProtectionPercent {
    if (receiveAmount <= 0 || !receiveAmount.isFinite) return 0;
    final buffer = receiveAmount - minimumReceiveAmount;
    return buffer <= 0 || !buffer.isFinite ? 0 : buffer / receiveAmount * 100;
  }

  /// Receive-side counterpart to [slippageToleranceText]: how much of the
  /// asset being received is protected by the configured slippage (the gap
  /// between the quoted and the guaranteed-minimum receive). Figma's review
  /// card lists this as a dedicated "Price protection" row.
  String get priceProtectionText {
    final percent = receiveProtectionPercent;
    final buffer = receiveAmount - minimumReceiveAmount;
    final amount = buffer <= 0 || !buffer.isFinite ? 0.0 : buffer;
    return '${formatSwapProtectionAmount(receiveAsset, amount)} '
        '${receiveAsset.symbol} (${formatSwapProtectionPercent(percent)})';
  }

  String get rateText {
    final override = rateTextOverride;
    if (override != null) {
      return override;
    }
    final rate = externalAsset.fallbackExternalPerZec;
    if (direction.sendsZec) {
      return '1 ZEC = ${rate.toStringAsFixed(2)} ${externalAsset.symbol}';
    }
    return '1 ${externalAsset.symbol} = ${(1 / rate).toStringAsFixed(4)} ZEC';
  }
}
