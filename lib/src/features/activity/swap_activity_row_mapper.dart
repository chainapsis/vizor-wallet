import 'package:flutter/widgets.dart';

import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../swap/models/swap_models.dart';
import 'activity_row_mapper.dart';
import 'models/activity_row_data.dart';

const _swapActivityAmountPrivacyMaskLength = 3;

class SwapActivityRowItem {
  const SwapActivityRowItem({
    required this.intentId,
    required this.providerLabel,
    required this.sellAmountText,
    required this.receiveEstimateText,
    required this.status,
    required this.activityTimestamp,
    this.direction,
    this.externalAsset,
    this.depositTxHash,
    this.depositClaimedAt,
    this.completedAt,
    this.lastStatusCheckedAt,
    this.updatedAt,
    this.receiveWalletTxidHex,
    this.depositWalletTxidHex,
  });

  factory SwapActivityRowItem.fromRecord(SwapIntentRecord record) {
    return SwapActivityRowItem(
      intentId: record.id,
      providerLabel: record.providerLabel,
      sellAmountText: record.sellAmountText,
      receiveEstimateText: record.receiveEstimateText,
      status: record.status,
      direction: record.direction,
      externalAsset: record.externalAsset,
      depositTxHash: record.depositTxHash,
      depositClaimedAt: record.depositClaimedAt,
      activityTimestamp: record.activityTimestamp,
      completedAt: record.completedAt,
      lastStatusCheckedAt: record.lastStatusCheckedAt,
      updatedAt: record.updatedAt,
      receiveWalletTxidHex: swapChainTxidToWalletTxidHex(
        record.destinationChainTxHash,
      ),
      depositWalletTxidHex: swapChainTxidToWalletTxidHex(record.depositTxHash),
    );
  }

  final String intentId;
  final String providerLabel;
  final String sellAmountText;
  final String receiveEstimateText;
  final SwapIntentStatus status;
  final SwapDirection? direction;
  final SwapAsset? externalAsset;
  final String? depositTxHash;
  final DateTime? depositClaimedAt;
  final DateTime? activityTimestamp;
  final DateTime? completedAt;
  final DateTime? lastStatusCheckedAt;
  final DateTime? updatedAt;

  /// Wallet-order txid of the ZEC payout (external→ZEC), used to absorb the
  /// matching on-chain receive row into this swap's sub row.
  final String? receiveWalletTxidHex;

  /// Wallet-order txid of our ZEC deposit broadcast (ZEC→external), used to
  /// suppress the duplicate standalone Sent row.
  final String? depositWalletTxidHex;
}

List<SwapActivityRowItem> swapActivityRowItemsFromRecords(
  Iterable<SwapIntentRecord> records,
) {
  return [for (final record in records) SwapActivityRowItem.fromRecord(record)];
}

ActivityRowData buildSwapActivityRow({
  required BuildContext context,
  required SwapActivityRowItem item,
  bool privacyModeEnabled = false,
  VoidCallback? onTap,
  String? receivedAmountText,
  VoidCallback? onReceivedLegTap,
}) {
  final colors = context.colors;
  final failed = _swapActivityFailed(item.status);
  final timedOut = item.status == SwapIntentStatus.expired;
  final returnsFunds = _swapActivityReturnsFunds(item);
  final incompleteDeposit = item.status == SwapIntentStatus.incompleteDeposit;
  final complete = item.status == SwapIntentStatus.complete;
  final sellAsset = _swapActivitySellAsset(item);
  final receiveAsset = _swapActivityReceiveAsset(item);
  final progress = _swapActivityProgress(item);

  return ActivityRowData(
    title: _swapActivityTitle(item.status),
    leadingIconName: AppIcons.swapArrows,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    leadingProgressValue: complete ? null : progress?.value,
    subtitle: returnsFunds
        ? '${sellAsset?.symbol ?? 'ZEC'} Refunded'
        : _swapActivityAssetSubtitle(sellAsset) ?? item.providerLabel,
    amountText: _swapActivityAmountText(
      item,
      includeSign: !(returnsFunds || timedOut),
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName: returnsFunds ? AppIcons.uturnUp : null,
    amountIconColor: returnsFunds ? colors.icon.regular : null,
    amountColor: colors.text.primary,
    amountSubtitle: timedOut ? 'Timeout' : null,
    amountSubtitleIconName: timedOut ? AppIcons.time : null,
    amountSubtitleIconColor: timedOut ? colors.text.secondary : null,
    statusText: _swapActivityStatusText(item.status, progress),
    statusIconName: failed
        ? AppIcons.skull
        : item.status == SwapIntentStatus.refunded
        ? AppIcons.uturnUp
        : incompleteDeposit
        ? AppIcons.warning
        : complete
        ? null
        : AppIcons.loader,
    statusColor: failed
        ? colors.text.destructive
        : incompleteDeposit
        ? colors.text.brandCrimson
        : colors.text.secondary,
    timestampText: formatActivityTimestamp(item.activityTimestamp),
    childRows: _swapActivityChildRows(
      context: context,
      item: item,
      receiveAsset: receiveAsset,
      privacyModeEnabled: privacyModeEnabled,
      receivedAmountText: receivedAmountText,
      onReceivedLegTap: onReceivedLegTap,
    ),
    onTap: onTap,
  );
}

/// Results-only sub rows: a single settled leg per swap group. In-progress
/// legs render no sub row — the parent's progress ring carries that state.
List<ActivityRowData> _swapActivityChildRows({
  required BuildContext context,
  required SwapActivityRowItem item,
  required SwapAsset? receiveAsset,
  required bool privacyModeEnabled,
  required String? receivedAmountText,
  required VoidCallback? onReceivedLegTap,
}) {
  final direction = item.direction;
  if (direction == null || receiveAsset == null) return const [];
  if (item.status != SwapIntentStatus.complete) return const [];

  final colors = context.colors;
  final receivesZec = direction == SwapDirection.externalToZec;
  // The absorbed on-chain receive carries the real settled amount; fall back
  // to the quote estimate until the payout tx is matched.
  final amountText =
      receivesZec && receivedAmountText != null && !privacyModeEnabled
      ? receivedAmountText
      : _swapActivityReceiveAmountText(
          item,
          privacyModeEnabled: privacyModeEnabled,
        );
  return [
    ActivityRowData(
      title: receivesZec
          ? 'Received ${receiveAsset.symbol}'
          : 'Deposited ${receiveAsset.symbol}',
      leadingIconName: AppIcons.swapArrows,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      amountText: amountText,
      amountColor: colors.text.primary,
      statusText: '',
      timestampText: '',
      onTap: receivesZec ? onReceivedLegTap : null,
    ),
  ];
}

String _swapActivityAmountText(
  SwapActivityRowItem item, {
  required bool includeSign,
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _swapActivityAmountPrivacyMaskLength,
    );
  }
  final amount = item.sellAmountText;
  if (amount.trim().isEmpty) return '--';
  if (!includeSign) return amount;
  return '-$amount';
}

