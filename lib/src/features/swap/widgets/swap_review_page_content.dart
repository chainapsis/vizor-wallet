import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import '../models/swap_address_formatting.dart';
import '../models/swap_detail_tooltips.dart';
import '../models/swap_fiat_value_formatting.dart';
import 'swap_amount_text.dart';
import 'swap_review_info.dart';

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
    super.key,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final bool expired;
  final String? amountWarning;
  final String? startError;
  final String? startBlockedReason;
  final String? slippageToleranceTextOverride;
  final String? payFiatTextOverride;
  final String? receiveFiatTextOverride;

  /// Copies the full counterparty address to the clipboard (and surfaces a
  /// toast). Wired by the screen so the review summary's Copy affordance
  /// reuses the same mechanic as the rest of the swap flow.
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_review_panel'),
      width: _swapReviewContentWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        detailText: payFiatTextOverride ?? _payFiatText(quote),
      );
    }
    final refundAddress = addressPlan.oneClickRefundTo.trim();
    return SwapReviewInfoSideData(
      asset: quote.sellAsset,
      label: "You're paying",
      amountText: quote.sellAmountText,
      detailText: 'Refund to: ${compactSwapAddress(refundAddress)}',
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
        detailText: receiveFiatTextOverride ?? _receiveFiatText(quote),
      );
    }
    final recipientAddress = addressPlan.userExternalAddress.trim();
    return SwapReviewInfoSideData(
      asset: quote.receiveAsset,
      label: "You're receiving",
      amountText: quote.receiveEstimateText,
      detailText:
          'To: ${compactSwapAddress(recipientAddress)} '
          'on ${quote.receiveAsset.chainLabel}',
      detailCopyText: recipientAddress,
    );
  }
}

class SwapReviewPageScrollArea extends StatefulWidget {
  const SwapReviewPageScrollArea({required this.child, super.key});

  final Widget child;

  @override
  State<SwapReviewPageScrollArea> createState() =>
      _SwapReviewPageScrollAreaState();
}

class _SwapReviewPageScrollAreaState extends State<SwapReviewPageScrollArea> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        key: const ValueKey('swap_review_scrollbar'),
        controller: _controller,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(AppRadii.full),
        thumbColor: colors.border.regular.withValues(alpha: 0.72),
        mainAxisMargin: AppSpacing.xxs,
        crossAxisMargin: AppSpacing.xxs,
        child: SingleChildScrollView(
          key: const ValueKey('swap_review_scroll_view'),
          controller: _controller,
          child: Padding(
            key: const ValueKey('swap_review_scroll_gutter'),
            padding: const EdgeInsets.only(right: AppSpacing.s),
            child: widget.child,
          ),
        ),
      ),
    );
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
        ReviewListRow(
          label: 'Slippage tolerance',
          value: slippageToleranceTextOverride ?? _slippageToleranceText(quote),
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

String _payFiatText(SwapQuote quote) {
  return _quoteFiatText(quote.fiatValueBasis?.sellUsdValue(quote.sellAmount));
}

String _receiveFiatText(SwapQuote quote) {
  return _quoteFiatText(
    quote.fiatValueBasis?.receiveUsdValue(quote.receiveAmount),
  );
}

String _quoteFiatText(double? value) {
  return value == null ? r'$--' : swapFormatCompactFiatValue(value);
}

String _slippageToleranceText(SwapQuote quote) {
  return compactSwapAmountText(quote.slippageToleranceText);
}
