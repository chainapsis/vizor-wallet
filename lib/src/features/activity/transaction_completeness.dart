import '../../core/l10n/l10n.dart';
import '../../providers/account_models.dart';
import '../../rust/api/sync.dart' as rust_sync;

bool transactionFeeIsUnknown(rust_sync.TransactionInfo tx) =>
    tx.feeState == rust_sync.TransactionFeeState.unknown;

/// Display-only fee evidence for this receipt. Never promotes account attribution
/// or accepts a late detail response for another transaction or activity role.
BigInt? unattributedReceiptNetworkFee(
  rust_sync.TransactionInfo tx,
  rust_sync.TransactionDetail? detail,
) {
  if (tx.feeState != rust_sync.TransactionFeeState.unknown ||
      detail == null ||
      detail.txidHex.toLowerCase() != tx.txidHex.toLowerCase() ||
      detail.txKind != tx.txKind) {
    return null;
  }
  return detail.networkFee;
}

/// How an entry shows its amount and network fee, so the fee appears once.
enum TransactionFeePresentation {
  /// The amount excludes the fee, which keeps its own line.
  separate,

  /// The amount is the balance change with the fee in it
  /// (`activityReceiptNetChange`); the fee keeps its own line.
  includedInAmount,

  /// The whole balance change is the fee: one `activityReceiptNetChange` line, with no
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

/// Whether the entry is incomplete: its payment details are missing, or the
/// wallet has not yet discovered all of its effects.
bool transactionDetailsIncomplete(rust_sync.TransactionInfo tx) =>
    !tx.detailsComplete || tx.provisional;

/// Whether a receipt's transparent details establish everything the receipt
/// shows, so it needs no incomplete-details notice even when its activity
/// entry does: the wallet marks a detail complete this way only when private
/// details name every payee.
bool receiptDetailsComplete(rust_sync.TransactionDetail? detail) =>
    detail != null &&
    detail.detailsComplete &&
    !detail.provisional &&
    detail.transparentDetailsState ==
        rust_sync.TransparentDetailsState.available;

/// Activity needs an established amount, role, and pool. Missing recipients or
/// memos belong to the expanded receipt and do not make that summary uncertain.
bool transactionActivitySummaryIncomplete(rust_sync.TransactionInfo tx) =>
    tx.provisional || tx.txKind == 'unknown' || tx.displayPool == 'unknown';

/// The completeness part of an entry, for refresh signatures: an entry whose
/// details or fee arrive, or whose fee presentation changes, may change
/// nothing else a signature compares.
String transactionCompletenessSignature(rust_sync.TransactionInfo tx) =>
    '${tx.feeState.name}:${tx.detailsComplete}:${tx.provisional}:' // l10n-ignore: signature
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

/// Short phrases for what the private details leave out, by the names
/// `TransactionDetail.transparentOmissions` uses.
String? _omissionPhrase(AppLocalizations l10n, String omission) =>
    switch (omission) {
      'multiple_source_scripts' => l10n.activityOmissionOtherSenders,
      'more_than_two_outputs' => l10n.activityOmissionLaterOutputs,
      'shielded_and_transparent_funding' =>
        l10n.activityOmissionShieldedFunding,
      'non_standard_sender' => l10n.activityOmissionSender,
      'non_standard_output' => l10n.activityOmissionOutputAddress,
      'shared_funding' => l10n.activityOmissionSharedFunding,
      _ => null,
    };

/// What [detail]'s transparent details leave out, in the order the wallet
/// lists them; empty when nothing is left out.
List<String> transparentOmissionPhrases(
  AppLocalizations l10n,
  rust_sync.TransactionDetail? detail,
) {
  final count = detail?.transparentOutputCount;
  return [
    for (final omission in detail?.transparentOmissions ?? const <String>[])
      if (omission == 'more_than_two_outputs' && count != null && count > 2)
        l10n.activityOmissionMoreOutputs(count - 2)
      else
        _omissionPhrase(l10n, omission) ?? omission.replaceAll('_', ' '),
  ];
}

/// Whether a receipt offers to load [detail]'s full details publicly: where
/// the load can show more than the receipt does. That is a receipt that shows
/// private mode cannot cover the transaction, or one listing outputs whose
/// private details stop after the second. A receipt that lists no outputs (a
/// receive names its own) or shows one sender gains nothing, so offers
/// nothing. Loading is always the user's explicit choice.
bool offersPublicDetailsLookup(rust_sync.TransactionDetail? detail) =>
    transparentDetailsNotice(detail) ==
        rust_sync.TransparentDetailsState.notCovered ||
    (listedTransactionOutputs(detail).isNotEmpty &&
        detail!.transparentOmissions.contains('more_than_two_outputs'));

/// How often a receipt re-reads details that may still arrive.
const kTransparentDetailsPollInterval = Duration(seconds: 5);

/// Whether [detail]'s transparent outputs may still arrive, so a receipt
/// keeps re-reading it and asks for it to be looked up first. A failed
/// lookup is worth waiting on only with Private queries on, where the
/// private service may answer later; with it off the receipt stops there,
/// as it always has. A lookup the wallet gave up on reads as unavailable
/// but is never waited on: no sync asks for it again.
bool transparentDetailsAwaited(
  rust_sync.TransactionDetail? detail, {
  required bool privateQueriesEnabled,
}) => switch (detail?.transparentDetailsState) {
  rust_sync.TransparentDetailsState.pending => true,
  rust_sync.TransparentDetailsState.unavailable => privateQueriesEnabled,
  // Listed, not defaulted, so a new state has to decide whether it is
  // waited on.
  rust_sync.TransparentDetailsState.gaveUp => false,
  rust_sync.TransparentDetailsState.available => false,
  rust_sync.TransparentDetailsState.notCovered => false,
  null => false,
};

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
///
/// Only an amount that is a payment, with its fee on its own line, fits that
/// shell. An amount that includes the fee is a balance change whose payment
/// role is not established, and a fee-only entry is its one fee line; both
/// keep the neutral receipt, which labels them as such.
bool receiptHasUnknownRecipient(
  rust_sync.TransactionInfo tx,
  rust_sync.TransactionDetail? detail,
) =>
    tx.txKind == 'sent' &&
    !transactionActivitySummaryIncomplete(tx) &&
    transactionFeePresentation(tx) == TransactionFeePresentation.separate &&
    receiptRecipientAddress(detail) == null;

/// The wallet account a receive came from, when the receipt has no exact
/// source address: the account the wallet recorded as sending its received
/// outputs, if it is still listed. It names an account, never an address or
/// a sole funder.
AccountInfo? receiptSourceAccount(
  rust_sync.TransactionDetail? detail,
  Iterable<AccountInfo> accounts,
) {
  final address = detail?.sourceAddress?.trim();
  if (address != null && address.isNotEmpty) return null;
  final uuid = detail?.sourceAccountUuid;
  if (uuid == null) return null;
  for (final account in accounts) {
    if (account.uuid == uuid) return account;
  }
  return null;
}

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
