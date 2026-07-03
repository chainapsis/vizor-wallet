import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/send_review_layout.dart';

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
    this.memoText,
    this.memoExpanded = false,
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
  final String? memoText;
  final bool memoExpanded;
  final VoidCallback? onExpandMemo;
  final VoidCallback? onTxIdPressed;
  final VoidCallback? onFeeHelpPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final memo = memoText?.trim();
    final title = switch (status) {
      ShieldedReceiptStatus.inProgress => l10n.shieldReceiptInProgress,
      ShieldedReceiptStatus.completed => l10n.shieldReceiptCompleted,
      ShieldedReceiptStatus.failed => l10n.shieldReceiptFailed,
    };
    final (statusValue, statusIconName, statusColor) = switch (status) {
      ShieldedReceiptStatus.inProgress => (
        l10n.activityInProgress,
        AppIcons.loader,
        colors.text.secondary,
      ),
      ShieldedReceiptStatus.completed => (
        l10n.activityCompleted,
        AppIcons.checkCircle,
        colors.text.positiveStrong,
      ),
      ShieldedReceiptStatus.failed => (
        l10n.activityFailed,
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
              ReviewInfoRow(
                label: l10n.navAmount,
                value: amountText,
                leading: ClipOval(
                  child: Image.asset(
                    'assets/icons/network_zec.png',
                    width: AppAssetSize.size,
                    height: AppAssetSize.size,
                    fit: BoxFit.cover,
                  ),
                ),
                bottomLeftIconName: AppIcons.transparentBalance,
                bottomLeftText: l10n.activityFromTransparentBalance,
              ),
              const _ShieldedArrowSeparator(),
              ReviewInfoRow(
                label: l10n.activityTo,
                value: l10n.homeShieldedBalance,
                leading: const ReviewInfoIconCircle(
                  iconName: AppIcons.shieldKeyholeOutline,
                ),
                bottomLeftIconName: AppIcons.shieldKeyhole,
                bottomLeftIconColor: colors.text.brandCrimson,
                bottomLeftText: l10n.receiveShielded,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        ReviewWrapCard(
          children: [
            ReviewListRow(
              label: l10n.navStatus,
              value: statusValue,
              valueColor: statusColor,
              leadingIconName: statusIconName,
            ),
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
                ReviewListRow(
                  label: l10n.activityTimestamp,
                  value: timestampText,
                ),
                ReviewListRow(
                  label: l10n.activityTxId,
                  value: txIdText,
                  trailingIconName: AppIcons.arrowTopRight,
                  onPressed: onTxIdPressed,
                ),
              ],
            ),
            if (feeText != null) ...[
              const ReviewWrapDivider(),
              ReviewListRow(
                label: l10n.txFeeSheetTitle,
                value: feeText!,
                trailingIconName: AppIcons.help,
                trailingIconColor: colors.text.secondary,
                trailingIconTooltip: l10n.txFeeHelpTooltip,
                onPressed: onFeeHelpPressed,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ShieldedArrowSeparator extends StatelessWidget {
  const _ShieldedArrowSeparator();

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
