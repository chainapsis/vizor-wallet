import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../payment_links/widgets/payment_link_batch_deck.dart';
import '../../payment_links/widgets/payment_link_gift_card.dart';
import '../../payment_links/widgets/payment_link_copy.dart';
import '../../send/widgets/send_review_layout.dart';
import '../gift_card_activity_index.dart';
import '../activity_row_mapper.dart' show giftCardActivityTitle;

/// Totals for a receipt that funded a group of cards in one transaction.
class GiftCardActivityBatch {
  const GiftCardActivityBatch({
    required this.count,
    required this.totalLabel,
    required this.totalText,
    required this.breakdownText,
  });

  final int count;
  final String totalLabel;
  final String totalText;
  final String breakdownText;
}

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
    this.isInFlight = false,
    this.isFailed = false,
    this.supportingText,
    this.message,
    this.messageExpanded = false,
    this.onToggleMessage,
    super.key,
  }) : batch = null;

  /// A group receipt: [amountText] is the amount per card and the fee row is
  /// replaced by the group total.
  const GiftCardActivityDetailView.batch({
    required GiftCardActivityBatch this.batch,
    required this.artwork,
    required this.amountText,
    required this.statusText,
    required this.statusIconName,
    required this.statusColor,
    required this.timestampText,
    required this.txIdText,
    required this.onTxIdPressed,
    this.isInFlight = false,
    this.isFailed = false,
    this.message,
    this.messageExpanded = false,
    this.onToggleMessage,
    super.key,
  }) : kind = GiftCardActivityKind.created,
       feeText = null,
       supportingText = null;

  final GiftCardActivityKind kind;
  final GiftCardActivityBatch? batch;
  final bool isInFlight;
  final bool isFailed;
  final PaymentLinkCardArtwork artwork;
  final String amountText;
  final String? supportingText;
  final String statusText;
  final String statusIconName;
  final Color statusColor;
  final String timestampText;
  final String txIdText;

  /// The fee row value; the row and its divider are omitted when null.
  final String? feeText;
  final String? message;
  final bool messageExpanded;
  final VoidCallback? onToggleMessage;
  final VoidCallback onTxIdPressed;

  @override
  Widget build(BuildContext context) {
    final batch = this.batch;
    final gap = batch == null ? AppSpacing.base : AppSpacing.md;
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
                giftCardActivityTitle(
                  kind,
                  isInFlight: isInFlight,
                  isFailed: isFailed,
                  batchCount: batch?.count,
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: context.colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: gap),
              Center(
                child: batch == null
                    ? PaymentLinkGiftCard(
                        artwork: artwork,
                        cardWidth: 360,
                        cardHeight: 225,
                        amountText: amountText,
                        supportingText: supportingText,
                        showCaret: false,
                      )
                    : SizedBox(
                        width: 360,
                        height:
                            360 *
                            PaymentLinkBatchDeck.height /
                            PaymentLinkBatchDeck.width,
                        child: PaymentLinkBatchDeck(
                          card: PaymentLinkGiftCard(
                            artwork: artwork,
                            amountText: amountText,
                            showCaret: false,
                          ),
                          count: batch.count,
                          playReveal: false,
                        ),
                      ),
              ),
              SizedBox(height: gap),
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
                      if (batch != null)
                        ReviewListRow(
                          label: 'Cards',
                          value: '${batch.count} × $amountText ZEC',
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
                  if (batch != null || feeText != null)
                    const ReviewWrapDivider(),
                  if (batch == null && feeText != null)
                    ReviewListRow(
                      label: kind == GiftCardActivityKind.created
                          ? 'Card fee'
                          : 'Tx fee',
                      value: feeText!,
                      trailingIconName: AppIcons.help,
                      trailingIconColor: context.colors.text.secondary,
                      trailingIconTooltip: kind == GiftCardActivityKind.created
                          ? kPaymentLinkCardFeeHelpText
                          : kTxFeeHelpTooltip,
                    )
                  else if (batch != null)
                    ReviewListRow(
                      label: batch.totalLabel,
                      value: '${batch.totalText} ZEC',
                      trailingIconName: AppIcons.help,
                      trailingIconColor: context.colors.text.secondary,
                      trailingIconTooltip: batch.breakdownText,
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
