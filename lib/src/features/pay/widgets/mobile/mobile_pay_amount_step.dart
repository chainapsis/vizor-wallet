import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../swap/models/swap_models.dart';
import '../../../swap/widgets/swap_asset_icon.dart';
import '../../models/pay_amount_input.dart';

const _amountCardHeight = 240.0;
const _amountCardRadius = 28.0;
const _assetHeaderHeight = 56.0;
const _amountFieldHeight = 136.0;
const _amountInputRowHeight = 56.0;
const _amountMetaRowHeight = 20.0;
const _slippageButtonWidth = 90.0;

/// Mobile Pay amount step from the 393 px Figma frame. The screen host owns
/// top navigation; this widget fills the remaining height and pins its actions
/// above the keyboard while the amount content scrolls on shorter devices.
class MobilePayAmountStep extends StatelessWidget {
  const MobilePayAmountStep({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.zecAvailableZatoshi,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    required this.onToggleFiatInputMode,
    required this.onOpenAssetSelector,
    required this.slippageLabel,
    required this.onOpenSlippage,
    required this.onContinue,
    super.key,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final BigInt zecAvailableZatoshi;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;
  final VoidCallback onToggleFiatInputMode;
  final VoidCallback onOpenAssetSelector;
  final String slippageLabel;
  final VoidCallback onOpenSlippage;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final precisionError = state.quoteAmountPrecisionError;
    final hasAmount = state.receiveAmount != null || state.quoteAmount != null;
    final balanceExceeded = payAmountExceedsAvailableZec(
      state,
      zecAvailableZatoshi,
    );
    final canContinue =
        hasAmount &&
        precisionError == null &&
        !state.quoteLoading &&
        !balanceExceeded;
    final errorText = precisionError ?? state.quoteError;

    return Column(
      key: const ValueKey('mobile_pay_amount_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s,
              AppSpacing.sm,
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
                _EstimatedZecRow(state: state, hasAmount: hasAmount),
                if (errorText != null || balanceExceeded) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    balanceExceeded ? 'Not enough ZEC' : errorText!,
                    key: const ValueKey('mobile_pay_amount_error'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.s,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Row(
            key: const ValueKey('mobile_pay_amount_actions'),
            children: [
              SizedBox(
                width: _slippageButtonWidth,
                child: AppButton(
                  key: const ValueKey('mobile_pay_slippage_button'),
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  constrainContent: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  onPressed: onOpenSlippage,
                  trailing: const AppIcon(AppIcons.cog, size: 20),
                  child: Text(
                    slippageLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: AppButton(
                  key: const ValueKey('mobile_pay_amount_continue_button'),
                  expand: true,
                  constrainContent: true,
                  onPressed: canContinue ? onContinue : null,
                  child: const Text('Continue'),
                ),
              ),
            ],
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
    return Container(
      key: const ValueKey('mobile_pay_amount_card'),
      height: _amountCardHeight,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(_amountCardRadius),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Column(
        children: [
          SizedBox(
            height: _assetHeaderHeight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Paying in',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  button: true,
                  label: 'Choose payment asset',
                  child: GestureDetector(
                    key: const ValueKey('mobile_pay_asset_selector'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenAssetSelector,
                    child: SizedBox(
                      height: 44,
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
                          Column(
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
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: _amountFieldHeight,
            child: _MobilePayAmountField(
              state: state,
              controller: controller,
              focusNode: focusNode,
              onAmountChanged: onAmountChanged,
              onFiatAmountChanged: onFiatAmountChanged,
              onToggleFiatInputMode: onToggleFiatInputMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePayAmountField extends StatelessWidget {
  const _MobilePayAmountField({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    required this.onToggleFiatInputMode,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;
  final VoidCallback onToggleFiatInputMode;

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
    final counterpart = inputIsFiat
        ? state.receiveAmountText.trim()
        : state.receiveFiatText.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          SizedBox(
            key: const ValueKey('mobile_pay_amount_display'),
            height: _amountInputRowHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxInputWidth = (constraints.maxWidth - 108)
                    .clamp(56.0, 220.0)
                    .toDouble();
                return Center(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final inputWidth = payAmountInputWidth(
                        context: context,
                        text: controller.text,
                        style: amountStyle,
                        maxWidth: maxInputWidth,
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: inputWidth,
                            child: TextField(
                              key: const ValueKey('mobile_pay_amount_input'),
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                const CommaToDotInputFormatter(),
                                PayDecimalAmountInputFormatter(
                                  maxFractionDigits: inputIsFiat
                                      ? 2
                                      : asset.decimals,
                                ),
                              ],
                              onChanged: inputIsFiat
                                  ? onFiatAmountChanged
                                  : onAmountChanged,
                              textAlign: TextAlign.center,
                              style: amountStyle,
                              cursorColor: colors.text.accent,
                              decoration: InputDecoration.collapsed(
                                hintText: '0',
                                hintStyle: amountStyle.copyWith(
                                  color: colors.text.muted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            inputIsFiat ? 'USD' : asset.symbol,
                            key: const ValueKey('mobile_pay_amount_unit'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: unitStyle,
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            height: _amountMetaRowHeight,
            child: Semantics(
              button: true,
              label: inputIsFiat
                  ? 'Enter amount in ${asset.symbol}'
                  : 'Enter amount in USD',
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
                    if (counterpart.isEmpty) ...[
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
                            ? '$counterpart ${asset.symbol}'
                            : '\$$counterpart',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
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

class _EstimatedZecRow extends StatelessWidget {
  const _EstimatedZecRow({required this.state, required this.hasAmount});

  final SwapState state;
  final bool hasAmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final estimated = state.amountText.trim();
    final showEstimate = hasAmount && estimated.isNotEmpty;
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.primary,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        key: const ValueKey('mobile_pay_estimated_row'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Estimated:', style: labelStyle),
          const SizedBox(width: AppSpacing.xs),
          if (showEstimate)
            Text(
              estimated,
              key: const ValueKey('mobile_pay_estimated_zec'),
              style: labelStyle.copyWith(color: colors.text.accent),
            )
          else
            const _MobilePaySkeletonBar(
              key: ValueKey('mobile_pay_estimated_skeleton'),
            ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'ZEC',
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIcon(AppIcons.shieldKeyhole, size: 20, color: colors.icon.regular),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Shielded',
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
  }
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
