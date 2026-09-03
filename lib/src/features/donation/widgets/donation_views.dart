import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/send_review_layout.dart';

enum DonationAmountMode { zec, usd }

class DonationComposeView extends StatelessWidget {
  const DonationComposeView({
    required this.controller,
    required this.mode,
    required this.conversionText,
    required this.selectedPreset,
    required this.onAmountChanged,
    required this.onToggleMode,
    required this.onPresetSelected,
    required this.onContinue,
    this.errorText,
    this.isSubmitting = false,
    super.key,
  });

  final TextEditingController controller;
  final DonationAmountMode mode;
  final String conversionText;
  final String? selectedPreset;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onToggleMode;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback? onContinue;
  final String? errorText;
  final bool isSubmitting;

  static const zecPresets = ['0.02', '0.03', '0.06', '0.12'];
  static const usdPresets = ['15', '25', '50', '100'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isUsd = mode == DonationAmountMode.usd;
    final presets = isUsd ? usdPresets : zecPresets;
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: AppWindowSizing.contentAreaMaxWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
              ).copyWith(top: AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Support Vizor',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: 56),
                  _DonationAmountCard(
                    controller: controller,
                    isUsd: isUsd,
                    conversionText: conversionText,
                    errorText: errorText,
                    onChanged: onAmountChanged,
                    onToggleMode: onToggleMode,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final preset in presets)
                        _DonationPreset(
                          label: isUsd ? '\$$preset' : '$preset ZEC',
                          selected: selectedPreset == preset,
                          onTap: () => onPresetSelected(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 28,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Sending from your',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        AppIcon(
                          AppIcons.shieldKeyhole,
                          size: 20,
                          color: colors.icon.accent,
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
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.sm,
          child: Center(
            child: AppButton(
              key: const ValueKey('donation_continue_button'),
              minWidth: 196,
              onPressed: onContinue,
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DonationAmountCard extends StatelessWidget {
  const _DonationAmountCard({
    required this.controller,
    required this.isUsd,
    required this.conversionText,
    required this.errorText,
    required this.onChanged,
    required this.onToggleMode,
  });

  final TextEditingController controller;
  final bool isUsd;
  final String conversionText;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onToggleMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 248,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(32),
        boxShadow: appSurfaceShadow(colors),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        top: AppSpacing.md,
        right: AppSpacing.sm,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                SizedBox(
                  width: 266,
                  height: 28,
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: Center(
                          child: AppIcon(
                            AppIcons.donation,
                            size: 16.5,
                            color: colors.icon.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          'Enter your amount',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 90,
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/icons/network_zec.png',
                            width: 32,
                            height: 32,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        SizedBox(
                          width: 42,
                          height: 36,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRect(
                                child: SizedBox(
                                  height: AppSpacing.sm,
                                  child: Text(
                                    'ZEC',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              ClipRect(
                                child: SizedBox(
                                  height: AppSpacing.sm,
                                  child: Text(
                                    'Zcash',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.secondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            height: 132,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                _DonationAmountEditor(
                  controller: controller,
                  isUsd: isUsd,
                  hasError: errorText != null,
                  onChanged: onChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                GestureDetector(
                  onTap: onToggleMode,
                  child: SizedBox(
                    height: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          AppIcons.doubleArrowVertical,
                          size: 20,
                          color: colors.icon.muted,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          conversionText,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: AppSpacing.sm,
                  child: errorText == null
                      ? null
                      : Center(
                          child: Text(
                            errorText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.text.destructive,
                            ),
                          ),
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

class _DonationAmountEditor extends StatefulWidget {
  const _DonationAmountEditor({
    required this.controller,
    required this.isUsd,
    required this.hasError,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isUsd;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  State<_DonationAmountEditor> createState() => _DonationAmountEditorState();
}

class _DonationAmountEditorState extends State<_DonationAmountEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _DonationAmountEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() => setState(() {});

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = AppTypography.displayLarge.copyWith(
      color: widget.hasError ? colors.text.destructive : colors.text.accent,
    );
    final hintStyle = AppTypography.displayLarge.copyWith(
      color: widget.hasError ? colors.text.destructive : colors.text.muted,
    );
    final unitStyle = AppTypography.headlineLarge.copyWith(
      color: widget.hasError ? colors.text.destructive : colors.text.muted,
    );
    final measuredText = widget.controller.text.isEmpty
        ? '0'
        : widget.controller.text;
    final measuredStyle = widget.controller.text.isEmpty
        ? hintStyle
        : valueStyle;
    final inputWidth = (_textWidth(context, measuredText, measuredStyle) + 3)
        .clamp(30.0, 190.0);

    return SizedBox(
      height: 64,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: inputWidth,
              child: TextField(
                key: const ValueKey('donation_amount_field'),
                controller: widget.controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  _DonationAmountInputFormatter(isUsd: widget.isUsd),
                ],
                onChanged: widget.onChanged,
                style: valueStyle,
                decoration: InputDecoration.collapsed(
                  hintText: '0',
                  hintStyle: hintStyle,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(widget.isUsd ? 'USD' : 'ZEC', style: unitStyle),
          ],
        ),
      ),
    );
  }
}

class _DonationAmountInputFormatter extends TextInputFormatter {
  const _DonationAmountInputFormatter({required this.isUsd});

  final bool isUsd;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue.copyWith(text: text);

    final buffer = StringBuffer();
    var hasDecimal = false;
    for (final codeUnit in text.codeUnits) {
      final character = String.fromCharCode(codeUnit);
      if (character == '.') {
        if (hasDecimal) continue;
        hasDecimal = true;
        buffer.write(character);
      } else if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        buffer.write(character);
      }
    }

    text = buffer.toString();
    if (text.startsWith('.')) text = '0$text';
    final maxLength = isUsd ? 12 : 17;
    if (text.length > maxLength) text = text.substring(0, maxLength);
    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0) {
      final maxEnd = decimalIndex + 1 + (isUsd ? 2 : 8);
      if (text.length > maxEnd) text = text.substring(0, maxEnd);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DonationPreset extends StatelessWidget {
  const _DonationPreset({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background.ground,
          border: selected
              ? Border.all(color: colors.border.strong, width: 2)
              : null,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ),
    );
  }
}

class DonationVizorBadge extends StatelessWidget {
  const DonationVizorBadge({this.size = 32, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            'assets/illustrations/donation_vizor_badge_bg.svg',
            width: size * .9375,
            height: size * .9375,
          ),
          Positioned(
            left: size * .125,
            top: size * .0625,
            child: ClipOval(
              child: Image.asset(
                'assets/illustrations/donation_vizor_knight.png',
                width: size * .71875,
                height: size * .78125,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DonationReviewContentView extends StatelessWidget {
  const DonationReviewContentView({
    required this.amountText,
    required this.fiatText,
    required this.feeText,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.onConfirm,
    super.key,
  });

  final String amountText;
  final String? fiatText;
  final String feeText;
  final String confirmLabel;
  final String confirmIcon;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 656,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SendReviewContentColumn(
            title: 'Review Amount',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Column(
                  children: [
                    ReviewInfoRow(
                      label: 'Amount',
                      value: amountText,
                      leading: const ReviewZecCoinImage(),
                      bottomLeftText: fiatText,
                    ),
                    const ReviewConnectorIcon(iconName: AppIcons.arrowDown),
                    const ReviewInfoRow(
                      label: 'Donating to',
                      value: 'Vizor Wallet',
                      leading: DonationVizorBadge(),
                      reserveBottomRow: false,
                    ),
                  ],
                ),
              ),
              ReviewWrapCard(
                children: [
                  ReviewListRow(
                    label: 'Tx fee',
                    value: feeText,
                    trailingIconName: AppIcons.help,
                    trailingIconColor: colors.text.secondary,
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.sm,
            child: Center(
              child: AppButton(
                key: const ValueKey('donation_confirm_button'),
                minWidth: 196,
                leading: AppIcon(confirmIcon),
                onPressed: onConfirm,
                child: Text(confirmLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DonationSuccessBackground extends StatelessWidget {
  const DonationSuccessBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        height: 520,
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x26000000), Color(0x00000000)],
            stops: [.27, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: Image.asset(
            'assets/illustrations/donation_success_background.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class DonationSuccessView extends StatelessWidget {
  const DonationSuccessView({required this.onDone, super.key});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DonationHeartBadge(),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: 302,
              child: Text(
                'Thank you for supporting Vizor',
                textAlign: TextAlign.center,
                style: AppTypography.displayLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: 216,
              child: Text(
                'Your support keeps Vizor going.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('donation_done_button'),
              onPressed: onDone,
              minWidth: 96,
              size: AppButtonSize.mediumLarge,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationHeartBadge extends StatelessWidget {
  const _DonationHeartBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            'assets/illustrations/donation_success_heart.svg',
            width: 50,
            height: 46,
          ),
          Positioned(
            top: 6,
            child: ClipOval(
              child: Image.asset(
                'assets/illustrations/donation_vizor_knight.png',
                width: 35,
                height: 38,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
