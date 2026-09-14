import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_scan/domain/address_input_policy.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';

const btc = '1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo';
const evm = '0x1111111111111111111111111111111111111111';
const contract = '0x2222222222222222222222222222222222222222';
const zec = 'u1testaddress';

Future<AddressInputResult> resolve(
  String input,
  AddressInputContext context, {
  AddressBookNetwork network = AddressBookNetwork.bitcoin,
  ZcashNetwork zcashNetwork = ZcashNetwork.mainnet,
  CrossChainPaymentRequest? request,
  Future<String?> Function(String, ZcashNetwork)? zcashValidator,
}) => resolveAddressInput(
  input,
  policy: AddressInputPolicy(
    context: context,
    network: network,
    zcashNetwork: zcashNetwork,
  ),
  validateZcashAddress: zcashValidator ?? (_, _) async => null,
  parseCrossChainRequest: (_) async =>
      request ?? (throw const FormatException()),
);

CrossChainPaymentRequest bitcoin(String uri, {String? unsupportedReason}) =>
    CrossChainPaymentRequest(
      id: 'test',
      rawUri: uri,
      address: btc,
      isEvm: false,
      chain: 'btc',
      unsupportedReason: unsupportedReason,
    );
CrossChainPaymentRequest ethereum(
  String uri, {
  String? chainId = '8453',
  bool token = false,
}) => CrossChainPaymentRequest(
  id: 'test',
  rawUri: uri,
  address: evm,
  isEvm: true,
  chainId: chainId,
  contractAddress: token ? contract : null,
);

