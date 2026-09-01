import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../send/services/sapling_params.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_received_store.dart';
import 'payment_link_recovery_reconciler.dart';
import 'payment_link_recovery_store.dart';
import 'payment_link_transaction_matching.dart';

final paymentLinkServiceProvider = Provider<PaymentLinkService>((ref) {
  return PaymentLinkService(
    ref,
    ref.read(paymentLinkRecoveryStoreProvider),
    ref.read(paymentLinkReceivedStoreProvider),
    ref.read(paymentLinkRecoveryReconcilerProvider),
  );
});

const kPaymentLinkShareConfirmationTarget = 1;
const kPaymentLinkClaimConfirmationTarget = 6;
const _paymentLinkClaimMetadataWriteAttempts = 2;

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

class PaymentLinkFundingQuote {
  const PaymentLinkFundingQuote({
    required this.sourceAccountUuid,
    required this.recipientAmountZatoshi,
    required this.fundingFeeZatoshi,
    required this.claimFeeReserveZatoshi,
  });

  final String sourceAccountUuid;
  final BigInt recipientAmountZatoshi;
  final BigInt fundingFeeZatoshi;
  final BigInt claimFeeReserveZatoshi;

  BigInt get cardFeeZatoshi => fundingFeeZatoshi + claimFeeReserveZatoshi;

  BigInt get totalDeductedZatoshi => recipientAmountZatoshi + cardFeeZatoshi;
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

class PaymentLinkFundingProgress {
  const PaymentLinkFundingProgress({
    required this.confirmationCount,
    this.confirmationTarget = kPaymentLinkShareConfirmationTarget,
    this.broadcastAccepted = false,
  });

  final int confirmationCount;
  final int confirmationTarget;
  final bool broadcastAccepted;

  bool get isReady =>
      broadcastAccepted || confirmationCount >= confirmationTarget;

  PaymentLinkFundingProgress copyWith({bool? broadcastAccepted}) {
    return PaymentLinkFundingProgress(
      confirmationCount: confirmationCount,
      confirmationTarget: confirmationTarget,
      broadcastAccepted: broadcastAccepted ?? this.broadcastAccepted,
    );
  }
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

/// UI-facing boundary for the persisted Payment Link lifecycle.
///
/// Keeping the screen on this small surface makes transaction behavior
/// replaceable in widget tests without weakening the production service.
abstract interface class PaymentLinkOperations {
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  });

  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  });

  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  });

  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries();

  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  );

  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  );

  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries();

  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  );

  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  });

  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  );

  Future<void> discardClaimSession(PaymentLinkClaimSession session);

  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link);
}

final paymentLinkOperationsProvider = Provider<PaymentLinkOperations>((ref) {
  return ref.watch(paymentLinkServiceProvider);
});

class PaymentLinkClaimSession {
  const PaymentLinkClaimSession({
    required this.link,
    required this.destinationAddress,
    required this.destinationAccountUuid,
    required this.directory,
    required this.dbPath,
    required this.accountUuid,
    required this.totalZatoshi,
    required this.claimableZatoshi,
    required this.feeZatoshi,
    this.fundingConfirmationCount = 0,
    this.waitingForFundingConfirmations = false,
  });

  final VizorPaymentLink link;
  final String destinationAddress;
  final String destinationAccountUuid;
  final Directory directory;
  final String dbPath;
  final String accountUuid;
  final BigInt totalZatoshi;
  final BigInt claimableZatoshi;
  final BigInt feeZatoshi;
  final int fundingConfirmationCount;
  final bool waitingForFundingConfirmations;

  bool get canClaim =>
      claimableZatoshi > BigInt.zero && !waitingForFundingConfirmations;
}

enum PaymentLinkClaimBroadcastStatus {
  broadcasted,
  pendingBroadcast,
  partialBroadcast,
}

