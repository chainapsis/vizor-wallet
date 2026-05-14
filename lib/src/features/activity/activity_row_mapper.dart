import 'package:flutter/widgets.dart';

import '../../core/formatting/zec_amount.dart';
import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'models/activity_row_data.dart';

const _activityAmountPrivacyMaskLength = 3;

List<ActivityRowData> buildActivityRows({
  required BuildContext context,
  required Iterable<rust_sync.TransactionInfo> transactions,
  bool privacyModeEnabled = false,
  ValueChanged<rust_sync.TransactionInfo>? onTransactionTap,
}) {
  return [
    ...transactions.map(
      (tx) => buildTransactionActivityRow(
        context: context,
        transaction: tx,
        privacyModeEnabled: privacyModeEnabled,
        onTap: onTransactionTap == null ? null : () => onTransactionTap(tx),
      ),
    ),
  ];
}

ActivityRowData buildTransactionActivityRow({
  required BuildContext context,
  required rust_sync.TransactionInfo transaction,
  bool privacyModeEnabled = false,
  VoidCallback? onTap,
}) {
  final colors = context.colors;
  final isPending =
      transaction.minedHeight == BigInt.zero && !transaction.expiredUnmined;
  final isFailed = transaction.expiredUnmined;
  final kind = transaction.txKind;
  final amount = transaction.displayAmount;
  final isReceived = kind == 'received';
  final isReceiving = kind == 'receiving';
  final isSent = kind == 'sent';
  final isShielded = kind == 'shielded';
  final isInbound = isReceived || isReceiving;
  final signedAmount = isSent ? -amount : amount;
  final subtitle = isInbound || isSent
      ? _poolLabel(transaction.displayPool)
      : null;

  return ActivityRowData(
    title: _txTitle(kind),
    leadingIconName: _txIcon(kind),
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: subtitle,
    subtitleIconName: transaction.displayPool == 'shielded'
        ? AppIcons.shieldKeyholeOutline
        : null,
    amountText: _transactionAmountText(
      amount: amount,
      signedAmount: signedAmount,
      isFailed: isFailed,
      isShielded: isShielded,
      kind: kind,
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName: isFailed && amount != BigInt.zero
        ? AppIcons.arrowBack
        : null,
    amountIconColor: isFailed ? colors.icon.regular : null,
    amountColor: isFailed
        ? colors.text.accent
        : isInbound
        ? colors.text.brandCrimson
        : colors.text.accent,
    statusText: isFailed
        ? 'Failed'
        : isPending
        ? 'In progress'
        : 'Completed',
    statusIconName: isFailed
        ? AppIcons.skull
        : isPending
        ? AppIcons.loader
        : null,
    statusColor: isFailed ? colors.text.destructive : colors.text.secondary,
    timestampText: formatActivityTimestamp(_txTimestamp(transaction)),
    onTap: onTap,
  );
}

String _transactionAmountText({
  required BigInt amount,
  required BigInt signedAmount,
  required bool isFailed,
  required bool isShielded,
  required String kind,
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _activityAmountPrivacyMaskLength,
    );
  }
  if (amount == BigInt.zero) return '--';
  if (isFailed || isShielded) {
    return ZecAmount.fromZatoshi(amount).activity.toString();
  }
  return ZecAmount.fromZatoshi(signedAmount).signedActivity.toString();
}

String formatActivityTimestamp(DateTime? timestamp) {
  if (timestamp == null) return '--';
  final now = DateTime.now();
  final local = timestamp.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

  if (date == today) return 'Today, $time';
  if (date == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $time';
  }
  return '${_monthName(local.month)} ${local.day}, $time';
}

String _txTitle(String kind) {
  return switch (kind) {
    'receiving' => 'Receiving',
    'received' => 'Received',
    'sent' => 'Sent',
    'shielded' => 'Shielded',
    _ => 'Transaction',
  };
}

String _txIcon(String kind) {
  return switch (kind) {
    'receiving' => AppIcons.arrowDownCircle,
    'received' => AppIcons.arrowDownCircle,
    'sent' => AppIcons.plane,
    'shielded' => AppIcons.shieldKeyholeOutline,
    _ => AppIcons.history,
  };
}

String? _poolLabel(String pool) {
  return switch (pool) {
    'transparent' => 'Transparent',
    'shielded' => 'Shielded',
    'mixed' => 'Mixed',
    _ => null,
  };
}

DateTime? _txTimestamp(rust_sync.TransactionInfo tx) {
  final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}

String _monthName(int month) {
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month];
}
