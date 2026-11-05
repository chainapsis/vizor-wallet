import 'address_book_contact.dart';
import 'address_book_label_lookup.dart';

/// The recent recipients and saved contacts a recipient picker shows for the
/// current field text.
class RecipientSuggestions<R> {
  const RecipientSuggestions({
    required this.recents,
    required this.contacts,
    this.includesQueryAddress = false,
  });

  final List<R> recents;
  final List<AddressBookContact> contacts;

  /// Whether a listed row's address is the field text in full.
  final bool includesQueryAddress;

  bool get isNotEmpty => recents.isNotEmpty || contacts.isNotEmpty;

  /// Whether the field text reads as a search, which hides the address-format
  /// error. A full address is validated even when a row shows it.
  bool get isSearch => isNotEmpty && !includesQueryAddress;
}

/// Characters an address fragment needs to match the start of an address.
///
/// Six covers a two-character network prefix (`u1`, `t1`, `0x`) plus four.
const kRecipientAddressPrefixLength = 6;

/// Characters an address fragment needs to match the end of an address.
const kRecipientAddressSuffixLength = 4;

/// Matches the field text against [recents] and [contacts], shared by the
/// Send and Pay recipient steps.
///
/// Labels match by substring, including the name a recent row shows
/// ([recentLabel]). Addresses match by their start or end, the parts the app
/// shows, once the fragment has [kRecipientAddressPrefixLength] or
/// [kRecipientAddressSuffixLength] characters; the full address always
/// matches. A recent is left out when a matched contact already shows its
/// address.
RecipientSuggestions<R> matchRecipientSuggestions<R>({
  required String query,
  required AddressBookNetwork network,
  required List<R> recents,
  required String Function(R recent) recentAddress,
  String? Function(R recent)? recentLabel,
  required List<AddressBookContact> contacts,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return RecipientSuggestions(recents: recents, contacts: contacts);
  }
  final label = trimmed.toLowerCase();
  final matchedContacts = [
    for (final contact in contacts)
      if (contact.label.toLowerCase().contains(label) ||
          _addressMatches(contact.network, contact.address, trimmed))
        contact,
  ];
  final shownAddresses = {
    for (final contact in matchedContacts)
      normalizedAddressBookAddress(network, contact.address),
  };
  final matchedRecents = [
    for (final recent in recents)
      if ((_addressMatches(network, recentAddress(recent), trimmed) ||
              (recentLabel?.call(recent)?.toLowerCase().contains(label) ??
                  false)) &&
          !shownAddresses.contains(
            normalizedAddressBookAddress(network, recentAddress(recent)),
          ))
        recent,
  ];
  final queryAddress = normalizedAddressBookAddress(network, trimmed);
  return RecipientSuggestions(
    recents: matchedRecents,
    contacts: matchedContacts,
    includesQueryAddress:
        shownAddresses.contains(queryAddress) ||
        matchedRecents.any(
          (recent) =>
              normalizedAddressBookAddress(network, recentAddress(recent)) ==
              queryAddress,
        ),
  );
}

bool _addressMatches(
  AddressBookNetwork network,
  String address,
  String fragment,
) {
  final candidate = normalizedAddressBookAddress(network, address);
  final needle = normalizedAddressBookAddress(network, fragment);
  if (needle.isNotEmpty && candidate == needle) return true;
  return (needle.length >= kRecipientAddressPrefixLength &&
          candidate.startsWith(needle)) ||
      (needle.length >= kRecipientAddressSuffixLength &&
          candidate.endsWith(needle));
}
