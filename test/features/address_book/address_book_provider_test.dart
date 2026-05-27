import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads contacts sorted by network and creation time', () async {
    final repo = _FakeAddressBookRepository([
      _contact(
        id: 'sol-2',
        label: 'Sol 2',
        network: AddressBookNetwork.solana,
        createdAtMs: 20,
      ),
      _contact(
        id: 'zec-1',
        label: 'Zec 1',
        network: AddressBookNetwork.zcash,
        createdAtMs: 30,
      ),
      _contact(
        id: 'sol-1',
        label: 'Sol 1',
        network: AddressBookNetwork.solana,
        createdAtMs: 10,
      ),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    final state = await container.read(addressBookProvider.future);

    expect(state.contacts.map((contact) => contact.id), [
      'zec-1',
      'sol-1',
      'sol-2',
    ]);
  });

  test('adds trimmed contacts and persists the full list', () async {
    final repo = _FakeAddressBookRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(addressBookProvider.future);

    final contact = await container
        .read(addressBookProvider.notifier)
        .addContact(
          label: ' Alice ',
          network: AddressBookNetwork.zcash,
          address: ' u1alice ',
          profilePictureId: 'samurai',
        );

    expect(contact.label, 'Alice');
    expect(contact.address, 'u1alice');
    expect(repo.savedLists, hasLength(1));
    expect(repo.savedLists.single.single.id, contact.id);
    expect(container.read(addressBookProvider).value?.contacts.single, contact);
  });

  test('waits for the initial load before adding contacts', () async {
    final repo = _DelayedAddressBookRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    container.read(addressBookProvider);
    final addFuture = container
        .read(addressBookProvider.notifier)
        .addContact(
          label: ' Alice ',
          network: AddressBookNetwork.zcash,
          address: ' u1alice ',
          profilePictureId: 'samurai',
        );
    await pumpEventQueue();

    expect(repo.savedLists, isEmpty);

    repo.complete([_contact(id: 'existing', label: 'Existing')]);
    final added = await addFuture;

    expect(repo.savedLists, hasLength(1));
    expect(repo.savedLists.single.map((contact) => contact.id), [
      'existing',
      added.id,
    ]);
    expect(container.read(addressBookProvider).value?.contacts, hasLength(2));
  });

  test('decodes malformed persisted payloads as an empty contact list', () {
    expect(
      SecureStorageAddressBookRepository.decodeContactsJson('{not-json'),
      isEmpty,
    );
    expect(
      SecureStorageAddressBookRepository.decodeContactsJson(
        '[{"id":"future","label":"Future","network":"futurechain","address":"0x1"}]',
      ),
      isEmpty,
    );
  });

  test(
    'stores contacts as secure-store JSON without an unlock session',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = AppSecureStore.instance;
      await store.deleteAll();
      store.clearSessionPassword();
      addTearDown(() async {
        await store.deleteAll();
        store.clearSessionPassword();
      });

      final repo = SecureStorageAddressBookRepository(store: store);
      final contact = _contact(id: 'alice', label: 'Alice');

      await repo.saveContacts([contact]);

      final raw = await store.readString(kAddressBookContactsKey);
      final decoded = jsonDecode(raw!) as List<dynamic>;
      expect(decoded.single, containsPair('id', 'alice'));

      store.clearSessionPassword();
      final restored = await repo.loadContacts();

      expect(restored, hasLength(1));
      expect(restored.single.id, 'alice');
    },
  );

  test('filters by label address and network', () async {
    final repo = _FakeAddressBookRepository([
      _contact(
        id: 'zec',
        label: 'Mike',
        address: 'u1mike',
        network: AddressBookNetwork.zcash,
      ),
      _contact(
        id: 'sol',
        label: 'Exchange',
        address: '43123sol',
        network: AddressBookNetwork.solana,
      ),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(addressBookProvider.future);

    container.read(addressBookProvider.notifier).setQuery('solana');

    final state = container.read(addressBookProvider).value!;
    expect(state.filteredContacts.map((contact) => contact.id), ['sol']);
  });

  test('updates and removes contacts through persistence', () async {
    final repo = _FakeAddressBookRepository([
      _contact(id: 'zed', label: 'Zed'),
      _contact(id: 'bob', label: 'Bob'),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(addressBookProvider.future);
    final notifier = container.read(addressBookProvider.notifier);

    await notifier.updateContact(
      'zed',
      label: 'Zed Sol',
      network: AddressBookNetwork.solana,
      address: 'solzed',
      profilePictureId: 'dragon',
    );
    await notifier.removeContact('bob');

    final contacts = container.read(addressBookProvider).value!.contacts;
    expect(contacts, hasLength(1));
    expect(contacts.single.id, 'zed');
    expect(contacts.single.network, AddressBookNetwork.solana);
    expect(contacts.single.profilePictureId, 'dragon');
    expect(repo.savedLists, hasLength(2));
  });
}

ProviderContainer _container(AddressBookRepository repo) {
  return ProviderContainer(
    overrides: [addressBookRepositoryProvider.overrideWithValue(repo)],
  );
}

AddressBookContact _contact({
  required String id,
  required String label,
  AddressBookNetwork network = AddressBookNetwork.zcash,
  String address = 'u1address',
  String profilePictureId = 'knight',
  int createdAtMs = 0,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: network,
    address: address,
    profilePictureId: profilePictureId,
    createdAtMs: createdAtMs,
    updatedAtMs: createdAtMs,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  List<AddressBookContact> contacts;
  final savedLists = <List<AddressBookContact>>[];

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
    savedLists.add([...contacts]);
  }
}

class _DelayedAddressBookRepository implements AddressBookRepository {
  final _loadCompleter = Completer<List<AddressBookContact>>();
  var contacts = <AddressBookContact>[];
  final savedLists = <List<AddressBookContact>>[];

  void complete(List<AddressBookContact> contacts) {
    this.contacts = [...contacts];
    _loadCompleter.complete(this.contacts);
  }

  @override
  Future<List<AddressBookContact>> loadContacts() => _loadCompleter.future;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
    savedLists.add([...contacts]);
  }
}
