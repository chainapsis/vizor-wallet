import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test('quote posts exact-input payload and parses 1Click quote', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithPrices('72.5')),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountIn: '150000000',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          depositMemo: 'memo-7',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
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
        sellAmountText: '1.5',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
      ),
    );

    final request = transport.requests.last;
    expect(request.method, 'POST');
    expect(request.uri.path, '/v0/quote');
    expect(request.headers['authorization'], 'Bearer jwt-token');
    expect(request.body?['dry'], isFalse);
    expect(request.body?['swapType'], 'EXACT_INPUT');
    expect(request.body?['slippageTolerance'], 100);
    expect(request.body?['amount'], '150000000');
    expect(request.body?['originAsset'], 'nep141:zec.omft.near');
    expect(request.body?['destinationAsset'], 'nep141:usdc.example');
    expect(request.body?['refundTo'], 'u1refund');
    expect(request.body?['recipient'], '0xrecipient');
    expect(request.body?['deadline'], '2026-05-07T12:00:00Z');
    expect(request.body?['referral'], 'rowan');

    expect(quote.providerQuoteId, 'quote-1');
    expect(quote.pairText, 'ZEC -> USDC');
    expect(quote.sellAmountText, '1.5 ZEC');
    expect(quote.sellAmountBaseUnits, BigInt.from(150000000));
    expect(quote.receiveEstimateText, '105.25 USDC');
    expect(quote.minimumReceiveText, '104.75 USDC');
    expect(quote.rateText, '1 ZEC = 70.17 USDC');
    expect(quote.fiatValueBasis?.sellUsdUnitPrice, 72.5);
    expect(quote.fiatValueBasis?.receiveUsdUnitPrice, 1);
    expect(quote.fiatValueBasis?.capturedAt, DateTime.utc(2026, 5, 7, 10));
    expect(quote.depositInstruction.address, 't1deposit');
    expect(quote.depositInstruction.memo, 'memo-7');
    expect(quote.quoteExpiresAt, DateTime.utc(2026, 5, 7, 12));
    expect(quote.depositInstruction.deadline, DateTime.utc(2026, 5, 7, 12));
  });

  test('quote captures USDC token price from token response', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get(
        '/v0/tokens',
        _tokensWithPrices('72.5', usdcPrice: '0.98'),
      ),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountIn: '100000000',
          amountInFormatted: '1',
          amountOutFormatted: '72',
          minAmountOut: '71640000',
          depositAddress: 't1deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1,
        sellAmountText: '1',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
      ),
    );

    expect(quote.fiatValueBasis?.sellUsdUnitPrice, 72.5);
    expect(quote.fiatValueBasis?.receiveUsdUnitPrice, 0.98);
  });

  test('quote requires explicit amount text before posting', () async {
    final transport = _FakeOneClickTransport([]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'quote')
            .having(
              (error) => error.message,
              'message',
              'Quote amount text is required',
            ),
      ),
    );

    expect(transport.requests, isEmpty);
  });

  test('quote accepts response with a mismatched asset route echo', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:wrap.near',
          amountOut: '1250000',
          amountInFormatted: '1.5',
          amountOutFormatted: '1.25',
          minAmountOut: '1237500',
          depositAddress: 't1deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        sellAmountText: '1.5',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
      ),
    );

    expect(quote.pairText, 'ZEC -> USDC');
    expect(quote.receiveEstimateText, '1.25 USDC');
  });

  test('quote accepts response that echoes BTC(OMNI) for BTC', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: '1cs_v1:btc:native:coin',
          amountInFormatted: '1.5',
          amountOutFormatted: '0.00096',
          minAmountOut: '95000',
          depositAddress: 't1deposit',
          quoteRequestRecipient: 'bc1recipient',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.btc,
        sellAmount: 1.5,
        sellAmountText: '1.5',
        destination: 'bc1recipient',
        refundAddress: 'u1refund',
      ),
    );

    final request = transport.requests.last;
    expect(request.body?['destinationAsset'], 'nep141:btc.omft.near');
    expect(quote.pairText, 'ZEC -> BTC');
    expect(quote.receiveEstimateText, '0.00096 BTC');
  });

  test(
    'quote accepts response that echoes BTC(OMNI) for a BTC origin asset',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: '1cs_v1:btc:native:coin',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '0.001',
            amountOutFormatted: '1.5',
            minAmountOut: '149250000',
            depositAddress: 'btc-deposit',
            quoteRequestRefundTo: 'bc1refund',
            quoteRequestRecipient: 'u1recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.btc,
          sellAmount: 0.001,
          sellAmountText: '0.001',
          destination: 'u1recipient',
          refundAddress: 'bc1refund',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['swapType'], 'FLEX_INPUT');
      expect(request.body?['originAsset'], 'nep141:btc.omft.near');
      expect(quote.pairText, 'BTC -> ZEC');
      expect(quote.sellAmountText, '0.001 BTC');
    },
  );

  test(
    'status accepts response that echoes BTC(OMNI) for a BTC origin asset',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: '1cs_v1:btc:native:coin',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '0.001',
            amountOutFormatted: '1.5',
            minAmountOut: '149250000',
            depositAddress: 'btc-deposit',
            quoteRequestRefundTo: 'bc1refund',
            quoteRequestRecipient: 'u1recipient',
            status: 'PROCESSING',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final status = await provider.getStatus('btc-deposit');

      expect(status.pairText, 'BTC -> ZEC');
      expect(status.sellAmountText, '0.001 BTC');
      expect(status.status, SwapIntentStatus.processing);
    },
  );

  test('status accepts unique 1Click ticker fallback assets', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: '1cs_v1:btc:provider:echo',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '0.001',
          amountOutFormatted: '1.5',
          minAmountOut: '149250000',
          depositAddress: 'btc-deposit',
          quoteRequestRefundTo: 'bc1refund',
          quoteRequestRecipient: 'u1recipient',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final status = await provider.getStatus('btc-deposit');

    expect(status.pairText, 'BTC -> ZEC');
    expect(status.sellAmountText, '0.001 BTC');
    expect(status.status, SwapIntentStatus.processing);
  });

  test('status preserves exact 1Click BTC(OMNI) assets when listed', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithExactBtcOmniAsset),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: '1cs_v1:btc:native:coin',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '0.001',
          amountOutFormatted: '1.5',
          minAmountOut: '149250000',
          depositAddress: 'btc-deposit',
          quoteRequestRefundTo: 'bc1refund',
          quoteRequestRecipient: 'u1recipient',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final status = await provider.getStatus('btc-deposit');

    expect(status.pairText, 'BTC(OMNI) -> ZEC');
    expect(status.sellAmountText, '0.001 BTC(OMNI)');
    expect(status.status, SwapIntentStatus.processing);
  });

  test('quote rejects response with a mismatched swap type', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          swapType: 'EXACT_OUTPUT',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'quote')
            .having(
              (error) => error.message,
              'message',
              contains('did not match the requested route'),
            ),
      ),
    );
  });

  test(
    'quote rejects flex-input response for ZEC-to-external requests',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '1.5',
            amountOutFormatted: '105.25',
            minAmountOut: '104750000',
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1.5,
            sellAmountText: '1.5',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>()
              .having((error) => error.operation, 'operation', 'quote')
              .having(
                (error) => error.message,
                'message',
                contains('did not match the requested route'),
              ),
        ),
      );
    },
  );

  test('status accepts flex-input quote request echo', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:usdc.example',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '70',
          amountOutFormatted: '1',
          minAmountOut: '99500000',
          depositAddress: 'status-deposit',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final status = await provider.getStatus('status-deposit');

    expect(status.pairText, 'USDC -> ZEC');
    expect(status.sellAmountText, '70 USDC');
    expect(status.receiveEstimateText, '1 ZEC');
  });

  test(
    'quote accepts flex-input response for external assets into ZEC',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '1.5',
            amountOutFormatted: '0.021',
            minAmountOut: '2089500',
            depositAddress: '0xexternal-deposit',
            quoteRequestRefundTo: '0xrefund',
            quoteRequestRecipient: 'u1recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: 'u1recipient',
          refundAddress: '0xrefund',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['swapType'], 'FLEX_INPUT');
      expect(request.body?['amount'], '1500000');
      expect(quote.mode, SwapQuoteMode.flexInput);
      expect(quote.sellAmountText, '1.5 USDC');
      expect(quote.receiveEstimateText, '0.021 ZEC');
    },
  );

  test('quote accepts exact-input response without a swap type echo', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1.5',
          amountOutFormatted: '105.25',
          minAmountOut: '104750000',
          depositAddress: 't1deposit',
          includeQuoteRequestSwapType: false,
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        sellAmountText: '1.5',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
      ),
    );

    expect(quote.mode, SwapQuoteMode.exactInput);
  });

  test(
    'quote rejects response with mismatched quoteRequest amount echo',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountIn: '150000000',
            amountInFormatted: '1.5',
            amountOutFormatted: '105.25',
            minAmountOut: '104750000',
            depositAddress: 't1deposit',
            quoteRequestAmount: '100000000',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1.5,
            sellAmountText: '1.5',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>().having(
            (error) => error.message,
            'message',
            '1Click quote response did not match the requested amount',
          ),
        ),
      );
    },
  );

  test(
    'exact-input quote rejects response with a different provider amount',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountIn: '200000000',
            amountInFormatted: '2',
            amountOutFormatted: '140.5',
            minAmountOut: '139797500',
            depositAddress: 't1deposit',
            quoteRequestAmount: '150000000',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1.5,
            sellAmountText: '1.5',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>().having(
            (error) => error.message,
            'message',
            '1Click quote response did not match the requested amount',
          ),
        ),
      );
    },
  );

  test(
    'flex-input quote accepts response with a different provider amount',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountIn: '2000000',
            amountInFormatted: '2',
            amountOutFormatted: '0.03',
            minAmountOut: '2985000',
            depositAddress: '0xexternal-deposit',
            quoteRequestAmount: '1500000',
            quoteRequestRefundTo: '0xrefund',
            quoteRequestRecipient: 'u1recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: 'u1recipient',
          refundAddress: '0xrefund',
        ),
      );

      expect(transport.requests.last.body?['amount'], '1500000');
      expect(quote.mode, SwapQuoteMode.flexInput);
      expect(quote.sellAmountText, '2 USDC');
      expect(quote.sellAmountBaseUnits, BigInt.from(2000000));
    },
  );

  test(
    'flex-input quote rejects response with a different quote request amount',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountIn: '2000000',
            amountInFormatted: '2',
            amountOutFormatted: '0.03',
            minAmountOut: '2985000',
            depositAddress: '0xexternal-deposit',
            quoteRequestAmount: '2000000',
            quoteRequestRefundTo: '0xrefund',
            quoteRequestRecipient: 'u1recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.externalToZec,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1.5,
            sellAmountText: '1.5',
            destination: 'u1recipient',
            refundAddress: '0xrefund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>().having(
            (error) => error.message,
            'message',
            '1Click quote response did not match the requested amount',
          ),
        ),
      );
    },
  );

  test(
    'quote rejects mismatched sell formatted and base-unit amounts',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountIn: '150000000',
            amountInFormatted: '0.001',
            amountOutFormatted: '105.25',
            minAmountOut: '104750000',
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1.5,
            sellAmountText: '1.5',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>()
              .having((error) => error.operation, 'operation', 'quote')
              .having(
                (error) => error.message,
                'message',
                'Mismatched amountIn formatted and base-unit amounts',
              ),
        ),
      );
    },
  );

  test(
    'quote rejects mismatched receive formatted and base-unit amounts',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '1',
            amountOut: '105250000',
            amountOutFormatted: '1',
            minAmountOut: '995000',
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await expectLater(
        provider.quote(
          const SwapQuoteRequest(
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            sellAmount: 1,
            sellAmountText: '1',
            destination: '0xrecipient',
            refundAddress: 'u1refund',
          ),
        ),
        throwsA(
          isA<OneClickApiException>().having(
            (error) => error.message,
            'message',
            'Mismatched amountOut formatted and base-unit amounts',
          ),
        ),
      );
    },
  );

  test('quote rejects response with mismatched slippage echo', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1',
          amountOutFormatted: '70',
          minAmountOut: '69650000',
          depositAddress: 't1deposit',
          slippageTolerance: 500,
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1,
          sellAmountText: '1',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>().having(
          (error) => error.message,
          'message',
          '1Click quote response did not match the requested slippage',
        ),
      ),
    );
  });

  test('quote rejects response with mismatched address echo', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1',
          amountOutFormatted: '70',
          minAmountOut: '69650000',
          depositAddress: 't1deposit',
          quoteRequestRecipient: '0xattacker',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1,
          sellAmountText: '1',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>().having(
          (error) => error.message,
          'message',
          '1Click quote response did not match the requested addresses',
        ),
      ),
    );
  });

  test(
    'quote derives minimum receive from response slippage if min amount is missing',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithPrices('70')),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '1',
            amountOutFormatted: '100',
            slippageTolerance: 125,
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10),
      );

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1,
          sellAmountText: '1',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
          slippageBps: 125,
        ),
      );

      expect(quote.minimumReceiveText, '98.75 USDC');
      expect(quote.slippageToleranceText, '0.0125 ZEC (1.3%)');
    },
  );

  test(
    'quote posts exact-output payload using receive asset decimals',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            swapType: 'EXACT_OUTPUT',
            amountInFormatted: '1.5',
            amountOutFormatted: '105.25',
            minAmountIn: '148500000',
            minAmountOut: '104750000',
            refundFee: '10000',
            depositAddress: 'quote-placeholder-deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10),
      );

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          mode: SwapQuoteMode.exactOutput,
          amount: 105.25,
          amountText: '105.25',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
          dryRun: true,
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['dry'], isTrue);
      expect(request.body?['swapType'], 'EXACT_OUTPUT');
      expect(request.body?['slippageTolerance'], 100);
      expect(request.body?['amount'], '105250000');
      expect(request.body?['originAsset'], 'nep141:zec.omft.near');
      expect(request.body?['destinationAsset'], 'nep141:usdc.example');
      expect(quote.sellAmountText, '1.5 ZEC');
      expect(quote.receiveEstimateText, '105.25 USDC');
      expect(quote.mode, SwapQuoteMode.exactOutput);
      expect(quote.providerRefundInfo?.minimumDepositText, '1.485 ZEC');
      expect(quote.providerRefundInfo?.refundFeeText, '0.0001 ZEC');
    },
  );

  test('quote rejects amount text that exceeds token decimals', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          mode: SwapQuoteMode.exactOutput,
          amount: 105.1234567,
          amountText: '105.1234567',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>().having(
          (error) => error.message,
          'message',
          'Amount exceeds token precision',
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.method, 'GET');
  });

  test(
    'quote posts external-asset exact-output payload using ZEC receive decimals',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'EXACT_OUTPUT',
            amountInFormatted: '140.36',
            amountOutFormatted: '2',
            minAmountIn: '139650000',
            minAmountOut: '199000000',
            depositAddress: '0xexternal-deposit',
            quoteRequestRefundTo: '0xexternal-refund',
            quoteRequestRecipient: 'u1fresh-shielded-recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10),
      );

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          mode: SwapQuoteMode.exactOutput,
          amount: 2,
          amountText: '2',
          destination: 'u1fresh-shielded-recipient',
          refundAddress: '0xexternal-refund',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['dry'], isFalse);
      expect(request.body?['swapType'], 'EXACT_OUTPUT');
      expect(request.body?['amount'], '200000000');
      expect(request.body?['originAsset'], 'nep141:usdc.example');
      expect(request.body?['destinationAsset'], 'nep141:zec.omft.near');
      expect(request.body?['refundTo'], '0xexternal-refund');
      expect(request.body?['recipient'], 'u1fresh-shielded-recipient');
      expect(quote.pairText, 'USDC -> ZEC');
      expect(quote.sellAmountText, '140.36 USDC');
      expect(quote.receiveEstimateText, '2 ZEC');
      expect(quote.minimumReceiveText, '1.99 ZEC');
      expect(quote.providerRefundInfo?.minimumDepositText, '139.65 USDC');
    },
  );

  test('quote flips asset ids for external asset into ZEC', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.post(
        '/v0/quote',
        _quoteResponse(
          originAsset: 'nep141:usdc.example',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '140.35',
          amountOutFormatted: '2',
          minAmountOut: '199000000',
          depositAddress: '0xexternal-deposit',
          quoteRequestRefundTo: '0xexternal-refund',
          quoteRequestRecipient: 'u1fresh-shielded-recipient',
          status: null,
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10),
    );

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 140.35,
        sellAmountText: '140.35',
        destination: 'u1fresh-shielded-recipient',
        refundAddress: '0xexternal-refund',
      ),
    );
    final intent = await provider.startSwap(quote);

    final request = transport.requests.last;
    expect(request.body?['swapType'], 'FLEX_INPUT');
    expect(request.body?['amount'], '140350000');
    expect(request.body?['originAsset'], 'nep141:usdc.example');
    expect(request.body?['destinationAsset'], 'nep141:zec.omft.near');
    expect(request.body?['refundTo'], '0xexternal-refund');
    expect(request.body?['recipient'], 'u1fresh-shielded-recipient');
    expect(quote.pairText, 'USDC -> ZEC');
    expect(quote.receiveEstimateText, '2 ZEC');
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
    final provider = NearIntentsOneClickSwapAdapter(
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
        sellAmountText: '1.5',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
      ),
    );

    expect(
      transport.requests.last.body?['destinationAsset'],
      'nep141:base-usdc.example',
    );
  });

  test('token list exposes live chain variants with local icon keys', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithBscAssets),
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
    final provider = NearIntentsOneClickSwapAdapter(
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
    expect(baseUsdc.tokenIconAsset, 'assets/swap/tokens/usdc.png');
    expect(baseUsdc.chainIconAsset, 'assets/swap/chains/base.png');

    final bscUsdc = supported.singleWhere(
      (asset) => asset.symbol == 'USDC' && asset.chainTicker == 'bsc',
    );
    expect(bscUsdc.chainLabel, 'Binance Smart Chain');
    expect(bscUsdc.tokenIconAsset, 'assets/swap/tokens/usdc.png');
    expect(bscUsdc.chainIconKey, 'bsc');
    expect(bscUsdc.chainIconAsset, 'assets/swap/tokens/bnb.png');

    final bnb = supported.singleWhere(
      (asset) => asset.symbol == 'BNB' && asset.chainTicker == 'bsc',
    );
    expect(bnb.displayName, 'BNB');
    expect(bnb.tokenIconAsset, 'assets/swap/tokens/bnb.png');
    expect(bnb.chainIconAsset, 'assets/swap/tokens/bnb.png');

    await provider.quote(
      SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: baseUsdc,
        sellAmount: 1.5,
        sellAmountText: '1.5',
        destination: '0xrecipient',
        refundAddress: 'u1refund',
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
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final initial = await provider.loadPricingSnapshot();
    final refreshed = await provider.loadPricingSnapshot(forceRefresh: true);

    final initialUsdc = initial.supportedExternalAssets.singleWhere(
      (asset) => asset.hasSameMarketAs(SwapAsset.usdc),
    );
    final refreshedUsdc = refreshed.supportedExternalAssets.singleWhere(
      (asset) => asset.hasSameMarketAs(SwapAsset.usdc),
    );
    expect(initial.externalPerZec[initialUsdc], closeTo(540.62, 0.001));
    expect(refreshed.externalPerZec[refreshedUsdc], closeTo(541.10, 0.001));
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
            quoteRequestRecipient: 'bc1recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10),
      );

      final supported = await provider.listSupportedExternalAssets();
      expect(
        supported,
        containsAll([
          isA<SwapAsset>().having(
            (asset) => asset.hasSameMarketAs(SwapAsset.usdc),
            'USDC market',
            isTrue,
          ),
          isA<SwapAsset>().having(
            (asset) => asset.hasSameMarketAs(SwapAsset.btc),
            'BTC market',
            isTrue,
          ),
        ]),
      );

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.btc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: 'bc1recipient',
          refundAddress: 'u1refund',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['originAsset'], 'nep141:zec.omft.near');
      expect(request.body?['destinationAsset'], 'nep141:btc.omft.near');
      expect(quote.pairText, 'ZEC -> BTC');
      expect(quote.receiveEstimateText, '0.00096 BTC');
    },
  );

  test('supported assets are prioritized without picker grouping', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithAdditionalAssets),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    final supported = await provider.listSupportedExternalAssets();

    expect(supported.map((asset) => '${asset.symbol}:${asset.chainTicker}'), [
      'USDC:eth',
      'BTC:btc',
      'SOL:sol',
      'NEAR:near',
      'USDC:base',
      'USDC:near',
    ]);
  });

  test('representative live token icon mappings resolve to bundled images', () {
    final assets = [
      SwapAsset.live(
        assetId: 'nep141:aptos.omft.near',
        symbol: 'APT',
        blockchain: 'aptos',
        decimals: 8,
      ),
      SwapAsset.live(
        assetId: 'nep141:avax.omft.near',
        symbol: 'AVAX',
        blockchain: 'avax',
        decimals: 18,
      ),
      SwapAsset.live(
        assetId: 'nep141:bch.omft.near',
        symbol: 'BCH',
        blockchain: 'bch',
        decimals: 8,
      ),
      SwapAsset.live(
        assetId:
            'nep141:eth-0x6b175474e89094c44da98b954eedeac495271d0f.omft.near',
        symbol: 'DAI',
        blockchain: 'eth',
        decimals: 18,
      ),
      SwapAsset.live(
        assetId: 'nep141:ltc.omft.near',
        symbol: 'LTC',
        blockchain: 'ltc',
        decimals: 8,
      ),
      SwapAsset.live(
        assetId: 'nep245:v2_1.omni.hot.tg:10_11111111111111111111',
        symbol: 'ETH',
        blockchain: 'op',
        decimals: 18,
      ),
      SwapAsset.live(
        assetId: 'nep141:sui.omft.near',
        symbol: 'SUI',
        blockchain: 'sui',
        decimals: 9,
      ),
      SwapAsset.live(
        assetId: 'nep245:v2_1.omni.hot.tg:1117_',
        symbol: 'TON',
        blockchain: 'ton',
        decimals: 9,
      ),
      SwapAsset.live(
        assetId: 'nep245:v2_1.omni.hot.tg:1100_111',
        symbol: 'XLM',
        blockchain: 'stellar',
        decimals: 7,
      ),
      SwapAsset.live(
        assetId:
            'nep141:eth-0x68749665ff8d2d112fa859aa293f07a622782f38.omft.near',
        symbol: 'XAUT',
        blockchain: 'eth',
        decimals: 6,
      ),
      SwapAsset.live(
        assetId: 'nep245:v2_1.omni.hot.tg:143_usdt0',
        symbol: 'USDT0',
        blockchain: 'monad',
        decimals: 6,
      ),
      SwapAsset.live(
        assetId: 'nep141:base-gtusdcp.omft.near',
        symbol: 'gtUSDCp',
        blockchain: 'base',
        decimals: 18,
      ),
      SwapAsset.live(
        assetId: 'nep141:eth-hemibtc.omft.near',
        symbol: 'hemiBTC',
        blockchain: 'eth',
        decimals: 8,
      ),
      SwapAsset.live(
        assetId: 'nep141:sol-kv-gtsolb.omft.near',
        symbol: 'kV-gtSOLb',
        blockchain: 'sol',
        decimals: 9,
      ),
      SwapAsset.live(
        assetId: 'nep141:btc.omft.near',
        symbol: 'BTC(OMNI)',
        blockchain: 'btc',
        decimals: 8,
      ),
      SwapAsset.live(
        assetId: 'nep141:cfi.consumer-fi.near',
        symbol: 'CFI',
        blockchain: 'near',
        decimals: 18,
      ),
      SwapAsset.live(
        assetId: 'nep245:v2_1.omni.hot.tg:56_3NNshCLCt8r8E7x9FoDuiwoNQWgp',
        symbol: 'EVAA',
        blockchain: 'bsc',
        decimals: 9,
      ),
      SwapAsset.live(
        assetId: 'nep141:itlx.intellex_xyz.near',
        symbol: 'ITLX',
        blockchain: 'near',
        decimals: 24,
      ),
    ];

    for (final asset in assets) {
      expect(
        File(asset.tokenIconAsset).existsSync(),
        isTrue,
        reason: '${asset.symbol} token icon should exist',
      );
      expect(
        File(asset.chainIconAsset).existsSync(),
        isTrue,
        reason: '${asset.symbol} ${asset.chainTicker} chain icon should exist',
      );
    }
  });

  test(
    'quote serializes 24-decimal NEAR amounts without range errors',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:wrap.near',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '0.01',
            amountOutFormatted: '0.0002',
            minAmountOut: '19900',
            depositAddress: 'near-deposit',
            quoteRequestRefundTo: 'rowan.near',
            quoteRequestRecipient: 'u1shielded-zec-recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.near,
          sellAmount: 0.01,
          sellAmountText: '0.01',
          destination: 'u1shielded-zec-recipient',
          refundAddress: 'rowan.near',
        ),
      );

      final request = transport.requests.last;
      expect(request.body?['amount'], '10000000000000000000000');
      expect(request.body?['originAsset'], 'nep141:wrap.near');
      expect(request.body?['destinationAsset'], 'nep141:zec.omft.near');
      expect(quote.pairText, 'NEAR -> ZEC');
    },
  );

  test(
    'quote keeps original decimal text for exact-input base units',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:wrap.near',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '0.123456789012345678901234',
            amountOutFormatted: '0.0002',
            minAmountOut: '19900',
            depositAddress: 'near-deposit',
            quoteRequestRefundTo: 'rowan.near',
            quoteRequestRecipient: 'u1shielded-zec-recipient',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.near,
          sellAmount: 0.12345678901234568,
          sellAmountText: '0.123456789012345678901234',
          destination: 'u1shielded-zec-recipient',
          refundAddress: 'rowan.near',
        ),
      );

      expect(
        transport.requests.last.body?['amount'],
        '123456789012345678901234',
      );
    },
  );

  test(
    'token list preserves exact asset id variants for the same market',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokensWithDuplicateEthUsdc),
        _FakeResponse.post(
          '/v0/quote',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:eth-usdc.secondary',
            amountInFormatted: '1.5',
            amountOutFormatted: '105.25',
            minAmountOut: '104750000',
            depositAddress: 't1deposit',
            status: null,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final supported = await provider.listSupportedExternalAssets();
      final ethUsdcVariants = [
        for (final asset in supported)
          if (asset.symbol == 'USDC' && asset.chainTicker == 'eth') asset,
      ];

      expect(ethUsdcVariants, hasLength(2));
      expect(
        ethUsdcVariants.map((asset) => asset.assetId),
        unorderedEquals(['nep141:usdc.example', 'nep141:eth-usdc.secondary']),
      );
      expect(ethUsdcVariants.first, isNot(ethUsdcVariants.last));
      final secondaryEthUsdc = ethUsdcVariants.singleWhere(
        (asset) => asset.assetId == 'nep141:eth-usdc.secondary',
      );

      await provider.quote(
        SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: secondaryEthUsdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      );

      expect(
        transport.requests.last.body?['destinationAsset'],
        'nep141:eth-usdc.secondary',
      );
    },
  );

  test(
    'status uses deposit memo and maps 1Click success to complete',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:usdc.example',
            destinationAsset: 'nep141:zec.omft.near',
            swapType: 'FLEX_INPUT',
            amountInFormatted: '140.35',
            amountOutFormatted: '2',
            minAmountOut: '199000000',
            depositAddress: '0xexternal-deposit',
            depositMemo: '123',
            status: 'SUCCESS',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

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
      expect(status.status, SwapIntentStatus.complete);
      expect(status.nextAction, 'Swap complete');
    },
  );

  test(
    'status accepts live response shape with top-level correlation id',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '0.01',
            amountOutFormatted: '5.249679',
            minAmountOut: '5197182',
            depositAddress: 't1live-deposit',
            status: 'PENDING_DEPOSIT',
            includeNestedCorrelationId: false,
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10, 2),
      );

      final status = await provider.getStatus('t1live-deposit');

      expect(status.id, 't1live-deposit');
      expect(status.status, SwapIntentStatus.awaitingDeposit);
      expect(status.providerStatusRaw, 'PENDING_DEPOSIT');
      expect(status.depositInstruction.address, 't1live-deposit');
    },
  );

  test(
    'unknown 1Click status is exposed instead of hidden as processing',
    () async {
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
            depositAddress: 't1deposit',
            status: 'AWAITING_SOLVER',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final status = await provider.getStatus('t1deposit');

      expect(status.status, SwapIntentStatus.providerStatusUnknown);
      expect(status.providerStatusRaw, 'AWAITING_SOLVER');
      expect(
        status.nextAction,
        'Provider returned a status this wallet does not recognize',
      );
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
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

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
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    await expectLater(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
        ),
      ),
      throwsA(
        isA<OneClickApiException>()
            .having((error) => error.operation, 'operation', 'quote')
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.providerMessage,
              'providerMessage',
              'jwt missing',
            ),
      ),
    );
  });

  test('quote preserves operation when a requested asset is unsupported', () {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', [_tokens.first]),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    expect(
      provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: 1.5,
          sellAmountText: '1.5',
          destination: '0xrecipient',
          refundAddress: 'u1refund',
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
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

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

  test('status rejects ambiguous 1Click ticker fallback', () {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithNearUsdcFirst),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: '1cs_v1:usdc:native:coin',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '12',
          amountOutFormatted: '1',
          minAmountOut: '99500000',
          depositAddress: 'ambiguous-deposit',
          quoteRequestRefundTo: '0xrefund',
          quoteRequestRecipient: 'u1recipient',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    expect(
      provider.getStatus('ambiguous-deposit'),
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

  test('status rejects duplicate 1Click ticker fallback market variants', () {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokensWithDuplicateEthUsdc),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: '1cs_v1:usdc:native:coin',
          destinationAsset: 'nep141:zec.omft.near',
          swapType: 'FLEX_INPUT',
          amountInFormatted: '12',
          amountOutFormatted: '1',
          minAmountOut: '99500000',
          depositAddress: 'duplicate-market-deposit',
          quoteRequestRefundTo: '0xrefund',
          quoteRequestRecipient: 'u1recipient',
          status: 'PROCESSING',
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(transport: transport);

    expect(
      provider.getStatus('duplicate-market-deposit'),
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

  test(
    'status derives minimum receive from swap details slippage when min amount is missing',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '1',
            amountOutFormatted: '100',
            slippageTolerance: 100,
            depositAddress: 'status-deposit',
            status: 'PROCESSING',
            swapDetails: {'slippage': 200},
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final status = await provider.getStatus('status-deposit');

      expect(status.minimumReceiveText, '98 USDC');
      expect(status.slippageToleranceText, '0.02 ZEC (2.0%)');
    },
  );

  test(
    'status reports unavailable minimum receive when min amount and slippage are missing',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountInFormatted: '1',
            amountOutFormatted: '100',
            slippageTolerance: null,
            depositAddress: 'status-deposit',
            status: 'PROCESSING',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(transport: transport);

      final status = await provider.getStatus('status-deposit');

      expect(status.minimumReceiveText, 'Not reported');
      expect(status.slippageToleranceText, 'Not reported');
    },
  );

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
              swapType: scenario.direction.sendsZec
                  ? 'EXACT_INPUT'
                  : 'FLEX_INPUT',
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
        final provider = NearIntentsOneClickSwapAdapter(
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

  test('captures NEAR Intents hashes from status swap details', () async {
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
          depositAddress: 'status-deposit',
          status: 'PROCESSING',
          swapDetails: {
            'intentHashes': ['intent-hash-1'],
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10, 2),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.nearIntentHash, 'intent-hash-1');
  });

  test('captures provider refund amounts from status swap details', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          swapType: 'EXACT_OUTPUT',
          amountInFormatted: '1.5',
          amountOutFormatted: '70',
          minAmountIn: '148500000',
          minAmountOut: '69650000',
          depositAddress: 'status-deposit',
          status: 'REFUNDED',
          swapDetails: {
            'depositedAmountFormatted': '1.5',
            'refundedAmountFormatted': '0.01',
            'refundFee': '47000',
            'refundReason': 'UNUSED_INPUT',
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10, 2),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.providerRefundInfo?.minimumDepositText, '1.485 ZEC');
    expect(status.providerRefundInfo?.refundFeeText, '0.00047 ZEC');
    expect(status.providerRefundInfo?.depositedAmountText, '1.5 ZEC');
    expect(status.providerRefundInfo?.refundedAmountText, '0.01 ZEC');
    expect(status.providerRefundInfo?.refundReason, 'UNUSED_INPUT');
  });

  test('computes refunded total fees from status amounts', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '1.5',
          amountOutFormatted: '70',
          minAmountOut: '69650000',
          depositAddress: 'status-deposit',
          status: 'REFUNDED',
          swapDetails: {
            'depositedAmountFormatted': '1.5',
            'refundedAmountFormatted': '1.49953',
            'refundFee': '47000',
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 7, 10, 2),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.totalFeesText, '0.00047 ZEC');
  });

  test(
    'uses status details for actual amounts fees and realised slippage',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            amountIn: '200000',
            amountInFormatted: '0.002',
            amountOut: '1143483',
            amountOutFormatted: '1.143483',
            minAmountOut: '1137765',
            depositAddress: 'status-deposit',
            status: 'SUCCESS',
            appFees: const [
              {'recipient': 'vizor.near', 'fee': 67},
            ],
            swapDetails: {
              'amountIn': '200000',
              'amountInFormatted': '0.002',
              'amountOut': '1142725',
              'amountOutFormatted': '1.142725',
              'slippage': 7,
            },
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 27, 7, 25),
      );

      final status = await provider.getStatus('status-deposit');

      expect(status.status, SwapIntentStatus.complete);
      expect(status.sellAmountText, '0.002 ZEC');
      expect(status.receiveEstimateText, '1.142725 USDC');
      expect(status.totalFeesText, '0.0000134 ZEC');
      expect(status.realisedSlippageText, '0.000758 USDC (0.07%)');
    },
  );

  test('uses sell-asset delta for exact-output realised slippage', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          swapType: 'EXACT_OUTPUT',
          amountIn: '200000',
          amountInFormatted: '0.002',
          amountOut: '1200000',
          amountOutFormatted: '1.2',
          minAmountIn: '198000',
          minAmountOut: '1200000',
          depositAddress: 'status-deposit',
          status: 'SUCCESS',
          swapDetails: {
            'amountIn': '201000',
            'amountInFormatted': '0.00201',
            'amountOut': '1200000',
            'amountOutFormatted': '1.2',
            'slippage': '5',
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 27, 7, 25),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.sellAmountText, '0.00201 ZEC');
    expect(status.receiveEstimateText, '1.2 USDC');
    expect(status.realisedSlippageText, '0.00001 ZEC (0.05%)');
  });

  test(
    'uses base-unit precision for rounded ZEC realised slippage amounts',
    () async {
      final transport = _FakeOneClickTransport([
        _FakeResponse.get('/v0/tokens', _tokens),
        _FakeResponse.get(
          '/v0/status',
          _quoteResponse(
            originAsset: 'nep141:zec.omft.near',
            destinationAsset: 'nep141:usdc.example',
            swapType: 'EXACT_OUTPUT',
            amountIn: '189900',
            amountInFormatted: '0.0019',
            amountOut: '1200000',
            amountOutFormatted: '1.2',
            minAmountIn: '189000',
            minAmountOut: '1200000',
            depositAddress: 'status-deposit',
            status: 'SUCCESS',
            swapDetails: {
              'amountIn': '190185',
              'amountInFormatted': '0.0019',
              'amountOut': '1200000',
              'amountOutFormatted': '1.2',
              'slippage': '15',
            },
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 27, 7, 25),
      );

      final status = await provider.getStatus('status-deposit');

      expect(status.realisedSlippageText, '0.00000285 ZEC (0.15%)');
    },
  );

  test('uses base-unit precision for rounded ZEC app fees', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountIn: '200000',
          amountInFormatted: '0.0019',
          amountOut: '1200000',
          amountOutFormatted: '1.2',
          minAmountOut: '1194000',
          depositAddress: 'status-deposit',
          status: 'SUCCESS',
          appFees: const [
            {'recipient': 'vizor.near', 'fee': 67},
          ],
          swapDetails: {
            'amountIn': '200000',
            'amountInFormatted': '0.0019',
            'amountOut': '1200000',
            'amountOutFormatted': '1.2',
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 27, 7, 25),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.totalFeesText, '0.0000134 ZEC');
  });

  test('uses base-unit precision for refunded total fees', () async {
    final transport = _FakeOneClickTransport([
      _FakeResponse.get('/v0/tokens', _tokens),
      _FakeResponse.get(
        '/v0/status',
        _quoteResponse(
          originAsset: 'nep141:zec.omft.near',
          destinationAsset: 'nep141:usdc.example',
          amountInFormatted: '0.0015',
          amountOutFormatted: '1.2',
          minAmountOut: '1194000',
          depositAddress: 'status-deposit',
          status: 'REFUNDED',
          swapDetails: {
            'depositedAmount': '150000',
            'depositedAmountFormatted': '0.0015',
            'refundedAmount': '149953',
            'refundedAmountFormatted': '0.0015',
          },
        ),
      ),
    ]);
    final provider = NearIntentsOneClickSwapAdapter(
      transport: transport,
      now: () => DateTime.utc(2026, 5, 27, 7, 25),
    );

    final status = await provider.getStatus('status-deposit');

    expect(status.totalFeesText, '0.00000047 ZEC');
  });

  test(
    'captures snake-case NEAR Intents intent hashes from status swap details',
    () async {
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
            depositAddress: 'status-deposit',
            status: 'PROCESSING',
            swapDetails: {
              'intent_hashes': ['intent-hash-snake'],
            },
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10, 2),
      );

      final status = await provider.getStatus('status-deposit');

      expect(status.nearIntentHash, 'intent-hash-snake');
    },
  );

  test(
    'captures origin and destination transaction hashes from status details',
    () async {
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
            depositAddress: 'status-deposit',
            status: 'PROCESSING',
            swapDetails: {
              'intentHashes': ['intent-hash-1'],
              'originChainTxHashes': [
                {'hash': 'origin-chain-tx-hash'},
              ],
              'destinationChainTxHashes': [
                {'hash': 'destination-chain-tx-hash'},
              ],
            },
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 10, 2),
      );

      final status = await provider.getStatus('status-deposit');

      expect(status.nearIntentHash, 'intent-hash-1');
      expect(status.originChainTxHash, 'origin-chain-tx-hash');
      expect(status.destinationChainTxHash, 'destination-chain-tx-hash');
    },
  );

  test(
    'pending deposit status keeps provider status after the deposit deadline',
    () async {
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
            quoteDeadline: '2026-05-10T12:00:00Z',
            status: 'PENDING_DEPOSIT',
          ),
        ),
      ]);
      final provider = NearIntentsOneClickSwapAdapter(
        transport: transport,
        now: () => DateTime.utc(2026, 5, 7, 12, 1),
      );

      final status = await provider.getStatus('expired-deposit');

      expect(status.status, SwapIntentStatus.awaitingDeposit);
      expect(status.nextAction, 'Send ZEC to the one-time deposit address');
      expect(status.depositInstruction.deadline, DateTime.utc(2026, 5, 7, 12));
    },
  );
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

