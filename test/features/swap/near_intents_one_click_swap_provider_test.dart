import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_one_click_swap_provider.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test('quote posts exact-input payload and parses 1Click quote', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          depositMemo: 'memo-7',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(
      transport: transport,
      bearerToken: 'jwt-token',
      referral: 'rowan',
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1refund',
      ),
    );

    final request = transport.requests.last;
    expect(request.method, 'POST');
    expect(request.uri.path, '/v0/quote');
    expect(request.headers['authorization'], 'Bearer jwt-token');
    expect(request.body?['amount'], '150000000');
    expect(request.body?['originAsset'], 'nep141:zec.omft.near');
    expect(request.body?['destinationAsset'], 'nep141:usdc.example');
    expect(request.body?['refundTo'], 't1refund');
    expect(request.body?['recipient'], '0xrecipient');
    expect(request.body?['deadline'], '2026-05-07T10:10:00Z');
    expect(request.body?['referral'], 'rowan');

    expect(quote.providerQuoteId, 'quote-1');
    expect(quote.providerSignature, 'quote-signature');
    expect(quote.pairText, 'ZEC -> USDC');
    expect(quote.sellAmountText, '1.5 ZEC');
    expect(quote.receiveEstimateText, '~105.25 USDC');
    expect(quote.minimumReceiveText, '104.75 USDC');
    expect(quote.rateText, '1 ZEC = 70.17 USDC');
    expect(quote.depositInstruction.address, 't1deposit');
    expect(quote.depositInstruction.memo, 'memo-7');
    expect(quote.quoteExpiresAt, DateTime.utc(2026, 5, 7, 10, 8));
    expect(quote.depositInstruction.deadline, DateTime.utc(2026, 5, 7, 10, 10));
  });

  test('quote flips asset ids for external asset into ZEC', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:usdc.example',
          destinationAsset: 'nep141:zec.omft.near',
          amountInFormatted: '140.35',
          amountOutFormatted: '2',
          minAmountOut: '199000000',
          depositAddress: '0xexternal-deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 140.35,
        destination: 't1rotating-zec-recipient',
        refundAddress: '0xexternal-refund',
      ),
    );
    final intent = await provider.startSwap(quote);

    final request = transport.requests.last;
    expect(request.body?['amount'], '140350000');
    expect(request.body?['originAsset'], 'nep141:usdc.example');
    expect(request.body?['destinationAsset'], 'nep141:zec.omft.near');
    expect(request.body?['refundTo'], '0xexternal-refund');
    expect(request.body?['recipient'], 't1rotating-zec-recipient');
    expect(quote.pairText, 'USDC -> ZEC');
    expect(quote.receiveEstimateText, '~2 ZEC');
    expect(quote.rateText, '1 USDC = 0.0143 ZEC');
    expect(intent.id, '0xexternal-deposit');
    expect(intent.status, SwapIntentStatus.awaitingExternalDeposit);
  });

  test('quote can override the USDC 1Click asset id', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:base-usdc.example',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(
      transport: transport,
      bearerToken: 'jwt-token',
      assetIdOverrides: {SwapAsset.usdc: 'nep141:base-usdc.example'},
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1refund',
      ),
    );

    expect(
      transport.requests.last.body?['destinationAsset'],
      'nep141:base-usdc.example',
    );
  });

  test('token list exposes live chain variants with local icon keys', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:base-usdc.example',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    final supported = await provider.listSupportedExternalAssets();
    final baseUsdc = supported.singleWhere(
      (asset) => asset.symbol == 'USDC' && asset.chainTicker == 'base',
    );

    expect(baseUsdc.assetId, 'nep141:base-usdc.example');
    expect(baseUsdc.displayName, 'USD Coin');
    expect(baseUsdc.railLabel, 'Base USDC');
    expect(baseUsdc.tokenIconKey, 'usdc');
    expect(baseUsdc.chainIconKey, 'base');

    await provider.quote(
      SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: baseUsdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 't1refund',
      ),
    );

    expect(
      transport.requests.last.body?['destinationAsset'],
      'nep141:base-usdc.example',
    );
  });

  test('pricing snapshot derives indicative rates from token prices', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithPrices('540.62')),
      _FakeResponse.get('/v0/tokens', _tokensWithPrices('541.10')),
    ]);
    final provider = NearIntentsOneClickSwapProvider(transport: transport);

    final initial = await provider.loadPricingSnapshot();
    final refreshed = await provider.loadPricingSnapshot(forceRefresh: true);

    expect(initial.supportedExternalAssets, contains(SwapAsset.usdc));
    expect(initial.externalPerZec[SwapAsset.usdc], closeTo(540.62, 0.001));
    expect(refreshed.externalPerZec[SwapAsset.usdc], closeTo(541.10, 0.001));
    expect(transport.requests, hasLength(2));
  });

  test(
    'quote supports non-USDC external assets on their preferred chain',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:btc.omft.near',
            amountInFormatted: '1.5',
            amountOutFormatted: '0.00096',
            minAmountOut: '95000',
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapProvider(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10),
      );

      final supported = await provider.listSupportedExternalAssets();
      expect(supported, containsAll([SwapAsset.usdc, SwapAsset.btc]));

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.btc,
          sellAmount: 1.5,
          destination: 'bc1recipient',
          refundAddress: 't1refund',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['originAsset'], 'nep141:zec.omft.near');
      expect(request.body?['destinationAsset'], 'nep141:btc.omft.near');
      expect(quote.pairText, 'ZEC -> BTC');
      expect(quote.receiveEstimateText, '~0.00096 BTC');
    },
  );

  test(
    'status uses deposit memo and maps 1Click success into shielding pending',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            amountInFormatted: '140.35',
            amountOutFormatted: '2',
            minAmountOut: '199000000',
            depositAddress: '0xexternal-deposit',
            depositMemo: '123',
            status: 'SUCCESS',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapProvider(transport: transport);

      final status = await provider.getStatus(
        '0xexternal-deposit',
        depositMemo: '123',
      );

      final request = transport.requests.last;
      expect(request.method, 'GET');
      expect(request.uri.path, '/v0/status');
      expect(
        request.uri.queryParameters['depositAddress'],
        '0xexternal-deposit',
      );
      expect(request.uri.queryParameters['depositMemo'], '123');
      expect(status.status, SwapIntentStatus.shieldingPending);
      expect(status.nextAction, 'Shield received ZEC into this wallet');
    },
  );

  test(
    'submitDepositTransaction posts optional acceleration payload',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/deposit/submit',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '1',
            amountOutFormatted: '70',
            minAmountOut: '69650000',
            depositAddress: 't1deposit',
            status: 'KNOWN_DEPOSIT_TX',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapProvider(transport: transport);

      final status = await provider.submitDepositTransaction(
        depositAddress: 't1deposit',
        txHash: 'zec-txid',
        depositMemo: 'memo-7',
      );

      final request = transport.requests.last;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v0/deposit/submit');
      expect(request.body?['depositAddress'], 't1deposit');
      expect(request.body?['txHash'], 'zec-txid');
      expect(request.body?['memo'], 'memo-7');
      expect(status.status, SwapIntentStatus.depositObserved);
    },
  );

  test('non-success responses preserve operation and status code', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post('/v0/quote', {
        'message': 'jwt missing',
      }, statusCode: 401),
    ]);
    final provider = NearIntentsOneClickSwapProvider(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          destination: '0xrecipient',
          refundAddress: 't1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'quote')
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('quote preserves operation when a requested asset is unsupported', () {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', [_tokens.first]),
    ]);
    final provider = NearIntentsOneClickSwapProvider(transport: transport);

    expect(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          destination: '0xrecipient',
          refundAddress: 't1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'quote')
            .having(
              (error) => error.message,
              'message',
              contains('does not currently list USDC'),
            ),
      ),
    );
  });

  test('status rejects unsupported provider asset pairs as status errors', () {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:unsupported.asset',
          destinationAsset: 'nep141:zec.omft.near',
          amountInFormatted: '12',
          amountOutFormatted: '1',
          minAmountOut: '99500000',
          depositAddress: 'unsupported-deposit',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(transport: transport);

    expect(
      provider.getStatus('unsupported-deposit'),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'status')
            .having(
              (error) => error.message,
              'message',
              contains('Unsupported 1Click status pair'),
            ),
      ),
    );
  });

  group('status mapping', () {
    for (final scenario in _statusScenarios) {
      test('${scenario.oneClickStatus} maps to ${scenario.expectedStatus.name} '
          'for ${scenario.direction.name}', () async {
        final originAsset = scenario.direction.sendsZec
            ? 'nep141:zec.omft.near'
            : 'nep141:usdc.example';
        final destinationAsset = scenario.direction.sendsZec
            ? 'nep141:usdc.example'
            : 'nep141:zec.omft.near';
        final transport = _FakeOneClickTransport([
          _FakeResponse.get('/v0/tokens', _tokens),
          _FakeResponse.get(
            '/v0/status',
            _quoteResponse(
              originAsset: originAsset,
              destinationAsset: destinationAsset,
              amountInFormatted: scenario.direction.sendsZec ? '1' : '70',
              amountOutFormatted: scenario.direction.sendsZec ? '70' : '1',
              minAmountOut: scenario.direction.sendsZec
                  ? '69650000'
                  : '99500000',
              depositAddress: 'status-deposit',
              status: scenario.oneClickStatus,
            ),
          ),
        ]);
        final provider = NearIntentsOneClickSwapProvider(
          transport: transport,
          now: () => DateTime.utc(2026, 5, 7, 10, 2),
        );

        final status = await provider.getStatus('status-deposit');

        expect(status.status, scenario.expectedStatus);
        expect(status.nextAction, scenario.expectedNextAction);
        expect(status.pairText, scenario.expectedPairText);
      });
    }
  });

  test('pending deposit becomes expired after the deposit deadline', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1',
          amountOutFormatted: '70',
          minAmountOut: '69650000',
          depositAddress: 'expired-deposit',
          status: 'PENDING_DEPOSIT',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapProvider(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10, 11),
    );

    final status = await provider.getStatus('expired-deposit');

    expect(status.status, SwapIntentStatus.expired);
    expect(status.nextAction, 'Start a fresh quote');
    expect(
      status.depositInstruction.deadline,
      DateTime.utc(2026, 5, 7, 10, 10),
    );
  });
}

