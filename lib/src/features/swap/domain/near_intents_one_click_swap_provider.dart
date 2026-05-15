import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'swap_contract.dart';

class OneClickApiException implements Exception {
  const OneClickApiException(this.message, {this.operation, this.statusCode});

  final String message;
  final String? operation;
  final int? statusCode;

  @override
  String toString() => 'OneClickApiException: $message';
}

class OneClickHttpResponse {
  const OneClickHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  Object? get decodedJson => jsonDecode(body);

  Map<String, dynamic> get jsonObject {
    final decoded = decodedJson;
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const OneClickApiException('Expected a JSON object response');
  }

  List<dynamic> get jsonList {
    final decoded = decodedJson;
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw const OneClickApiException('Expected a JSON list response');
  }
}

abstract interface class OneClickApiTransport {
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  });

  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  });
}

class HttpClientOneClickApiTransport implements OneClickApiTransport {
  HttpClientOneClickApiTransport({
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    return _send('GET', uri, headers: headers);
  }

  @override
  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) {
    return _send('POST', uri, headers: headers, body: body);
  }

  Future<OneClickHttpResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(method, uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(_withoutNulls(body)));
    }

    final response = await request.close().timeout(timeout);
    final responseBody = await utf8.decoder.bind(response).join();
    return OneClickHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }
}

