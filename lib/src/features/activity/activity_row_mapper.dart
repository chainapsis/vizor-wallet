import 'package:flutter/widgets.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'models/activity_row_data.dart';

List<ActivityRowData> buildActivityRows({
  required BuildContext context,
  required SyncState sync,
  required Iterable<rust_sync.TransactionInfo> transactions,
  VoidCallback? onRetrySync,
}) {
  return [
    buildSyncActivityRow(
      context: context,
      sync: sync,
      onRetrySync: onRetrySync,
    ),
    ...transactions.map(
      (tx) => buildTransactionActivityRow(context: context, transaction: tx),
    ),
  ];
}

ActivityRowData buildSyncActivityRow({
  required BuildContext context,
  required SyncState sync,
  VoidCallback? onRetrySync,
}) {
  final colors = context.colors;

  if (sync.error != null) {
    return ActivityRowData(
      title: 'Wallet Synced',
      leadingIconName: AppIcons.sync,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      amountText: onRetrySync == null ? '--' : 'Retry',
      amountColor: colors.text.warning,
      statusText: 'Failed',
      statusIconName: AppIcons.skull,
      statusColor: colors.text.destructive,
      timestampText: formatActivityTimestamp(sync.lastSyncFailedAt),
      onTap: onRetrySync,
    );
  }

  if (sync.isSyncing) {
    final pct = (sync.percentage * 100).toStringAsFixed(0);
    return ActivityRowData(
      title: 'Wallet Synced',
      leadingIconName: AppIcons.sync,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      subtitle: sync.phase.isEmpty ? null : _capitalize(sync.phase),
      amountText: '$pct%',
      amountColor: colors.text.secondary,
      statusText: 'In progress',
      statusIconName: AppIcons.loader,
      statusColor: colors.text.secondary,
      timestampText: formatActivityTimestamp(sync.lastSyncStartedAt),
    );
  }

  return ActivityRowData(
    title: 'Wallet Synced',
    leadingIconName: AppIcons.sync,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    amountText: formatActivityZec(sync.totalBalance),
    amountColor: colors.text.accent,
    statusText: 'Completed',
    statusColor: colors.text.secondary,
    timestampText: formatActivityTimestamp(sync.lastSyncCompletedAt),
  );
}

ActivityRowData buildTransactionActivityRow({
  required BuildContext context,
  required rust_sync.TransactionInfo transaction,
}) {
  final colors = context.colors;
  final isPending =
      transaction.minedHeight == BigInt.zero && !transaction.expiredUnmined;
  final isFailed = transaction.expiredUnmined;
  final kind = transaction.txKind;
  final amount = transaction.displayAmount;
  final isReceived = kind == 'received';
  final isSent = kind == 'sent';
  final isShielded = kind == 'shielded';
  final signedAmount = isSent ? -amount : amount;
  final subtitle = isReceived || isSent
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
    ),
    amountIconName: isFailed && amount != BigInt.zero
        ? AppIcons.arrowBack
        : null,
    amountIconColor: isFailed ? colors.icon.regular : null,
    amountColor: isFailed
        ? colors.text.accent
        : isReceived
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
  );
}

String _transactionAmountText({
  required BigInt amount,
  required BigInt signedAmount,
  required bool isFailed,
  required bool isShielded,
  required String kind,
}) {
  if (amount == BigInt.zero) return '--';
  if (isFailed || isShielded || kind == 'internal') {
    return formatActivityZec(amount);
  }
  return formatSignedActivityZec(signedAmount);
}

String formatActivityZec(BigInt zatoshi) {
  final abs = zatoshi.abs();
  final whole = abs ~/ BigInt.from(100000000);
  final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
  final digits = whole == BigInt.zero && int.parse(frac) < 1000000
      ? frac
      : frac.substring(0, 2);
  return '$whole.$digits ZEC';
}

String formatSignedActivityZec(BigInt zatoshi) {
  final sign = zatoshi >= BigInt.zero ? '+' : '-';
  return '$sign${formatActivityZec(zatoshi)}';
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
    'received' => 'Received',
    'sent' => 'Sent',
    'shielded' => 'Shielded',
    'internal' => 'Internal',
    _ => 'Transaction',
  };
}

String _txIcon(String kind) {
  return switch (kind) {
    'received' => AppIcons.arrowDownCircle,
    'sent' => AppIcons.plane,
    'shielded' => AppIcons.shieldAsset,
    'internal' => AppIcons.sync,
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

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
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
