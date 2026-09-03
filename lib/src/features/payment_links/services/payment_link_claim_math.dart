/// Part of `payment_link_service.dart`: pure Gift Card claim and funding
/// arithmetic.
///
/// Confirmation counting, expiry, funding amounts, and received-status
/// derivation are decisions about numbers and wire strings only: they touch no
/// widget, no wallet DB, and no Rust call. They stay a `part` rather than their
/// own library so the `@visibleForTesting` contract on them keeps its meaning —
/// the annotation is library-scoped, and the service is their only production
/// caller.
part of 'payment_link_service.dart';

const kPaymentLinkClaimConfirmationTarget = 6;

/// The ZIP-317 fee for the payment link's expected one-input, one-output
/// shielded claim transaction.
const kPaymentLinkClaimFeeReserveZatoshi = 10000;

@visibleForTesting
Future<T> runPaymentLinkFundingSubmission<T>(
  Future<T> Function(void Function() markSubmissionStarted) operation,
) async {
  var submissionStarted = false;
  try {
    return await operation(() => submissionStarted = true);
  } catch (error, stackTrace) {
    if (!submissionStarted) {
      throw PaymentLinkFundingNotSubmittedException(error, stackTrace);
    }
    rethrow;
  }
}

BigInt paymentLinkFundingAmountZatoshi(BigInt recipientAmountZatoshi) {
  if (recipientAmountZatoshi <= BigInt.zero) {
    throw ArgumentError.value(
      recipientAmountZatoshi,
      'recipientAmountZatoshi',
      'Payment link amount must be positive.',
    );
  }
  return recipientAmountZatoshi +
      BigInt.from(kPaymentLinkClaimFeeReserveZatoshi);
}

@visibleForTesting
int paymentLinkConfirmationCount({
  required BigInt minedHeight,
  required BigInt chainTipHeight,
}) {
  if (minedHeight <= BigInt.zero || chainTipHeight < minedHeight) return 0;
  return (chainTipHeight - minedHeight + BigInt.one).toInt();
}

@visibleForTesting
BigInt paymentLinkVerifiedChainHeight({
  required int scannedHeight,
  required int chainTipHeight,
}) {
  if (scannedHeight <= 0 || chainTipHeight <= 0) return BigInt.zero;
  return BigInt.from(min(scannedHeight, chainTipHeight));
}

@visibleForTesting
int paymentLinkFundingConfirmationCountForClaim({
  required BigInt recipientAmountZatoshi,
  required List<rust_sync.TransactionInfo> transactions,
  required BigInt chainTipHeight,
}) {
  final expectedFunding = paymentLinkFundingAmountZatoshi(
    recipientAmountZatoshi,
  );
  var confirmationCount = 0;
  for (final transaction in transactions) {
    if (transaction.expiredUnmined ||
        transaction.txKind != 'received' ||
        BigInt.from(transaction.accountBalanceDelta) != expectedFunding) {
      continue;
    }
    confirmationCount = max(
      confirmationCount,
      paymentLinkConfirmationCount(
        minedHeight: transaction.minedHeight,
        chainTipHeight: chainTipHeight,
      ),
    );
  }
  return min(confirmationCount, kPaymentLinkClaimConfirmationTarget);
}

@visibleForTesting
bool paymentLinkShouldWaitForFunding({
  required BigInt recipientAmountZatoshi,
  required BigInt totalZatoshi,
  required int fundingConfirmationCount,
  required int birthdayHeight,
  required int currentTipHeight,
}) {
  if (fundingConfirmationCount >= kPaymentLinkClaimConfirmationTarget) {
    return false;
  }
  final expectedFunding = paymentLinkFundingAmountZatoshi(
    recipientAmountZatoshi,
  );
  if (totalZatoshi >= expectedFunding) return true;
  return currentTipHeight - birthdayHeight <
      kPaymentLinkClaimConfirmationTarget;
}