@visibleForTesting
PaymentLinkClaimBroadcastStatus paymentLinkClaimBroadcastStatusFromWire(
  String status,
) {
  return switch (status) {
    'broadcasted' => PaymentLinkClaimBroadcastStatus.broadcasted,
    'pending_broadcast' => PaymentLinkClaimBroadcastStatus.pendingBroadcast,
    'partial_broadcast' => PaymentLinkClaimBroadcastStatus.partialBroadcast,
    _ => throw StateError('Unknown payment link broadcast status: $status'),
  };
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

class PaymentLinkLongSyncConfirmationRequired implements Exception {
  const PaymentLinkLongSyncConfirmationRequired();
}

class PaymentLinkClaimDestinationChangedException implements Exception {
  const PaymentLinkClaimDestinationChangedException();

  @override
  String toString() =>
      'The Gift Card receiving account or address changed before claim.';
}

class PaymentLinkClaimInFlightException implements Exception {
  const PaymentLinkClaimInFlightException();

  @override
  String toString() => 'This Gift Card is already being received.';
}

@visibleForTesting
void requireMatchingPaymentLinkClaimDestination({
  required String preparedAddress,
  required String currentAddress,
}) {
  if (preparedAddress != currentAddress) {
    throw const PaymentLinkClaimDestinationChangedException();
  }
}

/// Claim databases are cached by the fields that determine the recovered
/// account and its scan range. Share-payload fields such as amount, label,
/// timestamp, and presentation deliberately do not participate, so a corrected
/// payload can reuse already-scanned state.
@visibleForTesting
String paymentLinkClaimWalletDirectoryName(VizorPaymentLink link) {
  final identity = sha256
      .convert(
        utf8.encode(
          '${link.network}:${link.address}:${link.mnemonic}:'
          '${link.birthdayHeight}',
        ),
      )
      .toString();
  return '$kPaymentLinkClaimWalletDirectoryPrefix$identity';
}

class PaymentLinkClaimResult {
  const PaymentLinkClaimResult({required this.txids, required this.status});

  final String txids;
  final PaymentLinkClaimBroadcastStatus status;

  bool get isBroadcasted =>
      status == PaymentLinkClaimBroadcastStatus.broadcasted;
}

/// A fully broadcast payment-link funding result.
///
/// When [fundingMetadataSaved] is false, the durable draft still preserves the
/// bearer secret, but callers must not offer another funding attempt as the
/// transaction already reached the network.
class PaymentLinkFundingResult {
  const PaymentLinkFundingResult({
    required this.link,
    required this.txids,
    required this.fundingMetadataSaved,
    required this.broadcastAccepted,
  });

  final VizorPaymentLink link;
  final String txids;

  /// Whether the durable recovery record advanced from draft to funded.
  /// The link remains recoverable from its draft when this is false.
  final bool fundingMetadataSaved;

  /// Whether the network explicitly accepted the funding broadcast. An
  /// uncertain hardware response falls back to one mined confirmation.
  final bool broadcastAccepted;
}

class PaymentLinkService implements PaymentLinkOperations {
  PaymentLinkService(
    this._ref,
    this._recoveryStore,
    this._receivedStore,
    this._recoveryReconciler,
  );

  final Ref _ref;
  final PaymentLinkRecoveryStore _recoveryStore;
  final PaymentLinkReceivedStore _receivedStore;
  final PaymentLinkRecoveryReconciler _recoveryReconciler;
  final Map<String, Future<void>> _claimSyncs = {};

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    if (sourceAccountUuid.isEmpty) {
      throw StateError('No active account.');
    }
    final fundingAmount = paymentLinkFundingAmountZatoshi(amountZatoshi);
    return _ref
        .read(syncProvider.notifier)
        .runWithAuthoritativeSpendable(
          accountUuid: sourceAccountUuid,
          operation: () async {
            final dbPath = await getWalletDbPath();
            final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
            final estimateAddress = await rust_wallet.getUnifiedAddress(
              dbPath: dbPath,
              network: endpoint.networkName,
              accountUuid: sourceAccountUuid,
            );
            final fundingFee = await rust_sync.estimateFee(
              dbPath: dbPath,
              network: endpoint.networkName,
              accountUuid: sourceAccountUuid,
              toAddress: estimateAddress,
              amountZatoshi: fundingAmount,
              memo: null,
            );
            return PaymentLinkFundingQuote(
              sourceAccountUuid: sourceAccountUuid,
              recipientAmountZatoshi: amountZatoshi,
              fundingFeeZatoshi: fundingFee,
              claimFeeReserveZatoshi: BigInt.from(
                kPaymentLinkClaimFeeReserveZatoshi,
              ),
            );
          },
        );
  }

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    if (_ref
        .read(accountProvider.notifier)
        .isHardwareAccount(sourceAccountUuid)) {
      throw StateError(
        'Keystone payment links require the hardware signing flow.',
      );
    }
    final link = await _createFundingLink(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
      presentation: presentation,
    );
    final funding = await PaymentLinkFundingRecovery(_recoveryStore)
        .fund<rust_sync.ExecuteProposalResult>(
          link: link,
          sourceAccountUuid: sourceAccountUuid,
          createTransaction: () => runPaymentLinkFundingSubmission(
            (markSubmissionStarted) => _sendShielded(
              fromAccountUuid: sourceAccountUuid,
              toAddress: link.address,
              amountZatoshi: paymentLinkFundingAmountZatoshi(amountZatoshi),
              memo: null,
              onSubmissionStarted: markSubmissionStarted,
            ),
          ),
          fundingTxids: (result) => result.txids,
        );
    final fundingResult = funding.transaction;
    if (!funding.fundingMetadataSaved) {
      log(
        'PaymentLinkService: funding was submitted but recovery metadata '
        'could not be saved after retry: ${funding.recoveryError}\n'
        '${funding.recoveryStackTrace}',
      );
    }

    unawaited(_refreshMainWalletAfterSend());
    return PaymentLinkFundingResult(
      link: link,
      txids: fundingResult.txids,
      fundingMetadataSaved: funding.fundingMetadataSaved,
      broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(
        fundingResult.status,
      ),
    );
  }

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) async {
    final recovery = await PaymentLinkFundingRecovery(_recoveryStore)
        .complete<String>(
          transaction: fundingTxids,
          address: address,
          fundingTxids: (txids) => txids,
        );
    if (recovery.fundingMetadataSaved) return;
    Error.throwWithStackTrace(
      recovery.recoveryError!,
      recovery.recoveryStackTrace!,
    );
  }

  /// Creates the bearer-secret account and persists its recovery record before
  /// any funding proposal can be signed or broadcast.
  Future<VizorPaymentLink> createFundingDraft({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    final link = await _createFundingLink(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
      presentation: presentation,
    );
    await _recoveryStore.saveDraft(
      link: link,
      sourceAccountUuid: sourceAccountUuid,
    );
    return link;
  }

  Future<VizorPaymentLink> _createFundingLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    if (sourceAccountUuid.isEmpty) {
      throw StateError('No active account.');
    }
    if (amountZatoshi <= BigInt.zero) {
      throw ArgumentError.value(
        amountZatoshi,
        'amountZatoshi',
        'Payment link amount must be positive.',
      );
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (!VizorPaymentLink.supportsNetwork(endpoint.networkName)) {
      throw StateError('Payment links are only available on mainnet.');
    }
    final paymentAccount = await rust_wallet.generateSoftwareAccount(
      network: endpoint.networkName,
    );
    final ephemeralAddress = paymentAccount.unifiedAddress;
    if (ephemeralAddress.isEmpty) {
      throw StateError('Payment link account was created without an address.');
    }

    final birthdayHeight = await _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .getLatestBlockHeight();
    final link = VizorPaymentLink(
      network: endpoint.networkName,
      address: ephemeralAddress,
      amountZatoshi: amountZatoshi,
      mnemonic: paymentAccount.mnemonic,
      birthdayHeight: birthdayHeight.toInt(),
      label: 'Payment link',
      createdAt: DateTime.now(),
      presentation: presentation,
    );
    return link;
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() =>
      _recoveryReconciler.load();

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) {
    return _recoveryStore.markShared(address: link.address);
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final needsHistory = records
        .where((record) => record.state == PaymentLinkRecoveryState.funded)
        .toList();
    if (needsHistory.isEmpty) {
      return {
        for (final record in records)
          record.link.address: PaymentLinkFundingProgress(
            confirmationCount: record.state == PaymentLinkRecoveryState.shared
                ? kPaymentLinkShareConfirmationTarget
                : 0,
          ),
      };
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final dbPath = await getWalletDbPath();
    final transactionsByAccount = <String, List<rust_sync.TransactionInfo>>{};
    for (final accountUuid
        in needsHistory.map((record) => record.sourceAccountUuid).toSet()) {
      transactionsByAccount[accountUuid] = await rust_sync
          .getTransactionHistory(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            limit: null,
          );
    }
    final cachedTip = _ref.read(syncProvider).value?.chainTipHeight ?? 0;
    final chainTipHeight = cachedTip > 0
        ? BigInt.from(cachedTip)
        : await _ref
              .read(rpcEndpointFailoverProvider.notifier)
              .getLatestBlockHeight();
    return {
      for (final record in records)
        record.link.address: record.state == PaymentLinkRecoveryState.shared
            ? const PaymentLinkFundingProgress(
                confirmationCount: kPaymentLinkShareConfirmationTarget,
              )
            : _fundingProgressForRecord(
                record: record,
                transactions:
                    transactionsByAccount[record.sourceAccountUuid] ?? const [],
                chainTipHeight: chainTipHeight,
              ),
    };
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() {
    return _receivedStore.load();
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> _,
  ) async {
    // The screen can optimistically render Receiving before the broadcast
    // result returns. Always reconcile from the persisted copy, which owns
    // the destination account UUID and claim txids needed for history lookup.
    var persistedRecords = await _receivedStore.load();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final submitting = persistedRecords
        .where(
          (record) =>
              record.needsClaimMetadataRecovery &&
              record.network == endpoint.networkName,
        )
        .toList();
    await Future.wait(
      submitting.map((record) async {
        try {
          await _recoverClaimMetadata(
            record: record,
            network: endpoint.networkName,
          );
        } catch (error, stackTrace) {
          log(
            'PaymentLinkService: retained claim metadata recovery failed for '
            '${record.address}: $error\n$stackTrace',
          );
        }
      }),
    );
    if (submitting.isNotEmpty) {
      persistedRecords = await _receivedStore.load();
    }
    final receiving = persistedRecords
        .where(
          (record) =>
              record.status == PaymentLinkReceivedStatus.receiving &&
              record.destinationAccountUuid != null &&
              record.claimTxids != null &&
              record.claimTxids!.trim().isNotEmpty,
        )
        .toList();
    if (receiving.isEmpty) return persistedRecords;

    final currentNetworkRecords = receiving
        .where((record) => record.network == endpoint.networkName)
        .toList();
    if (currentNetworkRecords.isEmpty) return persistedRecords;

    final retryableAddresses = <String>{};
    await Future.wait(
      currentNetworkRecords.map((record) async {
        try {
          if (await _syncRetainedClaimWallet(
            record: record,
            network: endpoint.networkName,
          )) {
            await _receivedStore.markReadyToClaim(address: record.address);
            retryableAddresses.add(record.address);
          }
        } catch (error, stackTrace) {
          log(
            'PaymentLinkService: retained claim wallet sync failed for '
            '${record.address}: $error\n$stackTrace',
          );
        }
      }),
    );
    final awaitingReceipt = currentNetworkRecords
        .where((record) => !retryableAddresses.contains(record.address))
        .toList();
    if (awaitingReceipt.isEmpty) return _receivedStore.load();

    final dbPath = await getWalletDbPath();
    final transactionsByAccount = <String, List<rust_sync.TransactionInfo>>{};
    for (final accountUuid
        in awaitingReceipt
            .map((record) => record.destinationAccountUuid!)
            .toSet()) {
      transactionsByAccount[accountUuid] = await rust_sync
          .getTransactionHistory(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            limit: null,
          );
    }
    final syncState = _ref.read(syncProvider).value;
    // A polled tip can advance before the main wallet DB has scanned it. In
    // particular, after a reorg the DB can still expose a transaction's old
    // mined height while chainTipHeight already describes the replacement
    // branch. Only confirmations covered by both heights are safe for the
    // destructive retained-wallet cleanup boundary.
    final chainTipHeight = paymentLinkVerifiedChainHeight(
      scannedHeight: syncState?.scannedHeight ?? 0,
      chainTipHeight: syncState?.chainTipHeight ?? 0,
    );

    for (final record in awaitingReceipt) {
      final status = paymentLinkReceivedStatusForTransactions(
        claimTxids: record.claimTxids!,
        transactions:
            transactionsByAccount[record.destinationAccountUuid!] ?? const [],
        chainTipHeight: chainTipHeight,
      );
      switch (status) {
        case PaymentLinkReceivedStatus.readyToClaim:
          await _receivedStore.markReadyToClaim(address: record.address);
        case PaymentLinkReceivedStatus.submitting:
          throw StateError(
            'Transaction reconciliation cannot produce submitting state.',
          );
        case PaymentLinkReceivedStatus.receiving:
          break;
        case PaymentLinkReceivedStatus.received:
          await finalizeConfirmedPaymentLinkClaim(
            record: record,
            deleteRetainedWallet: _deleteRetainedClaimWallet,
            markReceived: (address) =>
                _receivedStore.markReceived(address: address),
          );
      }
    }
    return _receivedStore.load();
  }

  PaymentLinkFundingProgress _fundingProgressForRecord({
    required PaymentLinkRecoveryRecord record,
    required List<rust_sync.TransactionInfo> transactions,
    required BigInt chainTipHeight,
  }) {
    final rawTxids = record.fundingTxids;
    if (record.state == PaymentLinkRecoveryState.draft ||
        rawTxids == null ||
        rawTxids.trim().isEmpty) {
      return const PaymentLinkFundingProgress(confirmationCount: 0);
    }
    final fundingTxids = rawTxids
        .split(',')
        .map(normalizePaymentLinkTxid)
        .where((txid) => txid.isNotEmpty)
        .toSet();
    if (fundingTxids.isEmpty) {
      return const PaymentLinkFundingProgress(confirmationCount: 0);
    }
    final minedHeights = <String, BigInt>{};
    for (final transaction in transactions) {
      final txid = normalizePaymentLinkTxid(transaction.txidHex);
      if (transaction.minedHeight <= BigInt.zero) continue;
      for (final fundingTxid in fundingTxids) {
        if (paymentLinkTxidsMatch(fundingTxid, txid)) {
          minedHeights[fundingTxid] = transaction.minedHeight;
        }
      }
    }
    final allFundingTransactionsMined = minedHeights.keys.toSet().containsAll(
      fundingTxids,
    );
    final minedHeight = allFundingTransactionsMined
        ? minedHeights.values.reduce(
            (latest, height) => height > latest ? height : latest,
          )
        : BigInt.zero;
    return PaymentLinkFundingProgress(
      confirmationCount: paymentLinkConfirmationCount(
        minedHeight: minedHeight,
        chainTipHeight: chainTipHeight,
      ),
    );
  }

  Future<PaymentLinkRecoveryRecord> setCreatedLinkArchived(
    VizorPaymentLink link, {
    required bool archived,
  }) {
    return _recoveryStore.setArchived(
      address: link.address,
      archived: archived,
    );
  }

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    final receiverState = _ref.read(accountProvider).value;
    final receiverAccountUuid = receiverState?.activeAccountUuid;
    final receiverAddress = receiverState?.activeAddress;
    if (receiverAccountUuid == null ||
        receiverAddress == null ||
        receiverAddress.isEmpty) {
      throw StateError('No active receive account.');
    }
    return _prepareSpend(
      link: link,
      destinationAddress: receiverAddress,
      destinationAccountUuid: receiverAccountUuid,
      allowLongSync: allowLongSync,
    );
  }

  Future<PaymentLinkClaimSession> _prepareSpend({
    required VizorPaymentLink link,
    required String destinationAddress,
    required String destinationAccountUuid,
    required bool allowLongSync,
  }) async {
    log('PaymentLinkClaim: preparation started');
    final existingRecord = await _receivedStore.find(link.address);
    if (existingRecord?.isClaimInFlight ?? false) {
      throw const PaymentLinkClaimInFlightException();
    }
    await _requireShieldedAddress(destinationAddress);
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${link.network}, but this wallet is using '
        '${endpoint.networkName}.',
      );
    }
    log('PaymentLinkClaim: endpoint validated');

    final currentTipHeight = await _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .getLatestBlockHeight();
    final claimBirthdayHeight = validatePaymentLinkClaimBirthday(
      advertisedBirthdayHeight: link.birthdayHeight,
      currentTipHeight: currentTipHeight.toInt(),
    );
    log('PaymentLinkClaim: birthday validated');
    if (!allowLongSync &&
        isLongPaymentLinkSync(
          birthdayHeight: claimBirthdayHeight,
          currentTipHeight: currentTipHeight.toInt(),
        )) {
      log('PaymentLinkClaim: long sync confirmation required');
      throw const PaymentLinkLongSyncConfirmationRequired();
    }

    final tempWallet = await _createOrOpenTemporaryWalletDb(link);
    log('PaymentLinkClaim: temporary wallet opened');
    var deleteOnError = !tempWallet.existed;
    try {
      final String importedAddress;
      final String importedAccountUuid;
      if (tempWallet.existed) {
        List<rust_wallet.AccountInfo>? accounts;
        try {
          accounts = await rust_wallet.listAccounts(
            dbPath: tempWallet.dbPath,
            network: endpoint.networkName,
          );
        } catch (e, st) {
          log(
            'PaymentLinkService: reopening payment-link claim wallet failed; '
            'recreating it: $e\n$st',
          );
        }
        if (accounts == null ||
            shouldRecreatePaymentLinkClaimWallet(
              accountAddresses: [
                for (final account in accounts) account.unifiedAddress,
              ],
              expectedAddress: link.address,
            )) {
          if (accounts != null) {
            log(
              'PaymentLinkService: recreating incomplete payment-link claim '
              'wallet with ${accounts.length} account(s)',
            );
          }
          deleteOnError = true;
          await _resetTemporaryWalletDb(tempWallet.directory);
          final imported = await _importPaymentLinkClaimAccount(
            link: link,
            birthdayHeight: claimBirthdayHeight,
            dbPath: tempWallet.dbPath,
            network: endpoint.networkName,
          );
          importedAddress = imported.address;
          importedAccountUuid = imported.accountUuid;
        } else {
          importedAddress = accounts.single.unifiedAddress;
          importedAccountUuid = accounts.single.uuid;
        }
      } else {
        final imported = await _importPaymentLinkClaimAccount(
          link: link,
          birthdayHeight: claimBirthdayHeight,
          dbPath: tempWallet.dbPath,
          network: endpoint.networkName,
        );
        importedAddress = imported.address;
        importedAccountUuid = imported.accountUuid;
      }
      if (importedAddress != link.address) {
        throw const FormatException(
          'Payment link address does not match its recovery phrase.',
        );
      }
      log('PaymentLinkClaim: recovery address validated');

      await _runClaimSync(link: link, dbPath: tempWallet.dbPath);
      log('PaymentLinkClaim: temporary wallet sync completed');
      final balance = await rust_sync.getBalance(
        dbPath: tempWallet.dbPath,
        network: endpoint.networkName,
        accountUuid: importedAccountUuid,
      );
      var claimableZatoshi = BigInt.zero;
      var feeZatoshi = BigInt.zero;
      try {
        final estimate = await rust_sync.estimateSendMax(
          dbPath: tempWallet.dbPath,
          network: endpoint.networkName,
          accountUuid: importedAccountUuid,
          toAddress: destinationAddress,
        );
        claimableZatoshi = paymentLinkClaimableAmountZatoshi(
          recipientAmountZatoshi: link.amountZatoshi,
          maxSpendableZatoshi: estimate.amountZatoshi,
        );
        feeZatoshi = estimate.feeZatoshi;
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('insufficient balance')) {
          rethrow;
        }
      }

      final transactions = await rust_sync.getTransactionHistory(
        dbPath: tempWallet.dbPath,
        network: endpoint.networkName,
        accountUuid: importedAccountUuid,
        limit: null,
      );
      final fundingConfirmationCount =
          paymentLinkFundingConfirmationCountForClaim(
            recipientAmountZatoshi: link.amountZatoshi,
            transactions: transactions,
            chainTipHeight: currentTipHeight,
          );
      final waitingForFundingConfirmations = paymentLinkShouldWaitForFunding(
        recipientAmountZatoshi: link.amountZatoshi,
        totalZatoshi: balance.total,
        fundingConfirmationCount: fundingConfirmationCount,
        birthdayHeight: claimBirthdayHeight,
        currentTipHeight: currentTipHeight.toInt(),
      );

      log(
        'PaymentLinkClaim: balance checked '
        'claimable=${claimableZatoshi > BigInt.zero} '
        'confirmations=$fundingConfirmationCount',
      );

      return PaymentLinkClaimSession(
        link: link,
        destinationAddress: destinationAddress,
        destinationAccountUuid: destinationAccountUuid,
        directory: tempWallet.directory,
        dbPath: tempWallet.dbPath,
        accountUuid: importedAccountUuid,
        totalZatoshi: balance.total,
        claimableZatoshi: claimableZatoshi,
        feeZatoshi: feeZatoshi,
        fundingConfirmationCount: fundingConfirmationCount,
        waitingForFundingConfirmations: waitingForFundingConfirmations,
      );
    } catch (_) {
      if (deleteOnError) {
        await _deleteTemporaryWalletDb(tempWallet.directory);
      }
      rethrow;
    }
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    // Checking a Gift Card is a read-only preview. Persist it only after the
    // user explicitly starts a claim, before any broadcast can occur, so an
    // interrupted submission remains recoverable without making previews look
    // received.
    await _receivedStore.saveReady(session.link);
    await _receivedStore.markClaimStarted(
      address: session.link.address,
      destinationAccountUuid: session.destinationAccountUuid,
    );
    var submissionStarted = false;
    try {
      final result = await _broadcastPreparedSpend(
        session,
        onSubmissionStarted: () => submissionStarted = true,
      );
      final metadataSaved = await _saveClaimMetadata(
        session: session,
        claimTxids: result.txids,
      );
      if (!metadataSaved) {
        log(
          'PaymentLinkService: claim was submitted but receiving metadata '
          'could not be saved after retry; retaining the claim wallet',
        );
      }
      // Keep the claim database for rebroadcast/reorg recovery. Reconciliation
      // deletes it only after every claim transaction reaches six confirmations.
      return result;
    } catch (_) {
      if (!submissionStarted) {
        await _receivedStore.markReadyToClaim(address: session.link.address);
      }
      rethrow;
    }
  }

  Future<PaymentLinkClaimResult> _broadcastPreparedSpend(
    PaymentLinkClaimSession session, {
    void Function()? onSubmissionStarted,
  }) async {
    if (!session.canClaim) {
      throw StateError('Payment link has no spendable shielded balance yet.');
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (session.link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${session.link.network}, but this wallet is '
        'using ${endpoint.networkName}.',
      );
    }
    final estimate = await rust_sync.estimateSendMax(
      dbPath: session.dbPath,
      network: endpoint.networkName,
      accountUuid: session.accountUuid,
      toAddress: session.destinationAddress,
    );
    if (estimate.amountZatoshi < session.link.amountZatoshi) {
      throw StateError(
        'Payment link does not yet have enough spendable shielded balance.',
      );
    }

    _requireWalletUnlocked();
    final sendResult = await _sendShielded(
      dbPath: session.dbPath,
      fromAccountUuid: session.accountUuid,
      toAddress: session.destinationAddress,
      amountZatoshi: session.link.amountZatoshi,
      memo: null,
      mnemonic: session.link.mnemonic,
      beforeExecute: () => _revalidateClaimDestination(session),
      onSubmissionStarted: onSubmissionStarted,
    );
    final claimResult = PaymentLinkClaimResult(
      txids: sendResult.txids,
      status: paymentLinkClaimBroadcastStatusFromWire(sendResult.status),
    );
    unawaited(_refreshMainWalletAfterSend());
    return claimResult;
  }

  Future<bool> _saveClaimMetadata({
    required PaymentLinkClaimSession session,
    required String claimTxids,
  }) async {
    for (
      var attempt = 0;
      attempt < _paymentLinkClaimMetadataWriteAttempts;
      attempt++
    ) {
      try {
        await _receivedStore.markReceiving(
          address: session.link.address,
          destinationAccountUuid: session.destinationAccountUuid,
          claimTxids: claimTxids,
        );
        return true;
      } catch (_) {
        if (attempt + 1 == _paymentLinkClaimMetadataWriteAttempts) {
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _revalidateClaimDestination(
    PaymentLinkClaimSession session,
  ) async {
    try {
      final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
      final currentAddress = await rust_wallet.getUnifiedAddress(
        dbPath: await getWalletDbPath(),
        network: endpoint.networkName,
        accountUuid: session.destinationAccountUuid,
      );
      requireMatchingPaymentLinkClaimDestination(
        preparedAddress: session.destinationAddress,
        currentAddress: currentAddress,
      );
    } on PaymentLinkClaimDestinationChangedException {
      rethrow;
    } catch (_) {
      throw const PaymentLinkClaimDestinationChangedException();
    }
  }

  @override
  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link) async {
    final session = await prepareClaim(link);
    return claimPreparedLink(session);
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {
    final claimId = paymentLinkClaimWalletDirectoryName(session.link);
    rust_sync.cancelPaymentLinkClaimSync(claimId: claimId);
    try {
      await _claimSyncs[claimId];
    } catch (_) {
      // A failed scan does not prevent the user-requested preview cleanup.
    }
    await _deleteTemporaryWalletDb(session.directory);
  }

  Future<void> _refreshMainWalletAfterSend() async {
    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e, stackTrace) {
      log(
        'PaymentLinkService: refreshAfterSend failed (non-critical): $e\n'
        '$stackTrace',
      );
    }
  }

  Future<rust_sync.ExecuteProposalResult> _sendShielded({
    String? dbPath,
    required String fromAccountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
    String? mnemonic,
    Future<void> Function()? beforeExecute,
    void Function()? onSubmissionStarted,
  }) async {
    await _requireShieldedAddress(toAddress);
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final sendFlowId = _newSendFlowId();
    Future<({String dbPath, rust_sync.ProposalResult proposal})> createProposal(
      String proposalDbPath,
    ) async {
      final proposal = await rust_sync.proposeSend(
        dbPath: proposalDbPath,
        network: endpoint.networkName,
        accountUuid: fromAccountUuid,
        sendFlowId: sendFlowId,
        toAddress: toAddress,
        amountZatoshi: amountZatoshi,
        memo: memo,
      );
      return (dbPath: proposalDbPath, proposal: proposal);
    }

    // The primary wallet shares the ordinary send flow's authoritative
    // spendable lease. Claim wallets are fully synchronized before this path.
    final proposalContext = dbPath == null
        ? await _ref
              .read(syncProvider.notifier)
              .runWithAuthoritativeSpendable(
                accountUuid: fromAccountUuid,
                operation: () async => createProposal(await getWalletDbPath()),
              )
        : await createProposal(dbPath);
    final walletDbPath = proposalContext.dbPath;
    final proposal = proposalContext.proposal;

    try {
      final result = await _executeProposal(
        dbPath: walletDbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        accountUuid: fromAccountUuid,
        proposalId: proposal.proposalId,
        sendFlowId: sendFlowId,
        needsSaplingParams: proposal.needsSaplingParams,
        mnemonic: mnemonic,
        beforeExecute: beforeExecute,
        onSubmissionStarted: onSubmissionStarted,
      );
      paymentLinkClaimBroadcastStatusFromWire(result.status);
      return result;
    } catch (e) {
      try {
        await rust_sync.discardProposal(
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
        );
      } catch (discardError) {
        log('PaymentLinkService: discardProposal failed: $discardError');
      }
      rethrow;
    }
  }

  Future<rust_sync.ExecuteProposalResult> _executeProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String accountUuid,
    required BigInt proposalId,
    required String sendFlowId,
    required bool needsSaplingParams,
    String? mnemonic,
    Future<void> Function()? beforeExecute,
    void Function()? onSubmissionStarted,
  }) async {
    var saplingParams = await loadSaplingParamsStatus();
    if (needsSaplingParams && !saplingParams.complete) {
      await downloadMissingSaplingParams(
        saplingParams,
        log: (message) => log('PaymentLinkService: $message'),
      );
      saplingParams = await loadSaplingParamsStatus();
    }

    await beforeExecute?.call();
    _requireWalletUnlocked();

    if (Platform.isMacOS && mnemonic == null) {
      final password = _ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      onSubmissionStarted?.call();
      return rust_sync.executeProposalWithMacosStoredMnemonic(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        password: password,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    }

    final mnemonicBytes = mnemonic == null
        ? await _ref
              .read(accountProvider.notifier)
              .getMnemonicBytesForAccount(accountUuid)
        : Uint8List.fromList(utf8.encode(mnemonic));
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw StateError('Mnemonic not found for payment link account.');
    }
    late final Future<rust_sync.ExecuteProposalResult> result;
    try {
      onSubmissionStarted?.call();
      result = rust_sync.executeProposal(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        mnemonicBytes: mnemonicBytes,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    } finally {
      _zeroize(mnemonicBytes);
    }
    return result;
  }

  Future<void> _runClaimSync({
    required VizorPaymentLink link,
    required String dbPath,
  }) {
    final claimId = paymentLinkClaimWalletDirectoryName(link);
    final existing = _claimSyncs[claimId];
    if (existing != null) return existing;
    final future = _runClaimSyncOnce(
      claimId: claimId,
      dbPath: dbPath,
      network: link.network,
    );
    _claimSyncs[claimId] = future;
    return future.whenComplete(() {
      if (identical(_claimSyncs[claimId], future)) {
        _claimSyncs.remove(claimId);
      }
    });
  }

  Future<void> _runClaimSyncOnce({
    required String claimId,
    required String dbPath,
    required String network,
  }) {
    return _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback<void>(
          operation: 'Gift Card claim sync',
          action: (endpoint) {
            if (endpoint.networkName != network) {
              throw StateError(
                'Payment link is for $network, but this wallet is using '
                '${endpoint.networkName}.',
              );
            }
            return rust_sync.runPaymentLinkClaimSync(
              claimId: claimId,
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: network,
            );
          },
        );
  }

  Future<void> _recoverClaimMetadata({
    required PaymentLinkReceivedRecord record,
    required String network,
  }) async {
    final link = record.claimLink;
    final destinationAccountUuid = record.destinationAccountUuid;
    if (link == null || destinationAccountUuid == null) return;

    final tempWallet = await _temporaryWalletLocation(link);
    if (!await File(tempWallet.dbPath).exists()) return;

    await _runClaimSync(link: link, dbPath: tempWallet.dbPath);
    final accounts = await rust_wallet.listAccounts(
      dbPath: tempWallet.dbPath,
      network: network,
    );
    if (shouldRecreatePaymentLinkClaimWallet(
      accountAddresses: [
        for (final account in accounts) account.unifiedAddress,
      ],
      expectedAddress: link.address,
    )) {
      return;
    }
    final transactions = await rust_sync.getTransactionHistory(
      dbPath: tempWallet.dbPath,
      network: network,
      accountUuid: accounts.single.uuid,
      limit: null,
    );
    final activeTxids = paymentLinkActiveClaimTxids(transactions);
    if (activeTxids.isEmpty) {
      await _receivedStore.markReadyToClaim(address: record.address);
      return;
    }
    await _receivedStore.markReceiving(
      address: record.address,
      destinationAccountUuid: destinationAccountUuid,
      claimTxids: activeTxids.join(','),
    );
  }

  Future<bool> _syncRetainedClaimWallet({
    required PaymentLinkReceivedRecord record,
    required String network,
  }) async {
    final link = record.claimLink;
    final claimTxids = record.claimTxids;
    if (link == null || claimTxids == null || claimTxids.trim().isEmpty) {
      return false;
    }

    final tempWallet = await _temporaryWalletLocation(link);
    if (!await File(tempWallet.dbPath).exists()) return false;

    await _runClaimSync(link: link, dbPath: tempWallet.dbPath);
    final accounts = await rust_wallet.listAccounts(
      dbPath: tempWallet.dbPath,
      network: network,
    );
    if (shouldRecreatePaymentLinkClaimWallet(
      accountAddresses: [
        for (final account in accounts) account.unifiedAddress,
      ],
      expectedAddress: link.address,
    )) {
      log(
        'PaymentLinkService: retained claim wallet no longer matches its '
        'Gift Card identity; leaving it recoverable from the stored link',
      );
      return false;
    }
    final transactions = await rust_sync.getTransactionHistory(
      dbPath: tempWallet.dbPath,
      network: network,
      accountUuid: accounts.single.uuid,
      limit: null,
    );
    return paymentLinkClaimTransactionsExpired(
      claimTxids: claimTxids,
      transactions: transactions,
    );
  }

  Future<bool> _deleteRetainedClaimWallet(
    PaymentLinkReceivedRecord record,
  ) async {
    final link = record.claimLink;
    if (link == null) return true;

    final tempWallet = await _temporaryWalletLocation(link);
    if (!await tempWallet.directory.exists()) return true;
    try {
      await tempWallet.directory.delete(recursive: true);
      return true;
    } catch (error, stackTrace) {
      log(
        'PaymentLinkService: failed to delete confirmed claim wallet: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }

  Future<({Directory directory, String dbPath})> _temporaryWalletLocation(
    VizorPaymentLink link,
  ) async {
    final supportDir = await getWalletSupportDirectory();
    final separator = Platform.pathSeparator;
    final directory = Directory(
      '${supportDir.path}$separator${paymentLinkClaimWalletDirectoryName(link)}',
    );
    return (
      directory: directory,
      dbPath: '${directory.path}${separator}zcash_wallet.db',
    );
  }

  Future<({Directory directory, String dbPath, bool existed})>
  _createOrOpenTemporaryWalletDb(VizorPaymentLink link) async {
    final location = await _temporaryWalletLocation(link);
    final existed = await File(location.dbPath).exists();
    await location.directory.create(recursive: true);
    return (
      directory: location.directory,
      dbPath: location.dbPath,
      existed: existed,
    );
  }

  Future<({String address, String accountUuid})>
  _importPaymentLinkClaimAccount({
    required VizorPaymentLink link,
    required int birthdayHeight,
    required String dbPath,
    required String network,
  }) async {
    final imported = await rust_wallet.importWallet(
      mnemonic: link.mnemonic,
      bip39Passphrase: '',
      birthdayHeight: BigInt.from(birthdayHeight),
      network: network,
      dbPath: dbPath,
      accountName: 'Payment link claim',
    );
    return (
      address: imported.unifiedAddress,
      accountUuid: imported.accountUuid,
    );
  }

  Future<void> _resetTemporaryWalletDb(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  Future<void> _deleteTemporaryWalletDb(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e, st) {
      log(
        'PaymentLinkService: failed to delete temporary payment-link DB '
        '${directory.path}: $e\n$st',
      );
    }
  }

  Future<void> _requireShieldedAddress(String address) async {
    final validation = await rust_sync.validateAddress(address: address);
    if (!validation.isValid ||
        (validation.addressType != 'unified' &&
            validation.addressType != 'sapling')) {
      throw StateError('Payment links only support shielded addresses.');
    }
  }

  void _requireWalletUnlocked() {
    requireUnlockedPaymentLinkWallet(
      requiresUnlock: _ref.read(appSecurityProvider).requiresUnlock,
    );
  }

  String _newSendFlowId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _zeroize(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}