void main() {
  for (final context in [
    AddressInputContext.pay,
    AddressInputContext.swapRecipient,
    AddressInputContext.swapRefund,
    AddressInputContext.contact,
  ]) {
    test(
      '$context accepts the eth address alias on selected EVM chains',
      () async {
        for (final network in [
          AddressBookNetwork.ethereum,
          AddressBookNetwork.base,
        ]) {
          for (final scheme in ['eth', 'ETH']) {
            final result = await resolve(
              '$scheme:$evm',
              context,
              network: network,
            );
            expect(result.kind, AddressInputResultKind.address);
            expect(result.address, evm);
          }
        }
      },
    );
    test(
      '$context does not discard terms or chain IDs from eth aliases',
      () async {
        for (final input in [
          'eth:$evm?value=1',
          'eth:$evm@11155111',
          'eth:$evm@8453',
          'eth:$contract/transfer?address=$evm&uint256=1',
          'eth:$evm#memo',
          'eth://$evm',
          'eth:invalid',
        ]) {
          expect(
            (await resolve(
              input,
              context,
              network: AddressBookNetwork.ethereum,
            )).kind,
            AddressInputResultKind.rejected,
            reason: input,
          );
        }
      },
    );
  }
  test(
    'eth aliases remain unavailable in Send and non-EVM address fields',
    () async {
      for (final context in AddressInputContext.values) {
        expect(
          (await resolve('eth:$evm', context)).kind,
          AddressInputResultKind.rejected,
        );
      }
    },
  );

  test('Send rejects another chain before invoking either parser', () async {
    final result = await resolveAddressInput(
      'ethereum:$evm',
      policy: const AddressInputPolicy(
        context: AddressInputContext.send,
        network: AddressBookNetwork.zcash,
        zcashNetwork: ZcashNetwork.mainnet,
      ),
      validateZcashAddress: (_, _) => throw StateError('must not validate'),
      parseCrossChainRequest: (_) => throw StateError('must not parse'),
    );
    expect(result.kind, AddressInputResultKind.rejected);
    expect(
      result.reason,
      'Only Zcash addresses and payment requests can be scanned here.',
    );
  });

  for (final context in [
    AddressInputContext.send,
    AddressInputContext.contact,
  ]) {
    test(
      '$context validates Zcash against the selected wallet network',
      () async {
        final calls = <ZcashNetwork>[];
        Future<String?> validate(String address, ZcashNetwork network) async {
          calls.add(network);
          return network == ZcashNetwork.testnet ? null : 'Wrong Zcash network';
        }

        for (final network in [ZcashNetwork.mainnet, ZcashNetwork.testnet]) {
          final result = await resolve(
            'zcash:utest1address',
            context,
            network: AddressBookNetwork.zcash,
            zcashNetwork: network,
            zcashValidator: validate,
          );
          expect(
            result.kind,
            network == ZcashNetwork.mainnet
                ? AddressInputResultKind.rejected
                : context == AddressInputContext.send
                ? AddressInputResultKind.paymentRequest
                : AddressInputResultKind.address,
          );
        }
        expect(calls, [ZcashNetwork.mainnet, ZcashNetwork.testnet]);
      },
    );
  }

  test('Send preserves supported Zcash payment terms', () async {
    final result = await resolve(
      'zcash:$zec?amount=1&message=hello',
      AddressInputContext.send,
    );
    expect(result.kind, AddressInputResultKind.paymentRequest);
    expect(result.zcashRequest!.primaryPayment.amount, '1');
  });

  for (final context in [
    AddressInputContext.pay,
    AddressInputContext.swapRecipient,
    AddressInputContext.swapRefund,
  ]) {
    for (final input in [zec, 'zcash:$zec?amount=1']) {
      test('$context rejects $input', () async {
        expect(
          (await resolve(input, context)).kind,
          AddressInputResultKind.rejected,
        );
      });
    }
  }

  test('Zcash-like prefix alone does not reject a NEAR account', () async {
    expect(
      (await resolve(
        't1example.near',
        AddressInputContext.pay,
        network: AddressBookNetwork.near,
      )).address,
      't1example.near',
    );
  });

  for (final workchain in ['0', '-1']) {
    test(
      'Raw TON workchain $workchain is an address, not a URI scheme',
      () async {
        final raw = '$workchain:${'1' * 64}';
        expect(
          (await resolve(
            raw,
            AddressInputContext.pay,
            network: AddressBookNetwork.ton,
          )).address,
          raw,
        );
      },
    );
  }

  for (final context in [
    AddressInputContext.pay,
    AddressInputContext.swapRecipient,
  ]) {
    test(
      '$context static fallback catalogue waits for live assets in the request card',
      () async {
        const uri = 'bitcoin:$btc?amount=1';
        final result = await resolveAddressInput(
          uri,
          policy: AddressInputPolicy(
            context: context,
            network: AddressBookNetwork.ethereum,
            zcashNetwork: ZcashNetwork.mainnet,
            assets: const [SwapAsset.btc, SwapAsset.eth, SwapAsset.usdc],
          ),
          validateZcashAddress: (_, _) async => null,
          parseCrossChainRequest: (_) async => bitcoin(uri),
        );
        expect(result.kind, AddressInputResultKind.paymentRequest);
      },
    );
  }

  test('Pay accepts a normal selected-chain address', () async {
    expect((await resolve(btc, AddressInputContext.pay)).address, btc);
  });

  for (final context in [
    AddressInputContext.pay,
    AddressInputContext.swapRecipient,
    AddressInputContext.swapRefund,
    AddressInputContext.contact,
  ]) {
    test('$context rejects Bitcoin testnet plain addresses', () async {
      expect(
        (await resolve('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn', context)).kind,
        AddressInputResultKind.rejected,
      );
    });
    test('$context never strips explicit testnet from a payment URI', () async {
      final uri = 'bitcoin:mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
      final result = await resolve(
        uri,
        context,
        request: bitcoin(
          uri,
          unsupportedReason: 'Test networks are unsupported',
        ),
      );
      expect(result.kind, AddressInputResultKind.rejected);
      expect(result.address, isNull);
    });
    test('$context rejects unsupported explicit EVM chain', () async {
      final uri = 'ethereum:$evm@11155111';
      expect(
        (await resolve(
          uri,
          context,
          network: AddressBookNetwork.ethereum,
          request: ethereum(uri, chainId: '11155111'),
        )).kind,
        AddressInputResultKind.rejected,
      );
    });
  }

  test('Pay keeps chain-less EVM requests for network selection', () async {
    final uri = 'ethereum:$evm?value=1';
    final result = await resolve(
      uri,
      AddressInputContext.pay,
      request: ethereum(uri, chainId: null),
    );
    expect(result.kind, AddressInputResultKind.paymentRequest);
    expect(result.crossChainRequest!.needsNetwork, isTrue);
  });

  test(
    'Pay request can propose another supported chain with catalogue loading',
    () async {
      final uri = 'ethereum:$evm@8453?value=1';
      expect(
        (await resolve(
          uri,
          AddressInputContext.pay,
          request: ethereum(uri),
        )).kind,
        AddressInputResultKind.paymentRequest,
      );
    },
  );

  for (final context in [
    AddressInputContext.pay,
    AddressInputContext.swapRecipient,
    AddressInputContext.swapRefund,
    AddressInputContext.contact,
  ]) {
    test(
      '$context address-only EVM URI cannot silently change chain',
      () async {
        final uri = 'ethereum:$evm@8453';
        expect(
          (await resolve(
            uri,
            context,
            network: AddressBookNetwork.ethereum,
            request: ethereum(uri),
          )).kind,
          AddressInputResultKind.rejected,
        );
        expect(
          (await resolve(
            uri,
            context,
            network: AddressBookNetwork.base,
            request: ethereum(uri),
          )).address,
          evm,
        );
      },
    );
  }

  for (final context in [
    AddressInputContext.swapRecipient,
    AddressInputContext.swapRefund,
  ]) {
    test('$context accepts address-only Bitcoin URI', () async {
      final uri = 'bitcoin:$btc';
      expect((await resolve(uri, context, request: bitcoin(uri))).address, btc);
    });
    for (final suffix in ['?', '?amount=0', '?label=', '?message=', '#memo']) {
      test(
        '$context handles payment syntax even if parser fields are empty: $suffix',
        () async {
          final uri = 'bitcoin:$btc$suffix';
          expect(
            (await resolve(uri, context, request: bitcoin(uri))).kind,
            context == AddressInputContext.swapRecipient
                ? AddressInputResultKind.paymentRequest
                : AddressInputResultKind.rejected,
          );
        },
      );
    }
  }

  test(
    'Swap recipient request can propose a different supported chain',
    () async {
      final uri = 'ethereum:$evm@8453?value=1';
      final result = await resolve(
        uri,
        AddressInputContext.swapRecipient,
        request: ethereum(uri),
      );
      expect(result.kind, AddressInputResultKind.paymentRequest);
      expect(result.crossChainRequest!.address, evm);
      expect(result.rawPaymentUri, uri);
    },
  );

  test(
    'Swap recipient cannot use a different chain address-only URI',
    () async {
      final uri = 'ethereum:$evm@8453';
      expect(
        (await resolve(
          uri,
          AddressInputContext.swapRecipient,
          request: ethereum(uri),
        )).kind,
        AddressInputResultKind.rejected,
      );
    },
  );

  test('Swap recipient refuses malformed or unsupported requests', () async {
    for (final reason in [null, 'Unknown required parameter']) {
      const uri = 'bitcoin:$btc?req-unknown=1';
      expect(
        (await resolve(
          uri,
          AddressInputContext.swapRecipient,
          request: reason == null
              ? null
              : bitcoin(uri, unsupportedReason: reason),
        )).kind,
        AddressInputResultKind.rejected,
      );
    }
  });

  test('Contact extracts ERC20 recipient instead of target contract', () async {
    final uri = 'ethereum:$contract@8453/transfer?address=$evm&uint256=1';
    final result = await resolve(
      uri,
      AddressInputContext.contact,
      network: AddressBookNetwork.base,
      request: ethereum(uri, token: true),
    );
    expect(result.address, evm);
  });

  for (final uri in [
    'zcash:$zec?address.1=u1otheraddress',
    'zcash:$zec?address=u1otheraddress',
    'zcash:$zec?req-unknown=1',
    'zcash://$zec',
  ]) {
    test(
      'Contact refuses ambiguous/malformed Zcash without fallback: $uri',
      () async {
        expect(
          (await resolve(
            uri,
            AddressInputContext.contact,
            network: AddressBookNetwork.zcash,
          )).kind,
          AddressInputResultKind.rejected,
        );
      },
    );
  }

  test('Contact can extract one supported Zcash request recipient', () async {
    expect(
      (await resolve(
        'zcash:$zec?amount=2&label=Alice',
        AddressInputContext.contact,
        network: AddressBookNetwork.zcash,
      )).address,
      zec,
    );
  });

  test('Malformed cross-chain URI is not retried as an address', () async {
    expect(
      (await resolve(
        'ethereum:$evm?value=bad',
        AddressInputContext.contact,
        network: AddressBookNetwork.ethereum,
      )).kind,
      AddressInputResultKind.rejected,
    );
  });

  test('Unknown scheme never falls back to a plausible path', () async {
    expect(
      (await resolve('unknown:$btc', AddressInputContext.pay)).kind,
      AddressInputResultKind.rejected,
    );
  });

  test('Async Zcash validation failure becomes rejection', () async {
    final completer = Completer<String?>();
    final pending = resolve(
      zec,
      AddressInputContext.send,
      zcashValidator: (_, _) => completer.future,
    );
    completer.completeError(StateError('validator failed'));
    expect((await pending).kind, AddressInputResultKind.rejected);
  });
}