const _tokensWithBscAssets = [
  ..._tokensWithNearUsdcFirst,
  {
    'assetId': 'nep245:v2_1.omni.hot.tg:56_11111111111111111111',
    'decimals': 18,
    'blockchain': 'bsc',
    'symbol': 'BNB',
  },
  {
    'assetId': 'nep245:v2_1.omni.hot.tg:56_2w93GqMcEmQFDru84j3HZZWt557r',
    'decimals': 6,
    'blockchain': 'bsc',
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

const _tokensWithExactBtcOmniAsset = [
  ..._tokensWithAdditionalAssets,
  {
    'assetId': '1cs_v1:btc:native:coin',
    'decimals': 8,
    'blockchain': 'btc',
    'symbol': 'BTC(OMNI)',
  },
];

const _tokensWithDuplicateEthUsdc = [
  ..._tokens,
  {
    'assetId': 'nep141:eth-usdc.secondary',
    'decimals': 6,
    'blockchain': 'eth',
    'symbol': 'USDC',
  },
];

List<Map<String, Object?>> _tokensWithPrices(
  String zecPrice, {
  String usdcPrice = '1',
}) {
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
      'price': usdcPrice,
    },
  ];
}

Map<String, Object?> _quoteResponse({
  required String originAsset,
  required String destinationAsset,
  String swapType = 'EXACT_INPUT',
  String? amountIn,
  required String amountInFormatted,
  String? amountOut,
  required String amountOutFormatted,
  String? minAmountOut,
  required String depositAddress,
  required String? status,
  String? depositMemo,
  String? minAmountIn,
  List<Map<String, Object?>> appFees = const [],
  bool includeNestedCorrelationId = true,
  String? refundFee,
  String quoteRequestDeadline = '2026-05-07T12:00:00Z',
  String quoteDeadline = '2026-05-07T12:00:00Z',
  String timeWhenInactive = '2026-05-07T10:08:00Z',
  int? slippageTolerance = 100,
  bool includeQuoteRequestSwapType = true,
  String? quoteRequestSwapType,
  String? quoteRequestAmount,
  String quoteRequestRefundTo = 'u1refund',
  String quoteRequestRecipient = '0xrecipient',
  Map<String, Object?>? swapDetails,
}) {
  final resolvedAmountIn =
      amountIn ?? _testBaseUnitsForAsset(amountInFormatted, originAsset);
  final resolvedAmountOut =
      amountOut ?? _testBaseUnitsForAsset(amountOutFormatted, destinationAsset);
  final resolvedQuoteRequestAmount = swapType == 'EXACT_OUTPUT'
      ? resolvedAmountOut
      : resolvedAmountIn;
  final quote = {
    if (includeNestedCorrelationId) 'correlationId': 'quote-1',
    'timestamp': '2026-05-07T10:00:00Z',
    'signature': 'quote-signature',
    'quoteRequest': {
      'dry': false,
      if (includeQuoteRequestSwapType)
        'swapType': quoteRequestSwapType ?? swapType,
      'slippageTolerance': ?slippageTolerance,
      'originAsset': originAsset,
      'depositType': 'ORIGIN_CHAIN',
      'destinationAsset': destinationAsset,
      'amount': quoteRequestAmount ?? resolvedQuoteRequestAmount,
      'refundTo': quoteRequestRefundTo,
      'refundType': 'ORIGIN_CHAIN',
      'recipient': quoteRequestRecipient,
      'recipientType': 'DESTINATION_CHAIN',
      'deadline': quoteRequestDeadline,
      'appFees': appFees,
    },
    'quote': {
      'amountIn': resolvedAmountIn,
      'amountInFormatted': amountInFormatted,
      'minAmountIn': ?minAmountIn,
      'amountOut': resolvedAmountOut,
      'amountOutFormatted': amountOutFormatted,
      'minAmountOut': ?minAmountOut,
      'timeEstimate': 120,
      'depositAddress': depositAddress,
      'depositMemo': depositMemo,
      'deadline': quoteDeadline,
      'timeWhenInactive': timeWhenInactive,
      'refundFee': ?refundFee,
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
    'swapDetails': swapDetails ?? <String, Object?>{},
  };
}

String _testBaseUnitsForAsset(String amount, String assetId) {
  return _testDecimalStringToBaseUnits(amount, _testDecimalsForAsset(assetId));
}

int _testDecimalsForAsset(String assetId) {
  if (assetId.contains('wrap.near')) return 24;
  if (assetId.contains('usdc')) return 6;
  if (assetId.contains('zec')) return 8;
  if (assetId.contains('btc')) return 8;
  return 8;
}

String _testDecimalStringToBaseUnits(String amount, int decimals) {
  final parts = amount.trim().split('.');
  if (parts.length > 2) {
    throw ArgumentError.value(amount, 'amount', 'Invalid decimal amount');
  }
  final whole = parts.first.isEmpty ? '0' : parts.first;
  final fraction = parts.length == 2 ? parts.last : '';
  if (fraction.length > decimals) {
    throw ArgumentError.value(amount, 'amount', 'Too many decimal places');
  }
  final raw = '$whole${fraction.padRight(decimals, '0')}';
  return BigInt.parse(raw).toString();
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
    expectedStatus: SwapIntentStatus.complete,
    expectedNextAction: 'Swap complete',
    expectedPairText: 'USDC -> ZEC',
  ),
  _StatusScenario(
    oneClickStatus: 'REFUNDED',
    direction: SwapDirection.zecToExternal,
    expectedStatus: SwapIntentStatus.refunded,
    expectedNextAction: 'Refund sent to your refund address',
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
