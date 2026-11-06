import 'package:flutter/widgets.dart';

import '../../core/formatting/date_format.dart';
import '../../core/formatting/zec_amount.dart';
import '../../core/l10n/l10n.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/pending_activity_evidence_provider.dart'
    show ActivityEta;
import '../../rust/api/sync.dart' as rust_sync;
import 'activity_amount_text.dart';
import 'gift_card_activity_index.dart';
import 'models/activity_row_data.dart';
import 'transaction_completeness.dart';

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
  GiftCardActivityKind? giftCardKind,
  BigInt? giftCardAmountZatoshi,
  int? giftCardBatchCount,
  bool giftCardClaimInFlight = false,
  String? giftCardStableId,
  DateTime? giftCardActivityTimestamp,
  String? giftCardDisplayPool,
  ActivityEta? pendingEta,
  String? pendingFallbackLabel,
  bool showPendingEstimate = true,
  bool privacyModeEnabled = false,
  bool privateQueriesEnabled = false,
  bool dateOnlyTimestamp = false,
  VoidCallback? onTap,
}) {
  final colors = context.colors;
  final l10n = context.l10n;
  // A visible expired leg does not fail a multi-leg claim still being received.
  final isFailed = transaction.expiredUnmined && !giftCardClaimInFlight;
  final isPending =
      !isFailed &&
      (transaction.minedHeight == BigInt.zero || giftCardClaimInFlight);
  final kind = transaction.txKind;
  final amount = giftCardAmountZatoshi ?? transaction.displayAmount;
  final isReceived = kind == 'received';
  final isReceiving = kind == 'receiving';
  final isSent = kind == 'sent';
  final isShielded = kind == 'shielded';
  final isMigration = kind == 'migration';
  final isInbound = isReceived || isReceiving;
  final isPayment = isInbound || isSent;
  final displayPool = giftCardKind == null
      ? transactionActivityPool(transaction)
      : giftCardDisplayPool ?? transactionActivityPool(transaction);
  final signedAmount = isSent ? -amount : amount;
  // A balance movement is shown neutrally, without claiming a payment or
  // a destination pool, even when its exact fee is known.
  final isNetChange =
      giftCardKind == null &&
      giftCardAmountZatoshi == null &&
      transactionFeePresentation(transaction) !=
          TransactionFeePresentation.separate;
  final replacesPool =
      showPendingEstimate && isPending && (isInbound || isSent || isShielded);
  final subtitle = replacesPool
      ? pendingEta?.label(l10n) ??
            pendingFallbackLabel ??
            l10n.commonCheckingStatus
      : isMigration
      ? 'Orchard → Ironwood' // l10n-ignore: product names only
      : isNetChange
      ? null
      : isInbound || isSent
      ? _poolLabel(
          l10n,
          normalizeActivityPool(displayPool),
          ordinary: isPayment,
        )
      : null;

  // Unconfirmed transactions render as in-flight rows: a pulsing loader
  // in the leading slot and a progressive title, per the Content Line
  // pending variant in the design.
  final isInFlight =
      isPending && (isInbound || isSent || isMigration || isShielded);

  return ActivityRowData(
    stableId: giftCardStableId ?? activityStableTransactionId(transaction),
    title: giftCardKind != null
        ? giftCardActivityTitle(
            l10n,
            giftCardKind,
            isInFlight: isInFlight,
            isFailed: isFailed,
            batchCount: giftCardBatchCount,
          )
        : isFailed && (isSent || isMigration)
        ? isMigration
              ? l10n.activityTitleMigrationFailed
              : l10n.commonSendFailed
        : isInFlight
        ? _pendingTxTitle(
            isMigration
                ? l10n.activityTitleMigratingVerb
                : isSent
                ? l10n.activityTitleSendingVerb
                : isShielded
                ? l10n.activityTitleShieldingVerb
                : l10n.activityTitleReceivingVerb,
          )
        : isNetChange
        ? l10n.activityReceiptNetChange
        : _txTitle(l10n, kind),
    leadingIconName: giftCardKind != null && !isInFlight
        ? AppIcons.giftCard
        : _txIcon(kind, isPending: isPending),
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: subtitle,
    subtitleIconName: replacesPool
        ? (pendingEta != null ? AppIcons.time : null)
        : isNetChange
        ? null
        : _poolIcon(normalizeActivityPool(displayPool), ordinary: isPayment),
    amountText: activityAmountTextForFormFactor(
      _transactionAmountText(
        amount: amount,
        signedAmount: signedAmount,
        isFailed: isFailed,
        isUnsignedAmount: isShielded || isMigration,
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
    amountSubtitle: isFailed && amount != BigInt.zero
        ? l10n.commonRefunded
        : privateQueriesEnabled &&
              transactionActivitySummaryIncomplete(transaction)
        ? l10n.activityReceiptDetailsIncomplete
        : null,
    statusText: isFailed
        ? l10n.commonFailed
        : isPending
        ? l10n.commonInProgress
        : l10n.commonCompleted,
    statusIsRoutine: !isFailed,
    statusIconName: isFailed
        ? AppIcons.skull
        : isPending
        ? AppIcons.loader
        : null,
    statusColor: isFailed ? colors.text.destructive : colors.text.secondary,
    timestampText: formatActivityTimestamp(
      l10n,
      giftCardActivityTimestamp ?? _txTimestamp(transaction),
      dateOnly: dateOnlyTimestamp,
    ),
    onTap: onTap,
  );
}

/// Shared by the activity row and the transaction receipt so a Gift Card
/// keeps one title across both surfaces.
String giftCardActivityTitle(
  AppLocalizations l10n,
  GiftCardActivityKind kind, {
  required bool isInFlight,
  required bool isFailed,
  int? batchCount,
}) {
  if (kind == GiftCardActivityKind.created &&
      batchCount != null &&
      batchCount > 1) {
    if (isFailed) return l10n.activityGiftGroupFailed;
    if (isInFlight) {
      return _pendingTxTitle(l10n.activityGiftCreatingMany(batchCount));
    }
    return l10n.activityGiftCreatedMany(batchCount);
  }
  if (isFailed) {
    return switch (kind) {
      GiftCardActivityKind.created => l10n.activityGiftCreationFailed,
      GiftCardActivityKind.redeemed => l10n.activityGiftRedemptionFailed,
    };
  }
  if (isInFlight) {
    return _pendingTxTitle(switch (kind) {
      GiftCardActivityKind.created => l10n.activityGiftCreating,
      GiftCardActivityKind.redeemed => l10n.activityGiftRedeeming,
    });
  }
  return switch (kind) {
    GiftCardActivityKind.created => l10n.activityGiftCreated,
    GiftCardActivityKind.redeemed => l10n.activityGiftRedeemed,
  };
}

/// Shared by the activity row and the transaction receipts. Memo-only
/// payments carry zero value, so a zero send or receipt shows `0 ZEC`; other
/// kinds keep `--` because their zero means the amount is unknown.
bool transactionShowsZeroAmount(String kind) =>
    kind == 'sent' || kind == 'received' || kind == 'receiving';

/// Pool labels for sends/receipts, including Gift Cards. Migration and
/// sender-source labels retain their own semantics.
String transactionActivityPool(rust_sync.TransactionInfo transaction) {
  final pool = transaction.activityPool ?? transaction.displayPool;
  return normalizeActivityPool(pool);
}

String normalizeActivityPool(String pool) =>
    pool == 'ironwood' ? 'shielded' : pool;

String activityStableTransactionId(rust_sync.TransactionInfo transaction) =>
    'tx:${transaction.txidHex}:${_stableTransactionRole(transaction.txKind)}';

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
  required bool isUnsignedAmount,
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
  if (amount == BigInt.zero) {
    return transactionShowsZeroAmount(kind)
        ? ZecAmount.fromZatoshi(amount).activity.toString()
        : '--';
  }
  if (isFailed || isUnsignedAmount) {
    return ZecAmount.fromZatoshi(amount).activity.toString();
  }
  return ZecAmount.fromZatoshi(signedAmount).signedActivity.toString();
}

/// Desktop keeps the older relative "Today, 13:40" form. Mobile activity
/// sections use absolute "May 29, 13:40" stamps, or date-only section labels.
String formatActivityTimestamp(
  AppLocalizations l10n,
  DateTime? timestamp, {
  bool dateOnly = false,
}) {
  if (timestamp == null) return '--';
  final local = timestamp.toLocal();
  final date = formatMonthDay(local, l10n.localeName);
  if (dateOnly) return date;
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (kAppFormFactor == AppFormFactor.mobile) return '$date, $time';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final localDate = DateTime(local.year, local.month, local.day);
  if (localDate == today) return l10n.activityRowToday(time);
  if (localDate == today.subtract(const Duration(days: 1))) {
    return l10n.activityRowYesterday(time);
  }
  return '$date, $time';
}

String _pendingTxTitle(String verb) =>
    kAppFormFactor == AppFormFactor.mobile ? '$verb...' : '$verb ...';

String _txTitle(AppLocalizations l10n, String kind) {
  return switch (kind) {
    'receiving' => l10n.activityTitleReceivingVerb,
    'received' => l10n.commonReceived,
    'sent' => l10n.activityTitleSent,
    'shielded' => l10n.activityTitleShielded,
    'migration' => l10n.activityTitleMigrated,
    _ => l10n.activityTitleTransaction,
  };
}

String _txIcon(String kind, {required bool isPending}) {
  if (isPending) {
    return switch (kind) {
      'receiving' ||
      'received' ||
      'sent' ||
      'migration' ||
      'shielded' => AppIcons.loader,
      _ => AppIcons.history,
    };
  }
  return switch (kind) {
    'receiving' => AppIcons.arrowDownCircle,
    'received' => AppIcons.arrowDownCircle,
    'sent' => AppIcons.plane,
    'shielded' => AppIcons.shieldKeyholeOutline,
    'migration' => AppIcons.migrationFast,
    _ => AppIcons.history,
  };
}

String? _poolLabel(
  AppLocalizations l10n,
  String pool, {
  bool ordinary = false,
}) {
  return switch (pool) {
    'transparent' => l10n.poolTransparent,
    'shielded' => l10n.poolShielded,
    'orchard' when ordinary => 'Orchard', // l10n-ignore: product name
    'sapling' when ordinary => 'Sapling', // l10n-ignore: product name
    'ironwood' => 'Ironwood', // l10n-ignore: product name
    'mixed' => l10n.activityPoolMixed,
    _ => null,
  };
}

String? _poolIcon(String pool, {bool ordinary = false}) {
  return switch (pool) {
    'transparent' => AppIcons.transparentBalance,
    'shielded' => AppIcons.shieldKeyholeOutline,
    'orchard' || 'sapling' when ordinary => AppIcons.shieldKeyholeOutline,
    'ironwood' => AppIcons.shieldKeyholeOutline,
    _ => null,
  };
}

DateTime? _txTimestamp(rust_sync.TransactionInfo tx) {
  final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}
