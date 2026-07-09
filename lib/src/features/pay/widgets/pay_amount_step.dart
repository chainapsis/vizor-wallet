import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../swap/models/swap_models.dart';
import '../../swap/widgets/swap_asset_icon.dart';
import '../models/pay_amount_input.dart';

/// Figma Young Serif Medium 40 amount style — larger than the serif display
/// tokens, specific to the pay amount input (spec-form-a §3b).
const _payAmountInputTextStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w500,
  fontSize: 40,
  height: 1.2,
  fontFeatures: [FontFeature.enable('case')],
);

/// Step 1 "Amount" of the desktop pay wizard (Form Option A) — Figma
/// 6133:124896: "Paying in" asset selector, centered serif amount input with
/// an inline fiat toggle, and the "Estimated spend" ZEC row.
class PayAmountStep extends StatelessWidget {
  const PayAmountStep({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onAmountChanged,
    required this.onFiatAmountChanged,
    required this.onToggleFiatInputMode,
    required this.onOpenAssetSelector,
    required this.onContinue,
    super.key,
  });

  final SwapState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onFiatAmountChanged;
  final VoidCallback onToggleFiatInputMode;
  final VoidCallback onOpenAssetSelector;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asset = state.externalAsset;
    final inputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final precisionError = state.quoteAmountPrecisionError;
    final quoteError = precisionError ?? state.quoteError;
    final hasAmount = state.receiveAmount != null || state.quoteAmount != null;
    final canContinue =
        hasAmount && precisionError == null && !state.quoteLoading;
    final counterpartText = inputIsFiat
        ? (state.receiveAmountText.trim().isEmpty
              ? null
              : '${state.receiveAmountText.trim()} ${asset.symbol}')
        : (state.receiveFiatText.trim().isEmpty
              ? null
              : state.receiveFiatText.trim());
    final estimatedZecText = state.amountText.trim();

    return Column(
      key: const ValueKey('pay_amount_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.background.base,
            borderRadius: BorderRadius.circular(AppRadii.large),
            boxShadow: appSurfaceShadow(colors),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Paying in',
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.text.secondary,
                    ),
                  ),
                  const Spacer(),
                  _PayAssetSelector(asset: asset, onTap: onOpenAssetSelector),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxInputWidth = (constraints.maxWidth - 120)
                      .clamp(56.0, 240.0)
                      .toDouble();
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final amountStyle = _payAmountInputTextStyle.copyWith(
                        color: colors.text.accent,
                      );
                      final inputWidth = payAmountInputWidth(
                        context: context,
                        text: controller.text,
                        style: amountStyle,
                        maxWidth: maxInputWidth,
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: inputWidth,
                            child: TextField(
                              key: const ValueKey('pay_amount_input'),
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
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
                                hintStyle: _payAmountInputTextStyle.copyWith(
                                  color: colors.text.muted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              inputIsFiat ? 'USD' : asset.symbol,
                              key: const ValueKey('pay_amount_unit'),
                              style: AppTypography.displaySmall.copyWith(
                                color: colors.text.muted,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: AppSpacing.s),
              Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('pay_amount_fiat_toggle'),
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
                        if (counterpartText != null)
                          Text(
                            inputIsFiat
                                ? counterpartText
                                : '\$$counterpartText',
                            key: const ValueKey('pay_amount_counterpart'),
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.text.secondary,
                            ),
                          )
                        else ...[
                          Text(
                            inputIsFiat ? asset.symbol : r'$',
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.text.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          const _PaySkeletonBar(width: 48),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xxs,
                      children: [
                        Text(
                          'Estimated spend',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.text.secondary,
                          ),
                        ),
                        if (estimatedZecText.isEmpty)
                          const _PaySkeletonBar(width: 48)
                        else
                          Text(
                            estimatedZecText,
                            key: const ValueKey('pay_estimated_spend'),
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.text.accent,
                            ),
                          ),
                        Text(
                          'ZEC',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SwapAssetIcon(
                        asset: SwapAsset.zec,
                        size: 32,
                        showChainBadge: false,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'ZEC',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paying from your ',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary,
                ),
              ),
              AppIcon(
                AppIcons.shieldKeyhole,
                size: 20,
                color: colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Shielded balance',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        if (quoteError != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            quoteError,
            key: const ValueKey('pay_amount_error'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('pay_amount_continue_button'),
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          expand: true,
          onPressed: canContinue ? onContinue : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PayAssetSelector extends StatelessWidget {
  const _PayAssetSelector({required this.asset, required this.onTap});

  final SwapAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('pay_asset_selector'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwapAssetIcon(asset: asset, size: 32),
            const SizedBox(width: AppSpacing.xs),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.symbol,
                  key: const ValueKey('pay_asset_selector_symbol'),
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  asset.chainLabel,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              AppIcons.doubleArrowVertical,
              size: 16,
              color: colors.icon.regular,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaySkeletonBar extends StatelessWidget {
  const _PaySkeletonBar({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
    );
  }
}
