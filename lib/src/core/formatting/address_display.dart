/// Canonical display formatting for addresses (Zcash and external chains)
/// and transaction ids.
///
/// Every shortened address or id the app shows goes through one of three
/// forms, chosen by what the reader does with it:
/// * [truncatedAddress] — the short form, for a line that also carries a
///   name, a label or an action (reviews, statuses, lists, composers).
/// * [truncatedLongAddress] — the long form, where checking the address is
///   the point and it has a line to itself: the wallet's own receive address,
///   the Send recipient lists, an address being saved as a contact, accounts
///   found on import. Pay's recipient rows carry amounts and stay short. A
///   deposit
///   address sits in a narrow value column beside its QR code and copy
///   action, so it takes the short form.
/// * [truncatedTxid] — transaction ids and other hashes.
///
/// Log lines and viewing keys keep their own shortening. The full-address
/// viewer renders the raw string in Geist Mono and wraps naturally —
/// [addressVerifyGrid] remains for any caller that still needs the legacy
/// 5-character grouping.
library;

import '../layout/app_form_factor.dart';

/// Head/tail lengths for the single-line truncated form.
///
/// The Figma mocks are designer-typed placeholder strings with inconsistent
/// counts (7+6 on the review screens, 9+8 on the contact sub-line, 6+5 on
/// the status screens). The short form is for lines shared with a label, a
/// name or an action. Phones take 6+5 (`u19509 ... 90591`): the longer 7+6
/// pushed "To:" off such lines or broke the address in two. Desktop has the
/// room for 9+7 (`u19509151 ... d190591`), which leaves a look-alike address
/// far more characters to match on the review screens.
const kTruncatedAddressHeadLength = kAppFormFactor == AppFormFactor.mobile
    ? 6
    : 9;
const kTruncatedAddressTailLength = kAppFormFactor == AppFormFactor.mobile
    ? 5
    : 7;
const kTruncatedAddressSeparator = ' ... ';

/// Zcash address pool for display-only UI decisions.
enum ZcashAddressDisplayKind { shielded, transparent }

/// Classifies a Zcash address for UI copy/icon selection.
///
/// Unified and Sapling addresses are treated as shielded. Transparent
/// mainnet/testnet/regtest addresses all start with `t`.
ZcashAddressDisplayKind zcashAddressDisplayKind(String address) {
  final lower = address.trim().toLowerCase();
  return lower.startsWith('t')
      ? ZcashAddressDisplayKind.transparent
      : ZcashAddressDisplayKind.shielded;
}

/// The short form: first [kTruncatedAddressHeadLength] chars
/// + [kTruncatedAddressSeparator] + last [kTruncatedAddressTailLength] chars.
///
/// Addresses short enough that truncation would not save space (length up to
/// head + tail + separator) are returned unchanged.
String truncatedAddress(String address) {
  final trimmed = address.trim();
  const compactLength =
      kTruncatedAddressHeadLength +
      kTruncatedAddressTailLength +
      kTruncatedAddressSeparator.length;
  if (trimmed.length <= compactLength) return trimmed;
  return '${trimmed.substring(0, kTruncatedAddressHeadLength)}' // l10n-ignore: address format
      '$kTruncatedAddressSeparator'
      '${trimmed.substring(trimmed.length - kTruncatedAddressTailLength)}';
}

/// Head/tail lengths for the long form (`u1q6g2k3r4s5t ... 66778899aab`).
const kLongTruncatedAddressHeadLength = 13;
const kLongTruncatedAddressTailLength = 11;

/// The long form: first [kLongTruncatedAddressHeadLength] chars +
/// [kTruncatedAddressSeparator] + last [kLongTruncatedAddressTailLength]
/// chars, for surfaces where checking the address is the point.
///
/// Addresses short enough that truncation would not save space are returned
/// unchanged.
String truncatedLongAddress(String address) {
  final trimmed = address.trim();
  const compactLength =
      kLongTruncatedAddressHeadLength +
      kLongTruncatedAddressTailLength +
      kTruncatedAddressSeparator.length;
  if (trimmed.length <= compactLength) return trimmed;
  return '${trimmed.substring(0, kLongTruncatedAddressHeadLength)}' // l10n-ignore: address format
      '$kTruncatedAddressSeparator'
      '${trimmed.substring(trimmed.length - kLongTruncatedAddressTailLength)}';
}

