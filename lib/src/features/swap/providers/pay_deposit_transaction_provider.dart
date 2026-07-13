import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/swap_chain_txid.dart';

typedef PayDepositTransactionQuery =
    ({String accountUuid, String depositTxid});

typedef PayDepositTransactionLoader =
    Future<rust_sync.TransactionInfo?> Function({
      required String accountUuid,
      required String walletTxid,
    });

/// Loads one Pay deposit transaction from the account's complete wallet
/// history. SyncState intentionally keeps only the latest ten transactions, so
/// it cannot be the sole source for old Pay activity details.
final payDepositTransactionLoaderProvider =
    Provider<PayDepositTransactionLoader>((ref) {
      return ({required accountUuid, required walletTxid}) async {
        final dbPath = await getWalletDbPath();
        final endpoint = ref.read(rpcEndpointProvider);
        final transactions = await rust_sync.getTransactionHistory(
          dbPath: dbPath,
          network: endpoint.networkName,
          accountUuid: accountUuid,
        );
        final normalizedTxid = walletTxid.toLowerCase();
        for (final transaction in transactions) {
          if (transaction.txidHex.toLowerCase() == normalizedTxid) {
            return transaction;
          }
        }
        return null;
      };
    });

/// Scoped to the Pay activity detail currently on screen. A completed sync
/// invalidates the lookup so a previously unmined deposit can reveal its real
/// fee without keeping a full-history cache alive globally.
final payDepositTransactionProvider = FutureProvider.autoDispose.family<
  rust_sync.TransactionInfo?,
  PayDepositTransactionQuery
>((ref, query) async {
  ref.watch(
    syncProvider.select((sync) {
      final value = sync.value;
      if (value?.accountUuid != query.accountUuid) return null;
      return value?.lastSyncCompletedAt;
    }),
  );

  final walletTxid = swapChainTxidToWalletTxidHex(query.depositTxid);
  if (walletTxid == null) return null;
  return ref.read(payDepositTransactionLoaderProvider)(
    accountUuid: query.accountUuid,
    walletTxid: walletTxid,
  );
});
