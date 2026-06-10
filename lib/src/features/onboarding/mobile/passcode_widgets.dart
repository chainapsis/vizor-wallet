import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Diamond progress dots for passcode entry — Figma `Passcode 1`
/// (4394:82593): six rotated squares that fill as digits are typed.
class PasscodeDots extends StatelessWidget {
  const PasscodeDots({
    required this.length,
    required this.filled,
    this.error = false,
    super.key,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fillColor = error ? colors.text.destructive : colors.text.accent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: i < filled
                      ? fillColor
                      : colors.background.overlay.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Serif numpad — Figma `Passcode 1` (4394:82593). The design shows no
/// delete key; one is added bottom-right so a mistyped digit is
/// recoverable (WIP-design gap filled deliberately).
class PasscodeNumpad extends StatelessWidget {
  const PasscodeNumpad({
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, {VoidCallback? onTap, String? label}) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(height: 88, child: Center(child: child)),
        ),
      ),
    );

    Widget digitKey(int digit) {
      final colors = context.colors;
      return key(
        Text(
          '$digit',
          style: AppTypography.displayLarge.copyWith(
            color: enabled ? colors.text.accent : colors.text.disabled,
          ),
        ),
        onTap: () => onDigit(digit),
        label: 'Digit $digit',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [digitKey(1), digitKey(2), digitKey(3)]),
        Row(children: [digitKey(4), digitKey(5), digitKey(6)]),
        Row(children: [digitKey(7), digitKey(8), digitKey(9)]),
        Row(
          children: [
            key(const SizedBox.shrink()),
            digitKey(0),
            key(
              AppIcon(
                AppIcons.chevronBackward,
                size: 28,
                color: enabled
                    ? context.colors.icon.accent
                    : context.colors.icon.disabled,
              ),
              onTap: onBackspace,
              label: 'Delete digit',
            ),
          ],
        ),
      ],
    );
  }
}
