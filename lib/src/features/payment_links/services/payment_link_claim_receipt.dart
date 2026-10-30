part of 'payment_link_service.dart';

/// Receipt display follows normal Receive at one confirmation. Recovery ends
/// only after six scanned confirmations, without holding the receipt UI open.
@visibleForTesting
Future<void> reconcilePaymentLinkClaimReceipt({
  required PaymentLinkReceivedRecord record,
  required List<rust_sync.TransactionInfo> transactions,
  required BigInt verifiedHeight,
  required PaymentLinkReceivedStore store,
  required Future<bool> Function(PaymentLinkReceivedRecord)
  deleteRetainedWallet,
}) async {
  final status = paymentLinkReceivedStatusForTransactions(
    claimTxids: record.claimTxids!,
    transactions: transactions,
    chainTipHeight: verifiedHeight,
  );
  switch (status) {
    case PaymentLinkReceivedStatus.readyToClaim:
      await store.markReadyToClaim(address: record.address, expected: record);
    case PaymentLinkReceivedStatus.submitting:
      throw StateError(
        'Receipt reconciliation cannot produce submitting state.',
      );
    case PaymentLinkReceivedStatus.receiving:
      // Missing history or an unknown/lagging sync height is not evidence of
      // a reorg. Preserve a completed receipt until the wallet explicitly
      // reports one of its inbound transactions as unmined or expired.
      final claimTxids = record.claimTxids!.split(',');
      final hasInvalidatedReceipt = transactions.any(
        (tx) =>
            (tx.txKind == 'received' || tx.txKind == 'receiving') &&
            (tx.expiredUnmined || tx.minedHeight <= BigInt.zero) &&
            claimTxids.any((txid) => paymentLinkTxidsMatch(txid, tx.txidHex)),
      );
      if (record.status == PaymentLinkReceivedStatus.received &&
          hasInvalidatedReceipt) {
        await store.markReceiving(
          expected: record,
          address: record.address,
          destinationAccountUuid: record.destinationAccountUuid!,
          claimTxids: record.claimTxids!,
        );
      }
    case PaymentLinkReceivedStatus.received:
      if (record.status != PaymentLinkReceivedStatus.received) {
        await store.markReceived(address: record.address);
      }
      final recoveryStatus = paymentLinkReceivedStatusForTransactions(
        claimTxids: record.claimTxids!,
        transactions: transactions,
        chainTipHeight: verifiedHeight,
        confirmationTarget: kPaymentLinkClaimRecoveryConfirmationTarget,
      );
      if (recoveryStatus == PaymentLinkReceivedStatus.received) {
        await finalizeConfirmedPaymentLinkClaim(
          record: record,
          deleteRetainedWallet: deleteRetainedWallet,
          clearClaimSecret: (address) =>
              store.clearConfirmedClaimSecret(address: address),
        );
      }
  }
}

/// A redeemed Card does not block account removal during its recovery window.
/// An unclaimed setup Card is forgotten together with its removed recipient.
/// Exclude removed recipients before any retained-wallet sync or history query.
/// Failed file cleanup stays durable for the coordinator's next retry.
@visibleForTesting
Future<List<PaymentLinkReceivedRecord>>
discardPaymentLinkClaimsForDeletedAccounts({
  required List<PaymentLinkReceivedRecord> records,
  required String network,
  required Set<String> accountUuids,
  required PaymentLinkReceivedStore store,
  required Future<bool> Function(PaymentLinkReceivedRecord)
  deleteRetainedWallet,
}) async {
  final eligible = <PaymentLinkReceivedRecord>[];
  for (final record in records) {
    final destination =
        record.destinationAccountUuid ??
        (record.status == PaymentLinkReceivedStatus.readyToClaim
            ? record.setupAccountUuid
            : null);
    if (record.network != network ||
        destination == null ||
        accountUuids.contains(destination)) {
      eligible.add(record);
      continue;
    }
    if (await deleteRetainedWallet(record)) {
      await store.remove(record.address);
    }
  }
  return eligible;
}

/// Card observation covers confirmations independently of the recipient DB.
Future<void> reconcileObservedPaymentLinkClaimReceipt({
  required PaymentLinkReceivedRecord record,
  required int confirmationCount,
  required PaymentLinkReceivedStore store,
  required Future<bool> Function(PaymentLinkReceivedRecord)
  deleteRetainedWallet,
}) async {
  if (record.claimRecoveryConfirmed) {
    await finalizeConfirmedPaymentLinkClaim(
      record: record,
      deleteRetainedWallet: deleteRetainedWallet,
      clearClaimSecret: (address) =>
          store.clearConfirmedClaimSecret(address: address),
    );
    return;
  }
  if (confirmationCount == 0) {
    if (record.status == PaymentLinkReceivedStatus.received) {
      await store.markReceiving(
        expected: record,
        address: record.address,
        destinationAccountUuid: record.destinationAccountUuid!,
        claimTxids: record.claimTxids!,
      );
    }
    return;
  }
  var received = record;
  if (received.status != PaymentLinkReceivedStatus.received) {
    received = await store.markReceived(address: received.address);
  }
  if (confirmationCount < kPaymentLinkClaimRecoveryConfirmationTarget) return;
  final checkpoint = await store.markClaimRecoveryConfirmed(received);
  await finalizeConfirmedPaymentLinkClaim(
    record: checkpoint,
    deleteRetainedWallet: deleteRetainedWallet,
    clearClaimSecret: (address) =>
        store.clearConfirmedClaimSecret(address: address),
  );
}
