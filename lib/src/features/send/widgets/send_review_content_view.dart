import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_buttons_stack.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import 'send_review_layout.dart';

/// Presentational content view for the redesigned **Review send** step.
///
/// Covers both recipient variants from the Figma specs via
/// [SendReviewRecipient]: address-only (truncated UA headline + Shielded
/// badge) and contact (avatar + name headline + truncated address sub-line).
///
/// This widget owns no wallet/business logic — it renders a snapshot from
/// immutable props so the layout can be validated in Widgetbook before it is
/// wired into the live review screen. All callbacks are optional; the memo
/// expand chevron and fee help icon are visual affordances whose behavior is
/// supplied by the wiring slice.
class SendReviewContentView extends StatelessWidget {
  const SendReviewContentView({
    required this.amountText,
    required this.recipient,
    required this.feeText,
    this.isShieldedRecipient = true,
    this.recipientAddressType,
    this.fiatText,
    this.memoText,
    this.memoExpanded = false,
    this.confirmLabel,
    this.confirmLeadingIconName = AppIcons.plane,
    this.onConfirm,
    this.onCancel,
    this.onShowFullAddress,
    this.onExpandMemo,
    this.onFeeHelp,
    super.key,
  });

  /// Formatted send amount ("123.12 ZEC").
  final String amountText;

  final SendReviewRecipient recipient;

  /// Pool badge for raw-address recipients.
  final bool isShieldedRecipient;

  /// Full protocol address type from validation when available.
  final String? recipientAddressType;

  /// Formatted fee ("0.012 ZEC").
  final String feeText;

  /// Optional fiat sub-label under the amount; the row is hidden when null.
  final String? fiatText;

  /// Optional memo. When null the Message row (and its divider) is omitted
  /// from the wrap card; when present it renders single-line truncated with
  /// the expand affordance.
  final String? memoText;

  /// Whether the Message row shows the full memo (see [ReviewMemoRows]).
  final bool memoExpanded;

  /// Primary CTA label. The hardware-account wiring swaps in
  /// "Confirm with Keystone" while keeping the shared layout.
  /// Defaults to the localized "Confirm & send" when null.
  final String? confirmLabel;

  /// 20px leading icon on the primary CTA (plane, or QR for Keystone).
  final String confirmLeadingIconName;

  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onShowFullAddress;
  final VoidCallback? onExpandMemo;
  final VoidCallback? onFeeHelp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SendReviewContentColumn(
      title: AppLocalizations.of(context).sendReviewTitle,
      children: [
        SendReviewInfoSection(
          amountText: amountText,
          fiatText: fiatText,
          recipient: recipient,
          isShieldedRecipient: isShieldedRecipient,
          recipientAddressType: recipientAddressType,
          onShowFullAddress: onShowFullAddress,
        ),
        ReviewWrapCard(
          children: [
            if (memoText != null) ...[
              ReviewMemoRows(
                memoText: memoText!,
                expanded: memoExpanded,
                onToggle: onExpandMemo,
              ),
              const ReviewWrapDivider(),
            ],
            ReviewListRow(
              label: AppLocalizations.of(context).txFeeSheetTitle,
              value: feeText,
              trailingIconName: AppIcons.help,
              trailingIconColor: colors.text.secondary,
              trailingIconTooltip: AppLocalizations.of(
                context,
              ).txFeeHelpTooltip,
              onPressed: onFeeHelp,
            ),
          ],
        ),
        ReviewButtonsStack(
          primaryKey: const ValueKey('send_confirm_button'),
          primaryLabel:
              confirmLabel ?? AppLocalizations.of(context).sendConfirmAndSend,
          primaryLeadingIconName: confirmLeadingIconName,
          onPrimaryPressed: onConfirm,
          secondaryLabel: AppLocalizations.of(context).commonCancel,
          onSecondaryPressed: onCancel,
        ),
      ],
    );
  }
}
