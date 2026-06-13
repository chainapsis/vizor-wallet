import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../models/swap_models.dart';
import 'swap_modal_controls.dart';

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

    return Container(
      key: const ValueKey('swap_slippage_modal'),
      width: 312,
      height: 398,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SwapModalIconBadge(
                iconName: AppIcons.cog,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Text(
                'Slippage',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (final bps in swapSlippagePresetBps) ...[
            _SlippageRadioCard(
              bps: bps,
              height: bps == swapSlippagePresetBps.first ? 34 : 40,
              selected: _selectedPresetBps == bps,
              onTap: () => _selectPreset(bps),
            ),
            if (bps != swapSlippagePresetBps.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _SlippageCustomRadioCard(
            controller: _customController,
            focusNode: _customFocusNode,
            selected: _customSelected,
            invalid: _customValueInvalid,
            onTap: _selectCustom,
            onChanged: _handleCustomChanged,
          ),
          const Spacer(),
          SwapModalButtons(
            primaryKey: const ValueKey('swap_slippage_update_button'),
            cancelKey: const ValueKey('swap_slippage_cancel_button'),
            primaryLabel: _customValueInvalid
                ? 'Slippage must be 0.1 - 5%'
                : 'Update',
            primaryEnabled: canSubmit,
            onPrimary: () {
              final value = _selectedBps;
              if (value == null) return;
              widget.onSubmitted(value);
            },
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
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final int bps;
  final double height;
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
          height: height,
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.regular,
              width: selected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
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
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ),
              Container(
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
                    ? AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.icon.inverse,
                      )
                    : null,
              ),
            ],
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
    final borderColor = invalid
        ? colors.border.utilityDestructive
        : selected
        ? colors.border.strong
        : colors.border.regular;
    final valueColor = invalid ? colors.text.destructive : colors.text.accent;
    final valueStyle = AppTypography.labelLarge.copyWith(color: valueColor);
    final hintStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent.withValues(alpha: 0.4),
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
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
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
                      Text(
                        'Custom',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
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
                            // The decimal-pad key follows the device
                            // locale; normalise a comma to a period first.
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
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
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
                    ? AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.icon.inverse,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
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

