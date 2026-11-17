import '../../../core/l10n/l10n.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_intent.dart';
import 'swap_message.dart';

const defaultSwapSlippageBps = 200;
const swapSlippagePresetBps = <int>[50, 100, 200];
const swapQuoteDifferenceWarningThreshold = 0.05;

enum SwapAmountInputMode { token, fiat }

enum SwapAmountInputSide { pay, receive }

bool swapTokenAmountExceedsPrecision({
  required SwapAsset asset,
  required String amountText,
}) {
  final text = amountText.trim();
  if (text.isEmpty) return false;
  final parts = text.split('.');
  if (parts.length > 2) return false;
  final fractionalDigits = parts.length == 2 ? parts[1].length : 0;
  return fractionalDigits > asset.decimals;
}

String? swapTokenAmountPrecisionError(
  AppLocalizations l10n, {
  required SwapAsset asset,
  required String amountText,
}) {
  if (!swapTokenAmountExceedsPrecision(asset: asset, amountText: amountText)) {
    return null;
  }
  return l10n.swapActivityStateDecimalPlaces(asset.symbol, asset.decimals);
}

class SwapComposerPreferences {
  const SwapComposerPreferences({
    required this.direction,
    required this.externalAsset,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
}

/// The quote settings a Swap or Pay composer session keeps: slippage and the
/// confidential route, each chosen per swap and never saved.
class SwapQuoteSettingsSessions {
  const SwapQuoteSettingsSessions({
    this.swapBps = defaultSwapSlippageBps,
    this.payBps = defaultSwapSlippageBps,
    this.swapConfidential = false,
    this.payConfidential = false,
  });

  final int swapBps;
  final int payBps;
  final bool swapConfidential;
  final bool payConfidential;

  int slippageFor({required bool payMode}) => payMode ? payBps : swapBps;

  bool confidentialFor({required bool payMode}) =>
      payMode ? payConfidential : swapConfidential;

  SwapQuoteSettingsSessions update({
    required bool payMode,
    int? slippageBps,
    bool? confidential,
  }) {
    return payMode
        ? SwapQuoteSettingsSessions(
            swapBps: swapBps,
            payBps: slippageBps ?? payBps,
            swapConfidential: swapConfidential,
            payConfidential: confidential ?? payConfidential,
          )
        : SwapQuoteSettingsSessions(
            swapBps: slippageBps ?? swapBps,
            payBps: payBps,
            swapConfidential: confidential ?? swapConfidential,
            payConfidential: payConfidential,
          );
  }

  SwapQuoteSettingsSessions reset({required bool payMode}) => update(
    payMode: payMode,
    slippageBps: defaultSwapSlippageBps,
    confidential: false,
  );
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
    this.pendingHardwareSigningIntent,
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
    this.supportedAssetsError,
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
    this.userExternalContactId,
    this.confidential = false,
    this.quoteNoLiquidity = false,
  });

  final SwapDirection direction;
  final String amountText;
  final String receiveAmountText;
  final String destinationText;
  final SwapAsset externalAsset;
  final bool reviewVisible;
  final List<SwapIntent> intents;
  final SwapIntent? pendingHardwareSigningIntent;
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
  final SwapMessage? supportedAssetsError;
  final SwapQuote? reviewQuote;
  final SwapAddressPlan? reviewAddressPlan;
  final String? reviewAccountUuid;
  final bool quoteLoading;
  final bool quoteExpired;
  final SwapMessage? quoteError;
  final bool statusRefreshing;
  final SwapMessage? statusError;
  final bool startSubmitting;
  final bool maxAmountLoading;
  final SwapMessage? maxAmountError;
  final String depositTxHashText;
  final bool depositSubmitting;
  final String? selectedIntentId;
  final bool payMode;
  final String? userExternalContactId;

  /// Quote mode for the next review. Session-only: it is not saved with the
  /// composer preferences.
  final bool confidential;

  /// The last quote failed because the selected mode had no liquidity.
  /// Cleared with [quoteError].
  final bool quoteNoLiquidity;

  /// Standard had no quote, so the primary action offers the confidential
  /// route instead.
  bool get offersConfidentialQuote =>
      quoteError != null && quoteNoLiquidity && !confidential;

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

  SwapAsset get _quoteAmountAsset => quoteMode.usesInputAmount
      ? direction.fromAsset(externalAsset)
      : direction.toAsset(externalAsset);

  bool get hasQuoteAmountPrecisionError => swapTokenAmountExceedsPrecision(
    asset: _quoteAmountAsset,
    amountText: quoteAmountText,
  );

