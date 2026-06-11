import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Keyboard-like numeric entry panel — white key cards on a raised
/// panel, digits 1–9, then `.` / 0 / delete (Figma `Send Amount`
/// 4479:47503 and `Import — Calendar` 4575:112136 share the component).
///
/// Pass `onDecimalPoint: null` for integer-only fields (block heights,
/// dates) — the slot stays empty so the grid keeps its shape.
class AppNumericKeypad extends StatelessWidget {
  const AppNumericKeypad({
    required this.onDigit,
    required this.onBackspace,
    this.onDecimalPoint,
    this.enabled = true,
    this.keyPrefix,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onDecimalPoint;
  final bool enabled;

  /// When set, each key gets a `ValueKey('<keyPrefix>_<name>')`
  /// (`_0`–`_9`, `_decimal`, `_backspace`) so tests can tap precisely.
  final String? keyPrefix;

  static const _keyHeight = 46.0;

  Key? _keyFor(String name) =>
      keyPrefix == null ? null : ValueKey('${keyPrefix}_$name');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget key({
      required Widget child,
      required String label,
      required String name,
      required VoidCallback onTap,
      bool filled = true,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: _keyFor(name),
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: Container(
              height: _keyHeight,
              decoration: filled
                  ? BoxDecoration(
                      color: colors.background.ground,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    )
                  : null,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    Widget digitKey(int digit) => key(
      label: 'Digit $digit',
      name: '$digit',
      onTap: () => onDigit(digit),
      child: Text(
        '$digit',
        style: AppTypography.headlineSmall.copyWith(
          color: enabled ? colors.text.accent : colors.text.disabled,
        ),
      ),
    );

    Widget row(List<Widget> keys) => Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          keys[i],
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([digitKey(1), digitKey(2), digitKey(3)]),
          const SizedBox(height: AppSpacing.xs),
          row([digitKey(4), digitKey(5), digitKey(6)]),
          const SizedBox(height: AppSpacing.xs),
          row([digitKey(7), digitKey(8), digitKey(9)]),
          const SizedBox(height: AppSpacing.xs),
          row([
            if (onDecimalPoint == null)
              const Expanded(child: SizedBox(height: _keyHeight))
            else
              key(
                label: 'Decimal point',
                name: 'decimal',
                filled: false,
                onTap: onDecimalPoint!,
                child: Text(
                  '.',
                  style: AppTypography.headlineSmall.copyWith(
                    color: enabled ? colors.text.accent : colors.text.disabled,
                  ),
                ),
              ),
            digitKey(0),
            key(
              label: 'Delete digit',
              name: 'backspace',
              filled: false,
              onTap: onBackspace,
              // Same placeholder glyph as PasscodeNumpad — the icon set
              // has no backspace asset yet.
              child: Icon(
                Icons.backspace_outlined,
                size: 20,
                color: enabled ? colors.icon.accent : colors.icon.disabled,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
