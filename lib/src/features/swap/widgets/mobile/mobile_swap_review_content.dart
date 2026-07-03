import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../domain/swap_address_plan.dart';
import '../../domain/swap_contract.dart';
import '../../models/swap_address_formatting.dart';
import '../../models/swap_detail_tooltips.dart';
import '../swap_review_page_content.dart' show swapReviewSlippageToleranceText;
import '../swap_amount_text.dart' show compactSwapAmountText;
import 'mobile_swap_review_header.dart';

/// Mobile swap review — Figma `Review Qoute` (4731:85401): the serif
/// paying/receiving header over the rounded details card (slippage
/// tolerance, minimum receive, tx fee), with notices below. The
/// "Confirm & swap" / "Cancel" actions live in
/// [MobileSwapReviewActions] so the host can pin them to the bottom.
class MobileSwapReviewContent extends StatelessWidget {
  const MobileSwapReviewContent({
    required this.quote,
    required this.addressPlan,
    required this.accountLabel,
    required this.accountProfilePictureId,
    this.addressBookContacts = const [],
    required this.expired,
    required this.amountWarning,
    required this.startError,
    this.startBlockedReason,
    this.payFiatTextOverride,
    this.receiveFiatTextOverride,
    super.key,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final String? accountLabel;
  final String accountProfilePictureId;
  final Iterable<AddressBookContact> addressBookContacts;
  final bool expired;
  final String? amountWarning;
  final String? startError;
  final String? startBlockedReason;
  final String? payFiatTextOverride;
  final String? receiveFiatTextOverride;

  @override
  Widget build(BuildContext context) {
    final sendsZec = quote.direction.sendsZec;
    final externalAddress = addressPlan.userExternalAddress.trim();
    final externalLabel = sendsZec ? 'To' : 'From';
    final externalBottom =
        '$externalLabel: '
        '${compactSwapAddress(externalAddress, prefixLength: 6, suffixLength: 5, separator: ' ... ')}';

    final payRow = MobileSwapReviewHeaderRow(
      label: "You're paying",
      amountText: trimSwapAmountText(
        compactSwapAmountText(quote.sellAmountText),
      ),
      asset: quote.sellAsset,
      bottomText: sendsZec ? payFiatTextOverride : null,
    );
    final receiveRow = MobileSwapReviewHeaderRow(
      label: "You're receiving",
      amountText: trimSwapAmountText(
        compactSwapAmountText(quote.receiveEstimateText),
      ),
      asset: quote.receiveAsset,
      bottomText: sendsZec ? externalBottom : receiveFiatTextOverride,
      fullAddress: sendsZec ? externalAddress : null,
    );

    return Column(
      key: const ValueKey('mobile_swap_review_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSwapReviewHeader(pay: payRow, receive: receiveRow),
        const SizedBox(height: AppSpacing.sm),
        _ReviewCard(quote: quote),
        if (amountWarning != null) ...[
          const SizedBox(height: AppSpacing.s),
          _MobileReviewNotice(
            key: const ValueKey('mobile_swap_review_amount_warning'),
            message: amountWarning!,
          ),
        ],
        if (expired) ...[
          const SizedBox(height: AppSpacing.s),
          const _MobileReviewNotice(
            message: 'Quote expired. Review again for an updated rate.',
          ),
        ],
        if (startError != null) ...[
          const SizedBox(height: AppSpacing.s),
          _MobileReviewNotice(message: startError!),
        ],
        if (startBlockedReason != null) ...[
          const SizedBox(height: AppSpacing.s),
          _MobileReviewNotice(message: startBlockedReason!),
        ],
      ],
    );
  }
}

/// The rounded details card — Figma `Review Wrap` (4731:85565).
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewRow(
            label: 'Slippage tolerance',
            value: swapReviewSlippageToleranceText(quote),
          ),
          _ReviewRow(
            label: 'Guaranteed minimum',
            value: compactSwapAmountText(quote.minimumReceiveText),
            helpTooltip: swapMinimumReceiveTooltip(quote.receiveAsset.symbol),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Figma `border/neutral/default`.
          Container(height: 1, color: colors.border.regular),
          const SizedBox(height: AppSpacing.sm),
          _ReviewRow(
            label: 'Swap fee',
            value: quote.feeLabel,
            helpTooltip: swapFeeTooltip,
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.helpTooltip,
  });

  final String label;
  final String value;
  final String? helpTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xxs,
                AppSpacing.xxs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  if (helpTooltip != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    AppTooltip(
                      message: helpTooltip!,
                      tapToShow: true,
                      child: AppIcon(
                        AppIcons.help,
                        size: 20,
                        color: colors.icon.regular.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plum notice line under the card (quote drift, expiry, errors).
class _MobileReviewNotice extends StatelessWidget {
  const _MobileReviewNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppIcon(
            AppIcons.warning,
            size: AppIconSize.medium,
            color: colors.text.destructive,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom-pinned actions — Figma `Buttons Stack` (4731:85699):
/// "Confirm & swap" primary pill over a ghost Cancel.
class MobileSwapReviewActions extends StatelessWidget {
  const MobileSwapReviewActions({
    required this.expired,
    required this.starting,
    this.startBlockedReason,
    required this.sendsZec,
    required this.onCancelReview,
    required this.onReviewAgain,
    required this.onStartIntent,
    super.key,
  });

  final bool expired;
  final bool starting;
  final String? startBlockedReason;
  final bool sendsZec;
  final VoidCallback onCancelReview;
  final VoidCallback onReviewAgain;
  final VoidCallback onStartIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final startingLabel = sendsZec ? 'Sending' : 'Locking quote';
    final primaryLabel = expired
        ? 'Review again'
        : startBlockedReason != null
        ? 'Not enough ZEC'
        : starting
        ? startingLabel
        : 'Confirm & swap';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: expired
              ? const ValueKey('swap_review_again_button')
              : const ValueKey('swap_start_button'),
          expand: true,
          onPressed: startBlockedReason != null
              ? null
              : expired
              ? onReviewAgain
              : starting
              ? null
              : onStartIntent,
          leading: expired || starting || startBlockedReason != null
              ? null
              : const AppIcon(AppIcons.swapArrows, size: 20),
          child: Text(primaryLabel),
        ),
        const SizedBox(height: AppSpacing.s),
        Semantics(
          button: true,
          child: GestureDetector(
            key: const ValueKey('swap_review_cancel_button'),
            behavior: HitTestBehavior.opaque,
            onTap: onCancelReview,
            child: SizedBox(
              height: AppButtonSizing.largeHeight,
              child: Center(
                child: Text(
                  'Cancel',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.button.ghost.label,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
