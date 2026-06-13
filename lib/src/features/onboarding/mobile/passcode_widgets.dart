import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Icon;
import 'package:flutter/widgets.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Layout box of a single diamond dot (a rotated square → ~20 px diamond,
/// matching the Figma index). [PasscodePromptField] uses it to centre the
/// dots, so keep the two in sync.
const double kPasscodeDotSize = 14;

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
              child: Container(
                width: kPasscodeDotSize,
                height: kPasscodeDotSize,
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

/// The passcode entry field: the [PasscodeDots] pinned to the vertical
/// centre of the space it is given, with the error message rendered just
/// below them WITHOUT shifting the dots.
///
/// Centring (rather than fixed gaps under the title) keeps the field
/// balanced across window heights; rendering the error out of layout flow
/// keeps the dots from jumping when it toggles, so no reserved error slot
/// is needed. Place it inside an [Expanded] so it centres between the
/// title block and the keypad. [minGap] keeps a small breathing gap top
/// and bottom on short windows so the field never butts against its
/// neighbours.
class PasscodePromptField extends StatelessWidget {
  const PasscodePromptField({
    required this.length,
    required this.filled,
    this.error,
    this.minGap = AppSpacing.s,
    super.key,
  });

  final int length;
  final int filled;
  final String? error;
  final double minGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: minGap),
      child: SizedBox(
        // Fill the cross axis: the host Columns centre their children, so
        // without this the full-width dots/error rows would collapse.
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final centerY = constraints.maxHeight / 2;
            return Stack(
              // Let the error spill into the floor gap on short windows
              // rather than being clipped.
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: centerY - kPasscodeDotSize / 2,
                  left: 0,
                  right: 0,
                  child: PasscodeDots(length: length, filled: filled),
                ),
                if (error != null)
                  Positioned(
                    // Figma `Passcode Digits` (4596:50019) sets the message
                    // ~36 px below the dots' centre (8 px under the 57-tall
                    // dots field) — keep that gap with the dots centred.
                    top: centerY + 36,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        // Figma: Label M on text/destructive.
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
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