const _tokens = [
  {
    'assetId': 'nep141:zec.omft.near',
    'decimals': 8,
    'blockchain': 'zec',
    'symbol': 'ZEC',
  },
  {
    'assetId': 'nep141:usdc.example',
    'decimals': 6,
    'blockchain': 'eth',
    'symbol': 'USDC',
  },
  {
    'assetId': 'nep141:wrap.near',
    'decimals': 24,
    'blockchain': 'near',
    'symbol': 'wNEAR',
  },
];

const _tokensWithNearUsdcFirst = [
  {
    'assetId': 'nep141:near-usdc.example',
    'decimals': 6,
    'blockchain': 'near',
    'symbol': 'USDC',
  },
  ..._tokens,
  {
    'assetId': 'nep141:base-usdc.example',
    'decimals': 6,
    'blockchain': 'base',
    'symbol': 'USDC',
  },
];

const _tokensWithAdditionalAssets = [
  ..._tokensWithNearUsdcFirst,
  {
    'assetId': 'nep141:btc.omft.near',
    'decimals': 8,
    'blockchain': 'btc',
    'symbol': 'BTC',
  },
  {
    'assetId': 'nep141:sol.omft.near',
    'decimals': 9,
    'blockchain': 'sol',
    'symbol': 'SOL',
  },
];

