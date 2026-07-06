import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/swap_contract.dart';
import '../../models/swap_token_amount_formatting.dart';

part 'near_intents_one_click_json.dart';
part 'near_intents_one_click_models.dart';
part 'near_intents_one_click_transport.dart';

const _notReportedText = 'Not reported';

class NearIntentsOneClickSwapAdapter
    implements SwapProvider, SwapPricingProvider {
  NearIntentsOneClickSwapAdapter({
    Uri? baseUri,
    OneClickApiTransport? transport,
    this.bearerToken,
    this.referral,
    this.quoteWaitingTimeMs = 3000,
    this.slippageBps = 100,
    this.quoteDeadline = const Duration(hours: 2),
    this.assetIdOverrides = const {},
    DateTime Function()? now,
  }) : baseUri = baseUri ?? Uri.parse('https://1click.chaindefuser.com'),
       transport = transport ?? HttpClientOneClickApiTransport(),
       _now = now ?? DateTime.now;

  final Uri baseUri;
  final OneClickApiTransport transport;
  final String? bearerToken;
  final String? referral;
  final int quoteWaitingTimeMs;
  final int slippageBps;
  final Duration quoteDeadline;
  final Map<SwapAsset, String> assetIdOverrides;
  final DateTime Function() _now;

  List<_OneClickToken>? _tokenCache;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    final tokens = await _ensureTokens();
    return [
      for (final asset in _assetsFromTokens(tokens))
        if (asset != SwapAsset.zec) asset,
    ];
  }

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    final tokens = await _ensureTokens(forceRefresh: forceRefresh);
    return SwapPricingSnapshot(
      usdPrices: {
        for (final token in tokens)
          if ((token.price ?? 0) > 0) _assetForToken(token): token.price!,
      },
    );
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    _validateQuoteRequest(request);
    final quoteMode = _oneClickQuoteModeForRequest(request);
    final amountText = _requiredQuoteAmountText(request);

    final tokens = await _ensureTokens();
    final sellToken = _requireToken(
      request.sellAsset,
      tokens,
      operation: 'quote',
    );
    final receiveToken = _requireToken(
      request.receiveAsset,
      tokens,
      operation: 'quote',
    );
    final amountToken = quoteMode.usesInputAmount ? sellToken : receiveToken;
    final amountBaseUnits = _toBaseUnits(amountText, amountToken.decimals);
    final requestedSlippageBps = request.slippageBps ?? slippageBps;
    final requestedRefundTo = request.refundAddress!.trim();
    final requestedRecipient = request.destination.trim();

    final body = <String, Object?>{
      'dry': request.dryRun,
      'swapType': quoteMode.oneClickSwapType,
      'slippageTolerance': requestedSlippageBps,
      'originAsset': sellToken.assetId,
      'depositType': 'ORIGIN_CHAIN',
      'destinationAsset': receiveToken.assetId,
      'amount': amountBaseUnits,
      'refundTo': requestedRefundTo,
      'refundType': 'ORIGIN_CHAIN',
      'recipient': requestedRecipient,
      'recipientType': 'DESTINATION_CHAIN',
      'deadline': _deadlineIso(request.deadline ?? quoteDeadline),
      'depositMode': 'SIMPLE',
      'quoteWaitingTimeMs': quoteWaitingTimeMs,
      if (referral != null && referral!.isNotEmpty) 'referral': referral,
    };

    final response = await transport.post(
      _endpoint('/v0/quote'),
      headers: _headers(contentType: true),
      body: body,
    );
    _expectSuccess(response, 'quote');

    final quoteResponse = _OneClickQuoteResponse.fromJson(response.jsonObject);
    _validateQuoteResponseRequest(
      quoteResponse,
      expectedMode: quoteMode,
      expectedFixedAmountBaseUnits: amountBaseUnits,
      expectedSlippageBps: requestedSlippageBps,
      expectedRefundTo: requestedRefundTo,
      expectedRecipient: requestedRecipient,
      sellToken: sellToken,
      receiveToken: receiveToken,
      allowFlexibleQuotedAmount:
          request.direction == SwapDirection.externalToZec &&
          quoteMode == SwapQuoteMode.flexInput,
    );
    return _quoteFromOneClick(
      quoteResponse,
      direction: request.direction,
      externalAsset: request.externalAsset,
      mode: quoteMode,
      sellToken: sellToken,
      receiveToken: receiveToken,
      fallbackSlippageBps:
          quoteResponse.quoteRequest.slippageToleranceBps ??
          request.slippageBps ??
          slippageBps,
    );
  }

  SwapQuoteMode _oneClickQuoteModeForRequest(SwapQuoteRequest request) {
    if (request.direction == SwapDirection.externalToZec &&
        request.mode == SwapQuoteMode.exactInput) {
      return SwapQuoteMode.flexInput;
    }
    return request.mode;
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    final depositAddress = quote.depositInstruction.address;
    if (depositAddress == _placeholderDepositAddress) {
      throw const OneClickApiException(
        'Cannot start a swap without a provider deposit address',
      );
    }
    return SwapIntentSnapshot.fromQuote(quote, id: depositAddress);
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final tokens = await _ensureTokens();
    final response = await transport.get(
      _endpoint(
        '/v0/status',
        queryParameters: {
          'depositAddress': intentId,
          if (depositMemo != null && depositMemo.isNotEmpty)
            'depositMemo': depositMemo,
        },
      ),
      headers: _headers(),
    );
    _expectSuccess(response, 'status');
    return _snapshotFromStatusResponse(
      _OneClickStatusResponse.fromJson(response.jsonObject),
      tokens,
    );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    final tokens = await _ensureTokens();
    final response = await transport.post(
      _endpoint('/v0/deposit/submit'),
      headers: _headers(contentType: true),
      body: {
        'depositAddress': depositAddress,
        'txHash': txHash,
        if (depositMemo != null && depositMemo.isNotEmpty) 'memo': depositMemo,
        if (nearSenderAccount != null && nearSenderAccount.isNotEmpty)
          'nearSenderAccount': nearSenderAccount,
      },
    );
    _expectSuccess(response, 'deposit submit');
    return _snapshotFromStatusResponse(
      _OneClickStatusResponse.fromJson(response.jsonObject),
      tokens,
    );
  }

  Future<List<_OneClickToken>> _ensureTokens({
    bool forceRefresh = false,
  }) async {
    final cached = _tokenCache;
    if (!forceRefresh && cached != null) {
      return cached;
    }

    final response = await transport.get(
      _endpoint('/v0/tokens'),
      headers: _headers(),
    );
    _expectSuccess(response, 'token list');
    final tokens = [
      for (final item in response.jsonList)
        if (item is Map<String, dynamic>) _OneClickToken.fromJson(item),
    ];
    if (tokens.isEmpty) {
      throw const OneClickApiException('1Click returned no supported tokens');
    }
    _tokenCache = tokens;
    return tokens;
  }

  SwapIntentSnapshot _snapshotFromStatusResponse(
    _OneClickStatusResponse response,
    List<_OneClickToken> tokens,
  ) {
    final request = response.quoteResponse.quoteRequest;
    final sellAsset = _assetFromAssetId(request.originAsset, tokens);
    final receiveAsset = _assetFromAssetId(request.destinationAsset, tokens);
    if (sellAsset == null || receiveAsset == null) {
      throw OneClickApiException(
        'Unsupported 1Click status pair: '
        '${request.originAsset} -> ${request.destinationAsset}',
        operation: 'status',
      );
    }
    final direction = sellAsset == SwapAsset.zec
        ? SwapDirection.zecToExternal
        : SwapDirection.externalToZec;
    final externalAsset = sellAsset == SwapAsset.zec ? receiveAsset : sellAsset;
    final sellToken = _requireToken(sellAsset, tokens, operation: 'status');
    final receiveToken = _requireToken(
      receiveAsset,
      tokens,
      operation: 'status',
    );
    final quote = _quoteFromOneClick(
      response.quoteResponse,
      direction: direction,
      externalAsset: externalAsset,
      mode: request.mode,
      sellToken: sellToken,
      receiveToken: receiveToken,
      fallbackSlippageBps:
          response.swapDetails?.slippageBps ?? request.slippageToleranceBps,
    );
    final status = _statusFromOneClick(response.status, quote);
    final statusRefundInfo = _statusRefundInfo(
      response.swapDetails,
      sellAsset: sellAsset,
      sellToken: sellToken,
    );
    final providerRefundInfo =
        quote.providerRefundInfo?.merge(statusRefundInfo) ?? statusRefundInfo;
    final details = response.swapDetails;
    final sellAmountText =
        _statusAmountText(
          formatted: details?.amountInFormatted,
          baseUnits: details?.amountIn,
          asset: sellAsset,
          token: sellToken,
        ) ??
        quote.sellAmountText;
    final receiveEstimateText =
        _statusAmountText(
          formatted: details?.amountOutFormatted,
          baseUnits: details?.amountOut,
          asset: receiveAsset,
          token: receiveToken,
        ) ??
        quote.receiveEstimateText;

    return SwapIntentSnapshot(
      id: quote.depositInstruction.address,
      providerLabel: quote.providerLabel,
      pairText: quote.pairText,
      sellAmountText: sellAmountText,
      receiveEstimateText: receiveEstimateText,
      status: status,
      nextAction: _nextAction(status, quote),
      depositInstruction: quote.depositInstruction,
      sellAmountBaseUnits: quote.sellAmountBaseUnits,
      swapFeeText: quote.feeLabel,
      totalFeesText: _statusTotalFeesText(
        response,
        status: status,
        sellAsset: sellAsset,
        sellToken: sellToken,
        providerRefundInfo: providerRefundInfo,
      ),
      realisedSlippageText: _realisedSlippageText(
        response,
        sellAsset: sellAsset,
        sellToken: sellToken,
        receiveAsset: receiveAsset,
        receiveToken: receiveToken,
      ),
      slippageToleranceText: quote.slippageToleranceText,
      minimumReceiveText: quote.minimumReceiveText,
      providerStatusRaw: response.status,
      nearIntentHash: response.swapDetails?.intentHash,
      originChainTxHash: response.swapDetails?.originChainTxHash,
      destinationChainTxHash: response.swapDetails?.destinationChainTxHash,
      providerRefundInfo: providerRefundInfo,
      fiatValueBasis: quote.fiatValueBasis,
    );
  }

  SwapQuote _quoteFromOneClick(
    _OneClickQuoteResponse response, {
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required SwapQuoteMode mode,
    required _OneClickToken sellToken,
    required _OneClickToken receiveToken,
    required int? fallbackSlippageBps,
  }) {
    final quote = response.quote;
    final sellAsset = direction.fromAsset(externalAsset);
    final receiveAsset = direction.toAsset(externalAsset);
    final sellAmount = _parseAmount(quote.amountInFormatted, 'amountIn');
    final receiveAmount = _parseAmount(quote.amountOutFormatted, 'amountOut');
    final minimumReceive = _minimumReceiveDisplay(
      quote,
      receiveAsset: receiveAsset,
      receiveToken: receiveToken,
      receiveAmount: receiveAmount,
      fallbackSlippageBps: fallbackSlippageBps,
    );
    final userDeadline = response.quoteRequest.deadline;
    final quoteExpiresAt = _parseIsoDateTime(
      userDeadline ?? quote.timeWhenInactive,
    );
    final depositDeadline = _parseIsoDateTime(userDeadline);
    final quoteExpiryLabel = _expiryLabel(
      userDeadline ?? quote.timeWhenInactive,
    );
    final depositExpiryLabel = _expiryLabel(userDeadline);

    return SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      mode: mode,
      sellAmount: sellAmount,
      receiveAmount: receiveAmount,
      minimumReceiveAmount: minimumReceive.amount,
      providerLabel: providerLabel,
      feeLabel: 'Included in shown rate',
      totalFeesText: _appFeesText(
        appFeeBps: response.quoteRequest.appFeeBpsOrNull,
        amountInFormatted: quote.amountInFormatted,
        amountInBaseUnits: quote.amountIn,
        sellAsset: sellAsset,
        sellToken: sellToken,
      ),
      expiryLabel: quoteExpiryLabel,
      quoteExpiresAt: quoteExpiresAt,
      depositInstruction: SwapDepositInstruction(
        asset: sellAsset,
        address: quote.depositAddress ?? _placeholderDepositAddress,
        expiresInLabel: depositExpiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo: quote.depositMemo,
        deadline: depositDeadline,
      ),
      providerQuoteId: response.correlationId,
      sellAmountBaseUnits: _parseBaseUnits(quote.amountIn, 'amountIn'),
      sellAmountTextOverride:
          '${swapTrimDecimal(quote.amountInFormatted)} ${sellAsset.symbol}',
      receiveEstimateTextOverride:
          '${swapTrimDecimal(quote.amountOutFormatted)} ${receiveAsset.symbol}',
      minimumReceiveTextOverride: minimumReceive.text,
      slippageToleranceTextOverride:
          minimumReceive.slippageToleranceTextOverride,
      rateTextOverride: _rateText(
        sellAsset: sellAsset,
        sellAmount: sellAmount,
        receiveAsset: receiveAsset,
        receiveAmount: receiveAmount,
      ),
      providerRefundInfo: _quoteRefundInfo(
        quote,
        sellAsset: sellAsset,
        sellToken: sellToken,
      ),
      fiatValueBasis: _quoteFiatValueBasis(
        response,
        sellAsset: sellAsset,
        sellToken: sellToken,
        receiveAsset: receiveAsset,
        receiveToken: receiveToken,
      ),
    );
  }

  _MinimumReceiveDisplay _minimumReceiveDisplay(
    _OneClickQuote quote, {
    required SwapAsset receiveAsset,
    required _OneClickToken receiveToken,
    required double receiveAmount,
    required int? fallbackSlippageBps,
  }) {
    final minAmountOut = quote.minAmountOut;
    if (minAmountOut != null) {
      final text = swapBaseUnitsToDecimal(minAmountOut, receiveToken.decimals);
      return _MinimumReceiveDisplay(
        amount: double.tryParse(text) ?? receiveAmount,
        text: '${swapTrimDecimal(text)} ${receiveAsset.symbol}',
      );
    }

    final slippageBps = fallbackSlippageBps;
    if (slippageBps == null || slippageBps < 0) {
      return _MinimumReceiveDisplay(
        amount: receiveAmount,
        text: _notReportedText,
        slippageToleranceTextOverride: _notReportedText,
      );
    }

    final minimumReceiveAmount = receiveAmount * (1 - slippageBps / 10000);
    final minimumReceiveText = swapTrimDecimal(
      receiveAsset.formatAmountDown(minimumReceiveAmount),
    );
    return _MinimumReceiveDisplay(
      amount: minimumReceiveAmount,
      text: '$minimumReceiveText ${receiveAsset.symbol}',
    );
  }

  SwapProviderRefundInfo? _quoteRefundInfo(
    _OneClickQuote quote, {
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
  }) {
    final info = SwapProviderRefundInfo(
      minimumDepositText: _baseUnitAmountText(
        quote.minAmountIn,
        asset: sellAsset,
        token: sellToken,
      ),
      refundFeeText: _baseUnitAmountText(
        quote.refundFee,
        asset: sellAsset,
        token: sellToken,
      ),
    );
    return info.hasAny ? info : null;
  }

  SwapProviderRefundInfo? _statusRefundInfo(
    _OneClickSwapDetails? details, {
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
  }) {
    if (details == null) return null;
    final info = SwapProviderRefundInfo(
      depositedAmountText: _statusAmountText(
        formatted: details.depositedAmountFormatted,
        baseUnits: details.depositedAmount,
        asset: sellAsset,
        token: sellToken,
      ),
      refundedAmountText: _statusAmountText(
        formatted: details.refundedAmountFormatted,
        baseUnits: details.refundedAmount,
        asset: sellAsset,
        token: sellToken,
      ),
      refundFeeText: _baseUnitAmountText(
        details.refundFee,
        asset: sellAsset,
        token: sellToken,
      ),
      refundReason: _cleanOptionalText(details.refundReason),
    );
    return info.hasAny ? info : null;
  }

  String? _baseUnitAmountText(
    String? value, {
    required SwapAsset asset,
    required _OneClickToken token,
  }) {
    return swapBaseUnitAmountText(
      value: value,
      asset: asset,
      decimals: token.decimals,
    );
  }

  SwapFiatValueBasis? _quoteFiatValueBasis(
    _OneClickQuoteResponse response, {
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
    required SwapAsset receiveAsset,
    required _OneClickToken receiveToken,
  }) {
    final capturedAt = _parseIsoDateTime(response.timestamp) ?? _now().toUtc();
    final basis = SwapFiatValueBasis(
      capturedAt: capturedAt,
      sellUsdUnitPrice: _capturedUsdUnitPrice(sellToken),
      receiveUsdUnitPrice: _capturedUsdUnitPrice(receiveToken),
    );
    return basis.isUsable ? basis : null;
  }

  double? _capturedUsdUnitPrice(_OneClickToken token) =>
      _usableTokenPrice(token);

  double? _usableTokenPrice(_OneClickToken token) {
    final price = token.price;
    return price != null && price.isFinite && price > 0 ? price : null;
  }

  String? _statusAmountText({
    required String? formatted,
    required String? baseUnits,
    required SwapAsset asset,
    required _OneClickToken token,
  }) {
    return swapStatusAmountText(
      formatted: formatted,
      baseUnits: baseUnits,
      asset: asset,
      decimals: token.decimals,
    );
  }

  double? _statusDecimalAmount({
    required String? formatted,
    required String? baseUnits,
    required _OneClickToken token,
    bool preferBaseUnits = false,
  }) {
    return swapStatusDecimalAmount(
      formatted: formatted,
      baseUnits: baseUnits,
      decimals: token.decimals,
      preferBaseUnits: preferBaseUnits,
    );
  }

  String? _appFeesText({
    required int? appFeeBps,
    required String amountInFormatted,
    required String? amountInBaseUnits,
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
  }) {
    if (appFeeBps == null) return null;
    final amountIn =
        _statusDecimalAmount(
          formatted: amountInFormatted,
          baseUnits: amountInBaseUnits,
          token: sellToken,
          preferBaseUnits: true,
        ) ??
        0;
    final fee = amountIn * appFeeBps / 10000;
    return _feeAmountText(sellAsset, fee);
  }

  String? _statusTotalFeesText(
    _OneClickStatusResponse response, {
    required SwapIntentStatus status,
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
    required SwapProviderRefundInfo? providerRefundInfo,
  }) {
    final details = response.swapDetails;
    if (status == SwapIntentStatus.refunded ||
        status == SwapIntentStatus.failed) {
      final deposited = _statusDecimalAmount(
        formatted: details?.depositedAmountFormatted,
        baseUnits: details?.depositedAmount,
        token: sellToken,
        preferBaseUnits: true,
      );
      final refunded = _statusDecimalAmount(
        formatted: details?.refundedAmountFormatted,
        baseUnits: details?.refundedAmount,
        token: sellToken,
        preferBaseUnits: true,
      );
      if (deposited != null && refunded != null && deposited >= refunded) {
        return _feeAmountText(sellAsset, deposited - refunded);
      }
      final refundFee = providerRefundInfo?.refundFeeText;
      if (refundFee != null && refundFee.isNotEmpty) return refundFee;
    }

    return _appFeesText(
      appFeeBps: response.quoteResponse.quoteRequest.appFeeBpsOrNull,
      amountInFormatted:
          details?.amountInFormatted ??
          response.quoteResponse.quote.amountInFormatted,
      amountInBaseUnits:
          details?.amountIn ?? response.quoteResponse.quote.amountIn,
      sellAsset: sellAsset,
      sellToken: sellToken,
    );
  }

  String? _realisedSlippageText(
    _OneClickStatusResponse response, {
    required SwapAsset sellAsset,
    required _OneClickToken sellToken,
    required SwapAsset receiveAsset,
    required _OneClickToken receiveToken,
  }) {
    final slippageBps = response.swapDetails?.slippageBps;
    if (slippageBps == null) return null;
    final percentText = formatSwapProtectionPercent(slippageBps / 100);
    final delta = _realisedSlippageDelta(
      response,
      sellToken: sellToken,
      receiveToken: receiveToken,
    );
    if (delta == null) return percentText;
    final asset =
        response.quoteResponse.quoteRequest.mode == SwapQuoteMode.exactOutput
        ? sellAsset
        : receiveAsset;
    return '${_feeAmountText(asset, delta)} ($percentText)';
  }

  double? _realisedSlippageDelta(
    _OneClickStatusResponse response, {
    required _OneClickToken sellToken,
    required _OneClickToken receiveToken,
  }) {
    final details = response.swapDetails;
    if (details == null) return null;
    final quote = response.quoteResponse.quote;
    if (response.quoteResponse.quoteRequest.mode == SwapQuoteMode.exactOutput) {
      final expected = _statusDecimalAmount(
        formatted: quote.amountInFormatted,
        baseUnits: quote.amountIn,
        token: sellToken,
        preferBaseUnits: true,
      );
      final actual = _statusDecimalAmount(
        formatted: details.amountInFormatted,
        baseUnits: details.amountIn,
        token: sellToken,
        preferBaseUnits: true,
      );
      if (expected == null || actual == null) return null;
      return (actual - expected).clamp(0, double.infinity).toDouble();
    }

    final expected = _statusDecimalAmount(
      formatted: quote.amountOutFormatted,
      baseUnits: quote.amountOut,
      token: receiveToken,
      preferBaseUnits: true,
    );
    final actual = _statusDecimalAmount(
      formatted: details.amountOutFormatted,
      baseUnits: details.amountOut,
      token: receiveToken,
      preferBaseUnits: true,
    );
    if (expected == null || actual == null) return null;
    return (expected - actual).clamp(0, double.infinity).toDouble();
  }

  String _feeAmountText(SwapAsset asset, double amount) {
    return swapFeeAmountText(asset, amount);
  }

  void _validateQuoteRequest(SwapQuoteRequest request) {
    if (request.amount <= 0 || !request.amount.isFinite) {
      throw const OneClickApiException('Swap amount must be greater than zero');
    }
    if (request.destination.trim().isEmpty) {
      throw const OneClickApiException('Recipient address is required');
    }
    if (request.refundAddress == null ||
        request.refundAddress!.trim().isEmpty) {
      throw const OneClickApiException('Refund address is required');
    }
  }

  String _requiredQuoteAmountText(SwapQuoteRequest request) {
    final amountText = request.amountText?.trim();
    if (amountText == null || amountText.isEmpty) {
      throw const OneClickApiException(
        'Quote amount text is required',
        operation: 'quote',
      );
    }
    return amountText;
  }

  void _validateQuoteResponseRequest(
    _OneClickQuoteResponse response, {
    required SwapQuoteMode expectedMode,
    required String expectedFixedAmountBaseUnits,
    required int expectedSlippageBps,
    required String expectedRefundTo,
    required String expectedRecipient,
    required _OneClickToken sellToken,
    required _OneClickToken receiveToken,
    required bool allowFlexibleQuotedAmount,
  }) {
    final actual = response.quoteRequest;
    final actualSwapType = actual.swapTypeRaw?.trim().toUpperCase();
    final hasMismatchedSwapType = actualSwapType == null
        ? actual.mode != expectedMode
        : actualSwapType != expectedMode.oneClickSwapType;
    if (hasMismatchedSwapType) {
      throw OneClickApiException(
        '1Click quote response did not match the requested route',
        operation: 'quote',
      );
    }

    final quote = response.quote;
    final amountField = expectedMode.usesInputAmount
        ? quote.amountIn
        : quote.amountOut;
    final amountFieldName = expectedMode.usesInputAmount
        ? 'amountIn'
        : 'amountOut';
    final expectedFixedAmount = BigInt.parse(expectedFixedAmountBaseUnits);
    final responseFixedAmount = _parseQuoteResponseBaseUnits(
      amountField,
      amountFieldName,
    );
    final requestFixedAmount = _parseQuoteResponseBaseUnits(
      actual.amount,
      'quoteRequest.amount',
    );
    if (requestFixedAmount != expectedFixedAmount ||
        (!allowFlexibleQuotedAmount &&
            responseFixedAmount != expectedFixedAmount)) {
      throw OneClickApiException(
        '1Click quote response did not match the requested amount',
        operation: 'quote',
      );
    }

    _validateFormattedAmountMatchesBaseUnits(
      formatted: quote.amountInFormatted,
      baseUnits: _parseQuoteResponseBaseUnits(quote.amountIn, 'amountIn'),
      decimals: sellToken.decimals,
      fieldName: 'amountIn',
      operation: 'quote',
    );
    _validateFormattedAmountMatchesBaseUnits(
      formatted: quote.amountOutFormatted,
      baseUnits: _parseQuoteResponseBaseUnits(quote.amountOut, 'amountOut'),
      decimals: receiveToken.decimals,
      fieldName: 'amountOut',
      operation: 'quote',
    );

    if (actual.slippageToleranceBps != expectedSlippageBps) {
      throw const OneClickApiException(
        '1Click quote response did not match the requested slippage',
        operation: 'quote',
      );
    }
    if (actual.refundTo?.trim() != expectedRefundTo ||
        actual.recipient?.trim() != expectedRecipient) {
      throw const OneClickApiException(
        '1Click quote response did not match the requested addresses',
        operation: 'quote',
      );
    }
  }

  BigInt _parseQuoteResponseBaseUnits(String? value, String fieldName) {
    try {
      return _parseBaseUnits(value, fieldName);
    } on OneClickApiException catch (error) {
      throw OneClickApiException(
        error.message,
        operation: 'quote',
        statusCode: error.statusCode,
      );
    }
  }

  _OneClickToken _requireToken(
    SwapAsset asset,
    List<_OneClickToken> tokens, {
    String? operation,
  }) {
    final token = _tokenFor(asset, tokens);
    if (token == null) {
      throw OneClickApiException(
        'NEAR Intents does not currently list ${asset.symbol}',
        operation: operation,
      );
    }
    return token;
  }

  _OneClickToken? _tokenFor(SwapAsset asset, List<_OneClickToken> tokens) {
    final override = assetIdOverrides[asset];
    if (override != null) {
      for (final token in tokens) {
        if (token.assetId == override) {
          return token;
        }
      }
      return null;
    }

    final assetId = asset.assetId;
    if (assetId != null) {
      for (final token in tokens) {
        if (token.assetId == assetId) {
          return token;
        }
      }
    }

    final preferredBlockchain = asset.preferredBlockchain;
    for (final token in tokens) {
      final tokenAsset = _assetForToken(token);
      if (tokenAsset.hasSameMarketAs(asset) &&
          token.blockchain.toLowerCase() == preferredBlockchain) {
        return token;
      }
    }

    for (final token in tokens) {
      if (_assetForToken(token).hasSameMarketAs(asset)) {
        return token;
      }
    }
    return null;
  }

  List<SwapAsset> _assetsFromTokens(List<_OneClickToken> tokens) {
    final seen = <String>{};
    final assets = <SwapAsset>[];
    for (final token in tokens) {
      final asset = _assetForToken(token);
      if (seen.add(asset.identityKey)) {
        assets.add(asset);
      }
    }
    return sortSwapAssetsForSelection(assets);
  }

  SwapAsset? _assetFromAssetId(String assetId, List<_OneClickToken> tokens) {
    for (final token in tokens) {
      if (token.assetId == assetId) {
        return _assetForToken(token);
      }
    }
    for (final entry in assetIdOverrides.entries) {
      if (entry.value == assetId) {
        return entry.key;
      }
    }
    final oneClickTickerAsset = _oneClickUniqueTickerAssetFromId(
      assetId,
      tokens,
    );
    if (oneClickTickerAsset != null) return oneClickTickerAsset;
    return null;
  }

  SwapAsset? _oneClickUniqueTickerAssetFromId(
    String assetId,
    List<_OneClickToken> tokens,
  ) {
    final parts = assetId.trim().toLowerCase().split(':');
    if (parts.length < 2 || parts[0] != '1cs_v1') {
      return null;
    }

    final ticker = parts[1];
    if (ticker.isEmpty) return null;
    final candidates = <String, SwapAsset>{};
    for (final token in tokens) {
      final asset = _assetForToken(token);
      if (asset.symbol.toLowerCase() != ticker) continue;
      candidates.putIfAbsent(token.assetId, () => asset);
    }
    return candidates.length == 1 ? candidates.values.single : null;
  }

  SwapAsset _assetForToken(_OneClickToken token) {
    final symbol = token.symbol.toUpperCase();
    final chain = token.blockchain.toLowerCase();
    if (symbol == 'ZEC' || chain == 'zec') {
      return SwapAsset.zec;
    }
    return SwapAsset.live(
      assetId: token.assetId,
      symbol: token.symbol,
      blockchain: token.blockchain,
      decimals: token.decimals,
    );
  }

  Map<String, String> _headers({bool contentType = false}) {
    return {
      if (contentType) HttpHeaders.contentTypeHeader: 'application/json',
      if (bearerToken != null && bearerToken!.isNotEmpty)
        HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
    };
  }

  Uri _endpoint(String path, {Map<String, String> queryParameters = const {}}) {
    final base = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    return queryParameters.isEmpty
        ? uri
        : uri.replace(queryParameters: queryParameters);
  }

  String _deadlineIso(Duration offset) {
    final deadline = _now().toUtc().add(offset);
    return deadline.toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
  }
}

class _MinimumReceiveDisplay {
  const _MinimumReceiveDisplay({
    required this.amount,
    required this.text,
    this.slippageToleranceTextOverride,
  });

  final double amount;
  final String text;
  final String? slippageToleranceTextOverride;
}
