import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/widgets/contact_name_inline.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import '../models/swap_address_book_helpers.dart';
import '../models/swap_address_formatting.dart';
import '../models/swap_detail_tooltips.dart';
import 'swap_amount_text.dart';
import 'swap_review_info.dart';
import '../../../core/config/fiat_currencies.dart';

/// Content width inside the 420 content area (Figma ' Review' frame).
const double _swapReviewContentWidth = 396;

class SwapReviewPageContent extends StatelessWidget {
  const SwapReviewPageContent({
    required this.quote,
    required this.addressPlan,
    required this.expired,
    required this.amountWarning,
    required this.startError,
    this.startBlockedReason,
    this.slippageToleranceTextOverride,
    this.payFiatTextOverride,
    this.receiveFiatTextOverride,
    this.onCopy,
    this.showTitle = true,
    this.addressBookContacts = const [],
    this.fiatDisplay = kUsdFiatDisplay,
    super.key,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;

  /// Saved contacts used to label the recipient/refund address lines when
  /// they match an address-book entry.
  final Iterable<AddressBookContact> addressBookContacts;
  final bool expired;
  final String? amountWarning;
  final String? startError;
  final String? startBlockedReason;
  final String? slippageToleranceTextOverride;
  final String? payFiatTextOverride;

  /// Selected display currency + USD conversion for quote fiat values.
  final FiatDisplay fiatDisplay;
  final String? receiveFiatTextOverride;

  /// Copies the full counterparty address to the clipboard (and surfaces a
  /// toast). Wired by the screen so the review summary's Copy affordance
  /// reuses the same mechanic as the rest of the swap flow.
  final ValueChanged<String>? onCopy;

  /// The mobile host renders its own top-nav title; it hides this
  /// inline one so "Review swap" doesn't appear twice.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_review_panel'),
      width: _swapReviewContentWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Text(
              'Review swap',
              key: const ValueKey('swap_review_title'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
          SwapReviewInfo(
            pay: _paySideData(),
            receive: _receiveSideData(),
            onCopy: onCopy,
          ),
          const SizedBox(height: AppSpacing.base),
          _SwapReviewDetailCard(
            quote: quote,
            slippageToleranceTextOverride: slippageToleranceTextOverride,
          ),
          if (amountWarning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReviewNotice(
              key: const ValueKey('swap_review_amount_warning'),
              message: amountWarning!,
            ),
          ],
          if (expired) ...[
            const SizedBox(height: AppSpacing.sm),
            const _ReviewNotice(
              message: 'Quote expired. Review again for an updated rate.',
            ),
          ],
          if (startError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReviewNotice(message: startError!),
          ],
          if (startBlockedReason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReviewNotice(message: startBlockedReason!),
          ],
        ],
      ),
    );
  }

  SwapReviewInfoSideData _paySideData() {
    final sendsZec = quote.direction.sendsZec;
    // ZEC side shows the fiat value; the external pay side (external→ZEC)
    // shows the refund address.
    if (sendsZec) {
      return SwapReviewInfoSideData(
        asset: quote.sellAsset,
        label: "You're paying",
        amountText: quote.sellAmountText,
        detailText: payFiatTextOverride ?? _payFiatText(quote, fiatDisplay),
      );
    }
    final refundAddress = addressPlan.oneClickRefundTo.trim();
    return SwapReviewInfoSideData(
      asset: quote.sellAsset,
      label: "You're paying",
      amountText: quote.sellAmountText,
      detailText:
          'Refund to: ${_contactAwareAddressText(refundAddress, quote.sellAsset)}',
      detailCopyText: refundAddress,
    );
  }

  SwapReviewInfoSideData _receiveSideData() {
    final sendsZec = quote.direction.sendsZec;
    // ZEC side shows the fiat value; the external receive side (ZEC→external)
    // shows the recipient address with its chain label.
    if (!sendsZec) {
      return SwapReviewInfoSideData(
        asset: quote.receiveAsset,
        label: "You're receiving",
        amountText: quote.receiveEstimateText,
        detailText:
            receiveFiatTextOverride ?? _receiveFiatText(quote, fiatDisplay),
      );
    }
    final recipientAddress = addressPlan.userExternalAddress.trim();
    return SwapReviewInfoSideData(
      asset: quote.receiveAsset,
      label: "You're receiving",
      amountText: quote.receiveEstimateText,
      detailText:
          'To: ${_contactAwareAddressText(recipientAddress, quote.receiveAsset)} '
          'on ${quote.receiveAsset.chainLabel}',
      detailCopyText: recipientAddress,
    );
  }

