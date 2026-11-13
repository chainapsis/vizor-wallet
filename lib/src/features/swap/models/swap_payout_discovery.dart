import '../../../core/l10n/l10n.dart';
import 'swap_models.dart';

/// The wallet txid of a payout NEAR reports sent to a one-time address, which
/// only receiver recovery can find, or null for any other swap. Its age says
/// nothing about receipt, so only the wallet finding it settles it.
String? swapPayoutAwaitingDiscovery({
  required bool privateAddress,
  required SwapDirection? direction,
  required SwapIntentStatus status,
  required String? walletTxid,
}) {
  if (!privateAddress ||
      direction != SwapDirection.externalToZec ||
      status != SwapIntentStatus.complete) {
    return null;
  }
  return walletTxid;
}

/// The update notice for a swap whose one-time payout or refund the wallet
/// still has to find, or null for an ordinary or settled swap. An open swap
/// into ZEC, or one [findingPayout], waits on its payout. An open swap out of
/// ZEC may still be refunded.
String? swapUpdateRequiredText(
  AppLocalizations l10n,
  SwapIntent intent, {
  required bool findingPayout,
}) {
  if (!intent.privateAddress) return null;
  return switch (intent.direction) {
    SwapDirection.externalToZec
        when findingPayout || !intent.status.isTerminal =>
      l10n.swapPayoutUpdateRequired,
    SwapDirection.zecToExternal when !intent.status.isTerminal =>
      l10n.swapRefundUpdateRequired,
    _ => null,
  };
}
