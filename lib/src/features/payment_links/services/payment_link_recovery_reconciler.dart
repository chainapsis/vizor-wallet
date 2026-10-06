import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/ledger_capability.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_hardware_signing_service.dart';
import 'payment_link_lifecycle_revision.dart';
import 'payment_link_recovery_store.dart';
import 'payment_link_service.dart';
import 'payment_link_transaction_matching.dart';

typedef PaymentLinkFundingHistoryLoader =
    Future<Map<String, List<rust_sync.TransactionInfo>>> Function(
      Set<String> accountUuids,
    );

typedef PaymentLinkOwnFundingHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(VizorPaymentLink link);

/// How long a draft that never started its broadcast is kept before recovery
/// drops it — long enough for a creation still proposing in this process.
const kPaymentLinkInertDraftRetention = Duration(minutes: 10);

final paymentLinkRecoveryReconcilerProvider =
    Provider<PaymentLinkRecoveryReconciler>((ref) {
      final claimWallet = PaymentLinkClaimWallet(ref);
      final ledgerSupported = ref
          .watch(ledgerStaticCapabilityProvider)
          .supported;
      Future<List<LedgerSignedOperationMetadata>> loadLedgerOperations() async {
        // The Rust outbox uses the same Ledger network gate. Software-card
        // checks must still work when Ledger operations are unavailable.
        if (!ledgerSupported) return const [];
        return ref.read(ledgerSignedOperationServiceProvider).list();
      }

      return PaymentLinkRecoveryReconciler(
        ref.watch(paymentLinkRecoveryStoreProvider),
        loadCurrentHeight: () => ref
            .read(rpcEndpointFailoverProvider.notifier)
            .getLatestBlockHeight(),
        loadScannedHeight: () async {
          final endpoint = ref.read(rpcEndpointFailoverProvider).current;
          final status = await rust_sync.getSyncStatus(
            dbPath: await getWalletDbPath(),
            network: endpoint.networkName,
          );
          return status.scannedHeight;
        },
        loadTransactionsByAccount: (accountUuids) async {
          final endpoint = ref.read(rpcEndpointFailoverProvider).current;
          final dbPath = await getWalletDbPath();
          final entries = await Future.wait(
            accountUuids.map((accountUuid) async {
              final transactions = await rust_sync.getTransactionHistory(
                dbPath: dbPath,
                network: endpoint.networkName,
                accountUuid: accountUuid,
                limit: null,
              );
              return MapEntry(accountUuid, transactions);
            }),
          );
          return Map.fromEntries(entries);
        },
        loadLinkFundingHistory: claimWallet.loadFundingHistory,
        loadLedgerOperationRefs: () async => {
          for (final operation in await loadLedgerOperations())
            ?operation.externalRef,
        },
        loadSignedPendingGiftCardRefs: (accountUuid) async => {
          for (final operation in await loadLedgerOperations())
            if (operation.kind == LedgerSignedOperationKind.giftCard &&
                operation.accountUuid == accountUuid &&
                operation.state == 'signed_pending_broadcast')
              ?operation.externalRef,
        },
        isFundingSurfaceOpen: ref
            .read(paymentLinkFundingSurfaceRegistryProvider)
            .isOpen,
      );
    });

/// Count behind the account-removal warning; see
/// [PaymentLinkRecoveryReconciler.countUnsharedForRemovalWarning].
final paymentLinkUnsharedFundedCountProvider =
    FutureProvider.family<int, String>((ref, sourceAccountUuid) async {
      ref.watch(paymentLinkLifecycleRevisionProvider);
      return ref
          .watch(paymentLinkRecoveryReconcilerProvider)
          .countUnsharedForRemovalWarning(sourceAccountUuid);
    });

enum PaymentLinkPreparedFundingDisposition { pending, funded, expired }

