import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/recipient_suggestions.dart';

const _alice = AddressBookContact(
  id: 'alice',
  label: 'Alice',
  network: AddressBookNetwork.ethereum,
  address: '0x52908400098527886E0F7030069857D2E4169EE7',
  profilePictureId: 'pfp-01',
  createdAtMs: 0,
  updatedAtMs: 0,
);
const _bob = AddressBookContact(
  id: 'bob',
  label: 'Bob',
  network: AddressBookNetwork.ethereum,
  address: '0x1111111111111111111111111111111111111111',
  profilePictureId: 'pfp-02',
  createdAtMs: 0,
  updatedAtMs: 0,
);
const _recent = '0x2222222222222222222222222222222222229ee7';

RecipientSuggestions<String> _match(
  String query, {
  List<String> recents = const [_recent],
}) => matchRecipientSuggestions(
  query: query,
  network: AddressBookNetwork.ethereum,
  recents: recents,
  recentAddress: (address) => address,
  contacts: const [_alice, _bob],
);

RecipientSuggestions<String> _matchZcash(String query, List<String> recents) =>
    matchRecipientSuggestions(
      query: query,
      network: AddressBookNetwork.zcash,
      recents: recents,
      recentAddress: (address) => address,
      contacts: const [],
    );

void main() {
  test('empty text suggests every recent and contact', () {
    final suggestions = _match('  ');

    expect(suggestions.recents, [_recent]);
    expect(suggestions.contacts, [_alice, _bob]);
  });

  test('a label fragment matches contacts by name', () {
    final suggestions = _match('LI');

    expect(suggestions.contacts, [_alice]);
    expect(suggestions.recents, isEmpty);
  });

  test('an address start needs six characters', () {
    expect(_match('0x').isNotEmpty, isFalse);
    expect(_match('0x529').isNotEmpty, isFalse);
    expect(_match('0x5290').contacts, [_alice]);
  });

  test('an address end needs four characters', () {
    expect(_match('EE7').isNotEmpty, isFalse);
    expect(_match('9ee7').contacts, [_alice]);
    expect(_match('9EE7').recents, [_recent]);
  });

  test('a fragment from the middle of an address matches nothing', () {
    expect(_match('8400').isNotEmpty, isFalse);
  });

  test('a fragment is a search but a full listed address is not', () {
    expect(_match('ali').isSearch, isTrue);
    expect(_match('9ee7').isSearch, isTrue);
    expect(_match(_alice.address).isSearch, isFalse);
    expect(_match(_recent).isSearch, isFalse);
    expect(_match('zzzz').isSearch, isFalse);
  });

  test('a full short address always matches itself', () {
    final suggestions = matchRecipientSuggestions<String>(
      query: 'ab.near',
      network: AddressBookNetwork.near,
      recents: const ['ab.near', 'cd.ab.near'],
      recentAddress: (address) => address,
      contacts: const [],
    );

    expect(suggestions.recents, ['ab.near', 'cd.ab.near']);
    expect(suggestions.includesQueryAddress, isTrue);
  });

  test('a name that only ends a listed address is not that address', () {
    final suggestions = matchRecipientSuggestions<String>(
      query: 'alice.near',
      network: AddressBookNetwork.near,
      recents: const ['bob.alice.near'],
      recentAddress: (address) => address,
      contacts: const [],
    );

    expect(suggestions.recents, ['bob.alice.near']);
    expect(suggestions.includesQueryAddress, isFalse);
  });

  test('a recent at a matched contact address is not listed twice', () {
    final suggestions = _match(
      '9ee7',
      recents: [_alice.address.toLowerCase(), _recent],
    );

    expect(suggestions.contacts, [_alice]);
    expect(suggestions.recents, [_recent]);
  });

  test('a recent matches by the name its row shows', () {
    final suggestions = matchRecipientSuggestions<String>(
      query: 'sav',
      network: AddressBookNetwork.ethereum,
      recents: const [_recent],
      recentAddress: (address) => address,
      recentLabel: (_) => 'Savings',
      contacts: const [_alice, _bob],
    );

    expect(suggestions.recents, [_recent]);
    expect(suggestions.contacts, isEmpty);
  });

  test('Zcash addresses match from six leading characters', () {
    const unified = 'u1tvg2412a23kshielded0000k64123hhq6d';
    const transparent = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';
    const recents = [unified, transparent];

    expect(_matchZcash('u1', recents).isNotEmpty, isFalse);
    expect(_matchZcash('u1tvg', recents).isNotEmpty, isFalse);
    expect(_matchZcash('u1tvg2', recents).recents, [unified]);
    expect(_matchZcash('t1aW', recents).isNotEmpty, isFalse);
    expect(_matchZcash('t1aWwW', recents).recents, [transparent]);
    // Base58 transparent addresses are case-sensitive.
    expect(_matchZcash('t1awww', recents).isNotEmpty, isFalse);
    expect(_matchZcash(unified, recents).recents, [unified]);
  });

  test('the start length does not depend on the address format', () {
    const uppercase = 'U1TVG2412A23KSHIELDED0000K64123HHQ6D';
    const p2sh = 't3Vz22vK5z2LcKEdg16Yv4FFneEL1zg9ojd';
    const recents = [uppercase, p2sh];

    expect(_matchZcash('U1TVG', recents).isNotEmpty, isFalse);
    expect(_matchZcash('U1TVG2', recents).recents, [uppercase]);
    expect(_matchZcash('t3Vz2', recents).isNotEmpty, isFalse);
    expect(_matchZcash('t3Vz22', recents).recents, [p2sh]);
  });
}
