import '../../core/formatting/zec_amount.dart';
import '../../rust/api/sync.dart' as rust_sync;

/// Shown for a fee the wallet has not recorded. An unknown fee is never 0.
const kUnknownFeeText = 'Unknown';

/// Temporary private-mode feedback for an entry discovery can still change.
const kIncompleteDetailsText = 'Details incomplete';

/// Explains [kIncompleteDetailsText] on a receipt.
const kIncompleteDetailsHelpText =
    'Some details of this transaction, such as its recipients, memos, or '
    'fee, are not known yet. The amount shown may change.';

/// Titles the single line of an entry whose whole balance change is its
/// network fee, established by a recovered transparent self-transfer.
const kNetworkFeeText = 'Network fee';

/// Labels an amount that is the account's balance change, network fee
/// included.
const kNetChangeIncludesFeeText = 'Net change (includes network fee)';

bool transactionFeeIsUnknown(rust_sync.TransactionInfo tx) =>
    tx.feeState == rust_sync.TransactionFeeState.unknown;

/// How an entry shows its amount and network fee, so the fee appears once.
enum TransactionFeePresentation {
  /// The amount excludes the fee, which keeps its own line.
  separate,

  /// The amount is the balance change with the fee in it
  /// ([kNetChangeIncludesFeeText]); the fee keeps its own line.
  includedInAmount,

  /// The whole balance change is the fee: one [kNetworkFeeText] line, with no
  /// separate amount or fee line.
  feeOnly,
}

/// How [tx] shows its fee. Nothing is subtracted: an amount that includes the
/// fee is shown as it is.
TransactionFeePresentation transactionFeePresentation(
  rust_sync.TransactionInfo tx,
) {
  if (!tx.amountIncludesFee) return TransactionFeePresentation.separate;
  // Rust marks two distinct rows as including a fee: a reconstructed
  // transparent self-transfer with zero external payment, and an unknown-pool
  // balance movement whose payment role is not established. Only the former
  // justifies fee-only presentation. A mixed-pool movement can equal its fee
  // even after its effects settle, so !provisional alone is insufficient.
  // Missing recipient details do not invalidate an established self-transfer.
  final establishedSelfTransfer =
      !tx.provisional &&
      tx.txKind == 'sent' &&
      tx.displayPool == 'transparent' &&
      tx.isTransparent &&
      tx.feeState == rust_sync.TransactionFeeState.known &&
      tx.fee > BigInt.zero &&
      BigInt.from(tx.accountBalanceDelta) == -tx.fee;
  return establishedSelfTransfer && tx.displayAmount == tx.fee
      ? TransactionFeePresentation.feeOnly
      : TransactionFeePresentation.includedInAmount;
}

/// Whether a receipt without a recipient still titles the entry as a send:
/// its role is established and it moved more than its fee.
bool receiptTitlesSend(rust_sync.TransactionInfo tx) =>
    tx.txKind == 'sent' &&
    !transactionActivitySummaryIncomplete(tx) &&
    transactionFeePresentation(tx) != TransactionFeePresentation.feeOnly;

/// Whether the entry is incomplete: its payment details are missing, or the
/// wallet has not yet discovered all of its effects.
bool transactionDetailsIncomplete(rust_sync.TransactionInfo tx) =>
    !tx.detailsComplete || tx.provisional;

/// Activity needs an established amount, role, and pool. Missing recipients or
/// memos belong to the expanded receipt and do not make that summary uncertain.
bool transactionActivitySummaryIncomplete(rust_sync.TransactionInfo tx) =>
    tx.provisional || tx.txKind == 'unknown' || tx.displayPool == 'unknown';

/// The completeness part of an entry, for refresh signatures: an entry whose
/// details or fee arrive, or whose fee presentation changes, may change
/// nothing else a signature compares.
String transactionCompletenessSignature(rust_sync.TransactionInfo tx) =>
    '${tx.feeState.name}:${tx.detailsComplete}:${tx.provisional}:'
    '${transactionFeePresentation(tx).name}';

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

/// Shown for a transparent or mixed transaction whose outputs are not known
/// yet: no lookup has answered, or the last one failed. A later sync fills
/// them in.
const kTransparentDetailsUnavailableText =
    'Details unavailable — will update when the service is reachable';

