import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_intent.dart';

const defaultSwapSlippageBps = 100;
const swapSlippagePresetBps = <int>[50, 100, 200];
const swapQuoteDifferenceWarningThreshold = 0.05;

enum SwapAmountInputMode { token, fiat }

enum SwapAmountInputSide { pay, receive }

String? swapTokenAmountPrecisionError({
  required SwapAsset asset,
  required String amountText,
}) {
  final text = amountText.trim();
  if (text.isEmpty) return null;
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final fractionalDigits = parts.length == 2 ? parts[1].length : 0;
  if (fractionalDigits <= asset.decimals) return null;
  return '${asset.symbol} supports up to ${asset.decimals} decimal places.';
}

class SwapComposerPreferences {
  const SwapComposerPreferences({
    required this.direction,
    required this.externalAsset,
    this.slippageBps = defaultSwapSlippageBps,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final int slippageBps;
}

class SwapState {
  const SwapState({
    required this.direction,
    required this.amountText,
    required this.receiveAmountText,
    required this.destinationText,
    required this.externalAsset,
    required this.reviewVisible,
    required this.intents,
    this.pendingKeystoneSigningIntent,
    this.quoteMode = SwapQuoteMode.exactInput,
    this.amountInputMode = SwapAmountInputMode.token,
    this.receiveAmountInputMode = SwapAmountInputMode.token,
    this.amountFiatText = '',
    this.receiveFiatText = '',
    this.slippageBps = defaultSwapSlippageBps,
    this.supportedExternalAssets = swapExternalAssets,
    this.indicativeExternalPerZec = const {},
    this.indicativeUsdPrices = const {},
    this.pricingLoading = false,
    this.reviewQuote,
    this.reviewAddressPlan,
    this.reviewAccountUuid,
    this.quoteLoading = false,
    this.quoteExpired = false,
    this.quoteError,
    this.statusRefreshing = false,
    this.statusError,
    this.startSubmitting = false,
    this.maxAmountLoading = false,
    this.maxAmountError,
    this.depositTxHashText = '',
    this.depositSubmitting = false,
    this.selectedIntentId,
    this.payMode = false,
  });

  final SwapDirection direction;
  final String amountText;
  final String receiveAmountText;
  final String destinationText;
  final SwapAsset externalAsset;
  final bool reviewVisible;
  final List<SwapIntent> intents;
  final SwapIntent? pendingKeystoneSigningIntent;
  final SwapQuoteMode quoteMode;
  final SwapAmountInputMode amountInputMode;
  final SwapAmountInputMode receiveAmountInputMode;
  final String amountFiatText;
  final String receiveFiatText;
  final int slippageBps;
  final List<SwapAsset> supportedExternalAssets;
  final Map<SwapAsset, double> indicativeExternalPerZec;
  final Map<SwapAsset, double> indicativeUsdPrices;

  /// True only while the supported-asset/indicative-price snapshot is being
  /// loaded or refreshed. Live review quote submission uses [quoteLoading].
  final bool pricingLoading;
  final SwapQuote? reviewQuote;
  final SwapAddressPlan? reviewAddressPlan;
  final String? reviewAccountUuid;
  final bool quoteLoading;
  final bool quoteExpired;
  final String? quoteError;
  final bool statusRefreshing;
  final String? statusError;
  final bool startSubmitting;
  final bool maxAmountLoading;
  final String? maxAmountError;
  final String depositTxHashText;
  final bool depositSubmitting;
  final String? selectedIntentId;
  final bool payMode;

  SwapIntent? get selectedIntentOrNull {
    final selectedId = selectedIntentId;
    if (selectedId != null) {
      for (final intent in intents) {
        if (intent.id == selectedId) return intent;
      }
    }
    return intents.isEmpty ? null : intents.first;
  }

  SwapIntent get selectedIntent {
    final intent = selectedIntentOrNull;
    if (intent == null) {
      throw StateError('No selected swap intent');
    }
    return intent;
  }

  String get walletZecPlaceholderAddress => direction.sendsZec
      ? 'u1wallet-refund-placeholder'
      : 'u1wallet-shielded-placeholder';

  double? get sellAmount {
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) return null;
    return amount;
  }

  double? get receiveAmount {
    final amount = double.tryParse(receiveAmountText);
    if (amount == null || amount <= 0) return null;
    return amount;
  }

  double? get quoteAmount =>
      quoteMode.usesInputAmount ? sellAmount : receiveAmount;

  String get quoteAmountText =>
      quoteMode.usesInputAmount ? amountText.trim() : receiveAmountText.trim();

  String? get quoteAmountPrecisionError => swapTokenAmountPrecisionError(
    asset: quoteMode.usesInputAmount
        ? direction.fromAsset(externalAsset)
        : direction.toAsset(externalAsset),
    amountText: quoteAmountText,
  );

  SwapAddressPlan? get addressPlan => reviewAddressPlan ?? draftAddressPlan;

  SwapAddressPlan? get draftAddressPlan {
    if (destinationText.trim().isEmpty) return null;
    return SwapAddressPlan.fromUserInput(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: destinationText,
      walletZecAddress: walletZecPlaceholderAddress,
    );
  }

  String get destinationFieldLabel => direction.sendsZec
      ? 'Destination'
      : '${externalAsset.symbol} refund address';

  // The address belongs to a chain, not the token (you don't have a "USDC
  // address" — you have an Ethereum address that holds USDC), so name the
  // chain. Leading with it also keeps the relevant part visible in the narrow
  // modal field (the old "Refund address on the ET…" cut off the chain).
  String get destinationFieldHint => direction.sendsZec
      ? '${externalAsset.chainLabel} address or account'
      : '${externalAsset.chainLabel} address';

  /// Best-effort format check of [destinationText] against the external asset's
  /// chain. Returns null when empty, when the chain has no validator, or when
  /// the address looks valid; otherwise a short reason. Used as a hard gate on
  /// the swap review path so a malformed recipient/refund address cannot be
  /// committed into a 1Click quote.
  String? get destinationAddressFormatError {
    final trimmed = destinationText.trim();
    if (trimmed.isEmpty) return null;
    final network = AddressBookNetwork.tryFromChainTicker(
      externalAsset.chainTicker,
    );
    if (network == null) return null;
    return addressFormatIssue(network, trimmed);
  }

  bool get canReviewQuote =>
      quoteAmount != null &&
      quoteAmountPrecisionError == null &&
      draftAddressPlan != null &&
      destinationAddressFormatError == null &&
      !quoteLoading;

  bool get canSubmitDepositTx =>
      depositTxHashText.trim().isNotEmpty && !depositSubmitting;

  SwapQuote? get quote => reviewQuote ?? draftQuote;

  SwapQuote? get draftQuote {
    final amount = quoteAmount;
    if (amount == null) return null;
    return SwapQuote.estimate(
      direction: direction,
      externalAsset: externalAsset,
      mode: quoteMode,
      amount: amount,
      externalPerZec: indicativeExternalPerZec[externalAsset],
      slippageBps: slippageBps,
    );
  }

  String? get reviewAmountDifferenceWarning {
    final liveQuote = reviewQuote;
    final estimate = draftQuote;
    if (liveQuote == null || estimate == null) return null;
    if (liveQuote.direction != direction ||
        liveQuote.externalAsset != externalAsset ||
        !quoteMode.usesInputAmount) {
      return null;
    }
    if (estimate.sellAmount > 0) {
      final sellDelta =
          (liveQuote.sellAmount - estimate.sellAmount) / estimate.sellAmount;
      if (sellDelta.abs() >= swapQuoteDifferenceWarningThreshold) {
        final sellAsset = estimate.sellAsset;
        final liveText = sellAsset.formatAmount(liveQuote.sellAmount);
        final estimateText = sellAsset.formatAmount(estimate.sellAmount);
        return 'Live quote uses $liveText ${sellAsset.symbol} instead of $estimateText ${sellAsset.symbol}. Check the guaranteed minimum before you continue.';
      }
    }
    if (estimate.receiveAmount <= 0) return null;
    final delta =
        (liveQuote.receiveAmount - estimate.receiveAmount) /
        estimate.receiveAmount;
    final absoluteDelta = delta.abs();
    if (absoluteDelta < swapQuoteDifferenceWarningThreshold) return null;
    final percent = (absoluteDelta * 100).toStringAsFixed(
      absoluteDelta >= 0.1 ? 0 : 1,
    );
    final directionLabel = delta < 0 ? 'lower' : 'higher';
    return 'Live quote is $percent% $directionLabel than the earlier estimate. Check the guaranteed minimum before you continue.';
  }

  SwapState copyWith({
    SwapDirection? direction,
    String? amountText,
    String? receiveAmountText,
    String? destinationText,
    SwapAsset? externalAsset,
    bool? reviewVisible,
    List<SwapIntent>? intents,
    SwapIntent? pendingKeystoneSigningIntent,
    SwapQuoteMode? quoteMode,
    SwapAmountInputMode? amountInputMode,
    SwapAmountInputMode? receiveAmountInputMode,
    String? amountFiatText,
    String? receiveFiatText,
    int? slippageBps,
    List<SwapAsset>? supportedExternalAssets,
    Map<SwapAsset, double>? indicativeExternalPerZec,
    Map<SwapAsset, double>? indicativeUsdPrices,
    bool? pricingLoading,
    SwapQuote? reviewQuote,
    SwapAddressPlan? reviewAddressPlan,
    String? reviewAccountUuid,
    bool? quoteLoading,
    bool? quoteExpired,
    String? quoteError,
    bool? statusRefreshing,
    String? statusError,
    bool? startSubmitting,
    bool? maxAmountLoading,
    String? maxAmountError,
    String? depositTxHashText,
    bool? depositSubmitting,
    String? selectedIntentId,
    bool? payMode,
    bool clearReview = false,
    bool clearQuoteError = false,
    bool clearStatusError = false,
    bool clearMaxAmountError = false,
    bool clearSelectedIntent = false,
    bool clearPendingKeystoneSigningIntent = false,
  }) {
    return SwapState(
      direction: direction ?? this.direction,
      amountText: amountText ?? this.amountText,
      receiveAmountText: receiveAmountText ?? this.receiveAmountText,
      destinationText: destinationText ?? this.destinationText,
      externalAsset: externalAsset ?? this.externalAsset,
      reviewVisible: reviewVisible ?? this.reviewVisible,
      intents: intents ?? this.intents,
      pendingKeystoneSigningIntent: clearPendingKeystoneSigningIntent
          ? null
          : pendingKeystoneSigningIntent ?? this.pendingKeystoneSigningIntent,
      quoteMode: quoteMode ?? this.quoteMode,
      amountInputMode: amountInputMode ?? this.amountInputMode,
      receiveAmountInputMode:
          receiveAmountInputMode ?? this.receiveAmountInputMode,
      amountFiatText: amountFiatText ?? this.amountFiatText,
      receiveFiatText: receiveFiatText ?? this.receiveFiatText,
      slippageBps: slippageBps ?? this.slippageBps,
      supportedExternalAssets:
          supportedExternalAssets ?? this.supportedExternalAssets,
      indicativeExternalPerZec:
          indicativeExternalPerZec ?? this.indicativeExternalPerZec,
      indicativeUsdPrices: indicativeUsdPrices ?? this.indicativeUsdPrices,
      pricingLoading: pricingLoading ?? this.pricingLoading,
      reviewQuote: clearReview ? null : reviewQuote ?? this.reviewQuote,
      reviewAddressPlan: clearReview
          ? null
          : reviewAddressPlan ?? this.reviewAddressPlan,
      reviewAccountUuid: clearReview
          ? null
          : reviewAccountUuid ?? this.reviewAccountUuid,
      quoteLoading: quoteLoading ?? this.quoteLoading,
      quoteExpired: clearReview ? false : quoteExpired ?? this.quoteExpired,
      quoteError: clearQuoteError ? null : quoteError ?? this.quoteError,
      statusRefreshing: statusRefreshing ?? this.statusRefreshing,
      statusError: clearStatusError ? null : statusError ?? this.statusError,
      startSubmitting: startSubmitting ?? this.startSubmitting,
      maxAmountLoading: maxAmountLoading ?? this.maxAmountLoading,
      maxAmountError: clearMaxAmountError
          ? null
          : maxAmountError ?? this.maxAmountError,
      depositTxHashText: depositTxHashText ?? this.depositTxHashText,
      depositSubmitting: depositSubmitting ?? this.depositSubmitting,
      selectedIntentId: clearSelectedIntent
          ? null
          : selectedIntentId ?? this.selectedIntentId,
      payMode: payMode ?? this.payMode,
    );
  }
}