String _swapActivityReceiveAmountText(
  SwapActivityRowItem item, {
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _swapActivityAmountPrivacyMaskLength,
    );
  }
  final amount = item.receiveEstimateText.trim();
  if (amount.isEmpty) return '--';
  if (amount.startsWith('+')) return amount;
  return '+$amount';
}

String _swapActivityStatusText(
  SwapIntentStatus status,
  _SwapActivityProgress? progress,
) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit =>
      progress?.label ?? 'In progress',
    SwapIntentStatus.incompleteDeposit => 'Incomplete deposit',
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown => progress?.label ?? 'In progress',
    SwapIntentStatus.complete => 'Completed',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Failed',
    SwapIntentStatus.failed => 'Failed',
  };
}

class _SwapActivityProgress {
  const _SwapActivityProgress({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  double get value => currentStep / totalSteps;

  String get label => '$currentStep/$totalSteps In progress';
}

bool _swapActivityFailed(SwapIntentStatus status) {
  return status == SwapIntentStatus.failed ||
      status == SwapIntentStatus.expired;
}

bool _swapActivityReturnsFunds(SwapActivityRowItem item) {
  return item.status == SwapIntentStatus.refunded;
}

/// Whether the swap row itself represents the outgoing ZEC deposit, so the
/// feed may suppress the duplicate standalone Sent row. Refunded and
/// timed-out rows render their amount unsigned (no outgoing sign), so the
/// standalone Sent transaction must stay visible there — otherwise the feed
/// would show a refund credit with no matching debit.
bool swapActivityRowAbsorbsDepositLeg(SwapActivityRowItem item) {
  return item.status != SwapIntentStatus.expired &&
      !_swapActivityReturnsFunds(item);
}

String _swapActivityTitle(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => 'Swapped',
    SwapIntentStatus.failed ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.refunded => 'Swap failed',
    _ => 'Swapping...',
  };
}

SwapAsset? _swapActivitySellAsset(SwapActivityRowItem item) {
  final direction = item.direction;
  final externalAsset = item.externalAsset;
  if (direction == null || externalAsset == null) return null;
  return direction.fromAsset(externalAsset);
}

SwapAsset? _swapActivityReceiveAsset(SwapActivityRowItem item) {
  final direction = item.direction;
  final externalAsset = item.externalAsset;
  if (direction == null || externalAsset == null) return null;
  return direction.toAsset(externalAsset);
}

String? _swapActivityAssetSubtitle(SwapAsset? asset) {
  if (asset == null) return null;
  if (asset.isNativeZec) return '${asset.symbol} ${asset.chainLabel}';
  return '${asset.symbol} on ${asset.chainLabel}';
}

_SwapActivityProgress? _swapActivityProgress(SwapActivityRowItem item) {
  const totalSteps = 4;
  final hasDepositTx = item.depositTxHash?.trim().isNotEmpty ?? false;
  final depositSent = hasDepositTx || item.depositClaimedAt != null;
  return switch (item.status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => _SwapActivityProgress(
      currentStep: depositSent ? 2 : 1,
      totalSteps: totalSteps,
    ),
    SwapIntentStatus.depositObserved => const _SwapActivityProgress(
      currentStep: 2,
      totalSteps: totalSteps,
    ),
    SwapIntentStatus.processing || SwapIntentStatus.providerStatusUnknown =>
      const _SwapActivityProgress(currentStep: 3, totalSteps: totalSteps),
    SwapIntentStatus.complete => const _SwapActivityProgress(
      currentStep: 4,
      totalSteps: totalSteps,
    ),
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => null,
  };
}
