import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/receipt_loading_skeleton.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/send_review_layout.dart';
import '../../../core/l10n/l10n.dart';

/// Display status of a transparent-balance shielding transaction.
enum ShieldedReceiptStatus { inProgress, completed, failed }

/// Redesigned receipt for the activity row shown as "Shielded".
///
/// There is no dedicated Figma frame for this state yet, so this reuses the
/// send/receive receipt primitives: an Amount review row flowing into a
/// shielded-balance destination row, followed by the standard status detail
/// card.
class ShieldedReceiptView extends StatelessWidget {
  const ShieldedReceiptView({
    required this.amountText,
    required this.timestampText,
    required this.txIdText,
    this.status = ShieldedReceiptStatus.completed,
    this.feeText,
    this.feeLabel,
    this.feeHelpText,
    this.memoText,
    this.memoExpanded = false,
    this.memoLoading = false,
    this.onExpandMemo,
    this.onTxIdPressed,
    this.onFeeHelpPressed,
    super.key,
  });

  final String amountText;
  final String timestampText;
  final String txIdText;
  final ShieldedReceiptStatus status;
  final String? feeText;
  final String? feeLabel;
  final String? feeHelpText;
  final String? memoText;
  final bool memoExpanded;

  /// Reserves the collapsed message row until the detail read completes.
  final bool memoLoading;
  final VoidCallback? onExpandMemo;
  final VoidCallback? onTxIdPressed;
  final VoidCallback? onFeeHelpPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final memo = memoText?.trim();
    final title = switch (status) {
      ShieldedReceiptStatus.inProgress => l10n.activityTitleShieldingInProgress,
      ShieldedReceiptStatus.completed => l10n.commonShieldedSuccessfully,
      ShieldedReceiptStatus.failed => l10n.activityTitleShieldingFailed,
    };
    final (statusValue, statusIconName, statusColor) = switch (status) {
      ShieldedReceiptStatus.inProgress => (
        l10n.commonInProgress,
        AppIcons.loader,
        colors.text.secondary,
      ),
      ShieldedReceiptStatus.completed => (
        l10n.commonCompleted,
        AppIcons.checkCircle,
        colors.text.positiveStrong,
      ),
      ShieldedReceiptStatus.failed => (
        l10n.commonFailed,
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
          child: ReviewInfoFlow(
            connectorColor: colors.text.secondary,
            rows: [
              ReviewInfoRow(
                label: l10n.commonAmount,
                value: amountText,
                leading: ClipOval(
                  child: Image.asset(
                    'assets/icons/desktop/network_zec.png',
                    width: AppAssetSize.size,
                    height: AppAssetSize.size,
                    fit: BoxFit.cover,
                  ),
                ),
                bottomLeftIconName: AppIcons.transparentBalance,
                bottomLeftText: l10n.activityBalanceFromTransparent,
              ),
              ReviewInfoRow(
                label: l10n.commonTo,
                value: l10n.commonShieldedBalance,
                leading: const ReviewInfoIconCircle(
                  iconName: AppIcons.shieldKeyholeOutline,
                ),
                bottomLeftIconName: AppIcons.shieldKeyhole,
                bottomLeftIconColor: colors.text.brandCrimson,
                bottomLeftText: l10n.poolShielded,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        ReviewWrapCard(
          children: [
            ReviewListRow(
              label: l10n.activityReceiptStatus,
              value: statusValue,
              valueColor: statusColor,
              leadingIconName: statusIconName,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (memoLoading)
                  const ReceiptMemoSkeleton()
                else if (memo != null && memo.isNotEmpty)
                  ReviewMemoRows(
                    memoText: memo,
                    expanded: memoExpanded,
                    onToggle: onExpandMemo,
                  ),
                ReviewListRow(
                  label: l10n.commonTimestamp,
                  value: timestampText,
                ),
                ReviewListRow(
                  label: l10n.commonTxId,
                  value: txIdText,
                  trailingIconName: AppIcons.arrowTopRight,
                  onPressed: onTxIdPressed,
                ),
              ],
            ),
            if (feeText != null) ...[
              const ReviewWrapDivider(),
              ReviewListRow(
                label: feeLabel ?? l10n.txFeeInfoTitle,
                value: feeText!,
                trailingIconName: AppIcons.help,
                trailingIconColor: colors.text.secondary,
                trailingIconTooltip:
                    feeHelpText ?? context.l10n.txFeeHelpTooltip,
                onPressed: onFeeHelpPressed,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