PaymentLinkPreparedFundingDisposition _paymentLinkPreparedFundingDisposition({
  required String fundingTxid,
  required int? expiryHeight,
  required BigInt currentHeight,
  required BigInt scannedHeight,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  // A software proposal can carry several ids; every one has to be mined.
  if (paymentLinkFundingTransactionsExist(
    fundingTxids: fundingTxid,
    transactions: transactions,
  )) {
    return PaymentLinkPreparedFundingDisposition.funded;
  }
  // The wallet watched this transaction expire unmined, which is definitive
  // whatever the record knows about expiry heights.
  if (paymentLinkFundingExpired(
    fundingTxids: fundingTxid,
    transactions: transactions,
  )) {
    return PaymentLinkPreparedFundingDisposition.expired;
  }
  // A software draft carries its broadcast transaction but no expiry height,
  // so it can only be promoted once mined; without a height there is nothing
  // to discard it on.
  if (expiryHeight != null &&
      currentHeight >= BigInt.from(expiryHeight) &&
      scannedHeight >= BigInt.from(expiryHeight)) {
    return PaymentLinkPreparedFundingDisposition.expired;
  }
  return PaymentLinkPreparedFundingDisposition.pending;
}

/// The transaction ids by which a Gift Card's own wallet holds funds.
///
/// Only inbound transactions count: `sent` rows are the Card being claimed,
/// and Rust labels an inbound transaction `receiving` until it is mined
/// ([`receiving_tx_kind`] in `rust/src/wallet/sync/transactions.rs`), so a
/// funding still in the mempool has to count too — treating it as unseen
/// would discard a Card that does hold funds.
List<String> _paymentLinkOwnFundingTxids(
  Iterable<rust_sync.TransactionInfo> transactions, {
  required BigInt expectedZatoshi,
}) {
  return transactions
      .where(
        (transaction) =>
            (transaction.txKind == 'received' ||
                transaction.txKind == 'receiving') &&
            !transaction.expiredUnmined &&
            // Only the promised funding counts; unrelated dust must not
            // promote the draft.
            BigInt.from(transaction.accountBalanceDelta) >= expectedZatoshi &&
            transaction.txidHex.trim().isNotEmpty,
      )
      .map((transaction) => transaction.txidHex.trim())
      .toSet()
      .toList();
}

class PaymentLinkRecoveryReconciler {
  const PaymentLinkRecoveryReconciler(
    this._store, {
    required Future<BigInt> Function() loadCurrentHeight,
    required Future<BigInt> Function() loadScannedHeight,
    required PaymentLinkFundingHistoryLoader loadTransactionsByAccount,
    required PaymentLinkOwnFundingHistoryLoader loadLinkFundingHistory,
    Future<Set<String>> Function()? loadLedgerOperationRefs,
    Future<Set<String>> Function(String accountUuid)?
    loadSignedPendingGiftCardRefs,
    bool Function(String address)? isFundingSurfaceOpen,
  }) : _loadCurrentHeight = loadCurrentHeight,
       _loadScannedHeight = loadScannedHeight,
       _loadTransactionsByAccount = loadTransactionsByAccount,
       _loadLinkFundingHistory = loadLinkFundingHistory,
       _loadLedgerOperationRefs = loadLedgerOperationRefs,
       _loadSignedPendingGiftCardRefs = loadSignedPendingGiftCardRefs,
       _isFundingSurfaceOpen = isFundingSurfaceOpen;

  final PaymentLinkRecoveryStore _store;
  final Future<BigInt> Function() _loadCurrentHeight;
  final Future<BigInt> Function() _loadScannedHeight;
  final PaymentLinkFundingHistoryLoader _loadTransactionsByAccount;
  final PaymentLinkOwnFundingHistoryLoader _loadLinkFundingHistory;

  /// External refs of every Ledger signed-outbox operation. Without this and
  /// [_isFundingSurfaceOpen], abandoned prepared drafts wait for expiry.
  final Future<Set<String>> Function()? _loadLedgerOperationRefs;

  /// External refs of this account's Gift Card Ledger operations that are
  /// signed but not yet broadcast.
  final Future<Set<String>> Function(String accountUuid)?
  _loadSignedPendingGiftCardRefs;
  final bool Function(String address)? _isFundingSurfaceOpen;

  /// Removes drafts that were saved but never reached the broadcast boundary
  /// (app killed mid-propose): they hold nothing and would otherwise sit in
  /// the list forever.
  Future<List<PaymentLinkRecoveryRecord>> _dropInertDrafts(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final now = DateTime.now().toUtc();
    final inert = records.where(
      (record) =>
          record.isInertDraft &&
          now.difference(record.updatedAt) > kPaymentLinkInertDraftRetention,
    );
    var changed = false;
    final handledBatches = <String>{};
    for (final record in inert) {
      try {
        final batchId = record.batchId;
        if (batchId != null) {
          if (!handledBatches.add(batchId)) continue;
          final members = records
              .where((entry) => entry.batchId == batchId)
              .toList();
          if (members.length != record.batchCount ||
              members.any(
                (entry) =>
                    !entry.isInertDraft ||
                    now.difference(entry.updatedAt) <=
                        kPaymentLinkInertDraftRetention,
              )) {
            continue;
          }
          await _store.removeUnsubmittedBatch(batchId);
        } else {
          await _store.removeUnsubmittedDraft(address: record.link.address);
        }
        changed = true;
      } catch (error) {
        log(
          'PaymentLinkRecoveryReconciler: inert draft cleanup failed '
          'address=${record.link.address} error=$error',
        );
      }
    }
    return changed ? _store.load() : records;
  }

  /// Removes hardware drafts prepared but abandoned before their broadcast
  /// boundary, instead of waiting for expiry and a synced wallet. A Ledger
  /// outbox operation exists from the moment the device signature is
  /// checkpointed, and an open funding flow owns its draft until then, so
  /// neither a draft being signed nor one awaiting broadcast is touched.
  Future<List<PaymentLinkRecoveryRecord>> _dropAbandonedPreparedDrafts(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final loadLedgerOperationRefs = _loadLedgerOperationRefs;
    final isFundingSurfaceOpen = _isFundingSurfaceOpen;
    if (loadLedgerOperationRefs == null || isFundingSurfaceOpen == null) {
      return records;
    }
    final now = DateTime.now().toUtc();
    final candidates = records
        .where(
          (record) =>
              record.state == PaymentLinkRecoveryState.draft &&
              (record.fundingTxids?.trim().isNotEmpty ?? false) &&
              record.submittedAtHeight == null &&
              now.difference(record.updatedAt) >
                  kPaymentLinkInertDraftRetention &&
              !isFundingSurfaceOpen(record.link.address),
        )
        .toList();
    if (candidates.isEmpty) return records;
    final Set<String> operationRefs;
    try {
      operationRefs = await loadLedgerOperationRefs();
    } catch (error) {
      // Includes the pause during account deletion; retry on a later load.
      log('PaymentLinkRecoveryReconciler: Ledger outbox lookup failed: $error');
      return records;
    }
    var changed = false;
    final handledBatches = <String>{};
    for (final record in candidates) {
      final address = record.link.address;
      final batchId = record.batchId;
      if (batchId != null && !handledBatches.add(batchId)) continue;
      if (operationRefs.contains(address) ||
          (batchId != null && operationRefs.contains(batchId)) ||
          isFundingSurfaceOpen(address)) {
        continue;
      }
      try {
        if (batchId != null) {
          final members = records.where((member) => member.batchId == batchId);
          if (members.length != record.batchCount ||
              members.any(
                (member) =>
                    !candidates.contains(member) ||
                    isFundingSurfaceOpen(member.link.address),
              )) {
            continue;
          }
          await _store.removeUnbroadcastBatch(batchId);
        } else {
          await _store.removeUnsubmittedPreparedDraft(address: address);
        }
        changed = true;
      } catch (error) {
        log(
          'PaymentLinkRecoveryReconciler: abandoned draft cleanup failed '
          'address=$address error=$error',
        );
      }
    }
    return changed ? _store.load() : records;
  }

  Future<int> countUnsharedFundedForAccount(String sourceAccountUuid) async {
    if (sourceAccountUuid.isEmpty) return 0;
    return countUnsharedFundedPaymentLinks(
      await load(),
      sourceAccountUuid: sourceAccountUuid,
    );
  }

  /// [countUnsharedFundedForAccount] plus drafts whose Ledger funding is
  /// signed and can still be broadcast. Throws when the outbox is unreadable,
  /// so the warning falls back to "couldn't check".
  Future<int> countUnsharedForRemovalWarning(String sourceAccountUuid) async {
    if (sourceAccountUuid.isEmpty) return 0;
    final records = await load();
    final count = countUnsharedFundedPaymentLinks(
      records,
      sourceAccountUuid: sourceAccountUuid,
    );
    final loadSignedPending = _loadSignedPendingGiftCardRefs;
    if (loadSignedPending == null) return count;
    final signedPending = await loadSignedPending(sourceAccountUuid);
    return count +
        records
            .where(
              (record) =>
                  record.sourceAccountUuid == sourceAccountUuid &&
                  record.state == PaymentLinkRecoveryState.draft &&
                  !record.mayHoldUnsharedFunds &&
                  (signedPending.contains(record.link.address) ||
                      (record.batchId != null &&
                          signedPending.contains(record.batchId))),
            )
            .length;
  }

  Future<List<PaymentLinkRecoveryRecord>> load() async {
    var records = await _store.load();
    records = await _dropInertDrafts(records);
    records = await _dropAbandonedPreparedDrafts(records);
    final preparedDrafts = records
        .where(
          (record) =>
              record.state == PaymentLinkRecoveryState.draft &&
              (record.fundingTxids?.trim().isNotEmpty ?? false),
        )
        .toList();
    // A broadcast the wallet started but never got a result for. It has no
    // transaction id to match, so it is settled against the Gift Card's own
    // wallet rather than the source account's history.
    final ambiguousDrafts = records
        .where((record) => record.isAmbiguousSubmission)
        .toList();
    final unsharedFundings = records
        .where(
          (record) =>
              record.state == PaymentLinkRecoveryState.funded &&
              (record.fundingTxids?.trim().isNotEmpty ?? false),
        )
        .toList();
    if (preparedDrafts.isEmpty &&
        ambiguousDrafts.isEmpty &&
        unsharedFundings.isEmpty) {
      return records;
    }

    try {
      final accountUuids = {
        for (final record in [...preparedDrafts, ...unsharedFundings])
          record.sourceAccountUuid,
      };
      late final BigInt currentHeight;
      late final BigInt scannedHeight;
      late final Map<String, List<rust_sync.TransactionInfo>>
      transactionsByAccount;
      if (preparedDrafts.isEmpty) {
        transactionsByAccount = await _loadTransactionsByAccount(accountUuids);
      } else {
        final lookupResults = await Future.wait<Object>([
          _loadCurrentHeight(),
          _loadScannedHeight(),
          _loadTransactionsByAccount(accountUuids),
        ]);
        currentHeight = lookupResults[0] as BigInt;
        scannedHeight = lookupResults[1] as BigInt;
        transactionsByAccount =
            lookupResults[2] as Map<String, List<rust_sync.TransactionInfo>>;
      }

      var changed = false;
      final handledPreparedBatches = <String>{};
      for (final record in preparedDrafts) {
        if (record.batchId case final batchId?) {
          if (!handledPreparedBatches.add(batchId)) continue;
          final members = records
              .where((entry) => entry.batchId == batchId)
              .toList();
          if (members.length != record.batchCount ||
              members.any(
                (entry) =>
                    entry.state != PaymentLinkRecoveryState.draft ||
                    entry.fundingTxids != record.fundingTxids ||
                    entry.submittedAtHeight == null,
              )) {
            continue;
          }
          final disposition = _paymentLinkPreparedFundingDisposition(
            fundingTxid: record.fundingTxids!.trim(),
            expiryHeight: record.preparedExpiryHeight,
            currentHeight: currentHeight,
            scannedHeight: scannedHeight,
            transactions:
                transactionsByAccount[record.sourceAccountUuid] ?? const [],
          );
          try {
            switch (disposition) {
              case PaymentLinkPreparedFundingDisposition.pending:
                break;
              case PaymentLinkPreparedFundingDisposition.funded:
                await _store.markBatchFunded(
                  batchId: batchId,
                  fundingTxids: record.fundingTxids!.trim(),
                );
                changed = true;
              case PaymentLinkPreparedFundingDisposition.expired:
                await _store.removeTerminalBatch(batchId);
                changed = true;
            }
          } catch (error) {
            log(
              'PaymentLinkRecoveryReconciler: prepared batch update failed '
              'batch=$batchId error=$error',
            );
          }
          continue;
        }
        final fundingTxid = record.fundingTxids!.trim();
        final disposition = _paymentLinkPreparedFundingDisposition(
          fundingTxid: fundingTxid,
          expiryHeight: record.preparedExpiryHeight,
          currentHeight: currentHeight,
          scannedHeight: scannedHeight,
          transactions:
              transactionsByAccount[record.sourceAccountUuid] ?? const [],
        );
        try {
          switch (disposition) {
            case PaymentLinkPreparedFundingDisposition.pending:
              continue;
            case PaymentLinkPreparedFundingDisposition.funded:
              await _store.markFunded(
                address: record.link.address,
                fundingTxids: fundingTxid,
              );
              changed = true;
              break;
            case PaymentLinkPreparedFundingDisposition.expired:
              await _store.removeUnbroadcastDraft(address: record.link.address);
              changed = true;
              break;
          }
        } catch (error) {
          log(
            'PaymentLinkRecoveryReconciler: prepared funding update failed '
            'address=${record.link.address} error=$error',
          );
        }
      }
      final handledAmbiguousBatches = <String>{};
      for (final record in ambiguousDrafts) {
        if (record.batchId case final batchId?) {
          if (!handledAmbiguousBatches.add(batchId)) continue;
          final members = records
              .where((entry) => entry.batchId == batchId)
              .toList();
          if (members.length != record.batchCount ||
              members.any((entry) => !entry.isAmbiguousSubmission)) {
            continue;
          }
          try {
            // One transaction funds every member or none, so probe the claim
            // wallets one at a time and stop at the first that disagrees.
            Set<String>? common;
            for (final entry in members) {
              final funding = _paymentLinkOwnFundingTxids(
                await _loadLinkFundingHistory(entry.link),
                expectedZatoshi: paymentLinkFundingAmountZatoshi(
                  entry.link.amountZatoshi,
                ),
              ).toSet();
              common = common == null ? funding : common.intersection(funding);
              if (common.isEmpty) break;
            }
            if (common == null || common.length != 1) continue;
            final txid = common.single;
            await _store.markBatchSubmitted(
              batchId: batchId,
              fundingTxids: txid,
            );
            await _store.markBatchFunded(batchId: batchId, fundingTxids: txid);
            changed = true;
          } catch (error) {
            log(
              'PaymentLinkRecoveryReconciler: batch funding update failed batch=$batchId error=$error',
            );
          }
          continue;
        }
        try {
          final fundingTxids = _paymentLinkOwnFundingTxids(
            await _loadLinkFundingHistory(record.link),
            expectedZatoshi: paymentLinkFundingAmountZatoshi(
              record.link.amountZatoshi,
            ),
          );
          if (fundingTxids.isNotEmpty) {
            final txids = fundingTxids.join(',');
            // Record the recovered id before promoting, so a failure between
            // the two still leaves a draft the prepared path can settle.
            await _store.markSubmitted(
              address: record.link.address,
              fundingTxids: txids,
            );
            await _store.markFunded(
              address: record.link.address,
              fundingTxids: txids,
            );
            changed = true;
            continue;
          }
          // Absence is not proof that the broadcast failed. The Gift Card is
          // scanned through separately selected lightwalletd infrastructure,
          // which can omit compact-block data or disagree with the source
          // wallet's scan. Retain the bearer secret unless positive funding
          // evidence promotes it; automatic cleanup could make mined funds
          // permanently unspendable.
        } catch (error) {
          log(
            'PaymentLinkRecoveryReconciler: ambiguous funding update failed '
            'address=${record.link.address} error=$error',
          );
        }
      }
      for (final record in unsharedFundings) {
        final fundingTxids = record.fundingTxids!.trim();
        if (!paymentLinkFundingExpired(
          fundingTxids: fundingTxids,
          transactions:
              transactionsByAccount[record.sourceAccountUuid] ?? const [],
        )) {
          continue;
        }
        try {
          await _store.removeUnsharedExpiredFunding(
            address: record.link.address,
            fundingTxids: fundingTxids,
          );
          changed = true;
        } catch (error) {
          log(
            'PaymentLinkRecoveryReconciler: expired funding cleanup failed '
            'address=${record.link.address} error=$error',
          );
        }
      }
      return changed ? await _store.load() : records;
    } catch (error) {
      // Retain the bearer secret and retry on the next foreground refresh when
      // chain height or wallet history is temporarily unavailable.
      log(
        'PaymentLinkRecoveryReconciler: prepared funding lookup failed: $error',
      );
      return records;
    }
  }
}
