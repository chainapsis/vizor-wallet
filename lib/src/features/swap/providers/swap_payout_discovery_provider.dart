import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/swap_models.dart';
import '../models/swap_payout_discovery.dart';

export '../models/swap_payout_discovery.dart';

/// Reads an account's rows for `walletTxids` only, not its whole history.
typedef SwapPayoutRowsLoader =
    Future<List<rust_sync.TransactionInfo>> Function(
      String accountUuid,
      List<String> walletTxids,
    );

/// Loads payout rows with [SyncNotifier.transactionRowsForTxids], so a
/// wallet reset waits for the read or refuses it, and a read never names a
/// new wallet. Without a wallet it fails, giving no answer. Overridable in
/// tests.
final swapPayoutRowsLoaderProvider = Provider<SwapPayoutRowsLoader>(
  (ref) =>
      (accountUuid, walletTxids) async =>
          await ref
              .read(syncProvider.notifier)
              .transactionRowsForTxids(accountUuid, walletTxids) ??
          (throw StateError('No wallet to read payouts from.')),
);

/// Answers payout checks with one read per account for all the checks a
/// screen starts in one build.
class SwapPayoutLookup {
  SwapPayoutLookup(this._loadRows);

  final SwapPayoutRowsLoader _loadRows;
  final _pending = <String, Map<String, Completer<bool>>>{};

  /// Whether the account's wallet has `walletTxid`. Checks asked for before
  /// the next microtask share its read.
  Future<bool> has(String accountUuid, String walletTxid) {
    final batch = _pending.putIfAbsent(accountUuid, () {
      scheduleMicrotask(() => _read(accountUuid));
      return {};
    });
    return batch.putIfAbsent(walletTxid, Completer<bool>.new).future;
  }

  /// Answers the account's waiting checks from one read, or fails them all.
  Future<void> _read(String accountUuid) async {
    final batch = _pending.remove(accountUuid)!;
    try {
      final rows = await _loadRows(accountUuid, batch.keys.toList());
      final found = {for (final row in rows) row.txidHex.toLowerCase()};
      batch.forEach((txid, check) => check.complete(found.contains(txid)));
    } catch (error, stackTrace) {
      for (final check in batch.values) {
        check.completeError(error, stackTrace);
      }
    }
  }
}

/// The [SwapPayoutLookup] payout checks share.
final swapPayoutLookupProvider = Provider<SwapPayoutLookup>(
  (ref) => SwapPayoutLookup(ref.watch(swapPayoutRowsLoaderProvider)),
);

/// Whether the account's wallet has the payout `walletTxid`. Answers at once
/// from the recent transactions, reads just that transaction otherwise (see
/// [SwapPayoutLookup]), and checks again when the recent transactions change.
final swapPayoutFoundProvider = FutureProvider.autoDispose
    .family<bool, ({String accountUuid, String walletTxid})>((ref, key) {
      final txid = key.walletTxid.toLowerCase();
      final recent = ref.watch(
        syncProvider.select((value) => value.value?.recentTransactions),
      );
      if (recent?.any((tx) => tx.txidHex.toLowerCase() == txid) ?? false) {
        return true;
      }
      return ref.read(swapPayoutLookupProvider).has(key.accountUuid, txid);
    });

/// Whether the wallet is still finding a one-time payout NEAR reported sent:
/// see [swapPayoutAwaitingDiscovery]. Only a check that found the payout ends
/// this. A pending or failed check keeps the last answer, or finding without
/// one, so an unknown result never reads as received.
bool watchSwapFindingPayout(
  WidgetRef ref, {
  required String? accountUuid,
  required String? awaitingTxid,
}) {
  if (accountUuid == null || awaitingTxid == null) return false;
  final found = ref.watch(
    swapPayoutFoundProvider((
      accountUuid: accountUuid,
      walletTxid: awaitingTxid,
    )),
  );
  return found.value != true;
}

/// [watchSwapFindingPayout] for [intent].
bool watchIntentFindingPayout(WidgetRef ref, SwapIntent intent) =>
    watchSwapFindingPayout(
      ref,
      accountUuid: intent.accountUuid?.trim(),
      awaitingTxid: swapPayoutAwaitingDiscovery(
        privateAddress: intent.privateAddress,
        direction: intent.direction,
        status: intent.status,
        walletTxid: swapChainTxidToWalletTxidHex(intent.destinationChainTxHash),
      ),
    );
