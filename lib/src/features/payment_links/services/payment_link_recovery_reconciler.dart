import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/vizor_payment_link.dart';
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

/// How far past its submission height an ambiguous funding broadcast is
/// treated as never having reached the chain.
///
/// A Zcash transaction expires 40 blocks after the height it was built at
/// (ZIP-203), and the wallet's own scan trails the tip; 20 blocks of margin
/// keeps a slow scan from discarding a Gift Card that really was funded.
const kPaymentLinkAmbiguousFundingExpiryDelta = 60;

/// How long an ambiguous funding is kept when no submission height was known.
const kPaymentLinkAmbiguousFundingUndatedRetention = Duration(hours: 24);

/// How long a draft that never started its broadcast is kept before recovery
/// drops it — long enough for a creation still proposing in this process.
const kPaymentLinkInertDraftRetention = Duration(minutes: 10);

final paymentLinkRecoveryReconcilerProvider =
    Provider<PaymentLinkRecoveryReconciler>((ref) {
      final claimWallet = PaymentLinkClaimWallet(ref);
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
      );
    });

final paymentLinkUnsharedFundedCountProvider =
    FutureProvider.family<int, String>((ref, sourceAccountUuid) async {
      ref.watch(paymentLinkLifecycleRevisionProvider);
      return ref
          .watch(paymentLinkRecoveryReconcilerProvider)
          .countUnsharedFundedForAccount(sourceAccountUuid);
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
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where(
        (transaction) =>
            (transaction.txKind == 'received' ||
                transaction.txKind == 'receiving') &&
            !transaction.expiredUnmined &&
            transaction.txidHex.trim().isNotEmpty,
      )
      .map((transaction) => transaction.txidHex.trim())
      .toSet()
      .toList();
}

bool _paymentLinkAmbiguousFundingExpired({
  required PaymentLinkRecoveryRecord record,
  required BigInt scannedHeight,
}) {
  final submittedAtHeight = record.submittedAtHeight ?? 0;
  if (submittedAtHeight <= 0) {
    // No height was known at submission, so age is the only measure left.
    return DateTime.now().toUtc().difference(record.updatedAt) >
        kPaymentLinkAmbiguousFundingUndatedRetention;
  }
  return scannedHeight >=
      BigInt.from(submittedAtHeight + kPaymentLinkAmbiguousFundingExpiryDelta);
}

class PaymentLinkRecoveryReconciler {
  const PaymentLinkRecoveryReconciler(
    this._store, {
    required Future<BigInt> Function() loadCurrentHeight,
    required Future<BigInt> Function() loadScannedHeight,
    required PaymentLinkFundingHistoryLoader loadTransactionsByAccount,
    required PaymentLinkOwnFundingHistoryLoader loadLinkFundingHistory,
  }) : _loadCurrentHeight = loadCurrentHeight,
       _loadScannedHeight = loadScannedHeight,
       _loadTransactionsByAccount = loadTransactionsByAccount,
       _loadLinkFundingHistory = loadLinkFundingHistory;

  final PaymentLinkRecoveryStore _store;
  final Future<BigInt> Function() _loadCurrentHeight;
  final Future<BigInt> Function() _loadScannedHeight;
  final PaymentLinkFundingHistoryLoader _loadTransactionsByAccount;
  final PaymentLinkOwnFundingHistoryLoader _loadLinkFundingHistory;

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
    for (final record in inert) {
      try {
        await _store.removeUnsubmittedDraft(address: record.link.address);
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

  Future<int> countUnsharedFundedForAccount(String sourceAccountUuid) async {
    if (sourceAccountUuid.isEmpty) return 0;
    return countUnsharedFundedPaymentLinks(
      await load(),
      sourceAccountUuid: sourceAccountUuid,
    );
  }

  Future<List<PaymentLinkRecoveryRecord>> load() async {
    var records = await _store.load();
    records = await _dropInertDrafts(records);
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
      if (preparedDrafts.isEmpty && ambiguousDrafts.isEmpty) {
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
      for (final record in preparedDrafts) {
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
      for (final record in ambiguousDrafts) {
        try {
          final fundingTxids = _paymentLinkOwnFundingTxids(
            await _loadLinkFundingHistory(record.link),
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
          if (!_paymentLinkAmbiguousFundingExpired(
            record: record,
            scannedHeight: scannedHeight,
          )) {
            continue;
          }
          // The wallet scanned well past any height this broadcast could have
          // been mined at and the Gift Card holds nothing: the transaction
          // never reached the chain.
          await _store.removeUnbroadcastDraft(address: record.link.address);
          changed = true;
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
      return changed ? _store.load() : records;
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
