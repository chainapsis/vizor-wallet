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

const _payAmountSkeletonPeriod = Duration(milliseconds: 1200);

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
    super.key,
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
    final inputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final precisionError = state.quoteAmountPrecisionError;
    final quoteError =
        precisionError ?? state.externalAssetSupportError ?? state.quoteError;
    final counterpartText = inputIsFiat
        ? (state.receiveAmountText.trim().isEmpty
              ? null
              : '${state.receiveAmountText.trim()} ${asset.symbol}')
        : (state.receiveFiatText.trim().isEmpty
              ? null
              : state.receiveFiatText.trim());
    final inputText = inputIsFiat
        ? state.receiveFiatText.trim()
        : state.receiveAmountText.trim();
    final hasInput = inputText.isNotEmpty;
    final counterpartLoading = hasInput && state.pricingLoading;
    final estimatedZecText = state.amountText.trim();
    final estimatedSpendLoading = hasInput && state.pricingLoading;

    return Padding(
      key: const ValueKey('pay_amount_step'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('pay_amount_card'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.xLarge),
              boxShadow: appSurfaceShadow(colors),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      Text(
                        'Paying in',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.text.secondary,
                        ),
                      ),
                      const Spacer(),
                      _PayAssetSelector(
                        asset: asset,
                        onTap: onOpenAssetSelector,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  height: 132,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 64,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxInputWidth = (constraints.maxWidth - 120)
                                .clamp(56.0, 240.0)
                                .toDouble();
                            return AnimatedBuilder(
                              animation: controller,
                              builder: (context, _) {
                                final amountStyle = AppTypography.displayLarge
                                    .copyWith(color: colors.text.accent);
                                final inputWidth = payAmountInputWidth(
                                  context: context,
                                  text: controller.text,
                                  style: amountStyle,
                                  maxWidth: maxInputWidth,
                                );
                                return Row(
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
                                          hintStyle: AppTypography.displayLarge
                                              .copyWith(
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
                                        style: AppTypography.displaySmall
                                            .copyWith(color: colors.text.muted),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MouseRegion(
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
                              if (!hasInput)
                                Text(
                                  inputIsFiat ? '0 ${asset.symbol}' : r'$ 0',
                                  key: const ValueKey('pay_amount_counterpart'),
                                  style: AppTypography.labelLarge.copyWith(
                                    fontWeight: FontWeight.w400,
                                    color: colors.text.secondary,
                                  ),
                                )
                              else if (!counterpartLoading)
                                Text(
                                  inputIsFiat
                                      ? counterpartText ?? '-- ${asset.symbol}'
                                      : '\$${counterpartText ?? '--'}',
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
                                const _PaySkeletonBar(
                                  key: ValueKey(
                                    'pay_amount_counterpart_loading',
                                  ),
                                  width: 48,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  height: 56,
                  child: Row(
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
                            if (estimatedSpendLoading)
                              const _PaySkeletonBar(
                                key: ValueKey('pay_estimated_spend_loading'),
                                width: 48,
                              )
                            else
                              Text(
                                estimatedZecText.isEmpty
                                    ? (hasInput ? '--' : '0')
                                    : estimatedZecText,
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
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Paying from your',
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.text.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppIcon(
                      AppIcons.shieldKeyhole,
                      size: 20,
                      color: colors.icon.regular,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Shielded balance',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
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
        ],
      ),
    );
  }
}

/// Bottom-pinned action for the Amount step.
class PayAmountAction extends StatelessWidget {
  const PayAmountAction({
    required this.state,
    required this.onContinue,
    super.key,
  });

  final SwapState state;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('pay_amount_continue_button'),
      variant: AppButtonVariant.primary,
      size: AppButtonSize.large,
      minWidth: 196,
      onPressed: payAmountCanContinue(state) ? onContinue : null,
      child: const Text('Continue'),
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

class _PaySkeletonBar extends StatefulWidget {
  const _PaySkeletonBar({required this.width, super.key});

  final double width;

  @override
  State<_PaySkeletonBar> createState() => _PaySkeletonBarState();
}

class _PaySkeletonBarState extends State<_PaySkeletonBar>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(
      vsync: this,
      duration: _payAmountSkeletonPeriod,
    );
  }

  bool get _shouldAnimate {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    return TickerMode.valuesOf(context).enabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _controller;
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) _activeController.repeat();
      return;
    }
    if (controller != null) {
      controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.background.overlay.withValues(alpha: 0.15);
    final highlightColor = colors.background.raised;
    return SizedBox(
      width: widget.width,
      height: 12,
      child: _shouldAnimate
          ? AnimatedBuilder(
              animation: _activeController,
              builder: (context, _) => CustomPaint(
                painter: _PaySkeletonPainter(
                  progress: _activeController.value,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
              ),
            )
          : CustomPaint(
              painter: _PaySkeletonPainter(
                progress: 0,
                baseColor: baseColor,
                highlightColor: highlightColor,
                animate: false,
              ),
            ),
    );
  }
}

class _PaySkeletonPainter extends CustomPainter {
  const _PaySkeletonPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
    this.animate = true,
  });

  final double progress;
  final Color baseColor;
  final Color highlightColor;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(AppRadii.full));
    if (!animate) {
      final shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [highlightColor, baseColor],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = shader);
      return;
    }

    canvas.drawRRect(rrect, Paint()..color = baseColor);
    canvas.save();
    canvas.clipRRect(rrect);
    final sweepWidth = size.width * 1.6;
    final left = -sweepWidth + progress * (size.width + sweepWidth);
    final sweepRect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        baseColor.withValues(alpha: 0),
        highlightColor,
        baseColor.withValues(alpha: 0),
      ],
      stops: const [0, 0.5, 1],
    ).createShader(sweepRect);
    canvas.drawRect(sweepRect, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PaySkeletonPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        baseColor != oldDelegate.baseColor ||
        highlightColor != oldDelegate.highlightColor ||
        animate != oldDelegate.animate;
  }
}
