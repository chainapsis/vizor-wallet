import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/features/pay/models/payment_request_resolution.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';

const _bitcoinAddress = '1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo';
const _evmRecipient = '0x1111111111111111111111111111111111111111';
const _baseUsdc = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _otherContract = '0x2222222222222222222222222222222222222222';
const _solanaRecipient = 'mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN';
const _solanaUsdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

void main() {
  group('indicative ZEC cost', () {
    test('uses the resolved asset rate and preserves the requested amount', () {
      final usdc = _asset(contract: _baseUsdc);
      final resolution = resolveCrossChainPaymentRequest(
        _decode(_erc20Json()),
        [usdc],
      );
      expect(resolution.estimateZecAmount({usdc: 100}), 0.025);
      expect(resolution.estimateZecAmount({usdc: 200}), 0.0125);
      expect(resolution.amountText, '2.5');
    });

    test('missing or invalid prices cannot produce a fallback estimate', () {
      final usdc = _asset(contract: _baseUsdc);
      final resolution = resolveCrossChainPaymentRequest(
        _decode(_erc20Json()),
        [usdc],
      );
      expect(resolution.estimateZecAmount({}), isNull);
      expect(
        resolution.estimateZecAmount({
          _asset(id: 'other-usdc', contract: _otherContract): 100,
        }),
        isNull,
      );
      for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
        expect(resolution.estimateZecAmount({usdc: rate}), isNull);
      }
      expect(
        PaymentRequestResolution(asset: usdc).estimateZecAmount({usdc: 100}),
        isNull,
      );
      expect(
        resolveCrossChainPaymentRequest(
          _decode(_erc20Json()),
          [],
        ).estimateZecAmount({usdc: 100}),
        isNull,
      );
    });
  });

  group('parser JSON contract', () {
    test('preserves Bitcoin request identity, metadata, and one satoshi', () {
      const rawUri =
          'bitcoin:$_bitcoinAddress?amount=0.00000001&label=Coffee%20shop&message=Order%20123';
      final request = _decode(
        _utxoJson(
          amount: '0.00000001',
          label: 'Coffee shop',
          message: 'Order 123',
        ),
        rawUri: rawUri,
      );
      final resolution = resolveCrossChainPaymentRequest(request, [
        _asset(symbol: 'BTC', chain: 'btc', decimals: 8),
      ]);

      expect(request.id, 'request-1');
      expect(request.rawUri, rawUri);
      expect(request.address, _bitcoinAddress);
      expect(request.chain, 'btc');
      expect(request.isEvm, isFalse);
      expect(request.label, 'Coffee shop');
      expect(request.message, 'Order 123');
      expect(resolution.isReady, isTrue);
      expect(resolution.amountText, '0.00000001');
    });

    test('Litecoin stays on its own payment network', () {
      final request = _decode({
        ..._utxoJson(amount: '1.23456789'),
        'type': 'litecoin',
        'address': 'LT2KVaAy1ppRuxRgrS5RNU3vBsy7RibPeA',
      });
      final ltc = _asset(symbol: 'LTC', chain: 'ltc', decimals: 8);
      final resolution = resolveCrossChainPaymentRequest(request, [
        _asset(symbol: 'BTC', chain: 'btc', decimals: 8),
        ltc,
      ]);

      expect(request.chain, 'ltc');
      expect(resolution.asset, same(ltc));
      expect(resolution.amountText, '1.23456789');
    });

    test('ERC20 token contract never replaces the payment recipient', () {
      final request = _decode(_erc20Json());
      final usdc = _asset(contract: _baseUsdc);
      final resolution = resolveCrossChainPaymentRequest(request, [usdc]);

      expect(request.address, _evmRecipient);
      expect(request.contractAddress, _baseUsdc);
      expect(request.chainId, '8453');
      expect(request.isEvm, isTrue);
      expect(resolution.asset, same(usdc));
      expect(resolution.amountText, '2.5');
    });

    final malformed = <String, String>{
      'invalid JSON': '{',
      'non-object JSON': '[]',
      'null JSON': 'null',
      'unknown version': jsonEncode({..._nativeJson(), 'version': 2}),
      'unknown request type': jsonEncode({..._nativeJson(), 'type': 'unknown'}),
      'missing recipient': jsonEncode(
        {..._nativeJson()}..remove('recipient_address'),
      ),
      'numeric amount': jsonEncode({..._utxoJson(), 'amount': 1.25}),
      'non-hex atomic amount': jsonEncode({
        ..._nativeJson(),
        'value_hex': '2500000',
      }),
      'ERC20 missing contract': jsonEncode(
        {..._erc20Json()}..remove('token_contract_address'),
      ),
      'ERC20 null contract': jsonEncode({
        ..._erc20Json(),
        'token_contract_address': null,
      }),
      'ERC20 missing amount': jsonEncode(
        {..._erc20Json()}..remove('value_hex'),
      ),
      'ERC20 null amount': jsonEncode({..._erc20Json(), 'value_hex': null}),
      'native request with token contract': jsonEncode({
        ..._nativeJson(),
        'token_contract_address': _baseUsdc,
      }),
    };
    for (final entry in malformed.entries) {
      test('rejects ${entry.key} without accepting altered payment terms', () {
        expect(
          () => CrossChainPaymentRequest.fromParserJson(
            id: 'request-1',
            rawUri: 'ethereum:private-request',
            json: entry.value,
          ),
          throwsA(isA<CrossChainPaymentParseException>()),
        );
      });
    }
  });

  group('exact amounts', () {
    // The upstream EIP-681 JSON serializes this atomic integer (> 2^53) as hex.
    const cases = <int, String>{
      6: '9007199254.740993',
      8: '90071992.54740993',
      9: '9007199.254740993',
      18: '0.009007199254740993',
    };
    for (final entry in cases.entries) {
      test('retains every atomic unit with ${entry.key} decimals', () {
        final request = _decode({
          ..._erc20Json(),
          'token_contract_address': _otherContract,
          'value_hex': '0x20000000000001',
        });
        final resolution = resolveCrossChainPaymentRequest(request, [
          _asset(symbol: 'TKN', decimals: entry.key, contract: _otherContract),
        ]);

        expect(resolution.isReady, isTrue);
        expect(resolution.amountText, entry.value);
      });
    }

    test('native EVM and Solana preserve their smallest units', () {
      final native = resolveCrossChainPaymentRequest(
        _decode({..._nativeJson(), 'value_hex': '0x1'}),
        [_asset(symbol: 'ETH', decimals: 18)],
      );
      final solana = resolveCrossChainPaymentRequest(
        _decode(_solanaJson(amount: '0.000000001')),
        [_asset(symbol: 'SOL', chain: 'sol', decimals: 9)],
      );

      expect(native.amountText, '0.000000000000000001');
      expect(solana.amountText, '0.000000001');
    });

    test('keeps a 256-bit atomic integer exact', () {
      final amount = PaymentRequestAmount.atomicHex('0x${'f' * 64}');

      expect(
        amount!.forDecimals(0),
        '115792089237316195423570985008687907853269984665640564039457584007913129639935',
      );
      expect(
        () => PaymentRequestAmount.atomicHex('0x${'f' * 65}'),
        throwsA(isA<CrossChainPaymentParseException>()),
      );
    });

    test(
      'rejects excess SPL precision without rounding the payment amount',
      () {
        final resolution = resolveCrossChainPaymentRequest(
          _decode(_solanaJson(amount: '2.5000001', mint: _solanaUsdc)),
          [_asset(chain: 'sol', contract: _solanaUsdc)],
        );

        expect(resolution.isReady, isFalse);
        expect(resolution.asset, isNull);
        expect(resolution.amountText, isNull);
        expect(resolution.message, contains('decimal places'));
      },
    );

    test('allows lossless removal of trailing decimal zeros', () {
      final resolution = resolveCrossChainPaymentRequest(
        _decode(_solanaJson(amount: '2.5000000', mint: _solanaUsdc)),
        [_asset(chain: 'sol', contract: _solanaUsdc)],
      );

      expect(resolution.isReady, isTrue);
      expect(resolution.amountText, '2.5');
    });

    for (final entry in <String, Map<String, Object?>>{
      'zero atomic amount': {..._nativeJson(), 'value_hex': '0x0'},
      'zero display amount': _utxoJson(amount: '0.00000000'),
      'missing amount': _utxoJson(),
    }.entries) {
      test('${entry.key} leaves the amount for the user to enter', () {
        final resolution =
            resolveCrossChainPaymentRequest(_decode(entry.value), [
              _asset(symbol: 'ETH', decimals: 18),
              _asset(symbol: 'BTC', chain: 'btc', decimals: 8),
            ]);

        expect(resolution.asset, isNotNull);
        expect(resolution.amountText, isNull);
      });
    }

    test(
      'invalid amount syntax and unreasonable decimal scales are rejected',
      () {
        for (final text in ['', '-1', '1e6', '.5', '1.', 'NaN', '1' * 257]) {
          expect(
            () => PaymentRequestAmount.display(text),
            throwsA(isA<CrossChainPaymentParseException>()),
            reason: 'Invalid display amount: $text',
          );
        }
        for (final decimals in [-1, 256]) {
          expect(
            () => PaymentRequestAmount.atomicHex('0x1')!.forDecimals(decimals),
            throwsA(isA<CrossChainPaymentParseException>()),
          );
        }
      },
    );
  });

  group('network and asset resolution', () {
    test(
      'a request without chain or amount resolves the asset before editing',
      () {
        final request = _decode({
          ..._nativeJson(),
          'chain_id': null,
          'value_hex': null,
        });
        final eth = _asset(symbol: 'ETH', decimals: 18);
        final unresolved = resolveCrossChainPaymentRequest(request, [eth]);
        expect(unresolved.needsNetwork, isTrue);
        expect(unresolved.asset, isNull);
        expect(unresolved.amountText, isNull);
        expect(unresolved.message, contains('then enter an amount'));
        final resolved = resolveCrossChainPaymentRequest(request, [
          eth,
        ], selectedChain: 'base');
        expect(resolved.asset, same(eth));
        expect(resolved.amountText, isNull);
        expect(resolved.isReady, isTrue);
      },
    );

    test(
      'atomic token amounts use only the selected chain contract decimals',
      () {
        final request = _decode({..._erc20Json(), 'chain_id': null});
        final base = _asset(contract: _baseUsdc, decimals: 6);
        final ethereum = _asset(
          chain: 'eth',
          contract: _baseUsdc,
          decimals: 18,
        );
        final assets = [base, ethereum];
        final unresolved = resolveCrossChainPaymentRequest(request, assets);
        expect(unresolved.asset, isNull);
        expect(unresolved.amountText, isNull);
        final onBase = resolveCrossChainPaymentRequest(
          request,
          assets,
          selectedChain: 'base',
        );
        final onEthereum = resolveCrossChainPaymentRequest(
          request,
          assets,
          selectedChain: 'eth',
        );
        expect(onBase.asset, same(base));
        expect(onEthereum.asset, same(ethereum));
        expect(onBase.amountText, '2.5');
        expect(onEthereum.amountText, '0.0000000000025');
        expect(onBase.amountText, isNot(onEthereum.amountText));
      },
    );

    test('missing EVM chain requires an explicit supported selection', () {
      final request = _decode({..._nativeJson(), 'chain_id': null});
      final eth = _asset(symbol: 'ETH', chain: 'eth', decimals: 18);
      final baseEth = _asset(symbol: 'ETH', decimals: 18);
      final assets = [eth, baseEth];

      for (final selection in <String?>[null, 'btc']) {
        final unresolved = resolveCrossChainPaymentRequest(
          request,
          assets,
          selectedChain: selection,
        );
        expect(request.needsNetwork, isTrue);
        expect(unresolved.needsNetwork, isTrue);
        expect(unresolved.isReady, isFalse);
        expect(unresolved.asset, isNull);
      }
      final resolved = resolveCrossChainPaymentRequest(
        request,
        assets,
        selectedChain: 'base',
      );
      expect(resolved.asset, same(baseEth));
      expect(resolved.needsNetwork, isFalse);
      expect(resolved.isReady, isTrue);
    });

    test('an explicit chain cannot be replaced by the selected chain', () {
      final baseEth = _asset(symbol: 'ETH', decimals: 18);
      final resolution = resolveCrossChainPaymentRequest(
        _decode(_nativeJson()),
        [_asset(symbol: 'ETH', chain: 'eth', decimals: 18), baseEth],
        selectedChain: 'eth',
      );

      expect(resolution.asset, same(baseEth));
    });

    test(
      'an unsupported explicit chain cannot fall back to another network',
      () {
        final resolution = resolveCrossChainPaymentRequest(
          _decode({..._nativeJson(), 'chain_id': '999999'}),
          [_asset(symbol: 'ETH', decimals: 18)],
          selectedChain: 'base',
        );

        expect(resolution.isReady, isFalse);
        expect(resolution.asset, isNull);
        expect(resolution.needsNetwork, isFalse);
        expect(resolution.message, contains('network'));
      },
    );

    test(
      'matches EVM contracts without case sensitivity on the exact chain',
      () {
        final expected = _asset(contract: _baseUsdc.toLowerCase());
        final resolution =
            resolveCrossChainPaymentRequest(_decode(_erc20Json()), [
              _asset(chain: 'eth', contract: _baseUsdc),
              _asset(contract: _otherContract),
              expected,
            ]);

        expect(resolution.asset, same(expected));
      },
    );

    test('SPL mint matching is case sensitive', () {
      final request = _decode(_solanaJson(amount: '2.5', mint: _solanaUsdc));
      final differentMint = _asset(
        chain: 'sol',
        contract: 'e${_solanaUsdc.substring(1)}',
      );
      final expected = _asset(chain: 'sol', contract: _solanaUsdc);

      expect(
        resolveCrossChainPaymentRequest(request, [differentMint]).asset,
        isNull,
      );
      expect(
        resolveCrossChainPaymentRequest(request, [
          differentMint,
          expected,
        ]).asset,
        same(expected),
      );
    });

    test('persisted tokens still resolve by their exact contract or mint', () {
      for (final (request, asset) in [
        (_decode(_erc20Json()), _asset(contract: _baseUsdc)),
        (
          _decode(_solanaJson(amount: '2.5', mint: _solanaUsdc)),
          _asset(chain: 'sol', contract: _solanaUsdc),
        ),
      ]) {
        final restored = SwapAsset.fromPersistedJson(
          jsonDecode(jsonEncode(asset.toPersistedJson())),
        )!;
        final resolution = resolveCrossChainPaymentRequest(request, [restored]);
        expect(resolution.asset, same(restored));
        expect(resolution.amountText, '2.5');
      }
    });

    test('does not select another token merely because its symbol matches', () {
      final resolution =
          resolveCrossChainPaymentRequest(_decode(_erc20Json()), [
            _asset(contract: _otherContract),
            _asset(contract: '0x3333333333333333333333333333333333333333'),
          ]);

      expect(resolution.isReady, isFalse);
      expect(resolution.asset, isNull);
      expect(resolution.message, contains('not available'));
    });

    test('duplicate exact token matches stay unresolved', () {
      final resolution =
          resolveCrossChainPaymentRequest(_decode(_erc20Json()), [
            _asset(id: 'token-a', contract: _baseUsdc),
            _asset(id: 'token-b', contract: _baseUsdc),
          ]);

      expect(resolution.isReady, isFalse);
      expect(resolution.asset, isNull);
      expect(resolution.message, contains('More than one asset'));
    });

    test('a contract token named ETH cannot satisfy a native ETH request', () {
      final request = _decode(_nativeJson());
      final wrapped = _asset(
        symbol: 'ETH',
        decimals: 18,
        contract: _otherContract,
      );
      final native = _asset(symbol: 'ETH', decimals: 18);

      final restoredWrapped = SwapAsset.fromPersistedJson(
        jsonDecode(jsonEncode(wrapped.toPersistedJson())),
      )!;
      expect(
        resolveCrossChainPaymentRequest(request, [restoredWrapped]).asset,
        isNull,
      );
      expect(
        resolveCrossChainPaymentRequest(request, [wrapped, native]).asset,
        same(native),
      );
    });

    test('Optimism native requests select ETH instead of OP', () {
      final eth = _asset(symbol: 'ETH', chain: 'op', decimals: 18);
      final resolution = resolveCrossChainPaymentRequest(
        _decode({..._nativeJson(), 'chain_id': '10'}),
        [_asset(symbol: 'OP', chain: 'op', decimals: 18), eth],
      );

      expect(resolution.asset, same(eth));
    });

    test(
      'static preview assets without a live asset ID cannot be selected',
      () {
        final resolution = resolveCrossChainPaymentRequest(
          _decode({..._nativeJson(), 'chain_id': '1'}),
          [SwapAsset.eth],
        );

        expect(resolution.isReady, isFalse);
        expect(resolution.asset, isNull);
      },
    );
  });

  group('unsupported payment conditions', () {
    final unsupported = <String, Map<String, Object?>>{
      'Bitcoin testnet': {..._utxoJson(), 'network': 'testnet'},
      'Bitcoin regtest': {..._utxoJson(), 'network': 'regtest'},
      'ENS recipient': {..._nativeJson(), 'recipient_address': 'recipient.eth'},
      'ENS token contract': {
        ..._erc20Json(),
        'token_contract_address': 'token.eth',
      },
      'Solana reference': {
        ..._solanaJson(),
        'references': [_solanaRecipient],
      },
      'Solana memo': {..._solanaJson(), 'memo': 'order 123'},
      'Solana transaction': {
        'version': 1,
        'type': 'solana_transaction',
        'link': 'https://example.com/payment-request',
      },
      'arbitrary contract function': {
        'version': 1,
        'type': 'ethereum_unrecognised',
      },
      'native EVM gas limit': {..._nativeJson(), 'gas_limit_hex': '0x5208'},
      'native EVM gas price': {..._nativeJson(), 'gas_price_hex': '0x1'},
    };
    for (final entry in unsupported.entries) {
      test('${entry.key} stays a reviewable blocked request', () {
        final request = _decode(entry.value);
        final resolution = resolveCrossChainPaymentRequest(request, [
          _asset(symbol: 'BTC', chain: 'btc', decimals: 8),
          _asset(symbol: 'ETH', decimals: 18),
          _asset(symbol: 'SOL', chain: 'sol', decimals: 9),
          _asset(contract: _baseUsdc),
        ], selectedChain: 'base');

        expect(request.unsupportedReason, isNotNull);
        expect(resolution.message, request.unsupportedReason);
        expect(resolution.isReady, isFalse);
        expect(resolution.asset, isNull);
      });
    }
  });
}

