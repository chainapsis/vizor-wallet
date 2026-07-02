part of 'near_intents_one_click_swap_adapter.dart';

class _OneClickToken {
  const _OneClickToken({
    required this.assetId,
    required this.decimals,
    required this.blockchain,
    required this.symbol,
    this.price,
  });

  factory _OneClickToken.fromJson(Map<String, dynamic> json) {
    return _OneClickToken(
      assetId: _string(json, 'assetId'),
      decimals: _int(json, 'decimals'),
      blockchain: _string(json, 'blockchain'),
      symbol: _string(json, 'symbol'),
      price: _optionalDouble(json, 'price'),
    );
  }

  final String assetId;
  final int decimals;
  final String blockchain;
  final String symbol;
  final double? price;
}

class _OneClickQuoteRequest {
  const _OneClickQuoteRequest({
    required this.originAsset,
    required this.destinationAsset,
    required this.mode,
    required this.appFeeBpsOrNull,
    this.swapTypeRaw,
    this.amount,
    this.refundTo,
    this.recipient,
    this.slippageToleranceBps,
    this.deadline,
  });

  factory _OneClickQuoteRequest.fromJson(Map<String, dynamic> json) {
    return _OneClickQuoteRequest(
      originAsset: _string(json, 'originAsset'),
      destinationAsset: _string(json, 'destinationAsset'),
      mode: _oneClickSwapMode(_optionalString(json, 'swapType')),
      appFeeBpsOrNull: _appFeeBpsOrNull(json['appFees']),
      swapTypeRaw: _optionalString(json, 'swapType'),
      amount: _optionalString(json, 'amount'),
      refundTo: _optionalString(json, 'refundTo'),
      recipient: _optionalString(json, 'recipient'),
      slippageToleranceBps:
          _optionalInt(json, 'slippageTolerance') ??
          _optionalInt(json, 'slippage'),
      deadline: _optionalString(json, 'deadline'),
    );
  }

  final String originAsset;
  final String destinationAsset;
  final SwapQuoteMode mode;
  final int? appFeeBpsOrNull;
  final String? swapTypeRaw;
  final String? amount;
  final String? refundTo;
  final String? recipient;
  final int? slippageToleranceBps;
  final String? deadline;
}

class _OneClickQuote {
  const _OneClickQuote({
    this.amountIn,
    required this.amountInFormatted,
    this.amountOut,
    required this.amountOutFormatted,
    this.minAmountIn,
    this.minAmountOut,
    this.depositAddress,
    this.depositMemo,
    this.deadline,
    this.timeWhenInactive,
    this.refundFee,
  });

  factory _OneClickQuote.fromJson(Map<String, dynamic> json) {
    return _OneClickQuote(
      amountIn: _optionalString(json, 'amountIn'),
      amountInFormatted: _string(json, 'amountInFormatted'),
      amountOut: _optionalString(json, 'amountOut'),
      amountOutFormatted: _string(json, 'amountOutFormatted'),
      minAmountIn: _optionalString(json, 'minAmountIn'),
      minAmountOut: _optionalString(json, 'minAmountOut'),
      depositAddress: _optionalString(json, 'depositAddress'),
      depositMemo: _optionalString(json, 'depositMemo'),
      deadline: _optionalString(json, 'deadline'),
      timeWhenInactive: _optionalString(json, 'timeWhenInactive'),
      refundFee: _optionalString(json, 'refundFee'),
    );
  }

  final String? amountIn;
  final String amountInFormatted;
  final String? amountOut;
  final String amountOutFormatted;
  final String? minAmountIn;
  final String? minAmountOut;
  final String? depositAddress;
  final String? depositMemo;
  final String? deadline;
  final String? timeWhenInactive;
  final String? refundFee;
}

class _OneClickQuoteResponse {
  const _OneClickQuoteResponse({
    required this.correlationId,
    required this.quoteRequest,
    required this.quote,
    this.timestamp,
  });

