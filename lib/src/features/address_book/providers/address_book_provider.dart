import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/storage/app_secure_store.dart';
import '../models/address_book_contact.dart';
import '../models/address_book_label_lookup.dart';

const kAddressBookContactsKey = 'zcash_address_book_contacts_v1';

abstract class AddressBookRepository {
  Future<List<AddressBookContact>> loadContacts();
  Future<void> saveContacts(List<AddressBookContact> contacts);
}

class SecureStorageAddressBookRepository implements AddressBookRepository {
  SecureStorageAddressBookRepository({AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;

  final AppSecureStore _store;

  @override
  Future<List<AddressBookContact>> loadContacts() async {
    final raw = await _store.readString(kAddressBookContactsKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    return decodeContactsJson(raw);
  }

  static List<AddressBookContact> decodeContactsJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }

    if (decoded is! List) return const [];

    final contacts = <AddressBookContact>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final contact = _contactFromJsonItem(item);
      if (contact == null || !_isUsableContact(contact)) continue;
      contacts.add(contact);
    }
    return contacts;
  }

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    await _store.writeString(
      kAddressBookContactsKey,
      jsonEncode([for (final contact in contacts) contact.toJson()]),
    );
  }

  static bool _isUsableContact(AddressBookContact contact) {
    return contact.id.trim().isNotEmpty &&
        contact.label.trim().isNotEmpty &&
        contact.address.trim().isNotEmpty;
  }

  static AddressBookContact? _contactFromJsonItem(Map<dynamic, dynamic> item) {
    try {
      return AddressBookContact.tryFromJson(Map<String, Object?>.from(item));
    } catch (_) {
      return null;
    }
  }
}

class AddressBookState {
  const AddressBookState({this.contacts = const [], this.query = ''});

  final List<AddressBookContact> contacts;
  final String query;

  List<AddressBookContact> get filteredContacts {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return contacts;
    return [
      for (final contact in contacts)
        if (contact.label.toLowerCase().contains(normalized) ||
            contact.address.toLowerCase().contains(normalized) ||
            contact.network.id.toLowerCase().contains(normalized) ||
            contact.network.label.toLowerCase().contains(normalized))
          contact,
    ];
  }

  bool get hasContacts => contacts.isNotEmpty;
  bool get hasQuery => query.trim().isNotEmpty;

  AddressBookState copyWith({
    List<AddressBookContact>? contacts,
    String? query,
  }) {
    return AddressBookState(
      contacts: contacts ?? this.contacts,
      query: query ?? this.query,
    );
  }
}

final addressBookRepositoryProvider = Provider<AddressBookRepository>((ref) {
  return SecureStorageAddressBookRepository();
});

class AddressBookNotifier extends AsyncNotifier<AddressBookState> {
  final _random = Random.secure();

  @override
  FutureOr<AddressBookState> build() async {
    final repository = ref.watch(addressBookRepositoryProvider);
    final contacts = await repository.loadContacts();
    return AddressBookState(contacts: _sortedContacts(contacts));
  }

  void setQuery(String query) {
    final current = state.value ?? const AddressBookState();
    state = AsyncData(current.copyWith(query: query));
  }

  Future<AddressBookContact> addContact({
    required String label,
    required AddressBookNetwork network,
    required String address,
    required String profilePictureId,
  }) async {
    final current = await _loadedState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final contact = AddressBookContact(
      id: _newContactId(),
      label: _cleanLabel(label),
      network: network,
      address: address.trim(),
      profilePictureId: resolveProfilePictureOption(profilePictureId).id,
      createdAtMs: now,
      updatedAtMs: now,
    );
    final contacts = _sortedContacts([...current.contacts, contact]);
    await _persist(contacts);
    state = AsyncData(current.copyWith(contacts: contacts));
    return contact;
  }

  Future<void> updateContact(
    String id, {
    required String label,
    required AddressBookNetwork network,
    required String address,
    required String profilePictureId,
  }) async {
    final current = await _loadedState();
    final contacts = _sortedContacts([
      for (final contact in current.contacts)
        if (contact.id == id)
          contact.copyWith(
            label: _cleanLabel(label),
            network: network,
            address: address.trim(),
            profilePictureId: resolveProfilePictureOption(profilePictureId).id,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          )
        else
          contact,
    ]);
    await _persist(contacts);
    state = AsyncData(current.copyWith(contacts: contacts));
  }

  Future<void> removeContact(String id) async {
    final current = await _loadedState();
    final contacts = [
      for (final contact in current.contacts)
        if (contact.id != id) contact,
    ];
    await _persist(contacts);
    state = AsyncData(current.copyWith(contacts: contacts));
  }

  Future<int> importContacts(
    Iterable<AddressBookContact> importedContacts,
  ) async {
    final current = await _loadedState();
    final contacts = [...current.contacts];
    final existingIds = {for (final contact in contacts) contact.id};
    final existingKeys = {for (final contact in contacts) _contactKey(contact)};
    var added = 0;

    for (final imported in importedContacts) {
      final label = _cleanLabel(imported.label);
      final address = imported.address.trim();
      if (label.isEmpty || address.isEmpty) continue;
      final key = _contactKey(imported);
      if (existingKeys.contains(key)) continue;

      final id = imported.id.trim();
      final nextId = id.isEmpty || existingIds.contains(id)
          ? _newContactId()
          : id;
      final now = DateTime.now().millisecondsSinceEpoch;
      final contact = AddressBookContact(
        id: nextId,
        label: label,
        network: imported.network,
        address: address,
        profilePictureId: resolveProfilePictureOption(
          imported.profilePictureId,
        ).id,
        createdAtMs: imported.createdAtMs > 0 ? imported.createdAtMs : now,
        updatedAtMs: imported.updatedAtMs > 0 ? imported.updatedAtMs : now,
      );
      contacts.add(contact);
      existingIds.add(nextId);
      existingKeys.add(key);
      added += 1;
    }

    final sorted = _sortedContacts(contacts);
    await _persist(sorted);
    state = AsyncData(current.copyWith(contacts: sorted));
    return added;
  }

  Future<void> _persist(List<AddressBookContact> contacts) async {
    await ref.read(addressBookRepositoryProvider).saveContacts(contacts);
  }

  Future<AddressBookState> _loadedState() async {
    final current = state.value;
    if (current != null) return current;
    return future;
  }

  String _newContactId() {
    final entropy = _random.nextInt(0x3fffffff).toRadixString(16);
    return 'contact_${DateTime.now().microsecondsSinceEpoch}_$entropy';
  }

  static String _cleanLabel(String label) {
    final trimmed = label.trim();
    return trimmed.length <= 20 ? trimmed : trimmed.substring(0, 20);
  }

  static List<AddressBookContact> _sortedContacts(
    List<AddressBookContact> contacts,
  ) {
    return [...contacts]..sort((a, b) {
      final networkOrder = a.network.index.compareTo(b.network.index);
      if (networkOrder != 0) return networkOrder;
      return a.createdAtMs.compareTo(b.createdAtMs);
    });
  }

  static String _contactKey(AddressBookContact contact) {
    return '${contact.network.id}:'
        '${normalizedAddressBookAddress(contact.network, contact.address)}';
  }
}

final addressBookProvider =
    AsyncNotifierProvider<AddressBookNotifier, AddressBookState>(
      AddressBookNotifier.new,
    );
