import 'package:flutter/widgets.dart';

import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../swap/models/swap_models.dart';
import 'activity_amount_text.dart';
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
    this.hasConfirmedDepositEvidence = false,
    this.depositedAmountText,
    this.refundedAmountText,
    this.payMode = false,
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
      depositWalletTxidHex:
          swapChainTxidToWalletTxidHex(record.depositTxHash) ??
          (record.direction == SwapDirection.zecToExternal
              ? swapChainTxidToWalletTxidHex(record.originChainTxHash)
              : null),
      hasConfirmedDepositEvidence:
          swapHasConfirmedDepositEvidence(
            originChainTxHash: record.originChainTxHash,
            depositTxHash: record.depositTxHash,
            broadcastStatus: record.broadcastStatus,
          ) ||
          _isPositiveSwapAmount(record.providerRefundInfo?.depositedAmountText),
      depositedAmountText: record.providerRefundInfo?.depositedAmountText,
      refundedAmountText: record.providerRefundInfo?.refundedAmountText,
      payMode: record.payMode,
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

  /// Whether the deposit is known to have reached (or potentially reached)
  /// the network. Kept separate from [depositWalletTxidHex]: a locally-created
  /// pending broadcast has a txid without confirmed evidence, while a provider
  /// may report an amount without returning a matchable txid.
  final bool hasConfirmedDepositEvidence;

  /// Provider-reported amount actually detected at the deposit address.
  final String? depositedAmountText;

  /// Provider-reported amount actually returned to the source wallet.
  final String? refundedAmountText;

  final bool payMode;
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
  final payMode = item.payMode && item.direction == SwapDirection.zecToExternal;

  return ActivityRowData(
    stableId: 'swap:${item.intentId}',
    title: payMode
        ? _payActivityTitle(item.status)
        : _swapActivityTitle(item.status),
    leadingIconName: payMode ? AppIcons.coins : AppIcons.swapArrows,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    leadingProgressValue: complete ? null : progress?.value,
    subtitle: payMode
        ? _payActivitySubtitle(receiveAsset)
        : returnsFunds
        ? '${sellAsset?.symbol ?? 'ZEC'} Refunded'
        : _swapActivityAssetSubtitle(sellAsset) ?? item.providerLabel,
    amountText: activityAmountTextForFormFactor(
      payMode
          ? _payActivityAmountText(item, privacyModeEnabled: privacyModeEnabled)
          : _swapActivityAmountText(
              item,
              includeSign: !(returnsFunds || timedOut),
              privacyModeEnabled: privacyModeEnabled,
            ),
    ),
    amountIconName: returnsFunds ? AppIcons.uturnUp : null,
    amountIconColor: returnsFunds ? colors.icon.regular : null,
    amountColor: outgoingAmountColor(colors),
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
    timestampText: formatActivityTimestamp(
      item.activityTimestamp,
      dateOnly: dateOnlyTimestamp,
    ),
    childRows: _swapActivityChildRows(
      context: context,
      item: item,
      receiveAsset: receiveAsset,
      privacyModeEnabled: privacyModeEnabled,
      receivedAmountText: receivedAmountText,
      onReceivedLegTap: onReceivedLegTap,
      dateOnlyTimestamp: dateOnlyTimestamp,
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
  required bool dateOnlyTimestamp,
}) {
  final direction = item.direction;
  if (direction == null || receiveAsset == null) return const [];
  if (item.payMode && direction == SwapDirection.zecToExternal) {
    return const [];
  }
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
      stableId:
          'swap:${item.intentId}:${receivesZec ? 'received' : 'deposited'}',
      title: receivesZec
          ? 'Received ${receiveAsset.symbol}'
          : 'Deposited ${receiveAsset.symbol}',
      leadingIconName: AppIcons.swapArrows,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      amountText: activityAmountTextForFormFactor(amountText),
      amountColor: outgoingAmountColor(colors),
      statusText: '',
      timestampText: dateOnlyTimestamp
          ? _swapActivityChildTimestamp(item, dateOnly: true)
          : '',
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

String _payActivityAmountText(
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
  final depositedAmount = item.depositedAmountText?.trim();
  final hasProviderDepositAmount = _isPositiveSwapAmount(depositedAmount);
  final showsDepositDebit =
      _payActivityRepresentsDepositDebit(item) &&
      (item.status == SwapIntentStatus.failed ||
          item.status == SwapIntentStatus.incompleteDeposit);
  final showsRefundAmount = item.status == SwapIntentStatus.refunded;
  final refundedAmount = item.refundedAmountText?.trim();
  final amount = showsDepositDebit
      ? (depositedAmount?.isNotEmpty ?? false)
            ? depositedAmount!
            : item.sellAmountText.trim()
      : showsRefundAmount
      ? (refundedAmount?.isNotEmpty ?? false)
            ? refundedAmount!
            : item.sellAmountText.trim()
      : hasProviderDepositAmount &&
            (item.status == SwapIntentStatus.failed ||
                item.status == SwapIntentStatus.incompleteDeposit)
      ? depositedAmount!
      : item.receiveEstimateText.trim();
  if (showsDepositDebit && amount.isNotEmpty && !amount.startsWith('-')) {
    return '-$amount';
  }
  return amount.isEmpty ? '--' : amount;
}

bool _payActivityRepresentsDepositDebit(SwapActivityRowItem item) {
  return item.hasConfirmedDepositEvidence &&
      (item.depositWalletTxidHex?.trim().isNotEmpty ?? false);
}

bool _isPositiveSwapAmount(String? amountText) {
  if (amountText == null || amountText.isEmpty) return false;
  final numericText = amountText
      .split(RegExp(r'\s+'))
      .first
      .replaceAll(',', '');
  final amount = double.tryParse(numericText);
  return amount != null && amount.isFinite && amount > 0;
}

String _payActivityTitle(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => 'Paid',
    SwapIntentStatus.failed ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.refunded => 'Payment failed',
    _ => 'Payment in progress',
  };
}

