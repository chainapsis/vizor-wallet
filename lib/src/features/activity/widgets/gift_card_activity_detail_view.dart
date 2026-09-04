import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../payment_links/widgets/payment_link_gift_card.dart';
import '../../send/widgets/send_review_layout.dart';
import '../gift_card_activity_index.dart';

class GiftCardActivityDetailView extends StatelessWidget {
  const GiftCardActivityDetailView({
    required this.kind,
    required this.artwork,
    required this.amountText,
    required this.statusText,
    required this.statusIconName,
    required this.statusColor,
    required this.timestampText,
    required this.txIdText,
    required this.feeText,
    required this.onTxIdPressed,
    this.supportingText,
    this.message,
    this.messageExpanded = false,
    this.onToggleMessage,
    super.key,
  });

  final GiftCardActivityKind kind;
  final PaymentLinkCardArtwork artwork;
  final String amountText;
  final String? supportingText;
  final String statusText;
  final String statusIconName;
  final Color statusColor;
  final String timestampText;
  final String txIdText;
  final String feeText;
  final String? message;
  final bool messageExpanded;
  final VoidCallback? onToggleMessage;
  final VoidCallback onTxIdPressed;

  @override
  Widget build(BuildContext context) {
    final messageText = message?.trim();
    final hasMessage = messageText != null && messageText.isNotEmpty;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: AppWindowSizing.contentAreaMaxWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kind == GiftCardActivityKind.created
                    ? 'Created Gift Card'
                    : 'Redeemed Gift Card',
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: context.colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Center(
                child: PaymentLinkGiftCard(
                  artwork: artwork,
                  cardWidth: 360,
                  cardHeight: 225,
                  amountText: amountText,
                  supportingText: supportingText,
                  showCaret: false,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              ReviewWrapCard(
                children: [
                  Column(
                    children: [
                      ReviewListRow(
                        label: 'Status',
                        value: statusText,
                        valueColor: statusColor,
                        leadingIconName: statusIconName,
                      ),
                      if (hasMessage)
                        ReviewMemoRows(
                          memoText: messageText,
                          expanded: messageExpanded,
                          onToggle: onToggleMessage,
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
                  const ReviewWrapDivider(),
                  ReviewListRow(
                    label: 'Tx fee',
                    value: feeText,
                    trailingIconName: AppIcons.help,
                    trailingIconColor: context.colors.text.secondary,
                    trailingIconTooltip: kTxFeeHelpTooltip,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
