import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';

/// Mobile slippage editor — Figma `Slippage` (4700:121854 / 4700:123165 /
/// 4700:123470): a serif value that can be nudged with the minus/plus
/// steppers (0.25% within 0.1–5%) OR typed directly via the system
/// keypad. Out-of-range input turns the value and a "Slippage must be
/// 0.1 - 5%" message accent-magenta and disables Update.
class MobileSwapSlippageStepperModal extends StatefulWidget {
  const MobileSwapSlippageStepperModal({
    required this.slippageBps,
    required this.onSubmitted,
    required this.onCancel,
    super.key,
  });

  final int slippageBps;
  final ValueChanged<int> onSubmitted;
  final VoidCallback onCancel;

  @override
  State<MobileSwapSlippageStepperModal> createState() =>
      _MobileSwapSlippageStepperModalState();
}

class _MobileSwapSlippageStepperModalState
    extends State<MobileSwapSlippageStepperModal> {
  static const _minBps = 10; // 0.1%
  static const _maxBps = 500; // 5%
  static const _stepBps = 25; // 0.25%

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// Parsed basis points from the current text, or null when the field is
  /// empty / unparseable.
  int? _bps;

  @override
  void initState() {
    super.initState();
    final initial = widget.slippageBps.clamp(_minBps, _maxBps);
    _bps = initial;
    _controller = TextEditingController(text: _formatBps(initial));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static String _formatBps(int bps) {
    var text = (bps / 100).toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  bool get _inRange => _bps != null && _bps! >= _minBps && _bps! <= _maxBps;
  bool get _canUpdate => _inRange && _bps != widget.slippageBps;

  void _onChanged(String text) {
    final value = double.tryParse(text.trim());
    setState(() => _bps = value == null ? null : (value * 100).round());
  }

  void _step(int direction) {
    final base = (_bps ?? widget.slippageBps).clamp(_minBps, _maxBps);
    final next = (base + direction * _stepBps).clamp(_minBps, _maxBps);
    setState(() {
      _bps = next;
      _controller.text = _formatBps(next);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final invalid = !_inRange;
    // Out-of-range turns the value and message the destructive magenta
    // tone (Figma 4700:123470); in-range stays the primary serif colour.
    final valueColor = invalid ? colors.text.destructive : colors.text.primary;
    // The slippage value reuses the largest display token (40px); the unit
    // suffix sits one step down so it stays proportional.
    final valueStyle = AppTypography.displayLarge.copyWith(color: valueColor);
    final unitStyle = AppTypography.headlineLarge.copyWith(
      color: colors.text.secondary,
    );
    // Content only — hosted in a content-sized MobileSheetScaffold which
    // supplies the grabber, "Slippage" title and close button.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: MobileSheetFormBody(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StepperButton(
                  key: const ValueKey('mobile_swap_slippage_minus'),
                  label: '-',
                  enabled: (_bps ?? _minBps) > _minBps,
                  onTap: () => _step(-1),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: IntrinsicWidth(
                          child: TextField(
                            key: const ValueKey('mobile_swap_slippage_value'),
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _onChanged,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              // The decimal-pad key follows the device
                              // locale; normalise a comma to the period the
                              // filter keeps.
                              const CommaToDotInputFormatter(),
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            style: valueStyle,
                            cursorColor: colors.text.accent,
                            cursorWidth: 2,
                            cursorRadius: const Radius.circular(AppRadii.full),
                            decoration: const InputDecoration.collapsed(
                              hintText: '0',
                            ),
                          ),
                        ),
                      ),
                      Text(' %', style: unitStyle),
                    ],
                  ),
                ),
                _StepperButton(
                  key: const ValueKey('mobile_swap_slippage_plus'),
                  label: '+',
                  enabled: (_bps ?? _maxBps) < _maxBps,
                  onTap: () => _step(1),
                ),
              ],
            ),
            if (invalid) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                'Slippage must be 0.1 - 5%',
                key: const ValueKey('mobile_swap_slippage_error'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
          ],
        ),
        actions: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(
              key: const ValueKey('swap_slippage_update_button'),
              expand: true,
              onPressed: _canUpdate ? () => widget.onSubmitted(_bps!) : null,
              child: const Text('Update'),
            ),
            const SizedBox(height: AppSpacing.s),
            Semantics(
              button: true,
              child: GestureDetector(
                key: const ValueKey('swap_slippage_cancel_button'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onCancel,
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.background.raised,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.headlineMedium.copyWith(
                color: enabled ? colors.text.accent : colors.text.disabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
