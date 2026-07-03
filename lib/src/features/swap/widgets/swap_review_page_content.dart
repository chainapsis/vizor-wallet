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
import '../../../../l10n/app_localizations.dart';

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
              AppLocalizations.of(context).swapReviewSwap,
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
            pay: _paySideData(context),
            receive: _receiveSideData(context),
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
            _ReviewNotice(
              message: AppLocalizations.of(context).swapQuoteExpiredNotice,
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

  SwapReviewInfoSideData _paySideData(BuildContext context) {
    final sendsZec = quote.direction.sendsZec;
    // ZEC side shows the fiat value; the external pay side (external→ZEC)
    // shows the refund address.
    if (sendsZec) {
      return SwapReviewInfoSideData(
        asset: quote.sellAsset,
        label: AppLocalizations.of(context).swapYourePaying,
        amountText: quote.sellAmountText,
        detailText: payFiatTextOverride ?? _payFiatText(quote),
      );
    }
    final refundAddress = addressPlan.oneClickRefundTo.trim();
    return SwapReviewInfoSideData(
      asset: quote.sellAsset,
      label: AppLocalizations.of(context).swapYourePaying,
      amountText: quote.sellAmountText,
      detailText: AppLocalizations.of(context).swapRefundToAddress(
        compactSwapAddress(refundAddress),
      ),
      detailCopyText: refundAddress,
    );
  }

  SwapReviewInfoSideData _receiveSideData(BuildContext context) {
    final sendsZec = quote.direction.sendsZec;
    // ZEC side shows the fiat value; the external receive side (ZEC→external)
    // shows the recipient address with its chain label.
    if (!sendsZec) {
      return SwapReviewInfoSideData(
        asset: quote.receiveAsset,
        label: AppLocalizations.of(context).swapYoureReceiving,
        amountText: quote.receiveEstimateText,
        detailText: receiveFiatTextOverride ?? _receiveFiatText(quote),
      );
    }
    final recipientAddress = addressPlan.userExternalAddress.trim();
    return SwapReviewInfoSideData(
      asset: quote.receiveAsset,
      label: AppLocalizations.of(context).swapYoureReceiving,
      amountText: quote.receiveEstimateText,
      detailText: AppLocalizations.of(context).swapToAddressOnChain(
        compactSwapAddress(recipientAddress),
        quote.receiveAsset.chainLabel,
      ),
      detailCopyText: recipientAddress,
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
    final l10n = AppLocalizations.of(context);
    final startingLabel = sendsZec
        ? l10n.swapVerbSending
        : l10n.swapVerbLockingQuote;
    final primaryLabel = expired
        ? l10n.swapReviewAgain
        : startBlockedReason != null
        ? l10n.swapNotEnoughZec
        : starting
        ? startingLabel
        : l10n.swapConfirmSwap;
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
            child: Text(AppLocalizations.of(context).commonCancel),
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
              label: AppLocalizations.of(context).swapSlippageToleranceLabel,
              value:
                  slippageToleranceTextOverride ??
                  swapReviewSlippageToleranceText(quote),
            ),
            ReviewListRow(
              label: AppLocalizations.of(context).swapGuaranteedMinimumLabel,
              value: compactSwapAmountText(quote.minimumReceiveText),
              trailingIconName: AppIcons.help,
              trailingIconColor: colors.icon.muted,
              trailingIconTooltip: swapMinimumReceiveTooltip(
                AppLocalizations.of(context),
                quote.receiveAsset.symbol,
              ),
            ),
          ],
        ),
        const ReviewWrapDivider(),
        ReviewListRow(
          label: AppLocalizations.of(context).swapFeeLabel,
          value: quote.feeLabel,
          trailingIconName: AppIcons.help,
          trailingIconColor: colors.icon.muted,
          trailingIconTooltip: swapFeeTooltip(AppLocalizations.of(context)),
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
