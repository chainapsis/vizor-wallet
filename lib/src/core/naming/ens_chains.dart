import '../../features/address_book/models/address_book_contact.dart';

/// ENSIP-11 chain ids for the chains Vizor can resolve ENS names against.
/// Returns null for any chain not in this set (including non-EVM chains),
/// which callers treat as "names unsupported here".
int? evmChainIdFor(AddressBookNetwork network) => switch (network) {
  AddressBookNetwork.ethereum => 1,
  AddressBookNetwork.base => 8453,
  AddressBookNetwork.arbitrum => 42161,
  AddressBookNetwork.optimism => 10,
  AddressBookNetwork.polygon => 137,
  AddressBookNetwork.binanceSmartChain => 56,
  AddressBookNetwork.avalanche => 43114,
  AddressBookNetwork.gnosis => 100,
  AddressBookNetwork.scroll => 534352,
  _ => null,
};

/// True when [network] is both EVM and a chain Vizor can actually resolve
/// ENS names against (see [evmChainIdFor]). `null` (unrecognized chain
/// ticker) and non-resolvable EVM chains both resolve to false.
bool chainSupportsEnsNames(AddressBookNetwork? network) =>
    network != null && network.isEvm && evmChainIdFor(network) != null;
