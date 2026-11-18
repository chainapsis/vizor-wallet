import '../../../core/l10n/l10n.dart';
import 'swap_activity_status_mapper.dart' show swapActivityExplorerUri;
import 'swap_models.dart';

const swapSupportEmail = 'support@vizor.cash';

bool swapNeedsSupportNotice(SwapIntent intent) =>
    !intent.startPending &&
    intent.providerRefundInfo?.hasRecordedRefund != true &&
    (intent.status == SwapIntentStatus.expired ||
        (intent.status == SwapIntentStatus.failed &&
            (intent.hasConfirmedDepositEvidence ||
                intent.hasProviderObservedDepositEvidence)));

/// Copies transaction identifiers and route information for support.
/// Wallet credentials, recipient addresses and amounts are never included.
String swapSupportDetails(AppLocalizations l10n, SwapIntent intent) {
  String value(String? text) =>
      text?.trim().isNotEmpty == true ? text!.trim() : l10n.commonUnknown;
  final txHash = intent.depositTxHash?.trim().isNotEmpty == true
      ? intent.depositTxHash
      : intent.originChainTxHash;
  final routeDetails = intent.confidential
      ? l10n.swapSupportConfidentialRoute
      : l10n.swapSupportExplorer(
          value(swapActivityExplorerUri(intent)?.toString()),
        );
  return l10n.swapSupportDetails(
    value(intent.providerStatusRaw ?? intent.status.name),
    value(intent.depositAddress),
    value(txHash),
    routeDetails,
  );
}
