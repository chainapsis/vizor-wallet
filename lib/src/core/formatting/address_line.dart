import 'package:flutter/foundation.dart' show immutable;

import '../l10n/inline_spans.dart' show kInlineSlot;
import 'address_display.dart';

/// A one-line sentence naming a compacted address (`0x9aDF ... 819E2`),
/// optionally beside a saved contact's name, inside localized text such as
/// "To: {address} on {chain}".
///
/// `AddressLineText` never cuts [address]: when the line is too wide it gives
/// up the text after the address, then moves a contact name to its own line
/// above the address, then gives up the text before it (unless [keepBefore]),
/// so the head and tail of the address always show.
@immutable
class AddressLine {
  const AddressLine({
    required this.address,
    this.label,
    this.before = '',
    this.after = '',
    this.keepBefore = false,
    this.shortAddress,
  });

  /// Fills [template]'s address placeholder, e.g.
  /// `(address) => l10n.commonToAddressOnChain(address, chain)`.
  factory AddressLine.inTemplate(
    String Function(String address) template, {
    required String address,
    String? label,
    bool keepBefore = false,
  }) {
    final filled = template(kInlineSlot);
    final slot = filled.indexOf(kInlineSlot);
    assert(slot >= 0, 'The template has no address placeholder: $filled');
    if (slot < 0) return AddressLine(address: address, label: label);
    return AddressLine(
      address: address,
      label: label,
      before: filled.substring(0, slot),
      after: filled.substring(slot + kInlineSlot.length),
      keepBefore: keepBefore,
    );
  }

  /// The compacted address, shown whole.
  final String address;

  /// A saved contact's name, shown as `label (address)` while it fits and on
  /// its own line above the address when it does not.
  final String? label;

  /// Localized text before the address ("To: ").
  final String before;

  /// Localized text after the address (" on Ethereum").
  final String after;

  /// A shorter form of the same address (`truncatedAddress`) to show when
  /// [address] (`truncatedLongAddress`) does not fit even on its own, before
  /// the line wraps.
  final String? shortAddress;

  /// The same line naming [shortAddress] in place of [address].
  AddressLine? get withShortAddress {
    final short = shortAddress;
    if (short == null) return null;
    return AddressLine(
      address: short,
      label: label,
      before: before,
      after: after,
      keepBefore: keepBefore,
    );
  }

  /// Whether [before] states what the address is for ("Refund to: " under the
  /// amount paid) and must stay: a line too narrow for it wraps the address
  /// onto a second line instead.
  final bool keepBefore;

  /// [label] without surrounding whitespace, or null when it is blank.
  String? get contactLabel {
    final trimmed = label?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// The whole line, as shown when nothing has to give way.
  String get text => compose(label: contactLabel);

  /// The line naming [label] (left out when null), with or without the
  /// localized text around the address.
  String compose({
    required String? label,
    bool withBefore = true,
    bool withAfter = true,
  }) {
    final named = label == null ? address : labeledAddressText(label, address);
    return '${withBefore ? before : ''}$named${withAfter ? after : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is AddressLine &&
      other.address == address &&
      other.label == label &&
      other.before == before &&
      other.after == after &&
      other.keepBefore == keepBefore &&
      other.shortAddress == shortAddress;

  @override
  int get hashCode =>
      Object.hash(address, label, before, after, keepBefore, shortAddress);

  @override
  String toString() => 'AddressLine($text)'; // l10n-ignore: debug
}
