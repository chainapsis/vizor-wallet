import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import 'swap_models.dart';

/// Address-book helpers shared by the desktop and mobile swap screens:
/// which network a destination/refund contact belongs to, the picker
/// filters, and the auto-generated labels.
AddressBookNetwork? addressBookNetworkForSwapDestination(SwapState state) {
  final asset = state.externalAsset;
  return AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
}

/// Saved contact matching [address] on the chain of [asset], or `null` when
/// the asset is unknown or its chain has no address-book network.
AddressBookContact? addressBookContactForSwapAsset({
  required Iterable<AddressBookContact> contacts,
  required SwapAsset? asset,
  required String address,
  String? contactId,
}) {
  if (asset == null) return null;
  final network = AddressBookNetwork.tryFromChainTicker(asset.chainTicker);
  if (network == null) return null;
  final selectedId = contactId?.trim();
  if (selectedId != null && selectedId.isNotEmpty) {
    return addressBookContactFor(
      contacts: [
        for (final contact in contacts)
          if (contact.id == selectedId) contact,
      ],
      network: network,
      address: address,
    );
  }
  return addressBookContactFor(
    contacts: contacts,
    network: network,
    address: address,
  );
}

/// Saved contact matching the composer's destination/refund address on the
/// current external asset's chain.
AddressBookContact? swapDestinationContactFor(
  SwapState state,
  Iterable<AddressBookContact> contacts,
) {
  return addressBookContactForSwapAsset(
    contacts: contacts,
    asset: state.externalAsset,
    address: state.destinationText,
    contactId: state.userExternalContactId,
  );
}

List<AddressBookNetwork> swapContactPickerNetworks(SwapState state) {
  final network = addressBookNetworkForSwapDestination(state);
  if (network == null) return const [];
  // EVM addresses are interchangeable across EVM chains (the same 0x account
  // works on every one), so let the user pick any saved EVM contact — e.g. a
  // Polygon address as the refund for a Base swap. Non-EVM chains keep the
  // exact-network filter since those address formats are chain-specific.
  if (network.isEvm) {
    return [
      for (final candidate in AddressBookNetwork.values)
        if (candidate.isEvm) candidate,
    ];
  }
  return [network];
}

String swapContactPickerTitle(SwapState state) {
  final role = state.direction.sendsZec ? 'recipients' : 'refunds';
  return '${state.externalAsset.symbol} $role';
}

String swapContactPickerEmptyTitle(SwapState state) {
  final role = state.direction.sendsZec ? 'recipients' : 'refunds';
  return 'No saved ${state.externalAsset.symbol} $role';
}

String swapAddressBookLabel(SwapState state) {
  final role = state.direction.sendsZec ? 'recipient' : 'refund';
  return '${state.externalAsset.symbol} $role';
}
