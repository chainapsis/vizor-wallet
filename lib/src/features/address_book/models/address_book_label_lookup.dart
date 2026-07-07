import 'address_book_contact.dart';

/// Resolves the address-book contact for [address] on [network].
///
/// Returns the first matching contact with a non-empty label, or `null` when
/// no contact matches. Matching mirrors the swap activity details behavior: a
/// trimmed exact match, case-insensitive for EVM/NEAR networks and
/// case-sensitive otherwise (Zcash addresses are case-sensitive).
///
/// EVM addresses are interchangeable across EVM chains (matching the contact
/// picker, which offers any EVM contact for an EVM destination), so an EVM
/// [network] also matches contacts saved on other EVM networks. A contact
/// saved on the exact [network] wins over a family-wide match.
AddressBookContact? addressBookContactFor({
  required Iterable<AddressBookContact> contacts,
  required AddressBookNetwork network,
  required String address,
}) {
  final target = _normalizedAddress(network, address);
  if (target.isEmpty) return null;
  AddressBookContact? evmFamilyMatch;
  for (final contact in contacts) {
    if (contact.network != network) {
      if (network.isEvm && contact.network.isEvm && evmFamilyMatch == null) {
        if (_normalizedAddress(contact.network, contact.address) == target &&
            contact.label.trim().isNotEmpty) {
          evmFamilyMatch = contact;
        }
      }
      continue;
    }
    if (_normalizedAddress(network, contact.address) != target) continue;
    if (contact.label.trim().isEmpty) continue;
    return contact;
  }
  return evmFamilyMatch;
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
  return network.isEvm || network == AddressBookNetwork.near;
}
