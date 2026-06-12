import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

/// Mobile slippage editor — Figma `Slippage` (4700:121854): a serif
/// value with minus/plus steppers instead of the desktop's radio
/// presets. Steps by 0.25% within 0.1–5%.
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

  late int _bps = widget.slippageBps.clamp(_minBps, _maxBps);

  String get _percentText {
    final percent = _bps / 100;
    var text = percent.toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  void _step(int direction) {
    setState(() {
      _bps = (_bps + direction * _stepBps).clamp(_minBps, _maxBps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Slippage',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Semantics(
                label: 'Close',
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancel,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.background.raised,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.cross,
                        size: AppIconSize.medium,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(
                key: const ValueKey('mobile_swap_slippage_minus'),
                label: '-',
                enabled: _bps > _minBps,
                onTap: () => _step(-1),
              ),
              Expanded(
                child: Text.rich(
                  key: const ValueKey('mobile_swap_slippage_value'),
                  TextSpan(
                    text: _percentText,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                    ),
                    children: [
                      TextSpan(
                        text: ' %',
                        style: AppTypography.headlineMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              _StepperButton(
                key: const ValueKey('mobile_swap_slippage_plus'),
                label: '+',
                enabled: _bps < _maxBps,
                onTap: () => _step(1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('swap_slippage_update_button'),
            expand: true,
            onPressed: _bps == widget.slippageBps
                ? null
                : () => widget.onSubmitted(_bps),
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
