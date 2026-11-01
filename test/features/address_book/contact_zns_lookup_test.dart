import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/zns_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/zns_recipient_lookup.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/contact_zns_lookup.dart';

import '../../fakes/fake_zns_name_resolver.dart';

const _address =
    'u14lms6q2sg984hhng068lqesatnak86mlg297x0qkqsvkqgk2m7dyj5x2grlku3adg2tq6t'
    'rl5ue3vce7c3jnu5808kw9lsr890kfetrg524q4pgcn4zcnp84na85453pz67cjfy4sx7y6z'
    '6zc9t7666utasw5mehe9r2dwwcrgzp94ah';

const _zcash = AddressBookNetwork.zcash;

void main() {
  group('ContactZnsLookup', () {
    ContactZnsLookup lookupWith(
      ZnsNameResolver? resolver, {
      String? savedName,
      void Function()? onChanged,
    }) => ContactZnsLookup(
      savedName: savedName,
      readResolver: () => resolver,
      onChanged: onChanged ?? () {},
      debounce: Duration.zero,
    );

    test('a resolved name saves its address and keeps the name', () async {
      final lookup = lookupWith(FakeZnsNameResolver({'alice': _address}));

      lookup.update(address: 'Alice.zcash', network: _zcash);
      expect(lookup.canSave('Alice.zcash', _zcash), isFalse);
      expect(
        lookup.message('Alice.zcash')?.text,
        ZnsLookupStatus.resolving.message,
      );
      await pumpEventQueue();

      expect(lookup.canSave('Alice.zcash', _zcash), isTrue);
      expect(lookup.addressToSave('Alice.zcash'), _address);
      expect(lookup.nameToSave('Alice.zcash', _zcash), 'alice.zcash');
      expect(lookup.message('Alice.zcash')?.text, startsWith('Resolves to '));
      expect(lookup.message('Alice.zcash')?.isError, isFalse);
    });

    test(
      'an unregistered name or an unusable address blocks the save',
      () async {
        final missing = lookupWith(FakeZnsNameResolver());
        missing.update(address: 'nobody.zec', network: _zcash);
        await pumpEventQueue();
        expect(missing.canSave('nobody.zec', _zcash), isFalse);
        expect(missing.message('nobody.zec')?.isError, isTrue);

        final unusable = lookupWith(
          FakeZnsNameResolver({'bob': 'not-an-address'}),
        );
        unusable.update(address: 'bob.zcash', network: _zcash);
        await pumpEventQueue();
        expect(unusable.canSave('bob.zcash', _zcash), isFalse);
        expect(
          unusable.message('bob.zcash')?.text,
          ZnsLookupStatus.unusableAddress.message,
        );
      },
    );

    test('a name on another network is plain text and is never looked up', () {
      final resolver = FakeZnsNameResolver({'alice': _address});
      final lookup = lookupWith(resolver);

      lookup.update(address: 'alice.zcash', network: AddressBookNetwork.near);

      expect(resolver.lookups, isEmpty);
      expect(lookup.isName('alice.zcash', AddressBookNetwork.near), isFalse);
      expect(lookup.nameToSave('alice.zcash', AddressBookNetwork.near), isNull);
    });

    test('the resolver is read only when a name needs a lookup', () async {
      var reads = 0;
      final lookup = ContactZnsLookup(
        readResolver: () {
          reads++;
          return null;
        },
        onChanged: () {},
        debounce: Duration.zero,
      );

      lookup.update(address: _address, network: _zcash);
      await pumpEventQueue();
      expect(reads, 0);
      lookup.update(address: 'alice.zcash', network: _zcash);
      await pumpEventQueue();
      expect(reads, 1);
    });

    test('a saved name stays until the address is edited', () {
      final lookup = lookupWith(null, savedName: 'alice.zcash');
      expect(lookup.nameToSave(_address, _zcash), 'alice.zcash');
      expect(lookup.message(_address)?.text, 'Saved from alice.zcash');

      lookup.update(address: '${_address}x', network: _zcash);
      expect(lookup.nameToSave('${_address}x', _zcash), isNull);
    });

    test('rapid edits look up only the last name', () async {
      final resolver = FakeZnsNameResolver({'alice': _address});
      final lookup = ContactZnsLookup(
        readResolver: () => resolver,
        onChanged: () {},
        debounce: const Duration(milliseconds: 20),
      );

      for (final text in ['a.zcash', 'al.zcash', 'ali.zcash', 'alice.zcash']) {
        lookup.update(address: text, network: _zcash);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(resolver.lookups, ['alice']);
      expect(lookup.canSave('alice.zcash', _zcash), isTrue);
    });

    test('a resolver that cannot be read shows the lookup failure', () async {
      final lookup = ContactZnsLookup(
        readResolver: () => throw StateError('no network configuration'),
        onChanged: () {},
        debounce: Duration.zero,
      );

      lookup.update(address: 'alice.zcash', network: _zcash);
      await pumpEventQueue();

      expect(
        lookup.message('alice.zcash')?.text,
        ZnsLookupStatus.failed.message,
      );
      expect(lookup.canSave('alice.zcash', _zcash), isFalse);
    });

    test('a late answer for an earlier input is ignored', () async {
      final slow = Completer<ZnsResolution?>();
      final lookup = lookupWith(_GatedResolver(slow.future));

      lookup.update(address: 'alice.zcash', network: _zcash);
      lookup.update(address: _address, network: _zcash);
      slow.complete(const ZnsResolution(name: 'alice', address: _address));
      await pumpEventQueue();

      expect(lookup.message(_address), isNull);
      expect(lookup.nameToSave(_address, _zcash), isNull);
    });
  });

  group('AddressBookContact.znsName', () {
    AddressBookContact contact({String? znsName}) => AddressBookContact(
      id: 'c1',
      label: 'Alice',
      network: _zcash,
      address: _address,
      profilePictureId: kDefaultProfilePictureId,
      createdAtMs: 1,
      updatedAtMs: 2,
      znsName: znsName,
    );

    test('a contact saved by address keeps its stored form', () {
      expect(contact().toJson().containsKey('znsName'), isFalse);
    });

    test('round-trips through storage', () {
      final restored = AddressBookContact.tryFromJson(
        contact(znsName: 'alice.zcash').toJson(),
      );
      expect(restored?.znsName, 'alice.zcash');
      expect(
        restored?.previewWithName,
        'alice.zcash · ${restored?.addressPreview}',
      );
    });

    test('drops a stored name that is not valid', () {
      for (final stored in ['', 'alice', 'al-ice.zcash', 42]) {
        final json = contact().toJson()..['znsName'] = stored;
        expect(
          AddressBookContact.tryFromJson(json)?.znsName,
          isNull,
          reason: '$stored',
        );
      }
      final short = contact().toJson()..['znsName'] = 'Alice.ZEC';
      expect(AddressBookContact.tryFromJson(short)?.znsName, 'alice.zcash');
    });

    test('only a Zcash contact carries a name', () {
      final json = contact(znsName: 'alice.zcash').toJson()
        ..['network'] = AddressBookNetwork.ethereum.id;
      expect(AddressBookContact.tryFromJson(json)?.znsName, isNull);
    });
  });
}

class _GatedResolver implements ZnsNameResolver {
  _GatedResolver(this._answer);

  final Future<ZnsResolution?> _answer;

  @override
  Future<ZnsResolution?> resolve(String name) => _answer;
}
