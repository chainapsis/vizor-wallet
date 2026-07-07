import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_label_lookup.dart';

AddressBookContact _contact({
  required String label,
  required AddressBookNetwork network,
  required String address,
}) {
  return AddressBookContact(
    id: 'id_$label',
    label: label,
    network: network,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

void main() {
  const zcashAddress = 'u1tvg4akwn3gk64hhq6dfe05psw8zr0x4tspgwhkgy8x9yhy6djx';

  test('returns the label for an exact Zcash address match', () {
    final contacts = [
      _contact(
        label: 'Alice',
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      'Alice',
    );
  });

  test('matches Zcash addresses after trimming surrounding whitespace', () {
    final contacts = [
      _contact(
        label: 'Alice',
        network: AddressBookNetwork.zcash,
        address: '  $zcashAddress  ',
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: '$zcashAddress\n',
      ),
      'Alice',
    );
  });

  test('Zcash matching is case-sensitive', () {
    final contacts = [
      _contact(
        label: 'Alice',
        network: AddressBookNetwork.zcash,
        address: zcashAddress.toUpperCase(),
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      isNull,
    );
  });

  test('EVM matching ignores case', () {
    const checksummed = '0xAbC0000000000000000000000000000000000123';
    final contacts = [
      _contact(
        label: 'Bob',
        network: AddressBookNetwork.ethereum,
        address: checksummed,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.ethereum,
        address: checksummed.toLowerCase(),
      ),
      'Bob',
    );
  });

  test('ignores contacts on a different network', () {
    final contacts = [
      _contact(
        label: 'Eve',
        network: AddressBookNetwork.ethereum,
        address: zcashAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      isNull,
    );
  });

  test('returns null when nothing matches or input is empty', () {
    final contacts = [
      _contact(
        label: 'Alice',
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: 'u1someotheraddress',
      ),
      isNull,
    );
    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: '   ',
      ),
      isNull,
    );
    expect(
      addressBookLabelFor(
        contacts: const [],
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      isNull,
    );
  });

  test('skips matching contacts whose label is blank', () {
    final contacts = [
      _contact(
        label: '   ',
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      isNull,
    );
  });

  test('EVM contact matches across EVM chains, ignoring case', () {
    const evmAddress = '0x0cD7aD0301Bb0521Cc9d33Ab5D2951A9C0727181';
    final contacts = [
      _contact(
        label: 'Rowan',
        network: AddressBookNetwork.polygon,
        address: evmAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.base,
        address: evmAddress.toLowerCase(),
      ),
      'Rowan',
    );
  });

  test('exact-network EVM contact wins over a family-wide match', () {
    const evmAddress = '0x0cd7ad0301bb0521cc9d33ab5d2951a9c0727181';
    final contacts = [
      _contact(
        label: 'Polygon Rowan',
        network: AddressBookNetwork.polygon,
        address: evmAddress,
      ),
      _contact(
        label: 'Base Rowan',
        network: AddressBookNetwork.base,
        address: evmAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.base,
        address: evmAddress,
      ),
      'Base Rowan',
    );
  });

  test('non-EVM networks never match across networks', () {
    final contacts = [
      _contact(
        label: 'Sol Alice',
        network: AddressBookNetwork.solana,
        address: zcashAddress,
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.zcash,
        address: zcashAddress,
      ),
      isNull,
    );
  });

  test('NEAR matching ignores case', () {
    final contacts = [
      _contact(
        label: 'Near Bob',
        network: AddressBookNetwork.near,
        address: 'Bob.Near',
      ),
    ];

    expect(
      addressBookLabelFor(
        contacts: contacts,
        network: AddressBookNetwork.near,
        address: 'bob.near',
      ),
      'Near Bob',
    );
  });
}
