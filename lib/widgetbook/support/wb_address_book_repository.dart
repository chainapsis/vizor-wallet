import '../../src/features/address_book/models/address_book_contact.dart';
import '../../src/features/address_book/providers/address_book_provider.dart';

/// Scoped to one preview, never backed by the host wallet's secure storage.
class WbAddressBookRepository implements AddressBookRepository {
  List<AddressBookContact> _contacts = const [];

  @override
  Future<List<AddressBookContact>> loadContacts() async => List.of(_contacts);

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    _contacts = List.of(contacts);
  }
}
