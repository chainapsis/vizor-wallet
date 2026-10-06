import '../../rust/api/sync.dart' as rust_sync;

/// Shown for a fee the wallet has not recorded. An unknown fee is never 0.
const kUnknownFeeText = 'Unknown';

/// Temporary private-mode feedback for an entry discovery can still change.
const kIncompleteDetailsText = 'Details incomplete';

/// Explains [kIncompleteDetailsText] on a receipt.
const kIncompleteDetailsHelpText =
    'Some details of this transaction, such as its recipients, memos, or '
    'fee, are not known yet. The amount shown may change.';

/// Titles the single line of an entry whose whole balance change is the
/// account's own network fee, and labels a fee that is the whole
/// transaction's rather than the account's.
const kNetworkFeeText = 'Network fee';

/// Labels an amount that is the account's net balance change, not a payment.
const kNetChangeText = 'Net change';

/// Titles an activity row whose amount is the account's net balance change:
/// value left the account, but no payment of that amount is known.
const kSentNetText = 'Sent (net)';

/// Explains a [kNetworkFeeText] that is the whole transaction's fee, with
/// that of any funding transaction shown as part of it.
const kWholeTransactionFeeHelpText =
    'The network fee of the whole transaction, including any transaction '
    'that funded it. Others who funded them may have paid part of it, so '
    'this account\'s share is not known.';

bool transactionFeeIsUnknown(rust_sync.TransactionInfo tx) =>
    tx.feeState == rust_sync.TransactionFeeState.unknown;

/// Whether the shown fee is the whole transaction's: the account's own share
/// is unknown, so it is labelled [kNetworkFeeText], never as the account's.
bool transactionFeeIsWholeTransaction(rust_sync.TransactionInfo tx) =>
    tx.feeState == rust_sync.TransactionFeeState.wholeTransaction;

/// How an entry shows its amount and network fee, so the fee appears once.
enum TransactionFeePresentation {
  /// The amount is a payment or receipt, and the fee keeps its own line.
  separate,

  /// The amount is the account's net balance change ([kNetChangeText]), not
  /// a payment; the fee keeps its own line and is not subtracted from it.
  netChange,

  /// The whole balance change is the account's own fee: one [kNetworkFeeText]
  /// line, with no separate amount or fee line.
  feeOnly,
}

/// How [tx] shows its fee. Nothing is subtracted: a net change is shown as it
/// is, and is the fee alone only when the account's own fee equals it.
TransactionFeePresentation transactionFeePresentation(
  rust_sync.TransactionInfo tx,
) {
  if (!tx.amountIsNetChange) return TransactionFeePresentation.separate;
  // The change is the fee alone only when it is settled and exactly the
  // account's own known fee: a whole-transaction fee, or a change that can
  // still move, may hide a payment.
  final feeAlone =
      !tx.provisional &&
      tx.feeState == rust_sync.TransactionFeeState.known &&
      tx.fee > BigInt.zero &&
      BigInt.from(tx.accountBalanceDelta) == -tx.fee;
  return feeAlone && tx.displayAmount == tx.fee
      ? TransactionFeePresentation.feeOnly
      : TransactionFeePresentation.netChange;
}

/// Whether the entry is incomplete: its payment details are missing, or the
/// wallet has not yet discovered all of its effects.
bool transactionDetailsIncomplete(rust_sync.TransactionInfo tx) =>
    !tx.detailsComplete || tx.provisional;

/// Activity needs an established amount, role, and pool. Missing recipients or
/// memos belong to the expanded receipt and do not make that summary uncertain.
bool transactionActivitySummaryIncomplete(rust_sync.TransactionInfo tx) =>
    tx.provisional || tx.txKind == 'unknown' || tx.displayPool == 'unknown';

/// The completeness part of an entry, for refresh signatures: an entry whose
/// details or fee arrive changes nothing else a signature compares.
String transactionCompletenessSignature(rust_sync.TransactionInfo tx) =>
    '${tx.feeState.name}:${tx.detailsComplete}:${tx.provisional}:'
    '${tx.amountIsNetChange}';

/// The entry a receipt showing a provisional row of `txidHex` now shows.
///
/// A provisional entry's role can change once its details arrive: a net debit
/// can turn out to be a shielding. The receipt follows it only when the
/// transaction has a single row, so separate legs of a self-send are never
/// conflated.
rust_sync.TransactionInfo? provisionalRoleSuccessor(
  Iterable<rust_sync.TransactionInfo> transactions,
  bool Function(String txidHex) matchesTxid,
) {
  final rows = transactions.where((tx) => matchesTxid(tx.txidHex)).toList();
  return rows.length == 1 ? rows.single : null;
}
