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
class PayReviewStep extends StatelessWidget {
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
    required this.onShowFullAddress,
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
  final VoidCallback onShowFullAddress;
  final VoidCallback onConfirm;
  final VoidCallback onReviewAgain;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quote = this.quote;
    final contact = recipientContact;
    final valueStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
    );
    final compactRecipient = compactSwapAddress(
      recipientAddress,
      prefixLength: 8,
      suffixLength: 8,
      separator: '...',
      maxLength: 19,
    );
    return Padding(
      key: const ValueKey('pay_review_step'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
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
                  rowHeight: 76,
                  label: 'Paying',
                  value: quote.receiveEstimateText,
                  valueStyle: valueStyle,
                  leading: SwapAssetIcon(asset: quote.externalAsset, size: 32),
                  bottomLeftText: payingFiatText,
                ),
                const SizedBox(height: AppSpacing.sm),
                ReviewInfoRow(
                  key: const ValueKey('pay_review_to_row'),
                  rowHeight: 76,
                  label: 'To',
                  value: contact?.label ?? compactRecipient,
                  valueStyle: valueStyle,
                  leading: contact != null
                      ? AppProfilePicture(
                          profilePictureId: contact.profilePictureId,
                          size: AppProfilePictureSize.large,
                        )
                      : const ReviewInfoIconCircle(iconName: AppIcons.wallet),
                  bottomLeftText: contact != null
                      ? compactRecipient
                      : 'Unknown address',
                  trailingActionLabel: 'Show full address',
                  trailingActionKey: const ValueKey(
                    'pay_review_show_full_address',
                  ),
                  onTrailingAction: onShowFullAddress,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: _PayReviewDividerLine()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: expired
                                ? 'Quote expired'
                                : 'Quote expires in ',
                            style: AppTypography.labelLarge.copyWith(
                              color: expired
                                  ? colors.text.destructive
                                  : colors.text.secondary,
                            ),
                          ),
                          if (!expired)
                            TextSpan(
                              text: expiresInText ?? quote.expiryLabel,
                              style: AppTypography.labelLarge.copyWith(
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
          ),
          const SizedBox(height: AppSpacing.sm),
          Opacity(
            key: const ValueKey('pay_review_converted_opacity'),
            opacity: expired ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.xLarge),
                boxShadow: appSurfaceShadow(colors),
              ),
              child: ReviewInfoRow(
                key: const ValueKey('pay_review_converted_row'),
                rowHeight: 76,
                label: 'Converted amount',
                value: quote.sellAmountText,
                valueStyle: valueStyle,
                leading: const SwapAssetIcon(
                  asset: SwapAsset.zec,
                  size: 32,
                  showChainBadge: false,
                ),
                bottomLeftText: convertedFiatText,
              ),
            ),
          ),
          if (startError != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              startError!,
              key: const ValueKey('pay_review_start_error'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom-pinned action for active and expired review quotes.
class PayReviewAction extends StatelessWidget {
  const PayReviewAction({
    required this.expired,
    required this.starting,
    required this.startBlockedReason,
    required this.onConfirm,
    required this.onReviewAgain,
    super.key,
  });

  final bool expired;
  final bool starting;
  final String? startBlockedReason;
  final VoidCallback onConfirm;
  final VoidCallback onReviewAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (startBlockedReason != null && !expired) ...[
          SizedBox(
            width: 260,
            child: Text(
              startBlockedReason!,
              key: const ValueKey('pay_review_blocked_reason'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        AppButton(
          key: const ValueKey('pay_confirm_button'),
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: 196,
          onPressed: starting
              ? null
              : expired
              ? onReviewAgain
              : startBlockedReason != null
              ? null
              : onConfirm,
          leading: expired
              ? const AppIcon(AppIcons.renew, size: 20)
              : starting
              ? null
              : const AppIcon(AppIcons.paid, size: 20),
          child: Text(
            expired
                ? 'Refresh the quote'
                : startBlockedReason != null
                ? 'Not enough ZEC'
                : starting
                ? 'Paying'
                : 'Confirm & pay',
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
