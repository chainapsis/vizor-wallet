import 'package:flutter/widgets.dart';

import '../../core/formatting/zec_amount.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'activity_amount_text.dart';
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
  final isMigration = kind == 'migration';
  final isInbound = isReceived || isReceiving;
  final signedAmount = isSent ? -amount : amount;
  final subtitle = isMigration
      ? 'Orchard to Ironwood'
      : isInbound || isSent
      ? _poolLabel(transaction.displayPool)
      : null;

  // Unconfirmed sends/receives render as in-flight rows: a pulsing loader
  // in the leading slot and a progressive title, per the Content Line
  // pending variant in the design.
  final isInFlight = isPending && (isInbound || isSent);

  return ActivityRowData(
    stableId: 'tx:${transaction.txidHex}:${_stableTransactionRole(kind)}',
    title: isFailed && isSent
        ? 'Send failed'
        : isInFlight
        ? _pendingTxTitle(isSent ? 'Sending' : 'Receiving')
        : _txTitle(kind),
    leadingIconName: _txIcon(kind, isPending: isPending),
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: subtitle,
    subtitleIconName: _poolIcon(transaction.displayPool),
    amountText: activityAmountTextForFormFactor(
      _transactionAmountText(
        amount: amount,
        signedAmount: signedAmount,
        isFailed: isFailed,
        isShielded: isShielded,
        isMigration: isMigration,
        kind: kind,
        privacyModeEnabled: privacyModeEnabled,
      ),
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

String _stableTransactionRole(String kind) {
  return switch (kind) {
    'receiving' => 'received',
    _ => kind,
  };
}

String _transactionAmountText({
  required BigInt amount,
  required BigInt signedAmount,
  required bool isFailed,
  required bool isShielded,
  required bool isMigration,
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
  if (isFailed || isShielded || isMigration) {
    return ZecAmount.fromZatoshi(amount).activity.toString();
  }
  return ZecAmount.fromZatoshi(signedAmount).signedActivity.toString();
}

/// Desktop keeps the older relative "Today, 13:40" form. Mobile activity
/// sections use absolute "May 29, 13:40" stamps, or date-only section labels.
String formatActivityTimestamp(DateTime? timestamp, {bool dateOnly = false}) {
  if (timestamp == null) return '--';
  final local = timestamp.toLocal();
  final date = '${_monthName(local.month)} ${local.day}';
  if (dateOnly) return date;
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (kAppFormFactor == AppFormFactor.mobile) return '$date, $time';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final localDate = DateTime(local.year, local.month, local.day);
  if (localDate == today) return 'Today, $time';
  if (localDate == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $time';
  }
  return '$date, $time';
}

String _pendingTxTitle(String verb) =>
    kAppFormFactor == AppFormFactor.mobile ? '$verb...' : '$verb ...';

String _txTitle(String kind) {
  return switch (kind) {
    'receiving' => 'Receiving',
    'received' => 'Received',
    'sent' => 'Sent',
    'shielded' => 'Shielded',
    'migration' => 'Migration',
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
    'migration' => AppIcons.renew,
    _ => AppIcons.history,
  };
}

String? _poolLabel(String pool) {
  return switch (pool) {
    'transparent' => 'Transparent',
    'shielded' => 'Shielded',
    'ironwood' => 'Ironwood',
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
