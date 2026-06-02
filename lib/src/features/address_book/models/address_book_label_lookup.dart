import 'address_book_contact.dart';

/// Resolves the address-book label/nickname for [address] on [network].
///
/// Returns the first matching contact's non-empty label, or `null` when no
/// contact matches. Matching mirrors the swap activity details behavior: a
/// trimmed exact match, case-insensitive for EVM/NEAR networks and
/// case-sensitive otherwise (Zcash addresses are case-sensitive).
String? addressBookLabelFor({
  required Iterable<AddressBookContact> contacts,
  required AddressBookNetwork network,
  required String address,
}) {
  final target = _normalizedAddress(network, address);
  if (target.isEmpty) return null;
  for (final contact in contacts) {
    if (contact.network != network) continue;
    if (_normalizedAddress(network, contact.address) != target) continue;
    final label = contact.label.trim();
    if (label.isNotEmpty) return label;
  }
  return null;
}

String _normalizedAddress(AddressBookNetwork network, String address) {
  final trimmed = address.trim();
  return _addressBookNetworkIgnoresCase(network)
      ? trimmed.toLowerCase()
      : trimmed;
}

bool _addressBookNetworkIgnoresCase(AddressBookNetwork network) {
  return switch (network) {
    AddressBookNetwork.ethereum ||
    AddressBookNetwork.base ||
    AddressBookNetwork.arbitrum ||
    AddressBookNetwork.binanceSmartChain ||
    AddressBookNetwork.optimism ||
    AddressBookNetwork.avalanche ||
    AddressBookNetwork.gnosis ||
    AddressBookNetwork.polygon ||
    AddressBookNetwork.xLayer ||
    AddressBookNetwork.plasma ||
    AddressBookNetwork.abstractChain ||
    AddressBookNetwork.bera ||
    AddressBookNetwork.monad ||
    AddressBookNetwork.scroll ||
    AddressBookNetwork.near => true,
    _ => false,
  };
}