/// Shown when private mode cannot look the transaction's outputs up.
const kTransparentDetailsNotCoveredText = 'Not available in private mode';

/// How often a receipt re-reads details that may still arrive.
const kTransparentDetailsPollInterval = Duration(seconds: 5);

/// Whether [detail]'s transparent outputs may still arrive, so a receipt
/// keeps re-reading it and asks for it to be looked up first.
bool transparentDetailsAwaited(rust_sync.TransactionDetail? detail) =>
    switch (detail?.transparentDetailsState) {
      rust_sync.TransparentDetailsState.pending ||
      rust_sync.TransparentDetailsState.unavailable => true,
      _ => false,
    };

/// Names the recipient of a send the account recorded no recipient for.
const kUnknownRecipientText = 'Unknown recipient';

/// Labels the list of a transaction's other transparent outputs on a receipt
/// with no recorded recipient.
const kTransactionOutputsText = 'Transaction outputs';

/// Says the listed outputs are the transaction's, not payments the account
/// is known to have made.
const kTransactionOutputsUnattributedText = 'Recipient not confirmed';

/// The address a receipt names as the recipient: only the one the account
/// recorded for its payment.
///
/// Transparent txid enhancement knows every output of the transaction, not
/// which of them this account paid: a mixed send can pay a shielded recipient
/// while another party's transparent output follows, and a shared funding can
/// return someone else's change. So an output is never promoted to the
/// recipient, whatever its order or ownership.
String? receiptRecipientAddress(rust_sync.TransactionDetail? detail) {
  final recorded = detail?.primaryAddress?.trim();
  return recorded == null || recorded.isEmpty ? null : recorded;
}

/// Whether a receipt with an established send role but no recorded recipient
/// keeps the send shell with an unknown recipient.
bool receiptHasUnknownRecipient(
  rust_sync.TransactionInfo tx,
  rust_sync.TransactionDetail? detail,
) => receiptTitlesSend(tx) && receiptRecipientAddress(detail) == null;

/// The transparent outputs a receipt lists as the transaction's, attributed
/// to no one: every known output the account did not record as its own, in
/// transaction order, when the receipt has no recorded recipient.
///
/// The account's own outputs (a send's change) are left out, as they are from
/// a receipt built on the stored transaction. Receives and shieldings name
/// only the account's own outputs, so they list none, and a recorded
/// recipient makes the list redundant.
List<rust_sync.TransparentRecipient> listedTransactionOutputs(
  rust_sync.TransactionDetail? detail,
) {
  if (detail == null ||
      detail.transparentDetailsState !=
          rust_sync.TransparentDetailsState.available ||
      receiptRecipientAddress(detail) != null) {
    return const [];
  }
  switch (detail.txKind) {
    case 'received' || 'receiving' || 'shielded' || 'migration':
      return const [];
  }
  return [
    for (final output in detail.transparentRecipients)
      if (!output.isOwn) output,
  ]..sort((a, b) => a.outputIndex.compareTo(b.outputIndex));
}

/// The transparent details state a receipt reports, or null when the
/// receipt is whole without them: the outputs are not known yet or cannot be
/// looked up, and the receipt has no recorded recipient.
/// Receives and shieldings name the account's own outputs, which are
/// recorded, so they never wait on this.
rust_sync.TransparentDetailsState? transparentDetailsNotice(
  rust_sync.TransactionDetail? detail,
) {
  final state = detail?.transparentDetailsState;
  if (state == null || state == rust_sync.TransparentDetailsState.available) {
    return null;
  }
  return switch (detail!.txKind) {
    'received' || 'receiving' || 'shielded' || 'migration' => null,
    _ => receiptRecipientAddress(detail) == null ? state : null,
  };
}

/// One line describing a development lookup's result.
String describeTransparentDetailsLookup(
  rust_sync.TransparentDetailsLookup lookup,
) {
  if (lookup.outcome != 'found') return lookup.outcome;
  final fee = lookup.feeZatoshi;
  return [
    '${lookup.recipients.length} outputs',
    if (fee != null) 'fee ${ZecAmount.fromZatoshi(fee).fee}',
    '${lookup.transparentInputCount} inputs',
  ].join(' · ');
}