  String? quoteAmountPrecisionError(AppLocalizations l10n) =>
      swapTokenAmountPrecisionError(
        l10n,
        asset: _quoteAmountAsset,
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

  String destinationFieldLabel(AppLocalizations l10n) => direction.sendsZec
      ? l10n.swapActivityStateDestination
      : l10n.commonSymbolRefundAddress(externalAsset.symbol);

  // The address belongs to a chain, not the token (you don't have a "USDC
  // address" — you have an Ethereum address that holds USDC), so name the
  // chain. Leading with it also keeps the relevant part visible in the narrow
  // modal field (the old "Refund address on the ET…" cut off the chain).
  String destinationFieldHint(AppLocalizations l10n) => direction.sendsZec
      ? l10n.swapActivityStateAddressOrAccountHint(externalAsset.chainLabel)
      : l10n.commonAddressForChain(externalAsset.chainLabel);

  /// Best-effort format check of [destinationText] against the external asset's
  /// chain. Returns null when empty, when the chain has no validator, or when
  /// the address looks valid; otherwise a short reason. Used as a hard gate on
  /// the swap review path so a malformed recipient/refund address cannot be
  /// committed into a 1Click quote.
  AddressFormatFinding? get destinationAddressFormatIssue {
    final trimmed = destinationText.trim();
    if (trimmed.isEmpty) return null;
    final network = AddressBookNetwork.tryFromChainTicker(
      externalAsset.chainTicker,
    );
    if (network == null) return null;
    return addressFormatIssue(network, trimmed);
  }

  bool get externalAssetIsSupported {
    for (final candidate in supportedExternalAssets) {
      if (candidate == externalAsset ||
          candidate.hasSameMarketAs(externalAsset)) {
        return true;
      }
    }
    return false;
  }

  String? externalAssetSupportError(AppLocalizations l10n) {
    if (pricingLoading) return null;
    final loadError = supportedAssetsError;
    if (loadError != null) return loadError.text(l10n);
    if (externalAssetIsSupported) return null;
    return l10n.swapActivityStateAssetUnsupported(
      externalAsset.symbol,
      externalAsset.chainLabel,
    );
  }

  /// Whether the selected external asset can carry a quote. A failed token-list
  /// load keeps the last known [supportedExternalAssets], so
  /// [externalAssetIsSupported] alone still reads true while
  /// [supportedAssetsError] is set — every surface that gates on asset support
  /// must use this, or it offers an action the review path will refuse.
  bool get externalAssetIsAvailable =>
      externalAssetIsSupported && supportedAssetsError == null;

  bool get canReviewQuote =>
      quoteAmount != null &&
      !hasQuoteAmountPrecisionError &&
      draftAddressPlan != null &&
      destinationAddressFormatIssue == null &&
      externalAssetIsAvailable &&
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

  String? reviewAmountDifferenceWarning(AppLocalizations l10n) {
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
        return l10n.swapActivityStateQuoteUsesDifferentSell(
          liveText,
          estimateText,
          sellAsset.symbol,
        );
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
    return delta < 0
        ? l10n.swapActivityStateQuoteLower(percent)
        : l10n.swapActivityStateQuoteHigher(percent);
  }

  SwapState copyWith({
    SwapDirection? direction,
    String? amountText,
    String? receiveAmountText,
    String? destinationText,
    SwapAsset? externalAsset,
    bool? reviewVisible,
    List<SwapIntent>? intents,
    SwapIntent? pendingHardwareSigningIntent,
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
    SwapMessage? supportedAssetsError,
    SwapQuote? reviewQuote,
    SwapAddressPlan? reviewAddressPlan,
    String? reviewAccountUuid,
    bool? quoteLoading,
    bool? quoteExpired,
    SwapMessage? quoteError,
    bool? statusRefreshing,
    SwapMessage? statusError,
    bool? startSubmitting,
    bool? maxAmountLoading,
    SwapMessage? maxAmountError,
    String? depositTxHashText,
    bool? depositSubmitting,
    String? selectedIntentId,
    bool? payMode,
    String? userExternalContactId,
    bool? confidential,
    bool? quoteNoLiquidity,
    bool clearReview = false,
    bool clearQuoteError = false,
    bool clearSupportedAssetsError = false,
    bool clearStatusError = false,
    bool clearMaxAmountError = false,
    bool clearSelectedIntent = false,
    bool clearPendingHardwareSigningIntent = false,
    bool clearUserExternalContactId = false,
  }) {
    return SwapState(
      direction: direction ?? this.direction,
      amountText: amountText ?? this.amountText,
      receiveAmountText: receiveAmountText ?? this.receiveAmountText,
      destinationText: destinationText ?? this.destinationText,
      externalAsset: externalAsset ?? this.externalAsset,
      reviewVisible: reviewVisible ?? this.reviewVisible,
      intents: intents ?? this.intents,
      pendingHardwareSigningIntent: clearPendingHardwareSigningIntent
          ? null
          : pendingHardwareSigningIntent ?? this.pendingHardwareSigningIntent,
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
      supportedAssetsError: clearSupportedAssetsError
          ? null
          : supportedAssetsError ?? this.supportedAssetsError,
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
      userExternalContactId: clearUserExternalContactId
          ? null
          : userExternalContactId ?? this.userExternalContactId,
      confidential: confidential ?? this.confidential,
      quoteNoLiquidity: clearQuoteError
          ? false
          : quoteNoLiquidity ?? this.quoteNoLiquidity,
    );
  }
}