  /// Compact address, prefixed by the saved contact's name when the address
  /// matches an address-book entry on [asset]'s chain.
  String _contactAwareAddressText(String address, SwapAsset asset) {
    final label = addressBookContactForSwapAsset(
      contacts: addressBookContacts,
      asset: asset,
      address: address,
    )?.label.trim();
    final compact = compactSwapAddress(address);
    if (label == null || label.isEmpty) return compact;
    return contactAddressDisplayText(label: label, compactAddress: compact);
  }
}

class SwapReviewPageActions extends StatelessWidget {
  const SwapReviewPageActions({
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
    final startingLabel = sendsZec ? 'Sending' : 'Locking quote';
    final primaryLabel = expired
        ? 'Review again'
        : startBlockedReason != null
        ? 'Not enough ZEC'
        : starting
        ? startingLabel
        : 'Confirm swap';
    final showPrimaryArrow =
        !expired && !starting && startBlockedReason == null;
    return SizedBox(
      key: const ValueKey('swap_review_actions'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppButton(
            key: expired
                ? const ValueKey('swap_review_again_button')
                : const ValueKey('swap_start_button'),
            onPressed: startBlockedReason != null
                ? null
                : expired
                ? onReviewAgain
                : starting
                ? null
                : onStartIntent,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            minWidth: 196,
            leading: showPrimaryArrow
                ? const AppIcon(AppIcons.swapArrows)
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 184),
              child: Text(
                primaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('swap_review_cancel_button'),
            onPressed: onCancelReview,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.large,
            minWidth: 196,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Figma 'Review Wrap': the slippage / minimum / fee summary card, built on
/// the core [ReviewWrapCard] + [ReviewListRow] primitives.
class _SwapReviewDetailCard extends StatelessWidget {
  const _SwapReviewDetailCard({
    required this.quote,
    required this.slippageToleranceTextOverride,
  });

  final SwapQuote quote;
  final String? slippageToleranceTextOverride;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ReviewWrapCard(
      key: const ValueKey('swap_review_details'),
      children: [
        // One Figma `List` group: consecutive 32px rows stack with no gap —
        // the card's 16px child gap applies only around the divider.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewListRow(
              label: 'Slippage tolerance',
              value:
                  slippageToleranceTextOverride ??
                  swapReviewSlippageToleranceText(quote),
            ),
            ReviewListRow(
              label: 'Guaranteed minimum',
              value: compactSwapAmountText(quote.minimumReceiveText),
              trailingIconName: AppIcons.help,
              trailingIconColor: colors.icon.muted,
              trailingIconTooltip: swapMinimumReceiveTooltip(
                quote.receiveAsset.symbol,
              ),
            ),
          ],
        ),
        const ReviewWrapDivider(),
        ReviewListRow(
          label: 'Swap fee',
          value: quote.feeLabel,
          trailingIconName: AppIcons.help,
          trailingIconColor: colors.icon.muted,
          trailingIconTooltip: swapFeeTooltip,
        ),
      ],
    );
  }
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.destructive,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: textStyle.fontSize! * textStyle.height!,
          child: Center(
            child: AppIcon(
              AppIcons.warning,
              size: 16,
              color: colors.icon.destructive,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(message, style: textStyle)),
      ],
    );
  }
}

String _payFiatText(SwapQuote quote, FiatDisplay fiatDisplay) {
  return _quoteFiatText(
    quote.fiatValueBasis?.sellUsdValue(quote.sellAmount),
    fiatDisplay,
  );
}

String _receiveFiatText(SwapQuote quote, FiatDisplay fiatDisplay) {
  return _quoteFiatText(
    quote.fiatValueBasis?.receiveUsdValue(quote.receiveAmount),
    fiatDisplay,
  );
}

String _quoteFiatText(double? value, FiatDisplay fiatDisplay) {
  return value == null
      ? fiatDisplay.placeholderText
      : fiatDisplay.formatCompactUsdValue(value);
}

/// Public for the mobile review content, which renders the same row.
String swapReviewSlippageToleranceText(SwapQuote quote) {
  return compactSwapAmountText(quote.slippageToleranceText);
}
