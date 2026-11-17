import '../../../../core/l10n/l10n.dart';
import '../../../../core/l10n/locale_typography.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';
import '../../../../core/widgets/pool_badge.dart';
import '../../../swap/models/swap_models.dart';
import '../../../swap/widgets/swap_asset_icon.dart';
import '../../../swap/widgets/swap_quote_error_text.dart';
import '../../../swap/widgets/swap_confidential_ui.dart';
import '../../../../core/widgets/mobile/mobile_amount_card.dart';
import '../../models/pay_amount_input.dart';

const _slippageButtonWidth = 90.0;
const _slippageIconSize = 20.0;

/// Mobile Pay amount step from the 393 px Figma frame. The screen host owns
/// top navigation; this widget fills the remaining height and pins its actions
/// above the keyboard while the amount content scrolls on shorter devices.
class MobilePayAmountStep extends StatelessWidget {
  const MobilePayAmountStep({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.zecAvailableZatoshi,
    this.balanceMessage,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    required this.onToggleFiatInputMode,
    required this.onOpenAssetSelector,
    required this.slippageLabel,
    required this.confidentialReveal,
    required this.onOpenSlippage,
    required this.onContinue,
    super.key,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final BigInt zecAvailableZatoshi;

  /// Why [zecAvailableZatoshi] can't fund the payment, in place of
  /// "Not enough ZEC".
  final String? balanceMessage;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;
  final VoidCallback onToggleFiatInputMode;
  final VoidCallback onOpenAssetSelector;
  final String slippageLabel;

  /// Raised each time confidential turns on, landing the mark once.
  final int confidentialReveal;
  final VoidCallback onOpenSlippage;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final precisionError = state.quoteAmountPrecisionError(context.l10n);
    final balanceExceeded = payAmountExceedsAvailableZec(
      state,
      zecAvailableZatoshi,
    );
    final canContinue = payAmountCanContinue(state) && !balanceExceeded;
    final errorText =
        precisionError ??
        state.externalAssetSupportError(context.l10n) ??
        state.quoteError?.text(context.l10n);

    return Column(
      key: const ValueKey('mobile_pay_amount_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              kMobilePageMargin,
              AppSpacing.sm,
              kMobilePageMargin,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobilePayAmountCard(
                  state: state,
                  controller: controller,
                  focusNode: focusNode,
                  onAmountChanged: onAmountChanged,
                  onFiatAmountChanged: onFiatAmountChanged,
                  onToggleFiatInputMode: onToggleFiatInputMode,
                  onOpenAssetSelector: onOpenAssetSelector,
                ),
                const SizedBox(height: AppSpacing.md),
                _EstimatedZecRow(state: state),
                if (errorText != null || balanceExceeded) ...[
                  const SizedBox(height: AppSpacing.s),
                  SwapQuoteErrorText(
                    message: balanceExceeded
                        ? balanceMessage ?? context.l10n.commonNotEnoughZec
                        : errorText!,
                    textKey: const ValueKey('mobile_pay_amount_error'),
                    maxLines: balanceExceeded && balanceMessage != null
                        ? null
                        : 2,
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kMobilePageMargin,
            AppSpacing.s,
            kMobilePageMargin,
            kMobileFooterGap,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Icon, gap, label-slot padding and the custom button padding.
              final slippageWidth = math.max(
                _slippageButtonWidth,
                _scaledTextWidth(
                      context,
                      slippageLabel,
                      AppTypography.labelLarge,
                    ) +
                    _slippageIconSize +
                    AppSpacing.xxs * 5,
              );
              final slippage = SizedBox(
                width: slippageWidth,
                child: AppButton(
                  key: const ValueKey('mobile_pay_slippage_button'),
                  growWithContent: true,
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  constrainContent: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  onPressed: onOpenSlippage,
                  // Marks the button while the confidential route is set in
                  // the settings it opens.
                  leading: state.confidential
                      ? SwapConfidentialIcon(
                          reveal: confidentialReveal,
                          labeled: true,
                        )
                      : null,
                  trailing: const AppIcon(
                    AppIcons.cog,
                    size: _slippageIconSize,
                  ),
                  child: Text(
                    slippageLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
              final proceed = AppButton(
                key: const ValueKey('mobile_pay_amount_continue_button'),
                growWithContent: true,
                expand: true,
                constrainContent: true,
                onPressed: canContinue ? onContinue : null,
                child: Text(context.l10n.commonContinue),
              );
              final neededWidth =
                  slippageWidth +
                  AppSpacing.s +
                  _scaledTextWidth(
                    context,
                    context.l10n.commonContinue,
                    AppTypography.labelLarge,
                  ) +
                  AppSpacing.lg;
              if (neededWidth > constraints.maxWidth) {
                return Column(
                  key: const ValueKey('mobile_pay_amount_actions'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerRight, child: slippage),
                    const SizedBox(height: AppSpacing.s),
                    proceed,
                  ],
                );
              }
              return Row(
                key: const ValueKey('mobile_pay_amount_actions'),
                children: [
                  slippage,
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: proceed),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MobilePayAmountCard extends StatelessWidget {
  const _MobilePayAmountCard({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    required this.onToggleFiatInputMode,
    required this.onOpenAssetSelector,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;
  final VoidCallback onToggleFiatInputMode;
  final VoidCallback onOpenAssetSelector;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asset = state.externalAsset;
    return MobileAmountCard(
      key: const ValueKey('mobile_pay_amount_card'),
      header: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            context.l10n.payAmountPayingIn,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
          );
          final selector = Semantics(
            button: true,
            label: context.l10n.payAmountChooseAsset,
            child: GestureDetector(
              key: const ValueKey('mobile_pay_asset_selector'),
              behavior: HitTestBehavior.opaque,
              onTap: onOpenAssetSelector,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwapAssetIcon(
                      asset: asset,
                      size: AppAssetSize.size,
                      badgeScale: 0.5,
                      overhangScale: 0.1,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.symbol,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            asset.chainLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppIcon(
                      AppIcons.expand,
                      size: AppIconSize.medium,
                      color: colors.icon.accent,
                    ),
                  ],
                ),
              ),
            ),
          );
          final labelWidth = _scaledTextWidth(
            context,
            context.l10n.payAmountPayingIn,
            AppTypography.labelLarge,
          );
          final selectorWidth =
              AppAssetSize.size +
              AppSpacing.s +
              math.max(
                _scaledTextWidth(
                  context,
                  asset.symbol,
                  AppTypography.labelLarge,
                ),
                _scaledTextWidth(
                  context,
                  asset.chainLabel,
                  AppTypography.labelLarge,
                ),
              ) +
              AppSpacing.xs +
              AppIconSize.medium;
          if (labelWidth + AppSpacing.xs + selectorWidth <=
              constraints.maxWidth) {
            return Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: AppSpacing.xs),
                selector,
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: AppSpacing.xs),
              Align(alignment: Alignment.centerRight, child: selector),
            ],
          );
        },
      ),
      amount: _MobilePayAmountInput(
        key: const ValueKey('mobile_pay_amount_display'),
        state: state,
        controller: controller,
        focusNode: focusNode,
        onAmountChanged: onAmountChanged,
        onFiatAmountChanged: onFiatAmountChanged,
      ),
      conversion: _MobilePayAmountModeToggle(
        state: state,
        onToggleFiatInputMode: onToggleFiatInputMode,
      ),
    );
  }
}

/// The amount typed in the paying asset (or USD), with its unit beside it.
class _MobilePayAmountInput extends StatelessWidget {
  const _MobilePayAmountInput({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    super.key,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asset = state.externalAsset;
    final inputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: colors.text.accent,
    );
    final unitStyle = amountStyle.copyWith(
      color: colors.text.accent.withValues(alpha: 0.5),
      fontSize: 38,
      height: 40 / 38,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = inputIsFiat
            ? 'USD' // l10n-ignore: currency code
            : asset.symbol;
        final unitWidth = _scaledTextWidth(context, unit, unitStyle);
        final availableInputWidth =
            constraints.maxWidth - math.max(108, unitWidth + AppSpacing.xs);
        final enlarged =
            MediaQuery.textScalerOf(context).scale(amountStyle.fontSize!) >
            amountStyle.fontSize!;
        return Center(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final desiredInputWidth = payAmountInputWidth(
                context: context,
                text: controller.text,
                style: amountStyle,
                maxWidth: 220,
              );
              final stackUnit =
                  availableInputWidth < 56 ||
                  (enlarged && desiredInputWidth > availableInputWidth);
              final maxInputWidth = math.min(
                220.0,
                stackUnit ? constraints.maxWidth : availableInputWidth,
              );
              final inputWidth = payAmountInputWidth(
                context: context,
                text: controller.text,
                style: amountStyle,
                maxWidth: maxInputWidth,
              );
              final input = SizedBox(
                width: inputWidth,
                child: TextField(
                  key: const ValueKey('mobile_pay_amount_input'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    const CommaToDotInputFormatter(),
                    DecimalAmountInputFormatter(
                      maxFractionDigits: inputIsFiat ? 2 : asset.decimals,
                    ),
                  ],
                  onChanged: inputIsFiat
                      ? onFiatAmountChanged
                      : onAmountChanged,
                  textAlign: TextAlign.center,
                  style: amountStyle,
                  cursorColor: colors.text.accent,
                  cursorWidth: 3,
                  cursorRadius: const Radius.circular(AppRadii.full),
                  decoration: InputDecoration.collapsed(
                    hintText: '0',
                    hintStyle: amountStyle.copyWith(color: colors.text.muted),
                  ),
                ),
              );
              final suffix = Text(
                inputIsFiat
                    ? 'USD' // l10n-ignore: currency code
                    : asset.symbol,
                key: const ValueKey('mobile_pay_amount_unit'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: unitStyle,
              );
              return Flex(
                direction: stackUnit ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  input,
                  SizedBox(
                    width: stackUnit ? 0 : AppSpacing.xs,
                    height: stackUnit ? AppSpacing.xxs : 0,
                  ),
                  suffix,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The unit switch under the amount, showing the other unit's value.
class _MobilePayAmountModeToggle extends StatelessWidget {
  const _MobilePayAmountModeToggle({
    required this.state,
    required this.onToggleFiatInputMode,
  });

  final SwapState state;
  final VoidCallback onToggleFiatInputMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asset = state.externalAsset;
    final inputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final counterpart = inputIsFiat
        ? state.receiveAmountText.trim()
        : state.receiveFiatText.trim();
    final hasInput = _payAmountInputText(state).isNotEmpty;
    final counterpartLoading = hasInput && state.pricingLoading;
    return Semantics(
      button: true,
      label: inputIsFiat
          ? context.l10n.payAmountEnterIn(asset.symbol)
          : context.l10n.commonEnterAmountInUsd,
      child: GestureDetector(
        key: const ValueKey('mobile_pay_amount_mode_toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggleFiatInputMode,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.doubleArrowVertical,
              size: 20,
              color: colors.icon.regular,
            ),
            const SizedBox(width: AppSpacing.xxs),
            if (!hasInput)
              Text(
                inputIsFiat ? '0 ${asset.symbol}' : r'$ 0',
                key: const ValueKey('mobile_pay_amount_counterpart'),
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              )
            else if (counterpartLoading) ...[
              Text(
                inputIsFiat ? asset.symbol : r'$',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              const _MobilePaySkeletonBar(
                key: ValueKey('mobile_pay_amount_counterpart_skeleton'),
              ),
            ] else
              Text(
                inputIsFiat
                    ? '${counterpart.isEmpty ? '--' : counterpart} ${asset.symbol}'
                    : '\$${counterpart.isEmpty ? '--' : counterpart}',
                key: const ValueKey('mobile_pay_amount_counterpart'),
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EstimatedZecRow extends StatelessWidget {
  const _EstimatedZecRow({required this.state});

  final SwapState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final estimated = state.amountText.trim();
    final hasInput = _payAmountInputText(state).isNotEmpty;
    final estimateLoading = hasInput && state.pricingLoading;
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.primary,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        key: const ValueKey('mobile_pay_estimated_row'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.payAmountEstimated, style: labelStyle),
          const SizedBox(width: AppSpacing.xs),
          if (estimateLoading)
            const _MobilePaySkeletonBar(
              key: ValueKey('mobile_pay_estimated_skeleton'),
            )
          else
            Text(
              estimated.isEmpty ? (hasInput ? '--' : '0') : estimated,
              key: const ValueKey('mobile_pay_estimated_zec'),
              style: labelStyle.copyWith(color: colors.text.accent),
            ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'ZEC', // l10n-ignore: asset symbol
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // The shared pool label, as activity rows show it.
          const PoolBadge(isShielded: true),
        ],
      ),
    );
  }
}

String _payAmountInputText(SwapState state) {
  return (state.receiveAmountInputMode == SwapAmountInputMode.fiat
          ? state.receiveFiatText
          : state.receiveAmountText)
      .trim();
}

class _MobilePaySkeletonBar extends StatelessWidget {
  const _MobilePaySkeletonBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 48,
      height: 12,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.background.neutralSubtleOpacity,
            colors.background.overlay,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
    );
  }
}

// Measure the actual scaled font, including locale fallback, for layout choices.
double _scaledTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: withLocaleFontFallback(context, style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
