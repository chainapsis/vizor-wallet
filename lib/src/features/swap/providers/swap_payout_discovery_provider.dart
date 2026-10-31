import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sync_provider.dart';
import '../models/swap_models.dart';
import '../models/swap_payout_discovery.dart';

export '../models/swap_payout_discovery.dart';
import 'pay_deposit_transaction_provider.dart';

/// Whether the account's wallet has the payout `walletTxid`. Checks the recent
/// transactions first and the full history otherwise, and checks again when
/// the recent transactions change.
final swapPayoutFoundProvider = FutureProvider.autoDispose
    .family<bool, ({String accountUuid, String walletTxid})>((ref, key) async {
      final txid = key.walletTxid.toLowerCase();
      final recent = ref.watch(
        syncProvider.select((value) => value.value?.recentTransactions),
      );
      if (recent?.any((tx) => tx.txidHex.toLowerCase() == txid) ?? false) {
        return true;
      }
      final loaded = await ref.read(payDepositTransactionLoaderProvider)(
        accountUuid: key.accountUuid,
        walletTxid: txid,
      );
      return loaded != null;
    });

/// Whether the wallet is still finding a one-time payout NEAR reported sent:
/// see [swapPayoutAwaitingDiscovery]. Unknown until the check answers, which
/// reads as found so a finished swap never flickers back.
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
  return !(found.value ?? true);
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
        completedAt: intent.completedAt,
        walletTxid: swapChainTxidToWalletTxidHex(intent.destinationChainTxHash),
        now: DateTime.now().toUtc(),
      ),
    );
