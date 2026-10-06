import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';

/// Mobile slippage editor — Figma `Slippage` (`_Modal Type` 4755:84761): a
/// 60px Young Serif value flanked by 60×50 minus/plus pills (0.1% steps within
/// 0.1–5%), or typed directly via the system keypad, capped at two decimal
/// places. Out-of-range input turns the value and a "Slippage must be 0.1 - 5%"
/// message destructive and disables Update. The stepper keeps its 160px body;
/// guidance and input scroll together when the keyboard limits the space.
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

  /// Pay flow variant — mirrors [SwapSlippageModal.paymentMode] with the
  /// extra-ZEC explanation instead of Swap's rate-change explanation.
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
  final GlobalKey _stepperKey = GlobalKey();
  double _keyboardInset = 0;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset == _keyboardInset) return;
    _keyboardInset = inset;
    if (inset > 0) {
      // Opening the keyboard shrinks the scroll viewport after autofocus.
      // Reveal the whole input row, including the adjacent stepper buttons.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final stepperContext = _stepperKey.currentContext;
        if (mounted && _keyboardInset > 0 && stepperContext != null) {
          Scrollable.ensureVisible(stepperContext, alignment: 0.5);
        }
      });
    }
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
      constrainBody: true,
      // _Modal Type slippage variant: pb-16 (vs the default 24).
      bottomPadding: AppSpacing.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.paymentMode
                        ? 'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.'
                        : "Sets the maximum rate change you'll accept. Network fees are separate.",
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: _bodyHeight,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            key: _stepperKey,
                            children: [
                              _StepperButton(
                                key: const ValueKey(
                                  'mobile_swap_slippage_minus',
                                ),
                                label: '-',
                                enabled: (_bps ?? _minBps) > _minBps,
                                onTap: () => _step(-1),
                              ),
                              Expanded(
                                child: _buildValueInput(context, valueColor),
                              ),
                              _StepperButton(
                                key: const ValueKey(
                                  'mobile_swap_slippage_plus',
                                ),
                                label: '+',
                                enabled: (_bps ?? _maxBps) < _maxBps,
                                onTap: () => _step(1),
                              ),
                            ],
                          ),
                          // Reserve the error line (Figma keeps an opacity-0 slot) so
                          // the stepper stays put whether or not it shows.
                          const SizedBox(height: AppSpacing.sm),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 16),
                            child: invalid
                                ? Text(
                                    'Slippage must be 0.1 - 5%',
                                    key: const ValueKey(
                                      'mobile_swap_slippage_error',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: AppTypography.labelMedium.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: colors.text.destructive,
                                    ),
                                  )
                                : const SizedBox(height: 16),
                          ),
                        ],
                      ),
                    ),
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

  Widget _buildValueInput(BuildContext context, Color valueColor) {
    final valueStyle = AppTypography.displayLarge.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 60,
      height: 1,
      color: valueColor,
    );
    final percentStyle = valueStyle.copyWith(
      fontSize: 45,
      color: context.colors.text.secondary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = _controller.text.isEmpty ? '0' : _controller.text;
        double widthOf(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        double widthAt(double scale) =>
            widthOf(text, valueStyle.copyWith(fontSize: 60 * scale)) +
            widthOf(' %', percentStyle.copyWith(fontSize: 45 * scale)) +
            3; // Cursor width and clearance.

        var scale = 1.0;
        if (widthAt(scale) > constraints.maxWidth) {
          // Measure the actual text scaler, including nonlinear system scaling.
          var lower = 0.0;
          var upper = 1.0;
          for (var i = 0; i < 12; i++) {
            final candidate = (lower + upper) / 2;
            if (widthAt(candidate) <= constraints.maxWidth) {
              lower = candidate;
            } else {
              upper = candidate;
            }
          }
          scale = lower;
        }
        final fittedValueStyle = valueStyle.copyWith(fontSize: 60 * scale);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widthOf(text, fittedValueStyle) + 3,
              child: TextField(
                key: const ValueKey('mobile_swap_slippage_value'),
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: _onChanged,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  const CommaToDotInputFormatter(),
                  const DecimalAmountInputFormatter(maxFractionDigits: 2),
                ],
                style: fittedValueStyle,
                cursorColor: context.colors.text.accent,
                cursorWidth: 2,
                cursorRadius: const Radius.circular(AppRadii.full),
                decoration: const InputDecoration.collapsed(hintText: '0'),
              ),
            ),
            Text(' %', style: percentStyle.copyWith(fontSize: 45 * scale)),
          ],
        );
      },
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
