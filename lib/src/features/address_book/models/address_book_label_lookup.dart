import 'address_book_contact.dart';

/// Resolves the address-book contact for [address] on [network].
///
/// Returns the first matching contact with a non-empty label, or `null` when
/// no contact matches. Matching mirrors the swap activity details behavior: a
/// trimmed exact match, case-insensitive for EVM/NEAR networks and
/// case-sensitive otherwise (Zcash addresses are case-sensitive).
AddressBookContact? addressBookContactFor({
  required Iterable<AddressBookContact> contacts,
  required AddressBookNetwork network,
  required String address,
}) {
  final target = _normalizedAddress(network, address);
  if (target.isEmpty) return null;
  for (final contact in contacts) {
    if (contact.network != network) continue;
    if (_normalizedAddress(network, contact.address) != target) continue;
    if (contact.label.trim().isEmpty) continue;
    return contact;
  }
  return null;
}

/// Resolves the address-book label/nickname for [address] on [network].
///
/// Same matching as [addressBookContactFor]; returns the contact's trimmed
/// label, or `null` when no labeled contact matches.
String? addressBookLabelFor({
  required Iterable<AddressBookContact> contacts,
  required AddressBookNetwork network,
  required String address,
}) {
  return addressBookContactFor(
    contacts: contacts,
    network: network,
    address: address,
  )?.label.trim();
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