@visibleForTesting
PaymentLinkReceivedStatus paymentLinkReceivedStatusForTransactions({
  required String claimTxids,
  required List<rust_sync.TransactionInfo> transactions,
  required BigInt chainTipHeight,
}) {
  final expectedTxids = claimTxids
      .split(',')
      .map(normalizePaymentLinkTxid)
      .where((txid) => txid.isNotEmpty)
      .toSet();
  if (expectedTxids.isEmpty) return PaymentLinkReceivedStatus.receiving;

  bool everyTxidMatches(
    bool Function(rust_sync.TransactionInfo transaction) predicate,
  ) {
    return expectedTxids.every(
      (expectedTxid) => transactions.any(
        (transaction) =>
            paymentLinkTxidsMatch(expectedTxid, transaction.txidHex) &&
            predicate(transaction),
      ),
    );
  }

  final allConfirmed = everyTxidMatches(
    (transaction) =>
        transaction.txKind == 'received' &&
        paymentLinkConfirmationCount(
              minedHeight: transaction.minedHeight,
              chainTipHeight: chainTipHeight,
            ) >=
            kPaymentLinkClaimConfirmationTarget,
  );
  if (allConfirmed) return PaymentLinkReceivedStatus.received;

  final allExpired = paymentLinkClaimTransactionsExpired(
    claimTxids: claimTxids,
    transactions: transactions,
  );
  return allExpired
      ? PaymentLinkReceivedStatus.readyToClaim
      : PaymentLinkReceivedStatus.receiving;
}

@visibleForTesting
bool paymentLinkClaimTransactionsExpired({
  required String claimTxids,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  final expectedTxids = claimTxids
      .split(',')
      .map(normalizePaymentLinkTxid)
      .where((txid) => txid.isNotEmpty)
      .toSet();
  if (expectedTxids.isEmpty) return false;
  return expectedTxids.every(
    (expectedTxid) => transactions.any(
      (transaction) =>
          paymentLinkTxidsMatch(expectedTxid, transaction.txidHex) &&
          transaction.expiredUnmined,
    ),
  );
}

@visibleForTesting
List<String> paymentLinkActiveClaimTxids(
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where(
        (transaction) =>
            transaction.txKind == 'sent' &&
            !transaction.expiredUnmined &&
            transaction.txidHex.trim().isNotEmpty,
      )
      .map((transaction) => transaction.txidHex.trim())
      .toSet()
      .toList();
}

const _submittedPaymentLinkFundingStatuses = {
  'broadcasted',
  'pending_broadcast',
  'partial_broadcast',
  'broadcast_unknown',
  'broadcasted_storage_failed',
};

bool isPaymentLinkFundingSubmitted({
  required String status,
  required String txids,
}) {
  return txids.trim().isNotEmpty &&
      _submittedPaymentLinkFundingStatuses.contains(status);
}

bool isPaymentLinkFundingBroadcastAccepted(String status) {
  return status == 'broadcasted' || status == 'broadcasted_storage_failed';
}

@visibleForTesting
BigInt paymentLinkClaimableAmountZatoshi({
  required BigInt recipientAmountZatoshi,
  required BigInt maxSpendableZatoshi,
}) {
  return maxSpendableZatoshi >= recipientAmountZatoshi
      ? recipientAmountZatoshi
      : BigInt.zero;
}

@visibleForTesting
Future<bool> finalizeConfirmedPaymentLinkClaim({
  required PaymentLinkReceivedRecord record,
  required Future<bool> Function(PaymentLinkReceivedRecord record)
  deleteRetainedWallet,
  required Future<void> Function(String address) markReceived,
}) async {
  if (!await deleteRetainedWallet(record)) return false;
  await markReceived(record.address);
  return true;
}

@visibleForTesting
bool shouldRecreatePaymentLinkClaimWallet({
  required List<String> accountAddresses,
  required String expectedAddress,
}) {
  return accountAddresses.length != 1 ||
      accountAddresses.single != expectedAddress;
}

@visibleForTesting
void requireUnlockedPaymentLinkWallet({required bool requiresUnlock}) {
  if (requiresUnlock) {
    throw StateError('Wallet is locked.');
  }
}

@visibleForTesting
int validatePaymentLinkClaimBirthday({
  required int advertisedBirthdayHeight,
  required int currentTipHeight,
}) {
  if (currentTipHeight <= 0) {
    throw StateError('Current chain tip is unavailable.');
  }
  if (advertisedBirthdayHeight <= 0) {
    throw const FormatException('Payment link birthday must be positive.');
  }
  if (advertisedBirthdayHeight > currentTipHeight) {
    throw const FormatException(
      'Payment link birthday is ahead of the current chain tip.',
    );
  }
  return advertisedBirthdayHeight;
}

const kPaymentLinkLongSyncLookbackBlocks = 100000;

@visibleForTesting
bool isLongPaymentLinkSync({
  required int birthdayHeight,
  required int currentTipHeight,
}) {
  validatePaymentLinkClaimBirthday(
    advertisedBirthdayHeight: birthdayHeight,
    currentTipHeight: currentTipHeight,
  );
  return currentTipHeight - birthdayHeight > kPaymentLinkLongSyncLookbackBlocks;
}
