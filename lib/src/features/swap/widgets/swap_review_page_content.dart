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
    this.showTitle = true,
    this.payMode = false,
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

  /// The mobile host renders its own top-nav title; it hides this
  /// inline one so "Review swap" doesn't appear twice.
  final bool showTitle;
  final bool payMode;

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
              payMode ? 'Confirm payment' : 'Review swap',
              key: ValueKey(payMode ? 'pay_review_title' : 'swap_review_title'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
          if (payMode && quote.direction.sendsZec)
            _PayReviewCard(
              quote: quote,
              addressPlan: addressPlan,
              onCopy: onCopy,
            )
          else ...[
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
          ],
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
        label: payMode ? 'You pay' : "You're paying",
        amountText: quote.sellAmountText,
        detailText: payMode
            ? 'Privately, from shielded balance'
            : payFiatTextOverride ?? _payFiatText(quote),
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
      label: payMode ? 'Recipient gets' : "You're receiving",
      amountText: quote.receiveEstimateText,
      detailText:
          'To: ${compactSwapAddress(recipientAddress)} '
          'on ${quote.receiveAsset.chainLabel}',
      detailCopyText: recipientAddress,
    );
  }
}

class _PayReviewCard extends StatelessWidget {
  const _PayReviewCard({
    required this.quote,
    required this.addressPlan,
    required this.onCopy,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final recipientAddress = addressPlan.userExternalAddress.trim();
    final feeText = quote.totalFeesText?.trim();
    return ReviewWrapCard(
      key: const ValueKey('pay_review_summary'),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recipient gets',
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                color: colors.text.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                quote.receiveEstimateText,
                maxLines: 1,
                style: appSerifDisplayStyle(
                  color: colors.text.accent,
                ).copyWith(fontSize: 46, height: 1),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _PayRecipientPill(
              asset: quote.receiveAsset,
              address: recipientAddress,
              onCopy: onCopy,
            ),
          ],
        ),
        const ReviewWrapDivider(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'You pay',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '≈ ${quote.sellAmountText}',
                      maxLines: 1,
                      style: appSerifDisplayStyle(
                        color: colors.text.accent,
                      ).copyWith(fontSize: 20, height: 1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors.icon.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Privately, from shielded balance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const ReviewWrapDivider(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewListRow(label: 'Rate', value: quote.rateText),
            if (feeText != null && feeText.isNotEmpty)
              ReviewListRow(label: 'Network + conversion fees', value: feeText),
            ReviewListRow(label: 'Quote holds', value: quote.expiryLabel),
          ],
        ),
      ],
    );
  }
}

class _PayRecipientPill extends StatelessWidget {
  const _PayRecipientPill({
    required this.asset,
    required this.address,
    required this.onCopy,
  });

  final SwapAsset asset;
  final String address;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final copyable = address.isNotEmpty && onCopy != null;
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: copyable ? () => onCopy!(address) : null,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xxs,
          ),
          decoration: ShapeDecoration(
            color: colors.background.neutralSubtleOpacity,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '${asset.chainLabel} · ${compactSwapAddress(address)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              if (copyable) ...[
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(
                  AppIcons.copy,
                  size: AppIconSize.medium,
                  color: colors.icon.regular,
                ),
              ],
            ],
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
    this.payMode = false,
    this.receiveAmountText,
    super.key,
  });

  final bool expired;
  final bool starting;
  final String? startBlockedReason;
  final bool sendsZec;
  final VoidCallback onCancelReview;
  final VoidCallback onReviewAgain;
  final VoidCallback onStartIntent;
  final bool payMode;
  final String? receiveAmountText;

  @override
  Widget build(BuildContext context) {
    final startingLabel = payMode
        ? 'Paying'
        : sendsZec
        ? 'Sending'
        : 'Locking quote';
    final primaryLabel = expired
        ? 'Review again'
        : startBlockedReason != null
        ? 'Not enough ZEC'
        : starting
        ? startingLabel
        : payMode
        ? _payReviewActionLabel(receiveAmountText)
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
                ? payMode
                      ? const AppIcon(AppIcons.coins)
                      : const AppIcon(AppIcons.swapArrows)
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

String _payReviewActionLabel(String? receiveAmountText) {
  final amount = compactSwapAmountText(receiveAmountText ?? '').trim();
  return amount.isEmpty ? 'Confirm payment' : 'Pay $amount';
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

/// Public for the mobile review content, which renders the same row.
String swapReviewSlippageToleranceText(SwapQuote quote) {
  return compactSwapAmountText(quote.slippageToleranceText);
}
