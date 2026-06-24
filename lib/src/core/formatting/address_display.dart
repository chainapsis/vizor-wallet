/// Canonical display formatting for Zcash addresses.
///
/// Single source of truth for the send review/status screens, the received
/// receipt, and the verify-address modal. The redesign removed the old
/// per-screen address chunking rules; new surfaces must format through
/// [truncatedAddress] / [addressVerifyGrid].
library;

/// Head/tail lengths for the single-line truncated form.
///
/// The Figma mocks are designer-typed placeholder strings with inconsistent
/// counts (7+6 on the review screens, 9+8 on the contact sub-line, 6+5 on
/// the status screens). The 7+6 pair used by the primary review screens
/// (`u195091 ... 190591`) is the one canonical form; every surface renders
/// through [truncatedAddress] so the counts cannot drift again.
const kTruncatedAddressHeadLength = 7;
const kTruncatedAddressTailLength = 6;
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

/// Single-line truncated address: first [kTruncatedAddressHeadLength] chars
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
  return '${trimmed.substring(0, kTruncatedAddressHeadLength)}'
      '$kTruncatedAddressSeparator'
      '${trimmed.substring(trimmed.length - kTruncatedAddressTailLength)}';
}

/// Number of leading/trailing hex chars kept when middle-truncating a
/// transaction id / hash to `12345678...90abcdef`.
const kTruncatedTxidEndLength = 8;

/// Middle-truncates a transaction id / hash for display (`12345678...90abcdef`).
/// Matches the form the mobile status screens use, so desktop and mobile
/// render tx ids identically.
String truncatedTxid(String txid) {
  final trimmed = txid.trim();
  if (trimmed.length <= kTruncatedTxidEndLength * 2) return trimmed;
  return '${trimmed.substring(0, kTruncatedTxidEndLength)}'
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
      'AddressVerifyGroup($text${highlighted ? ', highlighted' : ''})';
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
