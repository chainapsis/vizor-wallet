import 'swap_asset.dart';
import 'swap_direction.dart';
import 'swap_fiat_value_basis.dart';
import 'swap_intent_status.dart';
import 'swap_quote.dart';

class SwapIntentSnapshot {
  const SwapIntentSnapshot({
    required this.id,
    required this.providerLabel,
    required this.pairText,
    required this.sellAmountText,
    required this.receiveEstimateText,
    required this.status,
    required this.nextAction,
    required this.depositInstruction,
    this.swapFeeText,
    this.totalFeesText,
    this.realisedSlippageText,
    this.slippageToleranceText,
    this.minimumReceiveText,
    this.providerStatusRaw,
    this.nearIntentHash,
    this.originChainTxHash,
    this.destinationChainTxHash,
    this.providerRefundInfo,
    this.sellAmountBaseUnits,
    this.fiatValueBasis,
  });

  factory SwapIntentSnapshot.fromQuote(
    SwapQuote quote, {
    String id = 'swap-new',
  }) {
    final status = quote.direction.sendsZec
        ? SwapIntentStatus.awaitingDeposit
        : SwapIntentStatus.awaitingExternalDeposit;
    return SwapIntentSnapshot(
      id: id,
      providerLabel: quote.providerLabel,
      pairText: quote.pairText,
      sellAmountText: quote.sellAmountText,
      receiveEstimateText: quote.receiveEstimateText,
      status: status,
      nextAction:
          'Send ${quote.sellAsset.symbol} to the one-time deposit address',
      depositInstruction: quote.depositInstruction,
      sellAmountBaseUnits: quote.sellAmountBaseUnits,
      swapFeeText: quote.feeLabel,
      totalFeesText: quote.totalFeesText,
      slippageToleranceText: quote.slippageToleranceText,
      minimumReceiveText: quote.minimumReceiveText,
      providerRefundInfo: quote.providerRefundInfo,
      fiatValueBasis: quote.fiatValueBasis,
    );
  }

  final String id;
  final String providerLabel;
  final String pairText;
  final String sellAmountText;
  final String receiveEstimateText;
  final SwapIntentStatus status;
  final String nextAction;
  final SwapDepositInstruction depositInstruction;
  final String? swapFeeText;
  final String? totalFeesText;
  final String? realisedSlippageText;
  final String? slippageToleranceText;
  final String? minimumReceiveText;
  final String? providerStatusRaw;
  final String? nearIntentHash;
  final String? originChainTxHash;
  final String? destinationChainTxHash;
  final SwapProviderRefundInfo? providerRefundInfo;
  final BigInt? sellAmountBaseUnits;
  final SwapFiatValueBasis? fiatValueBasis;
}

class SwapPricingSnapshot {
  const SwapPricingSnapshot({required this.usdPrices});

  final Map<SwapAsset, double> usdPrices;

  List<SwapAsset> get supportedExternalAssets {
    final zecPrice = usdPrices[SwapAsset.zec];
    if (zecPrice == null || zecPrice <= 0) return const [];
    return sortSwapAssetsForSelection([
      for (final entry in usdPrices.entries)
        if (entry.key != SwapAsset.zec && entry.value > 0) entry.key,
    ]);
  }

  Map<SwapAsset, double> get externalPerZec {
    final zecPrice = usdPrices[SwapAsset.zec];
    if (zecPrice == null || zecPrice <= 0) return const {};
    return {
      for (final entry in usdPrices.entries)
        if (entry.key != SwapAsset.zec && entry.value > 0)
          entry.key: zecPrice / entry.value,
    };
  }
}

abstract interface class SwapProvider {
  String get providerLabel;

  Future<List<SwapAsset>> listSupportedExternalAssets();

  Future<SwapQuote> quote(SwapQuoteRequest request);

  Future<SwapIntentSnapshot> startSwap(SwapQuote quote);

  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo});

  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  });
}

abstract interface class SwapPricingProvider {
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false});
}