CrossChainPaymentRequest _decode(
  Map<String, Object?> data, {
  String rawUri = 'ethereum:$_evmRecipient@8453',
}) => CrossChainPaymentRequest.fromParserJson(
  id: 'request-1',
  rawUri: rawUri,
  json: jsonEncode(data),
);

// Field names, nulls, and amount representation match the Rust parser's JSON v1.
Map<String, Object?> _utxoJson({
  String? amount,
  String? label,
  String? message,
}) => {
  'version': 1,
  'type': 'bitcoin',
  'address': _bitcoinAddress,
  'network': 'mainnet',
  'amount': amount,
  'label': label,
  'message': message,
};

Map<String, Object?> _nativeJson() => {
  'version': 1,
  'type': 'ethereum_native',
  'schema_prefix': 'ethereum',
  'has_pay': false,
  'chain_id': '8453',
  'recipient_address': _evmRecipient,
  'value_hex': '0xde0b6b3a7640000',
  'gas_limit_hex': null,
  'gas_price_hex': null,
};

Map<String, Object?> _erc20Json() => {
  'version': 1,
  'type': 'ethereum_erc20',
  'schema_prefix': 'ethereum',
  'has_pay': false,
  'chain_id': '8453',
  'token_contract_address': _baseUsdc,
  'recipient_address': _evmRecipient,
  'value_hex': '0x2625a0',
};

Map<String, Object?> _solanaJson({String? amount, String? mint}) => {
  'version': 1,
  'type': 'solana_transfer',
  'recipient': _solanaRecipient,
  'amount': amount,
  'spl_token': mint,
  'references': <String>[],
  'label': null,
  'message': null,
  'memo': null,
};

SwapAsset _asset({
  String? id,
  String symbol = 'USDC',
  String chain = 'base',
  int decimals = 6,
  String? contract,
}) => SwapAsset.live(
  assetId: id ?? '$chain:$symbol:${contract ?? 'native'}',
  symbol: symbol,
  blockchain: chain,
  decimals: decimals,
  contractAddress: contract,
);