class NearIntentsOneClickSwapProvider
    implements SwapProvider, SwapPricingProvider {
  NearIntentsOneClickSwapProvider({
    Uri? baseUri,
    OneClickApiTransport? transport,
    this.bearerToken,
    this.referral,
    this.quoteWaitingTimeMs = 3000,
    this.slippageBps = 100,
    this.quoteDeadline = const Duration(minutes: 10),
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

    final body = <String, Object?>{
      'dry': request.dryRun,
      'swapType': 'EXACT_INPUT',
      'slippageTolerance': request.slippageBps ?? slippageBps,
      'originAsset': sellToken.assetId,
      'depositType': 'ORIGIN_CHAIN',
      'destinationAsset': receiveToken.assetId,
      'amount': _toBaseUnits(
        request.sellAmountText ?? request.sellAmount.toString(),
        sellToken.decimals,
      ),
      'refundTo': request.refundAddress!.trim(),
      'refundType': 'ORIGIN_CHAIN',
      'recipient': request.destination.trim(),
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
    return _quoteFromOneClick(
      quoteResponse,
      direction: request.direction,
      externalAsset: request.externalAsset,
      sellToken: sellToken,
      receiveToken: receiveToken,
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    final depositAddress = quote.depositInstruction.address;
    if (depositAddress == _dryRunDepositAddress) {
      throw const OneClickApiException(
        'Cannot start a swap from a dry-run quote',
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
    final quote = _quoteFromOneClick(
      response.quoteResponse,
      direction: direction,
      externalAsset: externalAsset,
      sellToken: _requireToken(sellAsset, tokens, operation: 'status'),
      receiveToken: _requireToken(receiveAsset, tokens, operation: 'status'),
    );
    final status = _statusFromOneClick(response.status, quote, _now());

    return SwapIntentSnapshot(
      id: quote.depositInstruction.address,
      providerLabel: quote.providerLabel,
      pairText: quote.pairText,
      sellAmountText: quote.sellAmountText,
      receiveEstimateText: quote.receiveEstimateText,
      status: status,
      nextAction: _nextAction(status, quote),
      depositInstruction: quote.depositInstruction,
      providerStatusRaw: response.status,
      nearIntentHash: response.swapDetails?.intentHash,
      nearTransactionHash: response.swapDetails?.nearTransactionHash,
    );
  }

  SwapQuote _quoteFromOneClick(
    _OneClickQuoteResponse response, {
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required _OneClickToken sellToken,
    required _OneClickToken receiveToken,
  }) {
    final quote = response.quote;
    final sellAsset = direction.fromAsset(externalAsset);
    final receiveAsset = direction.toAsset(externalAsset);
    final sellAmount = _parseAmount(quote.amountInFormatted, 'amountIn');
    final receiveAmount = _parseAmount(quote.amountOutFormatted, 'amountOut');
    final minReceiveText = quote.minAmountOut == null
        ? receiveAsset.formatAmount(receiveAmount * 0.995)
        : _baseUnitsToDecimal(quote.minAmountOut!, receiveToken.decimals);
    final minimumReceiveAmount =
        double.tryParse(minReceiveText) ?? receiveAmount * 0.995;
    final quoteExpiresAt = _parseIsoDateTime(quote.timeWhenInactive);
    final depositDeadline = _parseIsoDateTime(
      quote.deadline ?? response.quoteRequest.deadline,
    );
    final quoteExpiryLabel = _expiryLabel(quote.timeWhenInactive);
    final depositExpiryLabel = _expiryLabel(
      quote.deadline ?? response.quoteRequest.deadline,
    );

    return SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      sellAmount: sellAmount,
      receiveAmount: receiveAmount,
      minimumReceiveAmount: minimumReceiveAmount,
      providerLabel: providerLabel,
      feeLabel: 'Included in shown rate',
      expiryLabel: quoteExpiryLabel,
      quoteExpiresAt: quoteExpiresAt,
      depositInstruction: SwapDepositInstruction(
        asset: sellAsset,
        address: quote.depositAddress ?? _dryRunDepositAddress,
        expiresInLabel: depositExpiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo: quote.depositMemo,
        deadline: depositDeadline,
      ),
      providerQuoteId: response.correlationId,
      providerSignature: response.signature,
      sellAmountTextOverride:
          '${_trimDecimal(quote.amountInFormatted)} ${sellAsset.symbol}',
      receiveEstimateTextOverride:
          '~${_trimDecimal(quote.amountOutFormatted)} ${receiveAsset.symbol}',
      minimumReceiveTextOverride:
          '${_trimDecimal(minReceiveText)} ${receiveAsset.symbol}',
      rateTextOverride: _rateText(
        sellAsset: sellAsset,
        sellAmount: sellAmount,
        receiveAsset: receiveAsset,
        receiveAmount: receiveAmount,
      ),
    );
  }

  void _validateQuoteRequest(SwapQuoteRequest request) {
    if (request.sellAmount <= 0 || !request.sellAmount.isFinite) {
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
    return assets;
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
    return null;
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
    this.deadline,
  });

  factory _OneClickQuoteRequest.fromJson(Map<String, dynamic> json) {
    return _OneClickQuoteRequest(
      originAsset: _string(json, 'originAsset'),
      destinationAsset: _string(json, 'destinationAsset'),
      deadline: _optionalString(json, 'deadline'),
    );
  }

  final String originAsset;
  final String destinationAsset;
  final String? deadline;
}

class _OneClickQuote {
  const _OneClickQuote({
    required this.amountInFormatted,
    required this.amountOutFormatted,
    this.minAmountOut,
    this.depositAddress,
    this.depositMemo,
    this.deadline,
    this.timeWhenInactive,
  });

  factory _OneClickQuote.fromJson(Map<String, dynamic> json) {
    return _OneClickQuote(
      amountInFormatted: _string(json, 'amountInFormatted'),
      amountOutFormatted: _string(json, 'amountOutFormatted'),
      minAmountOut: _optionalString(json, 'minAmountOut'),
      depositAddress: _optionalString(json, 'depositAddress'),
      depositMemo: _optionalString(json, 'depositMemo'),
      deadline: _optionalString(json, 'deadline'),
      timeWhenInactive: _optionalString(json, 'timeWhenInactive'),
    );
  }

  final String amountInFormatted;
  final String amountOutFormatted;
  final String? minAmountOut;
  final String? depositAddress;
  final String? depositMemo;
  final String? deadline;
  final String? timeWhenInactive;
}

class _OneClickQuoteResponse {
  const _OneClickQuoteResponse({
    required this.correlationId,
    required this.signature,
    required this.quoteRequest,
    required this.quote,
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
    return _OneClickQuoteResponse(
      correlationId:
          _optionalString(json, 'correlationId') ??
          fallbackCorrelationId ??
          (throw const OneClickApiException(
            'Missing string field: correlationId',
          )),
      signature: _string(json, 'signature'),
      quoteRequest: _OneClickQuoteRequest.fromJson(request),
      quote: _OneClickQuote.fromJson(quote),
    );
  }

  final String correlationId;
  final String signature;
  final _OneClickQuoteRequest quoteRequest;
  final _OneClickQuote quote;
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
  const _OneClickSwapDetails({this.intentHash, this.nearTransactionHash});

  factory _OneClickSwapDetails.fromJson(Map<String, dynamic> json) {
    return _OneClickSwapDetails(
      intentHash: _firstOptionalString(json, 'intentHashes', 'intent_hashes'),
      nearTransactionHash:
          _firstOptionalString(json, 'nearTxHashes', 'near_tx_hashes') ??
          _firstTransactionHash(json, 'nearSwapTransactions') ??
          _firstTransactionHash(json, 'near_swap_transactions') ??
          _firstTransactionHash(json, 'nearDepositTransactions') ??
          _firstTransactionHash(json, 'near_deposit_transactions'),
    );
  }

  final String? intentHash;
  final String? nearTransactionHash;
}

const _dryRunDepositAddress = 'dry-run-preview';

void _expectSuccess(OneClickHttpResponse response, String operation) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }
  throw OneClickApiException(
    'NEAR Intents $operation failed '
    '(${response.statusCode}): ${response.body}',
    operation: operation,
    statusCode: response.statusCode,
  );
}

Map<String, Object?> _withoutNulls(Map<String, Object?> value) {
  return {
    for (final entry in value.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  throw OneClickApiException('Missing string field: $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  throw OneClickApiException('Invalid string field: $key');
}

String? _firstOptionalString(
  Map<String, dynamic> json,
  String camelKey,
  String snakeKey,
) {
  final value = json[camelKey] ?? json[snakeKey];
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is List) {
    for (final item in value) {
      if (item == null) continue;
      final string = item is String ? item : item.toString();
      final trimmed = string.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
  return null;
}

String? _firstTransactionHash(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) return null;
  for (final item in value) {
    if (item is! Map) continue;
    final txHash = item['txHash'] ?? item['tx_hash'];
    if (txHash is! String) continue;
    final trimmed = txHash.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw OneClickApiException('Missing integer field: $key');
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  throw OneClickApiException('Invalid number field: $key');
}

double _parseAmount(String value, String fieldName) {
  final parsed = double.tryParse(value);
  if (parsed == null) {
    throw OneClickApiException('Invalid amount field: $fieldName');
  }
  return parsed;
}

String _toBaseUnits(String amount, int decimals) {
  if (decimals < 0) {
    throw const OneClickApiException('Invalid token decimals');
  }
  return _decimalStringToBaseUnits(amount, decimals);
}

String _decimalStringToBaseUnits(String value, int decimals) {
  var normalized = value.trim().toLowerCase();
  if (normalized.startsWith('+')) {
    normalized = normalized.substring(1);
  }
  if (normalized.startsWith('-') || normalized.isEmpty) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final exponentParts = normalized.split('e');
  if (exponentParts.length > 2 || exponentParts.first.isEmpty) {
    throw const OneClickApiException('Invalid quote amount');
  }
  final exponent = exponentParts.length == 2
      ? int.tryParse(exponentParts[1])
      : 0;
  if (exponent == null) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final mantissa = exponentParts.first;
  final decimalPointCount = '.'.allMatches(mantissa).length;
  if (decimalPointCount > 1) {
    throw const OneClickApiException('Invalid quote amount');
  }
  final pointIndex = mantissa.indexOf('.');
  final fractionalDigits = pointIndex == -1
      ? 0
      : mantissa.length - pointIndex - 1;
  var digits = mantissa.replaceAll('.', '');
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final decimalPlaces = fractionalDigits - exponent;
  final shift = decimals - decimalPlaces;
  if (shift >= 0) {
    digits = digits.padRight(digits.length + shift, '0');
  } else {
    final keepLength = digits.length + shift;
    if (keepLength <= 0) return '0';
    digits = digits.substring(0, keepLength);
  }

  final raw = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return raw.isEmpty ? '0' : raw;
}

String _baseUnitsToDecimal(String amount, int decimals) {
  final negative = amount.startsWith('-');
  final digits = negative ? amount.substring(1) : amount;
  final padded = digits.padLeft(decimals + 1, '0');
  final splitIndex = padded.length - decimals;
  final whole = padded.substring(0, splitIndex);
  final fraction = decimals == 0
      ? ''
      : padded.substring(splitIndex).replaceFirst(RegExp(r'0+$'), '');
  final value = fraction.isEmpty ? whole : '$whole.$fraction';
  return negative ? '-$value' : value;
}

String _trimDecimal(String value) {
  if (!value.contains('.')) {
    return value;
  }
  return value
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _expiryLabel(String? isoDate) {
  if (isoDate == null) {
    return 'Quote expiry pending';
  }
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) {
    return 'Quote expiry pending';
  }
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Expires $hour:$minute';
}

DateTime? _parseIsoDateTime(String? isoDate) {
  if (isoDate == null) return null;
  return DateTime.tryParse(isoDate)?.toUtc();
}

String _rateText({
  required SwapAsset sellAsset,
  required double sellAmount,
  required SwapAsset receiveAsset,
  required double receiveAmount,
}) {
  if (sellAmount <= 0) {
    return 'Rate pending';
  }
  final precision = receiveAsset == SwapAsset.zec ? 4 : 2;
  final rate = receiveAmount / sellAmount;
  return '1 ${sellAsset.symbol} = '
      '${rate.toStringAsFixed(precision)} ${receiveAsset.symbol}';
}

SwapIntentStatus _statusFromOneClick(
  String status,
  SwapQuote quote,
  DateTime now,
) {
  if (status == 'PENDING_DEPOSIT' &&
      _isDepositDeadlineExpired(quote.depositInstruction, now)) {
    return SwapIntentStatus.expired;
  }
  return switch (status) {
    'PENDING_DEPOSIT' =>
      quote.direction.sendsZec
          ? SwapIntentStatus.awaitingDeposit
          : SwapIntentStatus.awaitingExternalDeposit,
    'KNOWN_DEPOSIT_TX' => SwapIntentStatus.depositObserved,
    'PROCESSING' => SwapIntentStatus.processing,
    'INCOMPLETE_DEPOSIT' => SwapIntentStatus.incompleteDeposit,
    'SUCCESS' =>
      quote.receiveAsset == SwapAsset.zec
          ? SwapIntentStatus.shieldingPending
          : SwapIntentStatus.complete,
    'REFUNDED' => SwapIntentStatus.refunded,
    'FAILED' => SwapIntentStatus.failed,
    _ => SwapIntentStatus.providerStatusUnknown,
  };
}

bool _isDepositDeadlineExpired(
  SwapDepositInstruction instruction,
  DateTime now,
) {
  final deadline = instruction.deadline;
  if (deadline == null) return false;
  return !now.toUtc().isBefore(deadline);
}

String _nextAction(SwapIntentStatus status, SwapQuote quote) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit =>
      'Send ${quote.sellAsset.symbol} to the one-time deposit address',
    SwapIntentStatus.depositObserved => 'Deposit detected',
    SwapIntentStatus.processing => 'Swap is processing',
    SwapIntentStatus.providerStatusUnknown =>
      'Provider returned a status this wallet does not recognize',
    SwapIntentStatus.incompleteDeposit => 'Deposit is below the quoted amount',
    SwapIntentStatus.shieldingPending => 'Shield received ZEC into this wallet',
    SwapIntentStatus.shieldingConfirming =>
      'Wait for shield transaction confirmation',
    SwapIntentStatus.shieldingFailed => 'Retry wallet shielding',
    SwapIntentStatus.complete => 'Swap complete',
    SwapIntentStatus.refunded => 'Refund sent to the refund address',
    SwapIntentStatus.expired => 'Start a fresh quote',
    SwapIntentStatus.failed => 'Swap failed',
  };
}
