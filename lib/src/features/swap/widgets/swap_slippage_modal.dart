import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/locale_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../core/widgets/decimal_amount_input_formatter.dart';
import '../models/swap_models.dart';
import 'swap_confidential_ui.dart';

/// Quote settings for swap and Pay: the confidential route, then slippage.
/// Update applies both together; Cancel leaves both as they were.
class SwapSlippageModal extends StatefulWidget {
  const SwapSlippageModal({
    required this.slippageBps,
    required this.confidential,
    required this.onSubmitted,
    required this.onCancel,
    this.initialCustomText,
    this.paymentMode = false,
    super.key,
  });

  final int slippageBps;
  final bool confidential;
  final void Function(int slippageBps, bool confidential) onSubmitted;
  final VoidCallback onCancel;
  final String? initialCustomText;
  final bool paymentMode;

  @override
  State<SwapSlippageModal> createState() => _SwapSlippageModalState();
}

class _SwapSlippageModalState extends State<SwapSlippageModal> {
  static const int _minCustomBps = 10;
  static const int _maxCustomBps = 500;

  late int? _selectedPresetBps;
  late TextEditingController _customController;
  late final FocusNode _customFocusNode;
  late bool _confidential = widget.confidential;

  @override
  void initState() {
    super.initState();
    _initializeSelection(widget.slippageBps);
    _customFocusNode = FocusNode(debugLabel: 'SwapSlippageCustom');
    _customFocusNode.addListener(_handleCustomFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SwapSlippageModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.confidential != widget.confidential) {
      _confidential = widget.confidential;
    }
    if (oldWidget.slippageBps == widget.slippageBps &&
        oldWidget.initialCustomText == widget.initialCustomText) {
      return;
    }
    _customController.dispose();
    _initializeSelection(widget.slippageBps);
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  void _initializeSelection(int slippageBps) {
    final initialCustomText = widget.initialCustomText;
    if (initialCustomText != null) {
      _selectedPresetBps = null;
      _customController = TextEditingController(text: initialCustomText);
      return;
    }
    final normalized = slippageBps.clamp(_minCustomBps, _maxCustomBps).toInt();
    if (swapSlippagePresetBps.contains(normalized)) {
      _selectedPresetBps = normalized;
      _customController = TextEditingController();
      return;
    }
    _selectedPresetBps = null;
    _customController = TextEditingController(
      text: formatSwapSlippageValue(normalized),
    );
  }

  void _selectPreset(int bps) {
    setState(() {
      _selectedPresetBps = bps;
      _customFocusNode.unfocus();
    });
  }

  void _selectCustom() {
    setState(() => _selectedPresetBps = null);
    _customFocusNode.requestFocus();
  }

  void _handleCustomChanged(String _) {
    if (_selectedPresetBps == null) {
      setState(() {});
      return;
    }
    setState(() => _selectedPresetBps = null);
  }

  void _handleCustomFocusChanged() {
    if (_customFocusNode.hasFocus && _selectedPresetBps != null) {
      setState(() => _selectedPresetBps = null);
    }
  }

  int? get _customBps {
    final text = _customController.text.trim();
    if (text.isEmpty || text == '.') return null;
    final percent = double.tryParse(text);
    if (percent == null) return null;
    return (percent * 100).round();
  }

  bool get _customSelected => _selectedPresetBps == null;

  bool get _customValueInvalid {
    if (!_customSelected || _customController.text.trim().isEmpty) return false;
    final bps = _customBps;
    return bps == null || bps < _minCustomBps || bps > _maxCustomBps;
  }

  int? get _selectedBps {
    if (_selectedPresetBps != null) return _selectedPresetBps;
    final bps = _customBps;
    if (bps == null || bps < _minCustomBps || bps > _maxCustomBps) {
      return null;
    }
    return bps;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedBps = _selectedBps;
    final canSubmit = selectedBps != null;

    return AppModalCard(
      key: const ValueKey('swap_slippage_modal'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.paymentMode
                ? context.l10n.swapSettingsTitlePay
                : context.l10n.swapSettingsTitleSwap,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The confidential setting makes the body taller than a short window
          // or large text allows, so it scrolls between the fixed title and
          // actions.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwapConfidentialSetting(
                    confidential: _confidential,
                    onChanged: (value) => setState(() => _confidential = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(height: 1, color: colors.border.regular),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.swapSlippageTitle,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final bps in swapSlippagePresetBps) ...[
                    _SlippageRadioCard(
                      bps: bps,
                      selected: _selectedPresetBps == bps,
                      onTap: () => _selectPreset(bps),
                    ),
                    if (bps != swapSlippagePresetBps.last)
                      const SizedBox(height: AppSpacing.xs),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  _SlippageCustomRadioCard(
                    controller: _customController,
                    focusNode: _customFocusNode,
                    selected: _customSelected,
                    invalid: _customValueInvalid,
                    onTap: _selectCustom,
                    onChanged: _handleCustomChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SlippageValidationMessage(visible: _customValueInvalid),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          AppModalActions(
            cancelKey: const ValueKey('swap_slippage_cancel_button'),
            actionKey: const ValueKey('swap_slippage_update_button'),
            actionLabel: context.l10n.commonUpdate,
            onAction: canSubmit
                ? () {
                    final value = _selectedBps;
                    if (value == null) return;
                    widget.onSubmitted(value, _confidential);
                  }
                : null,
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _SlippageValidationMessage extends StatelessWidget {
  const _SlippageValidationMessage({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = withLocaleFontFallback(
      context,
      AppTypography.bodySmall.copyWith(color: colors.text.destructive),
    );
    final message = context.l10n.swapSlippageRangeError;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: message, style: style),
          textDirection: Directionality.of(context),
          textAlign: TextAlign.center,
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final reservedHeight = painter.height;
        painter.dispose();

        return SizedBox(
          height: reservedHeight,
          width: double.infinity,
          child: visible
              ? Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const ValueKey('swap_slippage_error_message'),
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _SlippageRadioCard extends StatefulWidget {
  const _SlippageRadioCard({
    required this.bps,
    required this.selected,
    required this.onTap,
  });

  final int bps;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SlippageRadioCard> createState() => _SlippageRadioCardState();
}

class _SlippageRadioCardState extends State<_SlippageRadioCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      key: ValueKey('swap_slippage_${widget.bps}bps'),
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          container: true,
          inMutuallyExclusiveGroup: true,
          checked: widget.selected,
          label: context.l10n.swapSlippagePresetSemantics(
            formatSwapSlippage(widget.bps),
          ),
          onTap: widget.onTap,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: _slippageRowDecoration(
                  colors,
                  selected: widget.selected,
                ),
                foregroundDecoration: _slippageFocusDecoration(
                  colors,
                  focused: _focused,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            formatSwapSlippage(widget.bps),
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: widget.selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                      ),
                      _SlippageRadioIndicator(selected: widget.selected),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlippageCustomRadioCard extends StatelessWidget {
  const _SlippageCustomRadioCard({
    required this.controller,
    required this.focusNode,
    required this.selected,
    required this.invalid,
    required this.onTap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool selected;
  final bool invalid;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueColor = invalid ? colors.text.destructive : colors.text.accent;
    // The entered value uses Geist Regular; label / suffix stay SemiBold.
    final valueStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w400,
      color: valueColor,
    );
    final hintStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.text.accent.withValues(alpha: 0.4),
    );
    final fixedLabelStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w600,
      color: invalid ? colors.text.destructive : colors.text.accent,
    );
    final inputWidth = _slippageInputWidth(
      context,
      text: controller.text,
      valueStyle: valueStyle,
      hintStyle: hintStyle,
    );
    final stackInput = MediaQuery.textScalerOf(context).scale(14) > 18.2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_slippage_custom_card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          decoration: _slippageRowDecoration(
            colors,
            selected: selected,
            invalid: invalid,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: stackInput
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.swapSlippageCustom,
                                key: const ValueKey(
                                  'swap_slippage_custom_label',
                                ),
                                style: fixedLabelStyle,
                              ),
                              const SizedBox(height: 4),
                              _SlippageCustomValueInput(
                                width: inputWidth,
                                controller: controller,
                                focusNode: focusNode,
                                onTap: onTap,
                                onChanged: onChanged,
                                valueStyle: valueStyle,
                                hintStyle: hintStyle,
                                fixedLabelStyle: fixedLabelStyle,
                                valueColor: valueColor,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Text(
                                context.l10n.swapSlippageCustom,
                                key: const ValueKey(
                                  'swap_slippage_custom_label',
                                ),
                                style: fixedLabelStyle,
                              ),
                              const SizedBox(width: 4),
                              _SlippageCustomValueInput(
                                width: inputWidth,
                                controller: controller,
                                focusNode: focusNode,
                                onTap: onTap,
                                onChanged: onChanged,
                                valueStyle: valueStyle,
                                hintStyle: hintStyle,
                                fixedLabelStyle: fixedLabelStyle,
                                valueColor: valueColor,
                              ),
                            ],
                          ),
                  ),
                ),
                _SlippageRadioIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlippageCustomValueInput extends StatelessWidget {
  const _SlippageCustomValueInput({
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    required this.valueStyle,
    required this.hintStyle,
    required this.fixedLabelStyle,
    required this.valueColor,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final TextStyle valueStyle;
  final TextStyle hintStyle;
  final TextStyle fixedLabelStyle;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          child: Semantics(
            label: context.l10n.swapSlippageCustomValueSemantics,
            child: TextField(
              key: const ValueKey('swap_slippage_custom_input'),
              controller: controller,
              focusNode: focusNode,
              onTap: onTap,
              onChanged: onChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [
                CommaToDotInputFormatter(),
                _SlippageCustomInputFormatter(),
              ],
              style: valueStyle,
              textAlign: TextAlign.right,
              cursorColor: valueColor,
              decoration: InputDecoration.collapsed(
                hintText: '0.1-5',
                hintStyle: hintStyle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          key: const ValueKey('swap_slippage_custom_percent'),
          '%',
          style: fixedLabelStyle,
        ),
      ],
    );
  }
}

/// Filled-row decoration shared by the preset and custom slippage cards.
///
/// Per the redesign each row sits on `Foreground/Neutral/Ground`. Every row
/// reserves the same 2dp outline; it is transparent until selected or focused.
BoxDecoration _slippageRowDecoration(
  AppColors colors, {
  required bool selected,
  bool invalid = false,
}) {
  return BoxDecoration(
    color: colors.background.ground,
    borderRadius: BorderRadius.circular(AppRadii.medium),
    boxShadow: appSurfaceShadow(colors),
    border: Border.all(
      color: selected
          ? invalid
                ? colors.border.utilityDestructive
                : colors.border.strong
          : const Color(0x00000000),
      width: 2,
    ),
  );
}

BoxDecoration? _slippageFocusDecoration(
  AppColors colors, {
  required bool focused,
}) {
  if (!focused) return null;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(AppRadii.medium),
    border: Border.all(
      color: colors.state.focusRing,
      width: 2,
      strokeAlign: BorderSide.strokeAlignOutside,
    ),
  );
}

/// 16dp circular radio indicator: filled with `Foreground/Neutral/Inverse`
/// plus a 12dp check when selected, otherwise a subtle empty circle.
class _SlippageRadioIndicator extends StatelessWidget {
  const _SlippageRadioIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: selected
          ? AppIcon(AppIcons.check, size: 12, color: colors.icon.inverse)
          : null,
    );
  }
}

double _slippageInputWidth(
  BuildContext context, {
  required String text,
  required TextStyle valueStyle,
  required TextStyle hintStyle,
}) {
  final hintWidth = _measureSlippageInputWidth(
    context,
    text: '0.1-5',
    style: hintStyle,
  );
  final valueWidth = text.isEmpty
      ? 0.0
      : _measureSlippageInputWidth(context, text: text, style: valueStyle);
  final measuredWidth = hintWidth > valueWidth ? hintWidth : valueWidth;
  final paddedWidth = measuredWidth.ceilToDouble() + 6;
  if (paddedWidth < 38) return 38;
  if (paddedWidth > 120) return 120;
  return paddedWidth;
}

double _measureSlippageInputWidth(
  BuildContext context, {
  required String text,
  required TextStyle style,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _SlippageCustomInputFormatter extends TextInputFormatter {
  const _SlippageCustomInputFormatter();

  static final RegExp _allowed = RegExp(r'^\d{0,3}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isNotEmpty && !_allowed.hasMatch(text)) return oldValue;
    return const DecimalAmountInputFormatter(
      maxFractionDigits: 2,
    ).formatEditUpdate(oldValue, newValue);
  }
}
