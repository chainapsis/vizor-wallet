import 'dart:async';

import '../../../../main.dart' show log;
import '../../../core/formatting/address_display.dart';
import '../../../core/naming/zns_name_resolver.dart';
import '../../../core/naming/zns_recipient_lookup.dart';
import 'address_book_contact.dart';
import 'address_format_validator.dart';

/// What a contact form's name line says, which sets its tone and icon.
enum ContactZnsMessageKind {
  /// The lookup is in flight.
  pending,

  /// The name resolved to a usable address.
  resolved,

  /// An edited contact keeps the name it was saved from.
  saved,

  /// The name has no usable address, or a plain address has a format error.
  error,
}

/// The line a contact form shows under its address field for a Zcash name.
class ContactZnsMessage {
  const ContactZnsMessage(this.text, this.kind);

  final String text;
  final ContactZnsMessageKind kind;

  bool get isError => kind == ContactZnsMessageKind.error;
}

/// Resolves a Zcash name typed into a contact form's address field.
///
/// A contact saves the address the name resolves to, with the name kept as
/// a label. The contact is then a fixed address the user approved, like any
/// other saved contact, and a later change to the name never moves it.
///
/// The form calls [update] whenever the address text or the network changes,
/// and rebuilds when [onChanged] fires. [readResolver] runs only when a name
/// needs a lookup, so a form that never sees a name never touches the
/// network configuration.
class ContactZnsLookup {
  ContactZnsLookup({
    required this.onChanged,
    required this.readResolver,
    String? savedName,
    this.debounce = kZnsLookupDebounce,
  }) : _state = ZnsRecipientState(carriedName: savedName);

  final void Function() onChanged;
  final ZnsNameResolver? Function() readResolver;

  /// The pause after the last edit before a lookup starts.
  final Duration debounce;
  final ZnsRecipientState _state;
  int _seq = 0;
  var _disposed = false;

  /// Starts a lookup when [address] is a Zcash name on the Zcash network.
  /// Any other edit drops the lookup and the saved name.
  void update({required String address, required AddressBookNetwork network}) {
    final seq = ++_seq;
    _state.reset();
    final name = _nameIn(address, network);
    if (name != null) {
      _state.begin();
      unawaited(_lookUp(address, name, seq));
    }
    onChanged();
  }

  Future<void> _lookUp(String address, String name, int seq) async {
    await Future<void>.delayed(debounce);
    if (_disposed || seq != _seq) return;
    final ZnsRecipientLookup lookup;
    try {
      lookup = await lookUpZnsRecipient(readResolver(), name);
    } catch (e) {
      // Reading the resolver can fail when the network configuration does
      // not load; the field shows the lookup failure instead of breaking.
      log('Contacts: ZNS resolver unavailable: $e');
      if (_disposed || seq != _seq) return;
      _state.fail(ZnsLookupStatus.failed);
      onChanged();
      return;
    }
    if (_disposed || seq != _seq) return;
    switch (lookup) {
      case ZnsRecipientMissing(:final status):
        _state.fail(status);
      case ZnsRecipientFound(:final resolution):
        _state.settle(
          address,
          resolution,
          addressValid:
              addressFormatIssue(
                AddressBookNetwork.zcash,
                resolution.address,
              ) ==
              null,
        );
    }
    onChanged();
  }

  void dispose() => _disposed = true;

  /// Whether [address] on [network] is a Zcash name, which the address book
  /// format check must not judge as a raw address.
  bool isName(String address, AddressBookNetwork network) =>
      _nameIn(address, network) != null;

  /// Whether the form can save [address]: it is not a name, or the name has
  /// resolved to a usable address.
  bool canSave(String address, AddressBookNetwork network) =>
      !isName(address, network) || _state.resolutionFor(address) != null;

  /// The address to store for field text [address].
  String addressToSave(String address) => _state.paymentAddress(address);

  /// The name to store with the contact, or null.
  String? nameToSave(String address, AddressBookNetwork network) =>
      network == AddressBookNetwork.zcash ? _state.displayName(address) : null;

  /// The line to show under the field, or null for none.
  ContactZnsMessage? message(String address) {
    final status = _state.status;
    if (status != null) {
      return ContactZnsMessage(
        status.message,
        status.isError
            ? ContactZnsMessageKind.error
            : ContactZnsMessageKind.pending,
      );
    }
    final resolution = _state.resolutionFor(address);
    if (resolution != null) {
      return ContactZnsMessage(
        'Resolves to ${truncatedAddress(resolution.address)}',
        ContactZnsMessageKind.resolved,
      );
    }
    final savedName = _state.displayName(address);
    if (savedName != null) {
      return ContactZnsMessage(
        'Saved from $savedName',
        ContactZnsMessageKind.saved,
      );
    }
    return null;
  }

  static String? _nameIn(String address, AddressBookNetwork network) =>
      network == AddressBookNetwork.zcash
      ? znsNameFromRecipientInput(address)
      : null;
}