/// A saved contact's name beside its compacted address: `Rowan (0x0cd7 ... 7181)`.
String labeledAddressText(String label, String compactAddress) =>
    '$label ($compactAddress)'; // l10n-ignore: name and address format

/// Number of leading/trailing hex chars kept when middle-truncating a
/// transaction id / hash to `12345678...90abcdef`.
const kTruncatedTxidEndLength = 8;

/// Middle-truncates a transaction id / hash for display (`12345678...90abcdef`).
/// Matches the form the mobile status screens use, so desktop and mobile
/// render tx ids identically.
String truncatedTxid(String txid) {
  final trimmed = txid.trim();
  // An id no longer than its shortened form stays whole.
  if (trimmed.length <= kTruncatedTxidEndLength * 2 + 3) return trimmed;
  return '${trimmed.substring(0, kTruncatedTxidEndLength)}' // l10n-ignore: txid format
      '...'
      '${trimmed.substring(trimmed.length - kTruncatedTxidEndLength)}';
}

/// Characters per group in the verify-address modal grid.
const kAddressVerifyGroupSize = 5;

/// Groups per row in the verify-address modal grid. With [kAddressVerifyGroupSize]
/// this reproduces the Figma mock's 5-groups-per-line, ~8-line layout for a
/// full unified address.
const kAddressVerifyGroupsPerRow = 5;

/// Fixed highlight positions, expressed from each end of the group list:
/// the Figma mock emphasizes groups 0 and 2 of the first row and the 3rd-last
/// and last groups of the last row (non-consecutive, skipping 1 and N-2).
const kAddressVerifyHeadHighlightOffsets = [0, 2];
const kAddressVerifyTailHighlightOffsets = [0, 2];

/// One fixed-size character group of a full address in the verify modal.
class AddressVerifyGroup {
  const AddressVerifyGroup({required this.text, required this.highlighted});

  /// Up to [kAddressVerifyGroupSize] characters; only the final group of an
  /// address may be shorter.
  final String text;

  /// Whether this group renders with the crimson emphasis color.
  final bool highlighted;

  @override
  bool operator ==(Object other) =>
      other is AddressVerifyGroup &&
      other.text == text &&
      other.highlighted == highlighted;

  @override
  int get hashCode => Object.hash(text, highlighted);

  @override
  String toString() =>
      'AddressVerifyGroup($text${highlighted ? ', highlighted' : ''})'; // l10n-ignore: debug
}

/// Splits a full address into rows of fixed-size groups for the verify
/// modal: [kAddressVerifyGroupSize] characters per group,
/// [kAddressVerifyGroupsPerRow] groups per row. The last group (and last
/// row) may be shorter.
///
/// Groups at the fixed positions [kAddressVerifyHeadHighlightOffsets] (from
/// the start) and [kAddressVerifyTailHighlightOffsets] (from the end) are
/// flagged [AddressVerifyGroup.highlighted], reproducing the Figma mock's
/// non-consecutive pattern (0, 2, N-3, N-1). Overlapping positions on short
/// addresses simply highlight once.
List<List<AddressVerifyGroup>> addressVerifyGrid(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return const [];

  final groupCount = (trimmed.length / kAddressVerifyGroupSize).ceil();
  final highlighted = <int>{
    for (final offset in kAddressVerifyHeadHighlightOffsets)
      if (offset < groupCount) offset,
    for (final offset in kAddressVerifyTailHighlightOffsets)
      if (groupCount - 1 - offset >= 0) groupCount - 1 - offset,
  };
  final groups = List<AddressVerifyGroup>.generate(groupCount, (index) {
    final start = index * kAddressVerifyGroupSize;
    final end = start + kAddressVerifyGroupSize;
    return AddressVerifyGroup(
      text: trimmed.substring(
        start,
        end > trimmed.length ? trimmed.length : end,
      ),
      highlighted: highlighted.contains(index),
    );
  });

  return [
    for (var row = 0; row * kAddressVerifyGroupsPerRow < groupCount; row++)
      groups.sublist(
        row * kAddressVerifyGroupsPerRow,
        ((row + 1) * kAddressVerifyGroupsPerRow) > groupCount
            ? groupCount
            : (row + 1) * kAddressVerifyGroupsPerRow,
      ),
  ];
}