List<Map<String, Object?>> _tokensWithPrices(String zecPrice) {
  return [
    {
      'assetId': 'nep141:zec.omft.near',
      'decimals': 8,
      'blockchain': 'zec',
      'symbol': 'ZEC',
      'price': zecPrice,
    },
    {
      'assetId': 'nep141:usdc.example',
      'decimals': 6,
      'blockchain': 'eth',
      'symbol': 'USDC',
      'price': '1',
    },
  ];
}

Map<String, Object?> _quoteResponse({
  required String originAsset,
  required String destinationAsset,
  required String amountInFormatted,
  required String amountOutFormatted,
  required String minAmountOut,
  required String depositAddress,
  required String? status,
  String? depositMemo,
}) {
  final quote = {
    'correlationId': 'quote-1',
    'timestamp': '2026-05-07T10:00:00Z',
    'signature': 'quote-signature',
    'quoteRequest': {
      'dry': false,
      'swapType': 'EXACT_INPUT',
      'slippageTolerance': 100,
      'originAsset': originAsset,
      'depositType': 'ORIGIN_CHAIN',
      'destinationAsset': destinationAsset,
      'amount': '100000000',
      'refundTo': 'refund-address',
      'refundType': 'ORIGIN_CHAIN',
      'recipient': 'recipient-address',
      'recipientType': 'DESTINATION_CHAIN',
      'deadline': '2026-05-07T10:10:00Z',
    },
    'quote': {
      'amountIn': '100000000',
      'amountInFormatted': amountInFormatted,
      'amountOut': '105250000',
      'amountOutFormatted': amountOutFormatted,
      'minAmountOut': minAmountOut,
      'timeEstimate': 120,
      'depositAddress': depositAddress,
      'depositMemo': depositMemo,
      'deadline': '2026-05-07T10:10:00Z',
      'timeWhenInactive': '2026-05-07T10:08:00Z',
    },
  };

  if (status == null) {
    return quote;
  }

  return {
    'correlationId': 'status-1',
    'quoteResponse': quote,
    'status': status,
    'updatedAt': '2026-05-07T10:02:00Z',
    'swapDetails': <String, Object?>{},
  };
}

class _FakeOneClickTransport implements OneClickApiTransport {
  _FakeOneClickTransport(this._responses);

  final List<_FakeResponse> _responses;
  final List<_FakeRequest> requests = [];

