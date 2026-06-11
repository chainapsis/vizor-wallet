import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/send_review_layout.dart';

/// Display status of a received transaction on the redesigned receipt.
///
/// Mirrors the send status phases ([inProgress] follows the send-in-progress
/// spec's loader row; [completed] is the Figma `received` frame). [failed]
/// covers an inbound transaction that expired unmined — no dedicated Figma
/// frame exists, so it extrapolates the send-failed status row without the
/// send-specific refund copy or dark-card treatment.
enum ReceivedReceiptStatus { inProgress, completed, failed }

/// Static content of the redesigned received-transaction receipt: status
/// title, optional From row joined to the Amount Review Info row by an
/// arrow-down connector, and the Review Wrap detail card.
///
/// Reached from the activity feed when a received transaction is tapped.
/// This widget is presentation-only — all values arrive as pre-formatted
/// display strings and the interactive affordances surface as callbacks;
/// the hosting screen (`ActivityTransactionStatusScreen` today) owns data
/// loading, formatting, and navigation.
class ReceivedReceiptView extends StatelessWidget {
  const ReceivedReceiptView({
    required this.amountText,
    required this.timestampText,
    required this.txIdText,
    this.status = ReceivedReceiptStatus.completed,
    this.fromRecipient,
    this.unknownFromPool,
    this.isShieldedSource = false,
    this.feeText,
    this.receivingAddress,
    this.isShieldedReceivingAddress = false,
    this.memoText,
    this.memoExpanded = false,
    this.onShowFullAddress,
    this.onExpandMemo,
    this.onTxIdPressed,
    this.onFeeHelpPressed,
    super.key,
  });

  /// Pre-formatted receive amount ("120 ZEC").
  final String amountText;

  /// Pre-formatted timestamp ("25 May, 13:30").
  final String timestampText;

  /// Display form of the transaction id (the row truncates when long).
  final String txIdText;

  /// Drives the title and the Status row (loader / check circle / cancel).
  final ReceivedReceiptStatus status;

  /// Sender display data. The From row (and its arrow connector) is omitted
  /// when null unless [unknownFromPool] is present.
  final SendReviewRecipient? fromRecipient;

  /// Sender pool when the exact source address is unavailable.
  final String? unknownFromPool;

  /// Pool badge under the From row: shielded (shield keyhole + "Shielded")
  /// vs transparent (transparent-balance glyph + "Transparent").
  final bool isShieldedSource;

  /// Pre-formatted network fee ("0.012 ZEC"); the Tx fee row and its
  /// divider are omitted when null — inbound transactions where the sender
  /// paid the fee have no fee to show.
  final String? feeText;

  /// Full address the funds arrived on, shown as the Amount row sub-line;
  /// the sub-line is omitted when null.
  final String? receivingAddress;

  /// Pool glyph in front of [receivingAddress] — defaults to the
  /// transparent-balance glyph shown in the Figma mock.
  final bool isShieldedReceivingAddress;

  /// Memo display text; the Message row is omitted when null or empty.
  final String? memoText;

  /// Inline Message row expansion state.
  final bool memoExpanded;

  /// "Show full address" ghost action on the From row.
  final VoidCallback? onShowFullAddress;

  /// Message row expand/collapse affordance.
  final VoidCallback? onExpandMemo;

  /// Tx ID row explorer-link affordance.
  final VoidCallback? onTxIdPressed;

