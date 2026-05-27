import 'package:flutter/widgets.dart';

import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../swap/models/swap_prototype_models.dart';
import 'activity_row_mapper.dart';
import 'models/activity_row_data.dart';

const _swapActivityAmountPrivacyMaskLength = 3;

List<ActivityRowData> buildSwapActivityRows({
  required BuildContext context,
  required Iterable<SwapIntentRecord> records,
  bool privacyModeEnabled = false,
  ValueChanged<SwapIntentRecord>? onSwapTap,
}) {
  return [
    for (final record in records)
      buildSwapActivityRow(
        context: context,
        record: record,
        privacyModeEnabled: privacyModeEnabled,
        onTap: onSwapTap == null ? null : () => onSwapTap(record),
      ),
  ];
}

ActivityRowData buildSwapActivityRow({
  required BuildContext context,
  required SwapIntentRecord record,
  bool privacyModeEnabled = false,
  VoidCallback? onTap,
}) {
  final colors = context.colors;
  final failed = _swapActivityFailed(record.status);
  final timedOut = record.status == SwapIntentStatus.expired;
  final returnsFunds = _swapActivityReturnsFunds(record.status);
  final incompleteDeposit = record.status == SwapIntentStatus.incompleteDeposit;
  final complete = record.status == SwapIntentStatus.complete;
  final sellAsset = _swapActivitySellAsset(record);
  final receiveAsset = _swapActivityReceiveAsset(record);
  final progress = _swapActivityProgress(record);

  return ActivityRowData(
    title: _swapActivityTitle(record.status),
    leadingIconName: AppIcons.swapArrows,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    leadingProgressValue: complete ? null : progress?.value,
    subtitle: _swapActivityAssetSubtitle(sellAsset) ?? record.providerLabel,
    amountText: _swapActivityAmountText(
      record,
      includeSign: !(returnsFunds || timedOut),
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName: returnsFunds ? AppIcons.arrowBack : null,
    amountIconColor: returnsFunds ? colors.icon.regular : null,
    amountColor: colors.text.accent,
    amountSubtitle: timedOut
        ? 'Timeout'
        : returnsFunds
        ? 'Refunded'
        : null,
    amountSubtitleIconName: timedOut ? AppIcons.time : null,
    amountSubtitleIconColor: timedOut ? colors.text.secondary : null,
    statusText: _swapActivityStatusText(record.status, progress),
    statusIconName: failed
        ? AppIcons.skull
        : record.status == SwapIntentStatus.refunded
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
    timestampText: formatActivityTimestamp(record.activityTimestamp),
    childRows: failed || returnsFunds || !_swapActivityShowsReceiveLeg(record)
        ? const []
        : _swapActivityChildRows(
            context: context,
            record: record,
            receiveAsset: receiveAsset,
            complete: complete,
            privacyModeEnabled: privacyModeEnabled,
          ),
    onTap: onTap,
  );
}

List<ActivityRowData> _swapActivityChildRows({
  required BuildContext context,
  required SwapIntentRecord record,
  required SwapAsset? receiveAsset,
  required bool complete,
  required bool privacyModeEnabled,
}) {
  final direction = record.direction;
  if (direction == null || receiveAsset == null) return const [];
  if (!complete && _swapActivityProgress(record) == null) {
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
        record,
        privacyModeEnabled: privacyModeEnabled,
      ),
      amountColor: colors.text.accent,
      statusText: active ? 'In progress' : 'Completed',
      statusIconName: active ? AppIcons.loader : null,
      statusColor: colors.text.secondary,
      timestampText: _swapActivityChildTimestamp(record),
    ),
  ];
}

String _swapActivityAmountText(
  SwapIntentRecord record, {
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
  final amount = record.sellAmountText;
  if (amount.trim().isEmpty) return '--';
  if (!includeSign) return amount;
  return '-$amount';
}

String _swapActivityReceiveAmountText(
  SwapIntentRecord record, {
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _swapActivityAmountPrivacyMaskLength,
    );
  }
  final amount = record.receiveEstimateText.trim();
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

bool _swapActivityReturnsFunds(SwapIntentStatus status) {
  return status == SwapIntentStatus.failed ||
      status == SwapIntentStatus.refunded;
}

String _swapActivityTitle(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => 'Swapped',
    SwapIntentStatus.failed || SwapIntentStatus.expired => 'Swap failed',
    SwapIntentStatus.refunded => 'Swap refunded',
    _ => 'Swapping...',
  };
}

SwapAsset? _swapActivitySellAsset(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return null;
  return direction.fromAsset(externalAsset);
}

SwapAsset? _swapActivityReceiveAsset(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
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

String _swapActivityChildTimestamp(SwapIntentRecord record) {
  final timestamp =
      record.completedAt ?? record.lastStatusCheckedAt ?? record.updatedAt;
  if (timestamp == null) return '--';
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

bool _swapActivityShowsReceiveLeg(SwapIntentRecord record) {
  return switch (record.status) {
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

_SwapActivityProgress? _swapActivityProgress(SwapIntentRecord record) {
  const totalSteps = 4;
  final hasDepositTx = record.depositTxHash?.trim().isNotEmpty ?? false;
  return switch (record.status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => _SwapActivityProgress(
      currentStep: hasDepositTx ? 2 : 1,
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