  @override
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    return _handle('GET', uri, headers: headers);
  }

  @override
  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) {
    return _handle('POST', uri, headers: headers, body: body);
  }

  Future<OneClickHttpResponse> _handle(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    requests.add(
      _FakeRequest(method: method, uri: uri, headers: headers, body: body),
    );
    if (_responses.isEmpty) {
      throw StateError('Unexpected $method ${uri.path}');
    }
    final response = _responses.removeAt(0);
    if (response.method != method || response.path != uri.path) {
      throw StateError(
        'Expected ${response.method} ${response.path}, '
        'got $method ${uri.path}',
      );
    }
    return OneClickHttpResponse(
      statusCode: response.statusCode,
      body: jsonEncode(response.body),
    );
  }
}

class _FakeResponse {
  const _FakeResponse._({
    required this.method,
    required this.path,
    required this.body,
    this.statusCode = 200,
  });

  factory _FakeResponse.get(String path, Object? body, {int statusCode = 200}) {
    return _FakeResponse._(
      method: 'GET',
      path: path,
      body: body,
      statusCode: statusCode,
    );
  }

  factory _FakeResponse.post(
    String path,
    Object? body, {
    int statusCode = 200,
  }) {
    return _FakeResponse._(
      method: 'POST',
      path: path,
      body: body,
      statusCode: statusCode,
    );
  }

  final String method;
  final String path;
  final Object? body;
  final int statusCode;
}

class _FakeRequest {
  const _FakeRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

const _statusScenarios = [
  _StatusScenario(
    oneClickStatus: 'PENDING_DEPOSIT',
    direction: SwapDirection.zecToExternal,
    expectedStatus: SwapIntentStatus.awaitingDeposit,
    expectedNextAction: 'Send ZEC to the one-time deposit address',
    expectedPairText: 'ZEC -> USDC',
  ),
  _StatusScenario(
    oneClickStatus: 'PENDING_DEPOSIT',
    direction: SwapDirection.externalToZec,
    expectedStatus: SwapIntentStatus.awaitingExternalDeposit,
    expectedNextAction: 'Send USDC to the one-time deposit address',
    expectedPairText: 'USDC -> ZEC',
  ),
  _StatusScenario(
    oneClickStatus: 'KNOWN_DEPOSIT_TX',
    direction: SwapDirection.zecToExternal,
    expectedStatus: SwapIntentStatus.depositObserved,
    expectedNextAction: 'Deposit detected',
    expectedPairText: 'ZEC -> USDC',
  ),
  _StatusScenario(
    oneClickStatus: 'PROCESSING',
    direction: SwapDirection.externalToZec,
    expectedStatus: SwapIntentStatus.processing,
    expectedNextAction: 'Swap is processing',
    expectedPairText: 'USDC -> ZEC',
  ),
  _StatusScenario(
    oneClickStatus: 'INCOMPLETE_DEPOSIT',
    direction: SwapDirection.externalToZec,
    expectedStatus: SwapIntentStatus.incompleteDeposit,
    expectedNextAction: 'Deposit is below the quoted amount',
    expectedPairText: 'USDC -> ZEC',
  ),
  _StatusScenario(
    oneClickStatus: 'SUCCESS',
    direction: SwapDirection.zecToExternal,
    expectedStatus: SwapIntentStatus.complete,
    expectedNextAction: 'Swap complete',
    expectedPairText: 'ZEC -> USDC',
  ),
  _StatusScenario(
    oneClickStatus: 'SUCCESS',
    direction: SwapDirection.externalToZec,
    expectedStatus: SwapIntentStatus.shieldingPending,
    expectedNextAction: 'Shield received ZEC into this wallet',
    expectedPairText: 'USDC -> ZEC',
  ),
  _StatusScenario(
    oneClickStatus: 'REFUNDED',
    direction: SwapDirection.zecToExternal,
    expectedStatus: SwapIntentStatus.refunded,
    expectedNextAction: 'Refund sent to the refund address',
    expectedPairText: 'ZEC -> USDC',
  ),
  _StatusScenario(
    oneClickStatus: 'FAILED',
    direction: SwapDirection.externalToZec,
    expectedStatus: SwapIntentStatus.failed,
    expectedNextAction: 'Swap failed',
    expectedPairText: 'USDC -> ZEC',
  ),
];

class _StatusScenario {
  const _StatusScenario({
    required this.oneClickStatus,
    required this.direction,
    required this.expectedStatus,
    required this.expectedNextAction,
    required this.expectedPairText,
  });

  final String oneClickStatus;
  final SwapDirection direction;
  final SwapIntentStatus expectedStatus;
  final String expectedNextAction;
  final String expectedPairText;
}