  /// Tx fee row help affordance.
  final VoidCallback? onFeeHelpPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final memo = memoText?.trim();
    final fromRecipient = this.fromRecipient;
    final unknownFromPool = this.unknownFromPool?.trim().toLowerCase();
    final hasUnknownFrom =
        fromRecipient == null &&
        unknownFromPool != null &&
        unknownFromPool.isNotEmpty;
    final title = switch (status) {
      ReceivedReceiptStatus.inProgress => 'Receive in progress...',
      ReceivedReceiptStatus.completed => 'Received successfully',
      ReceivedReceiptStatus.failed => 'Receive failed',
    };
    final (statusValue, statusIconName, statusColor) = switch (status) {
      ReceivedReceiptStatus.inProgress => (
        'In progress',
        AppIcons.loader,
        colors.text.secondary,
      ),
      ReceivedReceiptStatus.completed => (
        'Completed',
        AppIcons.checkCircle,
        colors.text.positiveStrong,
      ),
      ReceivedReceiptStatus.failed => (
        'Failed',
        AppIcons.cancel,
        colors.text.destructive,
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fromRecipient != null || hasUnknownFrom) ...[
                if (fromRecipient != null)
                  _fromRow(context, fromRecipient)
                else
                  _unknownFromRow(context, unknownFromPool!),
                const _ReceivedArrowSeparator(),
              ],
              ReviewInfoRow(
                label: 'Amount',
                value: amountText,
                leading: ClipOval(
                  child: Image.asset(
                    'assets/icons/network_zec.png',
                    width: AppAssetSize.size,
                    height: AppAssetSize.size,
                    fit: BoxFit.cover,
                  ),
                ),
                bottomLeftIconName: receivingAddress != null
                    ? _poolIconName(isShieldedReceivingAddress)
                    : null,
                bottomLeftIconColor: receivingAddress != null
                    ? _poolIconColor(context, isShieldedReceivingAddress)
                    : null,
                bottomLeftText: receivingAddress != null
                    ? truncatedAddress(receivingAddress!)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        ReviewWrapCard(
          children: [
            ReviewListRow(
              label: 'Status',
              value: statusValue,
              valueColor: statusColor,
              leadingIconName: statusIconName,
            ),
            // Detail rows form one Figma "List" group: 16px card gap between
            // groups, no extra gap between the 32px rows inside the group.
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (memo != null && memo.isNotEmpty)
                  ReviewMemoRows(
                    memoText: memo,
                    expanded: memoExpanded,
                    onToggle: onExpandMemo,
                  ),
                ReviewListRow(label: 'Timestamp', value: timestampText),
                ReviewListRow(
                  label: 'Tx ID',
                  value: txIdText,
                  trailingIconName: AppIcons.arrowTopRight,
                  onPressed: onTxIdPressed,
                ),
              ],
            ),
            if (feeText != null) ...[
              const ReviewWrapDivider(),
              ReviewListRow(
                label: 'Tx fee',
                value: feeText!,
                trailingIconName: AppIcons.help,
                trailingIconColor: colors.text.secondary,
                trailingIconTooltip: kTxFeeHelpTooltip,
                onPressed: onFeeHelpPressed,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _poolIconName(bool shielded) =>
      shielded ? AppIcons.shieldKeyhole : AppIcons.transparentBalance;

  static Color? _poolIconColor(BuildContext context, bool shielded) =>
      shielded ? context.colors.text.brandCrimson : null;

  Widget _fromRow(BuildContext context, SendReviewRecipient recipient) {
    return switch (recipient) {
      SendReviewAddressRecipient(:final address) => ReviewInfoRow(
        label: 'From',
        value: truncatedAddress(address),
        leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
        bottomLeftIconName: _poolIconName(isShieldedSource),
        bottomLeftIconColor: _poolIconColor(context, isShieldedSource),
        bottomLeftText: isShieldedSource ? 'Shielded' : 'Transparent',
        trailingActionLabel: 'Show full address',
        onTrailingAction: onShowFullAddress,
      ),
      SendReviewContactRecipient(
        :final address,
        :final name,
        :final profilePictureId,
      ) =>
        ReviewInfoRow(
          label: 'From',
          value: name,
          leading: AppProfilePicture(
            profilePictureId: profilePictureId,
            size: AppProfilePictureSize.large,
          ),
          bottomLeftText: truncatedAddress(address),
          trailingActionLabel: 'Show full address',
          onTrailingAction: onShowFullAddress,
        ),
    };
  }

  Widget _unknownFromRow(BuildContext context, String pool) {
    final isKnownPool = pool == 'shielded' || pool == 'transparent';
    final isShielded = pool == 'shielded';

    return ReviewInfoRow(
      label: 'From',
      value: 'Unknown sender',
      leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
      bottomLeftIconName: isKnownPool ? _poolIconName(isShielded) : null,
      bottomLeftIconColor: isKnownPool
          ? _poolIconColor(context, isShielded)
          : null,
      bottomLeftText: isKnownPool
          ? (isShielded ? 'Shielded' : 'Transparent')
          : null,
    );
  }
}

/// The 24px arrow-down connector between the From and Amount rows, centered
/// under the 32px leading-icon column.
class _ReceivedArrowSeparator extends StatelessWidget {
  const _ReceivedArrowSeparator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: AppAssetSize.size,
        child: Center(
          child: AppIcon(
            AppIcons.arrowDown,
            size: AppIconSize.large,
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