  factory _OneClickQuoteResponse.fromJson(
    Map<String, dynamic> json, {
    String? fallbackCorrelationId,
  }) {
    final request = json['quoteRequest'];
    final quote = json['quote'];
    if (request is! Map<String, dynamic> || quote is! Map<String, dynamic>) {
      throw const OneClickApiException('Malformed 1Click quote response');
    }
    // 1Click includes a quote signature for support/dispute evidence. Keep it
    // out of the normal swap read models unless we add a dedicated support
    // payload, so UI/state code does not depend on provider evidence fields.
    return _OneClickQuoteResponse(
      correlationId:
          _optionalString(json, 'correlationId') ??
          fallbackCorrelationId ??
          (throw const OneClickApiException(
            'Missing string field: correlationId',
          )),
      quoteRequest: _OneClickQuoteRequest.fromJson(request),
      quote: _OneClickQuote.fromJson(quote),
      timestamp: _optionalString(json, 'timestamp'),
    );
  }

  final String correlationId;
  final _OneClickQuoteRequest quoteRequest;
  final _OneClickQuote quote;
  final String? timestamp;
}

class _OneClickStatusResponse {
  const _OneClickStatusResponse({
    required this.status,
    required this.quoteResponse,
    this.swapDetails,
  });

  factory _OneClickStatusResponse.fromJson(Map<String, dynamic> json) {
    final quoteResponse = json['quoteResponse'];
    if (quoteResponse is! Map<String, dynamic>) {
      throw const OneClickApiException('Malformed 1Click status response');
    }
    final swapDetails = json['swapDetails'] ?? json['swap_details'];
    return _OneClickStatusResponse(
      status: _string(json, 'status'),
      quoteResponse: _OneClickQuoteResponse.fromJson(
        quoteResponse,
        fallbackCorrelationId: _optionalString(json, 'correlationId'),
      ),
      swapDetails: swapDetails is Map<String, dynamic>
          ? _OneClickSwapDetails.fromJson(swapDetails)
          : null,
    );
  }

  final String status;
  final _OneClickQuoteResponse quoteResponse;
  final _OneClickSwapDetails? swapDetails;
}

class _OneClickSwapDetails {
  const _OneClickSwapDetails({
    this.intentHash,
    this.amountIn,
    this.amountInFormatted,
    this.amountOut,
    this.amountOutFormatted,
    this.slippageBps,
    this.refundedAmount,
    this.refundedAmountFormatted,
    this.refundFee,
    this.refundReason,
    this.depositedAmount,
    this.depositedAmountFormatted,
    this.originChainTxHash,
    this.destinationChainTxHash,
  });

  factory _OneClickSwapDetails.fromJson(Map<String, dynamic> json) {
    return _OneClickSwapDetails(
      intentHash: _firstOptionalString(json, 'intentHashes', 'intent_hashes'),
      amountIn: _optionalString(json, 'amountIn'),
      amountInFormatted: _optionalString(json, 'amountInFormatted'),
      amountOut: _optionalString(json, 'amountOut'),
      amountOutFormatted: _optionalString(json, 'amountOutFormatted'),
      slippageBps: _optionalInt(json, 'slippage'),
      refundedAmount: _optionalString(json, 'refundedAmount'),
      refundedAmountFormatted: _optionalString(json, 'refundedAmountFormatted'),
      refundFee: _optionalString(json, 'refundFee'),
      refundReason: _optionalString(json, 'refundReason'),
      depositedAmount: _optionalString(json, 'depositedAmount'),
      depositedAmountFormatted: _optionalString(
        json,
        'depositedAmountFormatted',
      ),
      originChainTxHash:
          _firstChainTxHash(json, 'originChainTxHashes') ??
          _firstChainTxHash(json, 'origin_chain_tx_hashes'),
      destinationChainTxHash:
          _firstChainTxHash(json, 'destinationChainTxHashes') ??
          _firstChainTxHash(json, 'destination_chain_tx_hashes'),
    );
  }

  final String? intentHash;
  final String? amountIn;
  final String? amountInFormatted;
  final String? amountOut;
  final String? amountOutFormatted;
  final int? slippageBps;
  final String? refundedAmount;
  final String? refundedAmountFormatted;
  final String? refundFee;
  final String? refundReason;
  final String? depositedAmount;
  final String? depositedAmountFormatted;
  final String? originChainTxHash;
  final String? destinationChainTxHash;
}

const _placeholderDepositAddress = 'quote-placeholder-deposit';
