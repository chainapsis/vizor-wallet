import '../../../core/l10n/l10n.dart';
import '../domain/near_intents_explorer.dart';
import 'swap_models.dart';

const swapSupportEmail = 'support@vizor.cash';

bool swapNeedsSupportNotice(SwapIntent intent) =>
    !intent.startPending &&
    intent.providerRefundInfo?.hasRecordedRefund != true &&
    (intent.status == SwapIntentStatus.expired ||
        (intent.status == SwapIntentStatus.failed &&
            (intent.hasConfirmedDepositEvidence ||
                intent.hasProviderObservedDepositEvidence)));

/// Only transaction identifiers enter the explicitly copied support details.
/// Wallet credentials, recipient addresses and amounts are never included.
String swapSupportDetails(AppLocalizations l10n, SwapIntent intent) {
  String value(String? text) =>
      text?.trim().isNotEmpty == true ? text!.trim() : l10n.commonUnknown;
  final txHash = intent.depositTxHash?.trim().isNotEmpty == true
      ? intent.depositTxHash
      : intent.originChainTxHash;
  final explorer = nearIntentsExplorerUri(
    depositAddress: intent.depositAddress,
    depositTxHash: txHash,
    nearIntentHash: intent.nearIntentHash,
  );
  return l10n.swapSupportDetails(
    value(intent.providerStatusRaw ?? intent.status.name),
    value(intent.depositAddress),
    value(txHash),
    explorer?.toString() ?? l10n.commonUnknown,
  );
}