String _payActivitySubtitle(SwapAsset? receiveAsset) {
  final network = receiveAsset?.chainLabel;
  if (network == null || network.isEmpty) {
    return 'from shielded ZEC';
  }
  return 'from shielded ZEC · $network';
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

/// Whether the swap row represents the outgoing ZEC deposit, so the feed may
/// suppress the duplicate standalone Sent row. Pay rows additionally require
/// confirmed evidence and a matchable txid; provider amount-only recovery must
/// leave the standalone Sent row as the sole signed debit.
bool swapActivityRowAbsorbsDepositLeg(SwapActivityRowItem item) {
  if (item.status == SwapIntentStatus.expired ||
      _swapActivityReturnsFunds(item)) {
    return false;
  }
  final payMode = item.payMode && item.direction == SwapDirection.zecToExternal;
  return !payMode || _payActivityRepresentsDepositDebit(item);
}

/// Swap intents matched against the on-chain transaction list: which
/// standalone tx rows duplicate a swap row, and the matched ZEC payout per
/// intent. Home and the Activity screen share this so both feeds suppress
/// the same rows; Home only consumes the suppression set (its compact rows
/// render no children).
class SwapActivityLegAbsorption {
  const SwapActivityLegAbsorption({
    required this.absorbedTxidHexes,
    required this.receiveTxByIntent,
  });

  static const empty = SwapActivityLegAbsorption(
    absorbedTxidHexes: <String>{},
    receiveTxByIntent: <String, rust_sync.TransactionInfo>{},
  );

  /// Wallet-order txid hexes whose standalone rows are duplicates of a swap
  /// row (the matched payout, or our own ZEC deposit broadcast).
  final Set<String> absorbedTxidHexes;

  /// Matched ZEC payout per intent id, feeding the tappable 'Received ZEC'
  /// sub row on the Activity screen.
  final Map<String, rust_sync.TransactionInfo> receiveTxByIntent;

  bool absorbs(rust_sync.TransactionInfo tx) =>
      absorbedTxidHexes.contains(tx.txidHex.toLowerCase());
}

SwapActivityLegAbsorption matchSwapActivityLegAbsorption({
  required List<SwapActivityRowItem> swapItems,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  if (swapItems.isEmpty || transactions.isEmpty) {
    return SwapActivityLegAbsorption.empty;
  }
  final receiveTxByIntent = <String, rust_sync.TransactionInfo>{};
  final absorbedTxidHexes = <String>{};
  for (final item in swapItems) {
    final receiveHex = item.receiveWalletTxidHex;
    // Only suppress the deposit leg while the swap row carries the signed
    // outgoing amount; refunded/timed-out rows render unsigned, so their
    // standalone Sent row stays visible.
    final depositHex = swapActivityRowAbsorbsDepositLeg(item)
        ? item.depositWalletTxidHex
        : null;
    if (receiveHex == null && depositHex == null) continue;
    for (final tx in transactions) {
      final txHex = tx.txidHex.toLowerCase();
      if (receiveHex != null && txHex == receiveHex) {
        receiveTxByIntent[item.intentId] = tx;
        absorbedTxidHexes.add(txHex);
      } else if (depositHex != null && txHex == depositHex) {
        absorbedTxidHexes.add(txHex);
      }
    }
  }
  return SwapActivityLegAbsorption(
    absorbedTxidHexes: absorbedTxidHexes,
    receiveTxByIntent: receiveTxByIntent,
  );
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
