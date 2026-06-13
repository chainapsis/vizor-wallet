import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Icon;
import 'package:flutter/widgets.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Diamond progress dots for passcode entry — Figma `Passcode 1/2`
/// (4394:82593 / 4394:82878): six rotated squares that fill crimson as
/// digits are typed; errors are conveyed by the plum message below, not
/// by tinting the dots.
class PasscodeDots extends StatelessWidget {
  const PasscodeDots({required this.length, required this.filled, super.key});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Transform.rotate(
              angle: math.pi / 4,
              // 14 px square → ~20 px diamond, matching the Figma index.
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: i < filled
                      ? colors.icon.brandCrimson
                      : colors.background.overlay,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Serif numpad — Figma `Passcode 1/2` and `Sign In Passcode`
/// (4596:50000). The bottom row carries an optional help action on the
/// left and a delete key on the right that only appears once at least
/// one digit is entered.
class PasscodeNumpad extends StatelessWidget {
  const PasscodeNumpad({
    required this.onDigit,
    required this.onBackspace,
    this.canDelete = false,
    this.onHelp,
    this.onBiometric,
    this.biometricIcon,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  /// Whether any digits are entered; the delete key hides otherwise.
  final bool canDelete;

  /// Shows the (?) action bottom-left when provided (sign-in screens).
  final VoidCallback? onHelp;

  /// Manual biometric retry in the bottom-right slot while it is not
  /// occupied by the delete key (i.e. before any digit is typed).
  final VoidCallback? onBiometric;

  /// Glyph for [onBiometric] (Face ID vs fingerprint).
  final IconData? biometricIcon;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget key(Widget child, {VoidCallback? onTap, String? label}) => Expanded(
      child: Semantics(
        button: onTap != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(height: 104, child: Center(child: child)),
        ),
      ),
    );

    Widget digitKey(int digit) => key(
      Text(
        '$digit',
        // One-off 48px serif: the Figma numpad digits render 34 px
        // tall, between Display L and Headline XL, so not a shared
        // typography token.
        style: AppTypography.displayLarge.copyWith(
          fontSize: 48,
          height: 1,
          color: enabled ? colors.text.accent : colors.text.disabled,
        ),
      ),
      onTap: () {
        unawaited(AppHaptics.digit());
        onDigit(digit);
      },
      label: 'Digit $digit',
    );

    final helpKey = onHelp == null
        ? key(const SizedBox.shrink())
        : key(
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.border.regular, width: 1.5),
              ),
              child: Center(
                child: AppIcon(
                  AppIcons.help,
                  size: AppIconSize.medium,
                  color: colors.icon.accent,
                ),
              ),
            ),
            onTap: onHelp,
            label: 'Passcode help',
          );

    final deleteKey = canDelete
        ? key(
            // TODO(mobile-passcode): swap for the design-system delete
            // glyph once it is exported to assets/icons.
            Icon(
              Icons.backspace_outlined,
              size: 26,
              color: enabled ? colors.icon.accent : colors.icon.disabled,
            ),
            onTap: () {
              unawaited(AppHaptics.auxiliaryKey());
              onBackspace();
            },
            label: 'Delete digit',
          )
        : onBiometric != null
        ? key(
            // TODO(mobile-passcode): swap for the design-system Face ID
            // glyph once it is exported to assets/icons.
            Icon(
              biometricIcon ?? Icons.fingerprint,
              size: 28,
              color: enabled ? colors.icon.accent : colors.icon.disabled,
            ),
            onTap: () {
              unawaited(AppHaptics.auxiliaryKey());
              onBiometric?.call();
            },
            label: 'Biometric unlock',
          )
        : key(const SizedBox.shrink());

    // Figma keypad is a fixed 320-wide block centred in the screen, not
    // full-bleed; ConstrainedBox keeps it from spreading on wide phones.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [digitKey(1), digitKey(2), digitKey(3)]),
            Row(children: [digitKey(4), digitKey(5), digitKey(6)]),
            Row(children: [digitKey(7), digitKey(8), digitKey(9)]),
            Row(children: [helpKey, digitKey(0), deleteKey]),
          ],
        ),
      ),
    );
  }
}
