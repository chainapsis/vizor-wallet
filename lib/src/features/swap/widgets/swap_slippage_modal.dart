import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../models/swap_models.dart';

class SwapSlippageModal extends StatefulWidget {
  const SwapSlippageModal({
    required this.slippageBps,
    required this.onSubmitted,
    required this.onCancel,
    this.initialCustomText,
    super.key,
  });

  final int slippageBps;
  final ValueChanged<int> onSubmitted;
  final VoidCallback onCancel;
  final String? initialCustomText;

  @override
  State<SwapSlippageModal> createState() => _SwapSlippageModalState();
}

class _SwapSlippageModalState extends State<SwapSlippageModal> {
  static const int _minCustomBps = 10;
  static const int _maxCustomBps = 500;

  late int? _selectedPresetBps;
  late TextEditingController _customController;
  late final FocusNode _customFocusNode;

  @override
  void initState() {
    super.initState();
    _initializeSelection(widget.slippageBps);
    _customFocusNode = FocusNode(debugLabel: 'SwapSlippageCustom');
  }

  @override
  void didUpdateWidget(covariant SwapSlippageModal oldWidget) {
    super.didUpdateWidget(oldWidget);
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
            'Slippage',
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
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
          if (_customValueInvalid) ...[
            Text(
              'Slippage must be 0.1 - 5%',
              key: const ValueKey('swap_slippage_error_message'),
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          AppModalActions(
            cancelKey: const ValueKey('swap_slippage_cancel_button'),
            actionKey: const ValueKey('swap_slippage_update_button'),
            actionLabel: 'Update',
            onAction: canSubmit
                ? () {
                    final value = _selectedBps;
                    if (value == null) return;
                    widget.onSubmitted(value);
                  }
                : null,
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _SlippageRadioCard extends StatelessWidget {
  const _SlippageRadioCard({
    required this.bps,
    required this.selected,
    required this.onTap,
  });

  final int bps;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      key: ValueKey('swap_slippage_${bps}bps'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: _slippageRowDecoration(colors, selected: selected),
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
                      formatSwapSlippage(bps),
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: colors.text.accent,
                      ),
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_slippage_custom_card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
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
                    child: Row(
                      children: [
                        Text('Custom', style: fixedLabelStyle),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: inputWidth,
                          height: 18,
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
                        const SizedBox(width: 4),
                        Text(
                          key: const ValueKey('swap_slippage_custom_percent'),
                          '%',
                          style: fixedLabelStyle,
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

/// Filled-row decoration shared by the preset and custom slippage cards.
///
/// Per the redesign each row sits on `Foreground/Neutral/Ground`. Only the
/// selected row gains a 2dp `Border/Neutral/Strong` outline (destructive when
/// the custom value is out of range); unselected rows have no border.
BoxDecoration _slippageRowDecoration(
  AppColors colors, {
  required bool selected,
  bool invalid = false,
}) {
  return BoxDecoration(
    color: colors.background.ground,
    borderRadius: BorderRadius.circular(AppRadii.medium),
    boxShadow: appSurfaceShadow(colors),
    border: selected
        ? Border.all(
            color: invalid
                ? colors.border.utilityDestructive
                : colors.border.strong,
            width: 2,
          )
        : null,
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
  if (paddedWidth > 72) return 72;
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
    if (text.isEmpty || _allowed.hasMatch(text)) return newValue;
    return oldValue;
  }
}
