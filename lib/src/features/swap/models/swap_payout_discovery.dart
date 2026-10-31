import 'swap_models.dart';

/// What a swap whose one-time payout NEAR sent but the wallet hasn't found
/// yet shows as its status.
const kSwapFindingPayoutLabel = 'Finding your ZEC…';

/// How long after NEAR reports a one-time payout sent the wallet may still be
/// finding it. Older payouts are treated as found.
const swapPayoutDiscoveryWindow = Duration(days: 7);

/// The wallet txid of a payout NEAR reports sent to a one-time address within
/// [swapPayoutDiscoveryWindow] of [now], which only receiver recovery can
/// find, or null for any other swap.
String? swapPayoutAwaitingDiscovery({
  required bool privateAddress,
  required SwapDirection? direction,
  required SwapIntentStatus status,
  required DateTime? completedAt,
  required String? walletTxid,
  required DateTime now,
}) {
  if (!privateAddress ||
      direction != SwapDirection.externalToZec ||
      status != SwapIntentStatus.complete ||
      completedAt == null ||
      !completedAt.isAfter(now.subtract(swapPayoutDiscoveryWindow))) {
    return null;
  }
  return walletTxid;
}
