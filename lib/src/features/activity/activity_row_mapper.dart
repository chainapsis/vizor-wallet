import 'package:flutter/widgets.dart';

import '../../core/formatting/zec_amount.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'models/activity_row_data.dart';

const _activityAmountPrivacyMaskLength = 3;

/// Color for the "outgoing"/neutral amount line (sent, swap). Mobile
/// matches the transaction title (`text.accent`) so the amount reads as
/// heavy as the type; desktop keeps the lighter `text.primary`. Inbound
/// (green) and failed amounts keep their own semantic colors.
Color outgoingAmountColor(AppColors colors) =>
    kAppFormFactor == AppFormFactor.mobile
    ? colors.text.accent
    : colors.text.primary;

ActivityRowData buildTransactionActivityRow({
  required BuildContext context,
  required rust_sync.TransactionInfo transaction,
  bool privacyModeEnabled = false,
  bool dateOnlyTimestamp = false,
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
    title: isFailed && isSent
        ? 'Send failed'
        : _txTitle(kind, isPending: isPending),
    leadingIconName: _txIcon(kind, isPending: isPending),
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: subtitle,
    subtitleIconName: _poolIcon(transaction.displayPool),
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
        ? colors.text.positiveStrong
        : outgoingAmountColor(colors),
    amountSubtitle: isFailed && amount != BigInt.zero ? 'Refunded' : null,
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
    timestampText: formatActivityTimestamp(
      _txTimestamp(transaction),
      dateOnly: dateOnlyTimestamp,
    ),
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

/// Absolute `May 29, 13:40`-style stamp — the Figma activity rows use
/// the absolute form even for today's transactions.
String formatActivityTimestamp(DateTime? timestamp, {bool dateOnly = false}) {
  if (timestamp == null) return '--';
  final local = timestamp.toLocal();
  final date = '${_monthName(local.month)} ${local.day}';
  if (dateOnly) return date;
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date, $time';
}

String _txTitle(String kind, {required bool isPending}) {
  if (isPending) {
    return switch (kind) {
      'receiving' || 'received' => 'Receiving...',
      'sent' => 'Sending...',
      _ => 'Transaction',
    };
  }
  return switch (kind) {
    'receiving' => 'Receiving',
    'received' => 'Received',
    'sent' => 'Sent',
    'shielded' => 'Shielded',
    _ => 'Transaction',
  };
}

String _txIcon(String kind, {required bool isPending}) {
  if (isPending) {
    return switch (kind) {
      'receiving' || 'received' || 'sent' => AppIcons.loader,
      _ => AppIcons.history,
    };
  }
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

String? _poolIcon(String pool) {
  return switch (pool) {
    'transparent' => AppIcons.transparentBalance,
    'shielded' => AppIcons.shieldKeyholeOutline,
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
