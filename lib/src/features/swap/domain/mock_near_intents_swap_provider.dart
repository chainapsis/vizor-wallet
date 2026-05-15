import 'swap_contract.dart';

class MockNearIntentsSwapProvider implements SwapProvider {
  const MockNearIntentsSwapProvider();

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return swapExternalAssets;
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    return SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      sellAmount: request.sellAmount,
      providerLabel: providerLabel,
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    return SwapIntentSnapshot.fromQuote(quote);
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      sellAmount: 2.4,
      providerLabel: providerLabel,
    );
    return SwapIntentSnapshot.fromQuote(quote, id: intentId);
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      sellAmount: 2.4,
      providerLabel: providerLabel,
    );
    final base = SwapIntentSnapshot.fromQuote(quote, id: depositAddress);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Deposit detected',
      depositInstruction: base.depositInstruction,
    );
  }
}
