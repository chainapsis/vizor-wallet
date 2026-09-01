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
  required List<rust_sync.TransactionInfo> transactions,
}) {
  if (paymentLinkFundingTransactionExists(
    fundingTxid: fundingTxid,
    transactions: transactions,
  )) {
    return PaymentLinkPreparedFundingDisposition.funded;
  }
  if (currentHeight >= BigInt.from(expiryHeight)) {
    return PaymentLinkPreparedFundingDisposition.expired;
  }
  return PaymentLinkPreparedFundingDisposition.pending;
}

class PaymentLinkRecoveryReconciler {
  const PaymentLinkRecoveryReconciler(
    this._store, {
    required Future<BigInt> Function() loadCurrentHeight,
    required PaymentLinkFundingHistoryLoader loadTransactionsByAccount,
  }) : _loadCurrentHeight = loadCurrentHeight,
       _loadTransactionsByAccount = loadTransactionsByAccount;

  final PaymentLinkRecoveryStore _store;
  final Future<BigInt> Function() _loadCurrentHeight;
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
    if (preparedDrafts.isEmpty) return records;

    try {
      final lookupResults = await Future.wait<Object>([
        _loadCurrentHeight(),
        _loadTransactionsByAccount(
          preparedDrafts.map((record) => record.sourceAccountUuid).toSet(),
        ),
      ]);
      final currentHeight = lookupResults[0] as BigInt;
      final transactionsByAccount =
          lookupResults[1] as Map<String, List<rust_sync.TransactionInfo>>;

      var changed = false;
      for (final record in preparedDrafts) {
        final fundingTxid = record.fundingTxids!.trim();
        final disposition = _paymentLinkPreparedFundingDisposition(
          fundingTxid: fundingTxid,
          expiryHeight: record.preparedExpiryHeight!,
          currentHeight: currentHeight,
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
              await _store.clearPrepared(address: record.link.address);
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
