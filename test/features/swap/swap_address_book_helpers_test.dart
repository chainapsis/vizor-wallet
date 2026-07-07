import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_address_book_helpers.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

AddressBookContact _contact({
  required String label,
  required AddressBookNetwork network,
  required String address,
}) {
  return AddressBookContact(
    id: 'contact_$label',
    label: label,
    network: network,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

SwapState _state({String destinationText = ''}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: destinationText,
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: const {},
  );
}

void main() {
  const evmAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
  final contacts = [
    _contact(
      label: 'Treasury',
      network: AddressBookNetwork.ethereum,
      address: evmAddress,
    ),
  ];

  test('addressBookContactForSwapAsset resolves on the asset chain', () {
    expect(
      addressBookContactForSwapAsset(
        contacts: contacts,
        asset: SwapAsset.usdc,
        address: evmAddress.toUpperCase().replaceFirst('0X', '0x'),
      )?.label,
      'Treasury',
    );
  });

  test('addressBookContactForSwapAsset returns null for a null asset', () {
    expect(
      addressBookContactForSwapAsset(
        contacts: contacts,
        asset: null,
        address: evmAddress,
      ),
      isNull,
    );
  });

  test('addressBookContactForSwapAsset returns null when nothing matches', () {
    expect(
      addressBookContactForSwapAsset(
        contacts: contacts,
        asset: SwapAsset.usdc,
        address: '0x0000000000000000000000000000000000000000',
      ),
      isNull,
    );
  });

  test('swapDestinationContactFor resolves the composer destination', () {
    expect(
      swapDestinationContactFor(
        _state(destinationText: ' $evmAddress '),
        contacts,
      )?.label,
      'Treasury',
    );
    expect(swapDestinationContactFor(_state(), contacts), isNull);
  });
}
