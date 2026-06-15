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
  bool dateOnlyTimestamp = false,
  VoidCallback? onTap,
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
    subtitle: _swapActivityAssetSubtitle(sellAsset) ?? item.providerLabel,
    amountText: _swapActivityAmountText(
      item,
      includeSign: !(returnsFunds || timedOut),
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName: returnsFunds ? AppIcons.arrowBack : null,
    amountIconColor: returnsFunds ? colors.icon.regular : null,
    amountColor: outgoingAmountColor(colors),
    amountSubtitle: timedOut
        ? 'Timeout'
        : returnsFunds
        ? 'Refunded'
        : null,
    amountSubtitleIconName: timedOut ? AppIcons.time : null,
    amountSubtitleIconColor: timedOut ? colors.text.secondary : null,
    statusText: _swapActivityStatusText(item.status, progress),
    statusIconName: failed
        ? AppIcons.skull
        : item.status == SwapIntentStatus.refunded
        ? AppIcons.arrowBack
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
    timestampText: formatActivityTimestamp(
      item.activityTimestamp,
      dateOnly: dateOnlyTimestamp,
    ),
    childRows: failed || returnsFunds || !_swapActivityShowsReceiveLeg(item)
        ? const []
        : _swapActivityChildRows(
            context: context,
            item: item,
            receiveAsset: receiveAsset,
            complete: complete,
            privacyModeEnabled: privacyModeEnabled,
            dateOnlyTimestamp: dateOnlyTimestamp,
          ),
    onTap: onTap,
  );
}

List<ActivityRowData> _swapActivityChildRows({
  required BuildContext context,
  required SwapActivityRowItem item,
  required SwapAsset? receiveAsset,
  required bool complete,
  required bool privacyModeEnabled,
  required bool dateOnlyTimestamp,
}) {
  final direction = item.direction;
  if (direction == null || receiveAsset == null) return const [];
  if (!complete && _swapActivityProgress(item) == null) {
    return const [];
  }

  final colors = context.colors;
  final active = !complete;
  return [
    ActivityRowData(
      title: _swapActivityChildTitle(
        direction: direction,
        receiveAsset: receiveAsset,
        complete: complete,
      ),
      leadingIconName: AppIcons.swapArrows,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      amountText: _swapActivityReceiveAmountText(
        item,
        privacyModeEnabled: privacyModeEnabled,
      ),
      amountColor: outgoingAmountColor(colors),
      statusText: active ? 'In progress' : 'Completed',
      statusIconName: active ? AppIcons.loader : null,
      statusColor: colors.text.secondary,
      timestampText: _swapActivityChildTimestamp(
        item,
        dateOnly: dateOnlyTimestamp,
      ),
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

String _swapActivityTitle(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => 'Swapped',
    SwapIntentStatus.failed || SwapIntentStatus.expired => 'Swap failed',
    SwapIntentStatus.refunded => 'Swap refunded',
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

String _swapActivityChildTitle({
  required SwapDirection direction,
  required SwapAsset receiveAsset,
  required bool complete,
}) {
  if (direction == SwapDirection.externalToZec) {
    return complete
        ? '${receiveAsset.symbol} Received'
        : 'Receiving ${receiveAsset.symbol} ...';
  }
  return complete
      ? '${receiveAsset.symbol} Deposited'
      : 'Depositing ${receiveAsset.symbol}...';
}

String _swapActivityChildTimestamp(
  SwapActivityRowItem item, {
  bool dateOnly = false,
}) {
  final timestamp =
      item.completedAt ?? item.lastStatusCheckedAt ?? item.updatedAt;
  if (timestamp == null) return '--';
  if (dateOnly) return formatActivityTimestamp(timestamp, dateOnly: true);
  return _relativeActivityTimestamp(timestamp) ??
      formatActivityTimestamp(timestamp);
}

String? _relativeActivityTimestamp(DateTime timestamp) {
  final elapsed = DateTime.now().difference(timestamp.toLocal());
  if (elapsed.isNegative) return null;
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  return null;
}

bool _swapActivityShowsReceiveLeg(SwapActivityRowItem item) {
  return switch (item.status) {
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.complete => true,
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => false,
  };
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
