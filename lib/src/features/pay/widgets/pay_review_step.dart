import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../swap/domain/swap_asset.dart';
import '../../swap/domain/swap_quote.dart';
import '../../swap/models/swap_address_formatting.dart';
import '../../swap/widgets/swap_asset_icon.dart';

/// Step 3 "Review Payment" of the desktop pay wizard — Figma 6245:108761.
/// Paying/To card, quote-expiry divider, converted-amount card, and the
/// "Confirm & Pay" CTA.
class PayReviewStep extends StatefulWidget {
  const PayReviewStep({
    required this.quote,
    required this.recipientAddress,
    required this.recipientContact,
    required this.payingFiatText,
    required this.convertedFiatText,
    required this.expiresInText,
    required this.expired,
    required this.starting,
    required this.startBlockedReason,
    required this.startError,
    required this.onConfirm,
    required this.onReviewAgain,
    super.key,
  });

  final SwapQuote quote;
  final String recipientAddress;

  /// Saved contact matching the recipient, for the avatar + display name.
  final AddressBookContact? recipientContact;

  final String? payingFiatText;
  final String? convertedFiatText;

  /// Ticking "1:30" remainder; null falls back to the quote's static label.
  final String? expiresInText;
  final bool expired;
  final bool starting;

  /// Non-null blocks the CTA (e.g. not enough spendable ZEC).
  final String? startBlockedReason;
  final String? startError;
  final VoidCallback onConfirm;
  final VoidCallback onReviewAgain;

  @override
  State<PayReviewStep> createState() => _PayReviewStepState();
}

class _PayReviewStepState extends State<PayReviewStep> {
  var _showFullAddress = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quote = widget.quote;
    final contact = widget.recipientContact;
    final valueStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
    );
    final compactRecipient = compactSwapAddress(
      widget.recipientAddress,
      prefixLength: 8,
      suffixLength: 8,
      separator: '...',
      maxLength: 19,
    );
    return Column(
      key: const ValueKey('pay_review_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
            boxShadow: appSurfaceShadow(colors),
          ),
          child: Column(
            children: [
              ReviewInfoRow(
                key: const ValueKey('pay_review_paying_row'),
                label: 'Paying',
                value: quote.receiveEstimateText,
                valueStyle: valueStyle,
                leading: SwapAssetIcon(asset: quote.externalAsset, size: 32),
                bottomLeftText: widget.payingFiatText,
              ),
              ReviewInfoRow(
                key: const ValueKey('pay_review_to_row'),
                label: 'To',
                value: contact?.label ?? compactRecipient,
                valueStyle: valueStyle,
                leading: contact != null
                    ? AppProfilePicture(
                        profilePictureId: contact.profilePictureId,
                        size: AppProfilePictureSize.large,
                      )
                    : const ReviewInfoIconCircle(iconName: AppIcons.wallet),
                bottomLeftText: _showFullAddress
                    ? widget.recipientAddress
                    : contact != null
                    ? compactRecipient
                    : 'Unknown address',
                trailingActionLabel: _showFullAddress
                    ? 'Hide full address'
                    : 'Show full address',
                trailingActionKey: const ValueKey(
                  'pay_review_show_full_address',
                ),
                onTrailingAction: () =>
                    setState(() => _showFullAddress = !_showFullAddress),
              ),
              if (_showFullAddress)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                    widget.recipientAddress,
                    key: const ValueKey('pay_review_full_address'),
                    textAlign: TextAlign.center,
                    style: AppTypography.codeMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(child: _PayReviewDividerLine()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: widget.expired
                            ? 'Quote expired'
                            : 'Quote expires in ',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      if (!widget.expired)
                        TextSpan(
                          text: widget.expiresInText ?? quote.expiryLabel,
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                    ],
                  ),
                  key: const ValueKey('pay_review_quote_expiry'),
                ),
              ),
              Expanded(child: _PayReviewDividerLine()),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
            boxShadow: appSurfaceShadow(colors),
          ),
          child: ReviewInfoRow(
            key: const ValueKey('pay_review_converted_row'),
            label: 'Converted amount',
            value: quote.sellAmountText,
            valueStyle: valueStyle,
            leading: const SwapAssetIcon(
              asset: SwapAsset.zec,
              size: 32,
              showChainBadge: false,
            ),
            bottomLeftText: widget.convertedFiatText,
          ),
        ),
        if (widget.startError != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            widget.startError!,
            key: const ValueKey('pay_review_start_error'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Center(
          child: AppButton(
            key: const ValueKey('pay_confirm_button'),
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            minWidth: 196,
            onPressed: widget.starting
                ? null
                : widget.expired
                ? widget.onReviewAgain
                : widget.startBlockedReason != null
                ? null
                : widget.onConfirm,
            leading: widget.expired || widget.starting
                ? null
                : const AppIcon(AppIcons.paid, size: 20),
            child: Text(
              widget.expired
                  ? 'Review again'
                  : widget.startBlockedReason != null
                  ? 'Not enough ZEC'
                  : widget.starting
                  ? 'Paying'
                  : 'Confirm & Pay',
            ),
          ),
        ),
      ],
    );
  }
}

class _PayReviewDividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      decoration: BoxDecoration(
        color: context.colors.border.subtle,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
    );
  }
}
