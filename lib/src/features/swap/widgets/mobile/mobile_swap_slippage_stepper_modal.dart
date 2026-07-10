import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextEditingValue, TextInputFormatter;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';

/// Mobile slippage editor — Figma `Slippage` (`_Modal Type` 4755:84761): a
/// 60px Young Serif value flanked by 60×50 minus/plus pills (0.1% steps within
/// 0.1–5%), or typed directly via the system keypad, capped at two decimal
/// places. Out-of-range input turns the value and a "Slippage must be 0.1 - 5%"
/// message destructive and disables Update. The body is a fixed 160px so the
/// gap down to the Update button stays constant.
class MobileSwapSlippageStepperModal extends StatefulWidget {
  const MobileSwapSlippageStepperModal({
    required this.slippageBps,
    required this.onSubmitted,
    required this.onCancel,
    this.paymentMode = false,
    super.key,
  });

  final int slippageBps;
  final ValueChanged<int> onSubmitted;
  final VoidCallback onCancel;

  /// Pay flow variant — mirrors [SwapSlippageModal.paymentMode]: prepends the
  /// quote-movement explainer above the stepper.
  final bool paymentMode;

  @override
  State<MobileSwapSlippageStepperModal> createState() =>
      _MobileSwapSlippageStepperModalState();
}

class _MobileSwapSlippageStepperModalState
    extends State<MobileSwapSlippageStepperModal> {
  static const _minBps = 10; // 0.1%
  static const _maxBps = 500; // 5%
  static const _stepBps = 10; // 0.1%

  /// Figma `Body` is a fixed 160px tall area that centers the stepper.
  static const _bodyHeight = 160.0;

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
    // Out-of-range turns the value the destructive tone; in-range it is the
    // bright accent serif (Figma value = text.accent, not a dimmed primary).
    final valueColor = invalid ? colors.text.destructive : colors.text.accent;

    return MobileModalScaffold(
      title: 'Slippage',
      onClose: widget.onCancel,
      // _Modal Type slippage variant: pb-16 (vs the default 24).
      bottomPadding: AppSpacing.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.paymentMode) ...[
            Text(
              'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            height: _bodyHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                                  key: const ValueKey(
                                    'mobile_swap_slippage_value',
                                  ),
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  autofocus: true,
                                  onChanged: _onChanged,
                                  textAlign: TextAlign.center,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    // The decimal-pad key follows the device
                                    // locale; normalise a comma to the period
                                    // the filter keeps.
                                    const CommaToDotInputFormatter(),
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]'),
                                    ),
                                    // Cap at two decimal places (1.55 ok,
                                    // 1.555 rejected).
                                    const _TwoDecimalInputFormatter(),
                                  ],
                                  // Figma: 60px Young Serif Medium value.
                                  style: AppTypography.displayLarge.copyWith(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 60,
                                    height: 1,
                                    color: valueColor,
                                  ),
                                  cursorColor: colors.text.accent,
                                  cursorWidth: 2,
                                  cursorRadius: const Radius.circular(
                                    AppRadii.full,
                                  ),
                                  decoration: const InputDecoration.collapsed(
                                    hintText: '0',
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              ' %',
                              // Figma: 45px Young Serif Medium, secondary.
                              style: AppTypography.displayLarge.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: 45,
                                height: 1,
                                color: colors.text.secondary,
                              ),
                            ),
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
                  // Reserve the error line (Figma keeps an opacity-0 slot) so
                  // the stepper stays put whether or not it shows.
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 16,
                    child: invalid
                        ? Text(
                            'Slippage must be 0.1 - 5%',
                            key: const ValueKey('mobile_swap_slippage_error'),
                            textAlign: TextAlign.center,
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.text.destructive,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          // _Modal Type: 16px gap from the body to the buttons stack.
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('swap_slippage_update_button'),
            expand: true,
            onPressed: _canUpdate ? () => widget.onSubmitted(_bps!) : null,
            child: const Text('Update'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('swap_slippage_cancel_button'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
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
          // Mobile button rhythm: 60×50 secondary pill.
          width: 60,
          height: AppButtonSizing.largeHeight,
          decoration: BoxDecoration(
            color: colors.button.secondary.bg,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Center(
            child: Text(
              label,
              // "+"/"-" are centered on the math axis, so the default
              // `proportional` leading (which biases toward the larger ascent)
              // drops the glyph low. `even` splits the line leading equally so
              // the glyph sits dead-center in the 44px pill.
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w500,
                fontSize: 24,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
                color: enabled
                    ? colors.button.secondary.label
                    : colors.text.disabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rejects any candidate with more than two decimal places (1.55 ok,
/// 1.555 rejected) by restoring [oldValue] — same approach as
/// `_DecimalAmountInputFormatter` in the composer ticket, pinned to two
/// fraction digits for the slippage percentage.
class _TwoDecimalInputFormatter extends TextInputFormatter {
  const _TwoDecimalInputFormatter();

  static final _pattern = RegExp(r'^\d*(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    return _pattern.hasMatch(text) ? newValue : oldValue;
  }
}
