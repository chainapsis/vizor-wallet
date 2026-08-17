import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_chains.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';

void main() {
  group('evmChainIdFor', () {
    test('maps supported EVM chains to ENSIP-11 chain ids', () {
      expect(evmChainIdFor(AddressBookNetwork.ethereum), 1);
      expect(evmChainIdFor(AddressBookNetwork.base), 8453);
      expect(evmChainIdFor(AddressBookNetwork.arbitrum), 42161);
      expect(evmChainIdFor(AddressBookNetwork.optimism), 10);
      expect(evmChainIdFor(AddressBookNetwork.polygon), 137);
      expect(evmChainIdFor(AddressBookNetwork.binanceSmartChain), 56);
      expect(evmChainIdFor(AddressBookNetwork.avalanche), 43114);
      expect(evmChainIdFor(AddressBookNetwork.gnosis), 100);
      expect(evmChainIdFor(AddressBookNetwork.scroll), 534352);
    });

    test('returns null for non-EVM or unmapped chains', () {
      expect(evmChainIdFor(AddressBookNetwork.solana), isNull);
      expect(evmChainIdFor(AddressBookNetwork.zcash), isNull);
      expect(evmChainIdFor(AddressBookNetwork.bitcoin), isNull);
    });
  });

  group('chainSupportsEnsNames', () {
    test('true only for EVM chains with an ENSIP-11 mapping', () {
      expect(chainSupportsEnsNames(AddressBookNetwork.ethereum), isTrue);
      expect(chainSupportsEnsNames(AddressBookNetwork.base), isTrue);
    });

    test('false for null, non-EVM, and unmapped chains', () {
      expect(chainSupportsEnsNames(null), isFalse);
      expect(chainSupportsEnsNames(AddressBookNetwork.solana), isFalse);
      expect(chainSupportsEnsNames(AddressBookNetwork.zcash), isFalse);
    });
  });
}
