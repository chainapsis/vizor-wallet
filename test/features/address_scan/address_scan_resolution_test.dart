import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_format_validator.dart';
import 'package:zcash_wallet/src/features/address_scan/domain/address_scan_resolution.dart';

const _evm = '0x157D19957d4047Fb8601783805a54EF6ae80eaD7';
const _token = '0x1111111111111111111111111111111111111111';
const _btc = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _btcTestnet = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
const _cashAddr = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';
// The same key as `_cashAddr`, in the CashAddr specification's legacy form.
const _bchLegacy = '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu';
// A user-friendly TON address from the TON documentation.
const _ton = 'EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N';
const _solana = '7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs';
const _zcash = 't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCi';

AddressScanAccepted _accepted(
  String raw, {
  required AddressBookNetwork? network,
}) {
  final result = resolveAddressScan(raw, network: network);
  expect(result, isA<AddressScanAccepted>(), reason: raw);
  return result as AddressScanAccepted;
}

AddressScanRejected _rejected(
  String raw, {
  required AddressBookNetwork? network,
}) {
  final result = resolveAddressScan(raw, network: network);
  expect(result, isA<AddressScanRejected>(), reason: raw);
  return result as AddressScanRejected;
}

AddressScanRejection _rejection(
  String raw, {
  required AddressBookNetwork? network,
}) => _rejected(raw, network: network).reason;

/// The chain a wrong-network refusal names, or null when it names none.
AddressBookNetwork? _wrongNetworkNamed(
  String raw, {
  required AddressBookNetwork? network,
}) {
  final result = _rejected(raw, network: network);
  expect(result.reason, AddressScanRejection.wrongNetwork, reason: raw);
  return result.network;
}

