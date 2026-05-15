import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_asset_icon.dart';
import 'swap_deposit_qr_panel.dart';

const _reviewActionHeight = 54.0;

class SwapReviewModal extends StatelessWidget {
  const SwapReviewModal({
    required this.quote,
    required this.addressPlan,
    required this.expired,
    required this.amountWarning,
    required this.startError,
    required this.onReviewAgain,
    required this.onCancelReview,
    required this.onStartIntent,
    super.key,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final bool expired;
  final String? amountWarning;
  final String? startError;
  final VoidCallback onReviewAgain;
  final VoidCallback onCancelReview;
  final VoidCallback onStartIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      key: const ValueKey('swap_review_modal'),
      constraints: const BoxConstraints(maxWidth: 560),
      child: SizedBox(
        height: double.infinity,
        child: Container(
          key: const ValueKey('swap_review_panel'),
          margin: const EdgeInsets.all(AppSpacing.xs),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.base,
            border: Border.all(color: colors.border.regular),
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Swap review',
                      key: const ValueKey('swap_review_title'),
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                        fontSize: 26,
                        height: 32 / 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _ReviewStatusBadge(expired: expired),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReviewTradeSummary(quote: quote),
                      const SizedBox(height: AppSpacing.s),
                      _ReviewFeeSummary(quote: quote),
                      const SizedBox(height: AppSpacing.s),
                      if (quote.direction.sendsZec)
                        _ReviewDepositInstructionCard(quote: quote)
                      else
                        SwapDepositQrPanel(
                          key: const ValueKey('swap_review_deposit_qr_panel'),
                          title:
                              'Send ${quote.externalAsset.symbol} to source-chain deposit',
                          qrData: quote.depositInstruction.address,
                          addressLabel:
                              '${quote.externalAsset.symbol} source deposit',
                          address: quote.depositInstruction.address,
                          railLabel: quote.depositInstruction.asset.railLabel,
                          reuseWarning: quote.depositInstruction.reuseWarning,
                          memo: quote.depositInstruction.memo,
                          dense: true,
                        ),
                      const SizedBox(height: AppSpacing.s),
                      _ReviewDetailsDisclosure(
                        quote: quote,
                        addressPlan: addressPlan,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _ReviewConsentPanel(quote: quote),
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
                          message:
                              'Quote expired. Review again for a fresh route.',
                        ),
                      ],
                      if (startError != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        _ReviewNotice(message: startError!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _ReviewDivider(),
              const SizedBox(height: AppSpacing.sm),
              _ReviewActions(
                expired: expired,
                onCancelReview: onCancelReview,
                onReviewAgain: onReviewAgain,
                onStartIntent: onStartIntent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewConsentPanel extends StatelessWidget {
  const _ReviewConsentPanel({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sendsZec = quote.direction.sendsZec;
    final title = sendsZec
        ? 'Approval sends the ZEC deposit'
        : 'Approval locks deposit instructions';
    final detail = sendsZec
        ? 'The wallet creates the ZEC deposit transaction to a one-time transparent address. Only txid and status are used to track the swap.'
        : 'You still send ${quote.externalAsset.symbol} from the source chain. ZEC arrives in this wallet before the shield prompt.';
    return Container(
      key: const ValueKey('swap_review_consent_panel'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            sendsZec ? AppIcons.transparentBalance : AppIcons.shieldKeyhole,
            size: 18,
            color: colors.icon.brandCrimson,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                    fontSize: 15,
                    height: 20 / 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                    height: 18 / 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewDepositInstructionCard extends StatelessWidget {
  const _ReviewDepositInstructionCard({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final instruction = quote.depositInstruction;
    final title = quote.direction.sendsZec
        ? 'Send ZEC deposit to'
        : 'Send ${quote.externalAsset.symbol} to source-chain deposit';
    final detail = quote.direction.sendsZec
        ? 'The wallet uses this one-time transparent address after you continue.'
        : 'Send exactly from the source chain, then track the deposit from Activity.';
    return Container(
      key: const ValueKey('swap_review_deposit_instruction'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            AppIcons.transparentBalance,
            size: 18,
            color: colors.icon.brandCrimson,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                    fontSize: 15,
                    height: 20 / 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  instruction.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.codeSmall.copyWith(
                    color: colors.text.primary,
                    fontSize: 13,
                    height: 17 / 13,
                  ),
                ),
                if (instruction.memo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Memo ${instruction.memo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.codeSmall.copyWith(
                      color: colors.text.primary,
                      fontSize: 13,
                      height: 17 / 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${instruction.asset.railLabel}; ${instruction.reuseWarning}. $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStatusBadge extends StatelessWidget {
  const _ReviewStatusBadge({required this.expired});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = expired ? colors.text.destructive : colors.text.success;
    return Container(
      key: const ValueKey('swap_review_status_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            expired ? AppIcons.warning : AppIcons.checkCircle,
            size: 16,
            color: expired ? colors.icon.destructive : colors.icon.success,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            expired ? 'Quote expired' : 'Live quote',
            style: AppTypography.labelMedium.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ReviewTradeSummary extends StatelessWidget {
  const _ReviewTradeSummary({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 430;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReviewAmountColumn(
                  label: 'You send',
                  value: quote.sellAmountText,
                  asset: quote.sellAsset,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Container(height: 1, color: colors.border.subtle),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: AppIcon(
                        AppIcons.arrowDownward,
                        size: 16,
                        color: colors.icon.brandCrimson,
                      ),
                    ),
                    Expanded(
                      child: Container(height: 1, color: colors.border.subtle),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                const _ReviewDivider(),
                const SizedBox(height: AppSpacing.xs),
                _ReviewAmountColumn(
                  label: 'You receive',
                  value: quote.receiveEstimateText,
                  asset: quote.receiveAsset,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _ReviewAmountColumn(
                  label: 'You send',
                  value: quote.sellAmountText,
                  asset: quote.sellAsset,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: AppIcon(
                  AppIcons.arrowForwardIos,
                  size: 18,
                  color: colors.icon.brandCrimson,
                ),
              ),
              Expanded(
                child: _ReviewAmountColumn(
                  label: 'You receive',
                  value: quote.receiveEstimateText,
                  asset: quote.receiveAsset,
                  alignEnd: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewAmountColumn extends StatelessWidget {
  const _ReviewAmountColumn({
    required this.label,
    required this.value,
    required this.asset,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final SwapAsset asset;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
            fontSize: 13,
            height: 17 / 13,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!alignEnd) ...[
              SwapAssetIcon(asset: asset, size: 28),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                  fontSize: 20,
                  height: 24 / 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: AppSpacing.xs),
              SwapAssetIcon(asset: asset, size: 28),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReviewFeeSummary extends StatelessWidget {
  const _ReviewFeeSummary({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_review_fee_summary'),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.link, size: 18, color: colors.icon.brandCrimson),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Estimated fee',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                    fontSize: 15,
                    height: 20 / 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          _ReviewFeeRow(
            label: 'Swap fee',
            value: quote.feeLabel,
            detail: 'Already reflected in the shown rate.',
          ),
          _ReviewFeeRow(
            label: 'Price protection',
            value: _priceProtectionText(quote),
            detail: 'Difference between estimate and minimum receive.',
          ),
          _ReviewFeeRow(
            label: 'Minimum receive',
            value: quote.minimumReceiveText,
            detail: 'Lowest amount accepted before the swap refreshes.',
          ),
        ],
      ),
    );
  }
}

class _ReviewFeeRow extends StatelessWidget {
  const _ReviewFeeRow({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
                fontSize: 13,
                height: 17 / 13,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                    fontSize: 14,
                    height: 18 / 14,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _priceProtectionText(SwapQuote quote) {
  final buffer = quote.receiveAmount - quote.minimumReceiveAmount;
  final bounded = buffer.isFinite && buffer > 0 ? buffer : 0.0;
  final percent = quote.receiveAmount > 0 && quote.receiveAmount.isFinite
      ? bounded / quote.receiveAmount * 100
      : 0.0;
  final percentText = percent >= 1
      ? percent.toStringAsFixed(1)
      : percent.toStringAsFixed(2);
  return '${quote.receiveAsset.formatAmount(bounded)} '
      '${quote.receiveAsset.symbol} ($percentText%)';
}

class _ReviewDetailsDisclosure extends StatefulWidget {
  const _ReviewDetailsDisclosure({
    required this.quote,
    required this.addressPlan,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;

  @override
  State<_ReviewDetailsDisclosure> createState() =>
      _ReviewDetailsDisclosureState();
}

class _ReviewDetailsDisclosureState extends State<_ReviewDetailsDisclosure> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final refundLabel = widget.quote.direction.sendsZec
        ? 'Refund address'
        : '${widget.quote.externalAsset.symbol} refund';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: const ValueKey('swap_review_details_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _open ? 'Hide address details' : 'Address details',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                AppIcon(
                  _open ? AppIcons.arrowUpward : AppIcons.arrowDown,
                  size: 16,
                  color: colors.icon.muted,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          if (widget.quote.direction.sendsZec)
            _ReviewRow(
              label: 'Receive address',
              value: widget.addressPlan.reviewDeliveryValue,
            ),
          _ReviewRow(
            label: refundLabel,
            value: widget.addressPlan.oneClickRefundTo,
          ),
        ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(AppIcons.warning, size: 16, color: colors.icon.destructive),
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

class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.expired,
    required this.onCancelReview,
    required this.onReviewAgain,
    required this.onStartIntent,
  });

  final bool expired;
  final VoidCallback onCancelReview;
  final VoidCallback onReviewAgain;
  final VoidCallback onStartIntent;

  @override
  Widget build(BuildContext context) {
    if (expired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const ValueKey('swap_review_actions'),
            children: [
              Expanded(
                child: _ReviewActionButton(
                  buttonKey: const ValueKey('swap_review_cancel_button'),
                  onPressed: onCancelReview,
                  variant: AppButtonVariant.secondary,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: _ReviewActionButton(
                  buttonKey: const ValueKey('swap_review_again_button'),
                  onPressed: onReviewAgain,
                  variant: AppButtonVariant.primary,
                  leading: const AppIcon(AppIcons.renew),
                  child: const Text('Review again'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _ReviewActionButton(
            buttonKey: const ValueKey('swap_start_button'),
            onPressed: null,
            variant: AppButtonVariant.primary,
            child: const Text('Quote expired'),
          ),
        ],
      );
    }

    return Row(
      key: const ValueKey('swap_review_actions'),
      children: [
        Expanded(
          child: _ReviewActionButton(
            buttonKey: const ValueKey('swap_review_cancel_button'),
            onPressed: onCancelReview,
            variant: AppButtonVariant.secondary,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: _ReviewActionButton(
            buttonKey: const ValueKey('swap_start_button'),
            onPressed: onStartIntent,
            variant: AppButtonVariant.primary,
            trailing: const AppIcon(AppIcons.arrowForwardIos),
            child: const Text('Start swap'),
          ),
        ),
      ],
    );
  }
}

class _ReviewActionButton extends StatelessWidget {
  const _ReviewActionButton({
    required this.buttonKey,
    required this.onPressed,
    required this.variant,
    required this.child,
    this.leading,
    this.trailing,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth;
        return AppButton(
          key: buttonKey,
          onPressed: onPressed,
          variant: variant,
          size: AppButtonSize.large,
          height: _reviewActionHeight,
          minWidth: slotWidth.isFinite ? slotWidth : null,
          leading: leading,
          trailing: trailing,
          child: child,
        );
      },
    );
  }
}

class _ReviewDivider extends StatelessWidget {
  const _ReviewDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(height: 1, color: colors.border.subtle);
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 144,
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
