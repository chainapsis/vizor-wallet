import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'payment_link_lifecycle_revision.dart';
import 'payment_link_recovery_store.dart';
import 'payment_link_transaction_matching.dart';

typedef PaymentLinkFundingHistoryLoader =
    Future<Map<String, List<rust_sync.TransactionInfo>>> Function(
      Set<String> accountUuids,
    );

final paymentLinkRecoveryReconcilerProvider =
    Provider<PaymentLinkRecoveryReconciler>((ref) {
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
  required int expiryHeight,
  required BigInt currentHeight,
  required BigInt scannedHeight,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  if (paymentLinkFundingTransactionExists(
    fundingTxid: fundingTxid,
    transactions: transactions,
  )) {
    return PaymentLinkPreparedFundingDisposition.funded;
  }
  if (currentHeight >= BigInt.from(expiryHeight) &&
      scannedHeight >= BigInt.from(expiryHeight)) {
    return PaymentLinkPreparedFundingDisposition.expired;
  }
  return PaymentLinkPreparedFundingDisposition.pending;
}

class PaymentLinkRecoveryReconciler {
  const PaymentLinkRecoveryReconciler(
    this._store, {
    required Future<BigInt> Function() loadCurrentHeight,
    required Future<BigInt> Function() loadScannedHeight,
    required PaymentLinkFundingHistoryLoader loadTransactionsByAccount,
  }) : _loadCurrentHeight = loadCurrentHeight,
       _loadScannedHeight = loadScannedHeight,
       _loadTransactionsByAccount = loadTransactionsByAccount;

  final PaymentLinkRecoveryStore _store;
  final Future<BigInt> Function() _loadCurrentHeight;
  final Future<BigInt> Function() _loadScannedHeight;
  final PaymentLinkFundingHistoryLoader _loadTransactionsByAccount;

  Future<int> countUnsharedFundedForAccount(String sourceAccountUuid) async {
    if (sourceAccountUuid.isEmpty) return 0;
    return countUnsharedFundedPaymentLinks(
      await load(),
      sourceAccountUuid: sourceAccountUuid,
    );
  }

  Future<List<PaymentLinkRecoveryRecord>> load() async {
    final records = await _store.load();
    final preparedDrafts = records
        .where(
          (record) =>
              record.state == PaymentLinkRecoveryState.draft &&
              (record.fundingTxids?.trim().isNotEmpty ?? false),
        )
        .toList();
    final unsharedFundings = records
        .where(
          (record) =>
              record.state == PaymentLinkRecoveryState.funded &&
              (record.fundingTxids?.trim().isNotEmpty ?? false),
        )
        .toList();
    if (preparedDrafts.isEmpty && unsharedFundings.isEmpty) return records;

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
      for (final record in preparedDrafts) {
        final fundingTxid = record.fundingTxids!.trim();
        final disposition = _paymentLinkPreparedFundingDisposition(
          fundingTxid: fundingTxid,
          expiryHeight: record.preparedExpiryHeight!,
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