void main() {
  group('bare addresses', () {
    test('are accepted exactly when the field would accept them', () {
      const inputs = [
        _evm,
        _btc,
        _btcTestnet,
        _cashAddr,
        _solana,
        _zcash,
        'rowan.near',
        'https.near',
        'literally anything',
      ];
      for (final network in AddressBookNetwork.values) {
        for (final input in inputs) {
          final accepted =
              resolveAddressScan(input, network: network)
                  is AddressScanAccepted;
          expect(
            accepted,
            addressFormatIssue(network, input) == null,
            reason: '${network.id}: $input',
          );
        }
      }
    });

    test('are trimmed', () {
      final result = _accepted(
        '  rowan.near  ',
        network: AddressBookNetwork.near,
      );
      expect(result.address, 'rowan.near');
    });

    test('name the format problem when refused', () {
      final result = resolveAddressScan(
        _btc,
        network: AddressBookNetwork.ethereum,
      );
      expect(
        (result as AddressScanRejected).finding?.kind,
        AddressFormatKind.invalidEvm,
      );
      expect(result.reason, AddressScanRejection.invalidAddress);
    });

    test('a TON raw address is not mistaken for a URI', () {
      final raw = '0:${'ab' * 32}';
      expect(_accepted(raw, network: AddressBookNetwork.ton).address, raw);
    });

    test('pass through when the chain is unknown', () {
      expect(_accepted('anything', network: null).address, 'anything');
    });

    test('an empty scan is refused', () {
      expect(
        _rejection('   ', network: AddressBookNetwork.ethereum),
        AddressScanRejection.unsupported,
      );
    });
  });

  group('ethereum URIs', () {
    test('give up a plain recipient', () {
      final result = _accepted(
        'ethereum:$_evm',
        network: AddressBookNetwork.base,
      );
      expect(result.address, _evm);
    });

    test('accept the legacy eth alias and the pay- prefix', () {
      for (final raw in ['eth:$_evm', 'ethereum:pay-$_evm']) {
        expect(
          _accepted(raw, network: AddressBookNetwork.ethereum).address,
          _evm,
        );
      }
    });

    test('read an all-uppercase QR code', () {
      final upper = _evm.toUpperCase();
      expect(
        _accepted(
          'ETHEREUM:PAY-$upper',
          network: AddressBookNetwork.ethereum,
        ).address,
        upper,
      );
      expect(
        _accepted(
          'ETHEREUM:${_token.toUpperCase()}/TRANSFER?ADDRESS=$upper',
          network: AddressBookNetwork.ethereum,
        ).address,
        upper,
      );
    });

    test('accept a chain ID only for the field\'s own chain', () {
      expect(
        _accepted(
          'ethereum:$_evm@8453',
          network: AddressBookNetwork.base,
        ).address,
        _evm,
      );
      // Same address, but the code asked to be paid on Base: say so, so the
      // user can pick Base instead.
      expect(
        _wrongNetworkNamed(
          'ethereum:$_evm@8453',
          network: AddressBookNetwork.ethereum,
        ),
        AddressBookNetwork.base,
      );
    });

    test('treat Robinhood Chain as an EVM chain with its own ID', () {
      const hood = AddressBookNetwork.robinhoodChain;
      // MetaMask's receive code names no chain.
      expect(_accepted('ethereum:$_evm', network: hood).address, _evm);
      expect(_accepted('ethereum:$_evm@4663', network: hood).address, _evm);
      expect(
        _wrongNetworkNamed('ethereum:$_evm@1', network: hood),
        AddressBookNetwork.ethereum,
      );
      expect(
        _wrongNetworkNamed(
          'ethereum:$_evm@4663',
          network: AddressBookNetwork.base,
        ),
        hood,
      );
    });

    test('take a chainless code on HyperCore but not on Movement', () {
      expect(
        _accepted(
          'ethereum:$_evm',
          network: AddressBookNetwork.hyperCore,
        ).address,
        _evm,
      );
      expect(
        _rejection('ethereum:$_evm', network: AddressBookNetwork.movement),
        AddressScanRejection.wrongNetwork,
      );
    });

    test('read a chain ID written in hex', () {
      expect(
        _accepted(
          'ethereum:$_evm@0x2105',
          network: AddressBookNetwork.base,
        ).address,
        _evm,
      );
      expect(
        _accepted(
          'ethereum:$_evm@0X1',
          network: AddressBookNetwork.ethereum,
        ).address,
        _evm,
      );
      expect(
        _wrongNetworkNamed(
          'ethereum:$_evm@0x2105',
          network: AddressBookNetwork.ethereum,
        ),
        AddressBookNetwork.base,
      );
    });

    test('refuse a chain ID that names no known chain, naming none', () {
      for (final raw in [
        'ethereum:$_evm@999999999',
        'ethereum:$_evm@99999999999999999999999',
        'ethereum:$_evm@1e3',
        'ethereum:$_evm@0x',
        'ethereum:$_evm@0xZZ',
        'ethereum:$_evm@',
      ]) {
        for (final network in [AddressBookNetwork.ethereum, null]) {
          expect(
            _wrongNetworkNamed(raw, network: network),
            isNull,
            reason: '$network: $raw',
          );
        }
      }
    });

    test('give up the recipient of a request with an amount', () {
      final result = _accepted(
        'ethereum:$_evm@1?value=2.014e18',
        network: AddressBookNetwork.ethereum,
      );
      expect(result.address, _evm);
    });

    test('take a token transfer\'s recipient, never its contract', () {
      final result = _accepted(
        'ethereum:$_token@1/transfer?address=$_evm&uint256=1000000',
        network: AddressBookNetwork.ethereum,
      );
      expect(result.address, _evm);
    });

    test('refuse a call that names no single recipient', () {
      for (final raw in [
        'ethereum:$_token/transfer?uint256=1000000',
        'ethereum:$_token/approve?address=$_evm&uint256=1',
        'ethereum:$_token/transfer?address=$_evm&address=$_token',
        'ethereum:$_token/transfer?address=%FF',
      ]) {
        expect(
          _rejection(raw, network: AddressBookNetwork.ethereum),
          AddressScanRejection.unsupported,
          reason: raw,
        );
      }
    });

    test('refuse an address argument outside a call, never taking the '
        'target', () {
      for (final raw in [
        'ethereum:$_token?address=$_evm',
        'ethereum:$_token?ADDRESS=$_evm',
        'ethereum:$_token?address=$_evm&address=$_token',
        'ethereum:$_token?address=%FF',
        'ethereum:$_token#/transfer?address=$_evm',
        'ethereum:$_evm#anything',
      ]) {
        expect(
          _rejection(raw, network: AddressBookNetwork.ethereum),
          AddressScanRejection.unsupported,
          reason: raw,
        );
      }
    });

    test('are for another network on a non-EVM field', () {
      // Without a chain ID the code names no chain to point to.
      expect(
        _wrongNetworkNamed(
          'ethereum:$_evm',
          network: AddressBookNetwork.bitcoin,
        ),
        isNull,
      );
      for (final network in [AddressBookNetwork.bitcoin, null]) {
        expect(
          _wrongNetworkNamed('ethereum:$_evm@8453', network: network),
          AddressBookNetwork.base,
        );
      }
    });

    test('give up an EVM address on a chain the app does not know', () {
      // Such a chain may be EVM, as a bare address would be taken there.
      expect(_accepted('ethereum:$_evm', network: null).address, _evm);
      expect(
        _accepted(
          'ethereum:$_token/transfer?address=$_evm',
          network: null,
        ).address,
        _evm,
      );
      expect(
        _rejection('ethereum:not-an-address', network: null),
        AddressScanRejection.invalidAddress,
      );
    });
  });

  group('address-path URIs', () {
    test('give up the address on their own chain', () {
      final result = _accepted(
        'bitcoin:$_btc',
        network: AddressBookNetwork.bitcoin,
      );
      expect(result.address, _btc);
    });

    test('give up the address of a request with terms', () {
      final result = _accepted(
        'bitcoin:$_btc?amount=0.5&label=Shop',
        network: AddressBookNetwork.bitcoin,
      );
      expect(result.address, _btc);
    });

    test('read an all-uppercase QR code', () {
      final raw = 'BITCOIN:${_btc.toUpperCase()}?AMOUNT=0.5';
      final result = _accepted(raw, network: AddressBookNetwork.bitcoin);
      expect(result.address, _btc.toUpperCase());
    });

    test('keep the case of an address written as an authority', () {
      expect(
        _accepted(
          'solana://$_solana',
          network: AddressBookNetwork.solana,
        ).address,
        _solana,
      );
    });

    test('are refused on any other chain, naming their own', () {
      expect(
        _wrongNetworkNamed(
          'bitcoin:$_btc',
          network: AddressBookNetwork.litecoin,
        ),
        AddressBookNetwork.bitcoin,
      );
      expect(
        _wrongNetworkNamed(
          'solana:$_solana',
          network: AddressBookNetwork.ethereum,
        ),
        AddressBookNetwork.solana,
      );
      expect(
        _wrongNetworkNamed('bitcoin:$_btc', network: null),
        AddressBookNetwork.bitcoin,
      );
    });

    test('are still checked as addresses', () {
      expect(
        _rejection(
          'bitcoin:$_btcTestnet?amount=1',
          network: AddressBookNetwork.bitcoin,
        ),
        AddressScanRejection.invalidAddress,
      );
      // A Solana Pay transaction request carries a link, not a recipient.
      expect(
        _rejection(
          'solana:https%3A%2F%2Fexample.com%2Fpay',
          network: AddressBookNetwork.solana,
        ),
        AddressScanRejection.invalidAddress,
      );
    });

    test('keep a CashAddr prefix, with or without terms', () {
      final plain = _accepted(
        'bitcoincash:$_cashAddr',
        network: AddressBookNetwork.bitcoinCash,
      );
      expect(plain.address, 'bitcoincash:$_cashAddr');

      final request = _accepted(
        'bitcoincash:$_cashAddr?amount=1',
        network: AddressBookNetwork.bitcoinCash,
      );
      expect(request.address, 'bitcoincash:$_cashAddr');
    });

    test('read a CashAddr in any case, and a legacy address bare', () {
      for (final raw in [
        'BITCOINCASH:${_cashAddr.toUpperCase()}',
        'BITCOINCASH:$_cashAddr',
      ]) {
        expect(
          _accepted(raw, network: AddressBookNetwork.bitcoinCash).address,
          'bitcoincash:$_cashAddr',
          reason: raw,
        );
      }
      expect(
        _accepted(
          'bitcoincash:$_bchLegacy?amount=1',
          network: AddressBookNetwork.bitcoinCash,
        ).address,
        _bchLegacy,
      );
    });

    test('read a Tonkeeper transfer link', () {
      final plain = _accepted(
        'ton://transfer/$_ton',
        network: AddressBookNetwork.ton,
      );
      expect(plain.address, _ton);

      // The path holds the recipient even when a jetton is named.
      final request = _accepted(
        'ton://transfer/$_ton?amount=1000&text=hi&jetton=$_ton',
        network: AddressBookNetwork.ton,
      );
      expect(request.address, _ton);

      expect(
        _wrongNetworkNamed(
          'ton://transfer/$_ton',
          network: AddressBookNetwork.ethereum,
        ),
        AddressBookNetwork.ton,
      );
    });

    test('refuse a TON link that is not a plain transfer', () {
      for (final raw in [
        'ton://transfer/$_ton?amount=1&bin=te6cckEBAQEAAgAAAEysuc0%3D',
        'ton://stake/$_ton',
        'ton:$_ton',
      ]) {
        expect(
          _rejection(raw, network: AddressBookNetwork.ton),
          AddressScanRejection.unsupported,
          reason: raw,
        );
      }
    });
  });

  group('zcash URIs', () {
    test('are for another network outside a Zcash field', () {
      expect(
        _wrongNetworkNamed(
          'zcash:$_zcash',
          network: AddressBookNetwork.ethereum,
        ),
        AddressBookNetwork.zcash,
      );
    });

    test('give up the address, with or without terms', () {
      final plain = _accepted(
        'zcash:$_zcash',
        network: AddressBookNetwork.zcash,
      );
      expect(plain.address, _zcash);

      final request = _accepted(
        'zcash:$_zcash?amount=1.5&message=Thanks',
        network: AddressBookNetwork.zcash,
      );
      expect(request.address, _zcash);
    });

    test('refuse a request with no single recipient', () {
      expect(
        _rejection(
          'zcash:?address.1=$_zcash&address.1=$_zcash',
          network: AddressBookNetwork.zcash,
        ),
        AddressScanRejection.unsupported,
      );
    });
  });

  group('everything else', () {
    test('is not an address', () {
      for (final raw in [
        'https://example.com/pay?x=1',
        'ur:zcash-accounts/abcdef',
        'wc:abc@2?relay-protocol=irn',
        'bitcoin:',
        'ethereum:',
      ]) {
        for (final network in [
          AddressBookNetwork.bitcoin,
          AddressBookNetwork.ethereum,
          // No validator of its own: the scheme check is all that stops these.
          AddressBookNetwork.tron,
        ]) {
          expect(
            resolveAddressScan(raw, network: network),
            isA<AddressScanRejected>(),
            reason: '${network.id}: $raw',
          );
        }
      }
    });

    test('a malformed percent-escape is refused, not thrown', () {
      for (final raw in [
        'ethereum:%FF',
        'bitcoin:%FF',
        'ethereum:$_evm?address=%FF',
        'solana:abc?x=%E0%A4%A',
        'zcash:%FF',
      ]) {
        for (final network in AddressBookNetwork.values) {
          expect(
            () => resolveAddressScan(raw, network: network),
            returnsNormally,
            reason: '${network.id}: $raw',
          );
        }
      }
      expect(
        _rejection('bitcoin:%FF', network: AddressBookNetwork.bitcoin),
        AddressScanRejection.unsupported,
      );
    });
  });
}
