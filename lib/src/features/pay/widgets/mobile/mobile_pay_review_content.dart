import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/review_info_row.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../swap/domain/swap_quote.dart';
import '../../../swap/models/swap_address_formatting.dart';
import '../../../swap/widgets/swap_asset_icon.dart';

const _reviewCardRadius = 28.0;

/// Mobile Pay review content from Figma light/dark frames 6268:32537 and
/// 6268:85861, including the quote-expired variants 6268:85289/85888.
class MobilePayReviewContent extends StatefulWidget {
  const MobilePayReviewContent({
    required this.quote,
    required this.recipientAddress,
    required this.recipientContact,
    required this.payingFiatText,
    required this.convertedFiatText,
    required this.expiresInText,
    required this.expired,
    super.key,
  });

  final SwapQuote quote;
  final String recipientAddress;
  final AddressBookContact? recipientContact;
  final String? payingFiatText;
  final String? convertedFiatText;
  final String? expiresInText;
  final bool expired;

  @override
  State<MobilePayReviewContent> createState() => _MobilePayReviewContentState();
}

class _MobilePayReviewContentState extends State<MobilePayReviewContent> {
  var _showFullAddress = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quote = widget.quote;
    final contact = widget.recipientContact;
    final compactRecipient = compactSwapAddress(
      widget.recipientAddress,
      prefixLength: 6,
      suffixLength: 5,
      separator: ' ... ',
    );

    return Column(
      key: const ValueKey('mobile_pay_review_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('mobile_pay_review_summary_card'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(_reviewCardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewInfoRow(
                key: const ValueKey('mobile_pay_review_paying_row'),
                label: 'Paying',
                value: quote.receiveEstimateText,
                valueFit: BoxFit.scaleDown,
                leading: SwapAssetIcon(
                  asset: quote.receiveAsset,
                  size: AppAssetSize.size,
                  badgeScale: 0.5,
                  overhangScale: 0.1,
                ),
                bottomLeftText: widget.payingFiatText,
              ),
              const SizedBox(height: AppSpacing.md),
              ReviewInfoRow(
                key: const ValueKey('mobile_pay_review_recipient_row'),
                label: 'To',
                value: contact?.label ?? compactRecipient,
                leading: contact == null
                    ? const ReviewInfoIconCircle(iconName: AppIcons.wallet)
                    : AppProfilePicture(
                        profilePictureId: contact.profilePictureId,
                        size: AppProfilePictureSize.navLarge,
                      ),
                bottomLeftText: contact == null
                    ? 'Unknown address'
                    : compactRecipient,
                trailingActionLabel: _showFullAddress
                    ? 'Hide address'
                    : 'Full address',
                trailingActionKey: const ValueKey(
                  'mobile_pay_review_full_address_button',
                ),
                onTrailingAction: () =>
                    setState(() => _showFullAddress = !_showFullAddress),
              ),
              if (_showFullAddress) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.recipientAddress,
                  key: const ValueKey('mobile_pay_review_full_address'),
                  textAlign: TextAlign.center,
                  style: AppTypography.codeMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _QuoteExpiryDivider(
          expired: widget.expired,
          expiresInText: widget.expiresInText ?? quote.expiryLabel,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          key: const ValueKey('mobile_pay_review_converted_card'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(_reviewCardRadius),
          ),
          child: Opacity(
            key: const ValueKey('mobile_pay_review_converted_opacity'),
            opacity: widget.expired ? 0.5 : 1,
            child: ReviewInfoRow(
              key: const ValueKey('mobile_pay_review_converted_row'),
              label: 'Converted amount',
              value: quote.sellAmountText,
              valueFit: BoxFit.scaleDown,
              leading: SwapAssetIcon(
                asset: quote.sellAsset,
                size: AppAssetSize.size,
                showChainBadge: false,
              ),
              bottomLeftText: widget.convertedFiatText,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuoteExpiryDivider extends StatelessWidget {
  const _QuoteExpiryDivider({
    required this.expired,
    required this.expiresInText,
  });

  final bool expired;
  final String expiresInText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_pay_review_expiry_divider'),
      height: 38,
      child: Row(
        children: [
          Expanded(child: _DividerLine(color: colors.border.subtle)),
          const SizedBox(width: AppSpacing.s),
          if (expired)
            Text(
              'Quote expired',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.destructive,
              ),
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Quote expires in ',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  TextSpan(
                    text: expiresInText,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: _DividerLine(color: colors.border.subtle)),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
    );
  }
}

/// Bottom-pinned actions for the active, submitting, blocked, expired, and
/// inactive Pay review states. The inactive variant mirrors
/// [MobileSwapReviewActions]: a lone return button after Keystone signing
/// left this review without a live quote.
class MobilePayReviewActions extends StatelessWidget {
  const MobilePayReviewActions({
    required this.expired,
    required this.starting,
    this.inactive = false,
    required this.startBlockedReason,
    required this.onConfirm,
    required this.onRefreshQuote,
    required this.onCancel,
    super.key,
  });

  final bool expired;
  final bool starting;
  final bool inactive;
  final String? startBlockedReason;
  final VoidCallback onConfirm;
  final VoidCallback onRefreshQuote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final blocked = startBlockedReason != null;
    final primaryLabel = inactive
        ? 'Return to pay'
        : expired
        ? 'Refresh quote'
        : blocked
        ? 'Not enough ZEC'
        : starting
        ? 'Paying'
        : 'Confirm & pay';
    final primaryAction = inactive
        ? onCancel
        : expired
        ? onRefreshQuote
        : blocked || starting
        ? null
        : onConfirm;
    final primaryKey = inactive
        ? const ValueKey('mobile_pay_review_return_to_pay_button')
        : expired
        ? const ValueKey('mobile_pay_review_refresh_quote_button')
        : const ValueKey('mobile_pay_review_confirm_button');

    return Column(
      key: const ValueKey('mobile_pay_review_actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: primaryKey,
          expand: true,
          constrainContent: true,
          onPressed: primaryAction,
          leading: inactive || blocked || starting
              ? null
              : AppIcon(
                  expired ? AppIcons.renew : AppIcons.paid,
                  size: AppIconSize.large,
                ),
          child: Text(primaryLabel),
        ),
        if (!inactive) ...[
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_pay_review_cancel_button'),
            variant: AppButtonVariant.ghost,
            expand: true,
            constrainContent: true,
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }
}
