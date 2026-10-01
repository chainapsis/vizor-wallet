import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../address_book/models/address_book_contact.dart';
import '../domain/swap_asset.dart';
import '../models/swap_activity_status_mapper.dart';
import '../models/swap_address_formatting.dart';
import 'swap_asset_icon.dart';

/// Desktop Pay activity status for Figma nodes 6245:109737 / 6245:110194 and
/// their dark variants. The Activity pane host already provides the toolbar
/// reserve and 16px top inset, so this widget owns only the 396x549 content.
class PayActivityStatusContent extends StatelessWidget {
  const PayActivityStatusContent({
    required this.status,
    required this.amountAsset,
    required this.amountText,
    required this.amountFiatText,
    required this.recipientAddress,
    required this.onShowFullAddress,
    this.recipientContact,
    this.onOpenExplorer,
    super.key,
  });

  final PayActivityStatusPresentation status;
  final SwapAsset amountAsset;
  final String amountText;
  final String amountFiatText;
  final String recipientAddress;
  final AddressBookContact? recipientContact;
  final VoidCallback onShowFullAddress;
  final VoidCallback? onOpenExplorer;

  static const Size contentSize = Size(396, 549);
  static const double reviewInfoHeight = 204;
  static const double detailCardHeight = 257;

  int get _outcomeDetailRowCount => switch (status.phase) {
    PayActivityStatusPhase.failed =>
      1 + (status.refundAddress?.isNotEmpty == true ? 1 : 0),
    PayActivityStatusPhase.refunded => [
      status.refundedAmountText,
      status.refundAddress,
      status.refundFeeText,
    ].where((value) => value != null && value.isNotEmpty).length,
    _ => 2,
  };

  double get _extraDetailHeight => _outcomeDetailRowCount > 2
      ? (_outcomeDetailRowCount - 2) * ReviewListRow.height
      : 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('pay_activity_status_content'),
      width: contentSize.width,
      height: contentSize.height + _extraDetailHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status.title,
            key: const ValueKey('pay_activity_status_title'),
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          _reviewInfo(context),
          const SizedBox(height: AppSpacing.base),
          _detailCard(context),
        ],
      ),
    );
  }

  Widget _reviewInfo(BuildContext context) {
    final contact = recipientContact;
    final compactRecipient = compactSwapAddress(
      recipientAddress,
      maxLength: 19,
      prefixLength: 8,
      suffixLength: 8,
      separator: '...',
    );

    return SizedBox(
      key: const ValueKey('pay_status_review_info'),
      height: reviewInfoHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewInfoRow(
              key: const ValueKey('pay_status_amount_row'),
              label: 'Amount',
              value: amountText,
              leading: SwapAssetIcon(
                asset: amountAsset,
                size: 32,
                showChainBadge: true,
              ),
              bottomLeftText: amountFiatText,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: AppAssetSize.size,
                child: Center(
                  child: AppIcon(
                    AppIcons.arrowDown,
                    size: AppIconSize.large,
                    color: context.colors.text.accent,
                  ),
                ),
              ),
            ),
            ReviewInfoRow(
              key: const ValueKey('pay_status_recipient_row'),
              label: 'To',
              value: contact?.label ?? compactRecipient,
              leading: contact == null
                  ? const ReviewInfoIconCircle(iconName: AppIcons.wallet)
                  : AppProfilePicture(
                      profilePictureId: contact.profilePictureId,
                      size: AppProfilePictureSize.large,
                    ),
              bottomLeftText: contact == null
                  ? 'New address'
                  : compactRecipient,
              trailingActionLabel: 'Show full address',
              trailingActionKey: const ValueKey('pay_status_show_full_address'),
              onTrailingAction: onShowFullAddress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(BuildContext context) {
    final colors = context.colors;
    final (statusColor, statusIcon) = switch (status.phase) {
      PayActivityStatusPhase.completed => (
        colors.text.positiveStrong,
        AppIcons.checkCircle,
      ),
      PayActivityStatusPhase.refunded => (
        colors.text.positiveStrong,
        AppIcons.uturnUp,
      ),
      PayActivityStatusPhase.failed => (
        colors.text.destructive,
        AppIcons.warning,
      ),
      PayActivityStatusPhase.inProgress => (
        colors.text.secondary,
        AppIcons.loader,
      ),
    };
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SizedBox(
      key: const ValueKey('pay_status_detail_card'),
      height: detailCardHeight + _extraDetailHeight,
      child: ReviewWrapCard(
        children: [
          TickerMode(
            enabled: !animationsDisabled,
            child: ReviewListRow(
              key: const ValueKey('pay_status_status_row'),
              label: 'Status',
              value: status.statusLabel,
              valueColor: statusColor,
              leadingIconName: statusIcon,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewListRow(label: 'Timestamp', value: status.timestampText),
              ReviewListRow(
                label: 'Tx ID',
                value: status.txIdText,
                trailingIconName: onOpenExplorer == null
                    ? null
                    : AppIcons.arrowTopRight,
                trailingIconColor: colors.icon.muted,
                onPressed: onOpenExplorer,
              ),
            ],
          ),
          const ReviewWrapDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status.phase == PayActivityStatusPhase.failed)
                ReviewListRow(
                  label: 'Source amount',
                  value: status.convertedFromText,
                ),
              if (status.phase == PayActivityStatusPhase.refunded &&
                  status.refundedAmountText?.isNotEmpty == true)
                ReviewListRow(
                  label: 'Refunded amount',
                  value: status.refundedAmountText!,
                ),
              if ((status.phase == PayActivityStatusPhase.failed ||
                      status.phase == PayActivityStatusPhase.refunded) &&
                  status.refundAddress?.isNotEmpty == true)
                ReviewListRow(
                  label: 'Refund to',
                  value: compactSwapAddress(status.refundAddress!),
                  copyText: status.refundAddress,
                  scaleValueToFit: true,
                ),
              if (status.phase == PayActivityStatusPhase.refunded &&
                  status.refundFeeText?.isNotEmpty == true)
                ReviewListRow(
                  label: 'Refund fee',
                  value: status.refundFeeText!,
                ),
              if (status.phase == PayActivityStatusPhase.inProgress ||
                  status.phase == PayActivityStatusPhase.completed) ...[
                ReviewListRow(
                  label: 'Converted from',
                  value: status.convertedFromText,
                  trailingIconName: AppIcons.shieldKeyhole,
                ),
                ReviewListRow(
                  label: 'Tx fee',
                  value: status.transactionFeeText,
                  trailingIconName: AppIcons.help,
                  trailingIconColor: colors.text.secondary,
                  trailingIconTooltip: kTxFeeHelpTooltip,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
