import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import '../models/swap_address_formatting.dart';
import '../models/swap_detail_tooltips.dart';
import '../models/swap_fiat_value_formatting.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';
import 'swap_summary_amount_text.dart';

const _swapReviewDetailIconSize = 14.0;

class SwapReviewPageContent extends StatelessWidget {
  const SwapReviewPageContent({
    required this.quote,
    required this.addressPlan,
    this.addressBookContacts = const [],
    required this.accountLabel,
    required this.expired,
    required this.amountWarning,
    required this.startError,
    this.startBlockedReason,
    this.accountProfilePictureId = kDefaultProfilePictureId,
    this.slippageToleranceTextOverride,
    this.payFiatTextOverride,
    this.receiveFiatTextOverride,
    super.key,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final Iterable<AddressBookContact> addressBookContacts;
  final String? accountLabel;
  final String accountProfilePictureId;
  final bool expired;
  final String? amountWarning;
  final String? startError;
  final String? startBlockedReason;
  final String? slippageToleranceTextOverride;
  final String? payFiatTextOverride;
  final String? receiveFiatTextOverride;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_review_panel'),
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Review swap',
            key: const ValueKey('swap_review_title'),
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ReviewTradeSummaryCard(
            quote: quote,
            payFiatTextOverride: payFiatTextOverride,
            receiveFiatTextOverride: receiveFiatTextOverride,
          ),
          const SizedBox(height: AppSpacing.md),
          _ReviewDetailsList(
            quote: quote,
            addressPlan: addressPlan,
            addressBookContacts: addressBookContacts,
            accountLabel: accountLabel,
            accountProfilePictureId: accountProfilePictureId,
            slippageToleranceTextOverride: slippageToleranceTextOverride,
          ),
          if (amountWarning != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ReviewNotice(
              key: const ValueKey('swap_review_amount_warning'),
              message: amountWarning!,
            ),
          ],
          if (expired) ...[
            const SizedBox(height: AppSpacing.xs),
            const _ReviewNotice(
              message: 'Quote expired. Review again for an updated rate.',
            ),
          ],
          if (startError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ReviewNotice(message: startError!),
          ],
          if (startBlockedReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ReviewNotice(message: startBlockedReason!),
          ],
        ],
      ),
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
    final primaryLabel =
        expired
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
      width: 256,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key:
                expired
                    ? const ValueKey('swap_review_again_button')
                    : const ValueKey('swap_start_button'),
            onPressed:
                startBlockedReason != null
                    ? null
                    : expired
                    ? onReviewAgain
                    : starting
                    ? null
                    : onStartIntent,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            minWidth: 256,
            trailing:
                showPrimaryArrow
                    ? const AppIcon(AppIcons.arrowForwardIos)
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
            minWidth: 256,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ReviewTradeSummaryCard extends StatelessWidget {
  const _ReviewTradeSummaryCard({
    required this.quote,
    this.payFiatTextOverride,
    this.receiveFiatTextOverride,
  });

  final SwapQuote quote;
  final String? payFiatTextOverride;
  final String? receiveFiatTextOverride;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sellNeedsCompact = isLongSwapSummaryAmountText(quote.sellAmountText);
    final receiveNeedsCompact = isLongSwapSummaryAmountText(
      quote.receiveEstimateText,
    );
    final bothSidesNeedCompact = sellNeedsCompact && receiveNeedsCompact;
    final sellAmountText = compactSwapSummaryAmountText(
      quote.sellAmountText,
      forceCompactThousands: sellNeedsCompact,
      maxCharacters: swapReviewSummaryMaxChars,
    );
    final receiveAmountText = compactSwapSummaryAmountText(
      quote.receiveEstimateText,
      forceCompactThousands: receiveNeedsCompact,
      maxCharacters: swapReviewSummaryMaxChars,
    );
    final receiveNeedsWideSide =
        receiveAmountText.length > sellAmountText.length;
    final leftWidth =
        bothSidesNeedCompact
            ? 184.0
            : receiveNeedsWideSide
            ? 160.0
            : 205.0;
    final arrowLeft =
        bothSidesNeedCompact
            ? 184.0
            : receiveNeedsWideSide
            ? 161.5
            : 206.5;
    final rightLeft =
        bothSidesNeedCompact
            ? 216.0
            : receiveNeedsWideSide
            ? 195.0
            : 240.0;
    final rightWidth =
        bothSidesNeedCompact
            ? 184.0
            : receiveNeedsWideSide
            ? 205.0
            : 160.0;
    return Container(
      key: const ValueKey('swap_review_trade_summary'),
      width: 400,
      height: 120,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: leftWidth,
            child: _ReviewTradeSide(
              label: 'Pay',
              fiatText: payFiatTextOverride ?? _payFiatText(quote),
              amountText: sellAmountText,
              asset: quote.sellAsset,
            ),
          ),
          Positioned(
            left: arrowLeft,
            top: 0,
            bottom: 0,
            width: 32,
            child: Center(
              child: AppIcon(
                AppIcons.arrowForwardIos,
                size: 20,
                color: colors.text.homeCard,
              ),
            ),
          ),
          Positioned(
            left: rightLeft,
            top: 0,
            bottom: 0,
            width: rightWidth,
            child: _ReviewTradeSide(
              label: 'Receive',
              fiatText: receiveFiatTextOverride ?? _receiveFiatText(quote),
              amountText: receiveAmountText,
              asset: quote.receiveAsset,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTradeSide extends StatelessWidget {
  const _ReviewTradeSide({
    required this.label,
    required this.fiatText,
    required this.amountText,
    required this.asset,
  });

  final String label;
  final String fiatText;
  final String amountText;
  final SwapAsset asset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.homeCard,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    fiatText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.homeCard.withValues(alpha: 0.58),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwapAssetIcon(
                  asset: asset,
                  size: 32,
                  showChainBadge: !asset.isNativeZec,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwapSummaryAmountText(
                        amountText: amountText,
                        asset: asset,
                        keyPrefix:
                            'swap_review_${label.toLowerCase()}_summary_amount',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.homeCard,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        asset.chainLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.homeCard.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewDetailsList extends StatelessWidget {
  const _ReviewDetailsList({
    required this.quote,
    required this.addressPlan,
    required this.addressBookContacts,
    required this.accountLabel,
    required this.accountProfilePictureId,
    required this.slippageToleranceTextOverride,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final Iterable<AddressBookContact> addressBookContacts;
  final String? accountLabel;
  final String accountProfilePictureId;
  final String? slippageToleranceTextOverride;

  @override
  Widget build(BuildContext context) {
    final sendsZec = quote.direction.sendsZec;
    final externalAddress = _refundOrRecipientValue(addressPlan);
    final addressNetwork = AddressBookNetwork.tryFromChainTicker(
      addressPlan.externalAsset.chainTicker,
    );
    final addressBookLabel = addressNetwork == null
        ? null
        : addressBookLabelFor(
            contacts: addressBookContacts,
            network: addressNetwork,
            address: externalAddress,
          );
    final accountRow = _ReviewDetailRow(
      label: sendsZec ? 'From' : 'To',
      value: accountLabel ?? 'Current account',
      leadingValue: _AccountAvatar(profilePictureId: accountProfilePictureId),
    );
    final addressRow = addressBookLabel == null || addressNetwork == null
        ? _ReviewDetailRow(
            label: sendsZec ? 'To' : 'From',
            value: compactSwapAddress(externalAddress),
          )
        : _ReviewMatchedAddressRow(
            label: sendsZec ? 'To' : 'From',
            addressBookLabel: addressBookLabel,
            network: addressNetwork,
            value: compactSwapAddress(
              externalAddress,
              prefixLength: 7,
              suffixLength: 5,
              separator: '…',
            ),
          );
    return SizedBox(
      key: const ValueKey('swap_review_details'),
      width: 400,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sendsZec) accountRow else addressRow,
            if (sendsZec) addressRow else accountRow,
            const SizedBox(height: AppSpacing.sm),
            _ReviewDetailRow(
              label: 'Slippage tolerance',
              value:
                  slippageToleranceTextOverride ??
                  _slippageToleranceText(quote),
            ),
            _ReviewDetailRow(
              label: 'Guaranteed minimum',
              value: compactSwapAmountText(quote.minimumReceiveText),
              trailingIcon: AppIcons.help,
              tooltipMessage: swapMinimumReceiveTooltip(
                quote.receiveAsset.symbol,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ReviewDetailRow(
              label: 'Swap fee',
              value: quote.feeLabel,
              trailingIcon: AppIcons.help,
              tooltipMessage: swapFeeTooltip,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewMatchedAddressRow extends StatelessWidget {
  const _ReviewMatchedAddressRow({
    required this.label,
    required this.addressBookLabel,
    required this.network,
    required this.value,
  });

  final String label;
  final String addressBookLabel;
  final AddressBookNetwork network;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            addressBookLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        AppIcon(
                          AppIcons.user,
                          size: 14,
                          color: colors.icon.brandCrimson,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AddressBookNetworkIcon(network: network, size: 14),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      network.label,
                      maxLines: 1,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      value,
                      maxLines: 1,
                      style: AppTypography.codeSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewDetailRow extends StatelessWidget {
  const _ReviewDetailRow({
    required this.label,
    required this.value,
    this.leadingValue,
    this.trailingIcon,
    this.tooltipMessage,
  });

  final String label;
  final String value;
  final Widget? leadingValue;
  final String? trailingIcon;
  final String? tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingValue != null) ...[
                    leadingValue!,
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    _ReviewHelpIcon(
                      icon: trailingIcon!,
                      tooltipMessage: tooltipMessage,
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

class _ReviewHelpIcon extends StatelessWidget {
  const _ReviewHelpIcon({required this.icon, required this.tooltipMessage});

  final String icon;
  final String? tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = MouseRegion(
      cursor: SystemMouseCursors.help,
      child: AppIcon(
        icon,
        size: _swapReviewDetailIconSize,
        color: colors.icon.regular.withValues(alpha: 0.72),
      ),
    );
    final message = tooltipMessage;
    if (message == null ||
        message.isEmpty ||
        Overlay.maybeOf(context) == null) {
      return child;
    }
    return AppTooltip(message: message, child: child);
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicture(
      profilePictureId: profilePictureId,
      size: AppProfilePictureSize.medium,
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

String _refundOrRecipientValue(SwapAddressPlan addressPlan) {
  return addressPlan.direction.sendsZec
      ? addressPlan.userExternalAddress
      : addressPlan.oneClickRefundTo;
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
