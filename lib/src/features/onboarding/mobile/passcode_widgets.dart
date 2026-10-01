import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Layout box of a single diamond dot (a rotated square → ~20 px diamond,
/// matching the Figma index). [PasscodePromptField] uses it to centre the
/// dots, so keep the two in sync.
const double kPasscodeDotSize = 14;
const double kPasscodePromptDigitsHeight = 81;
const double kPasscodeKeySize = 80;
const double kPasscodeKeypadWidth = 320;
const double _kPasscodeBackspaceSlotWidth = 30;
const double _kPasscodeBackspaceSlotHeight = 32;
const double _kPasscodeBackspaceGlyphWidth = 26.25;
const double _kPasscodeBackspaceGlyphHeight = 23.15;
const double _kPasscodeBiometricButtonHeight = 36;
const double _kPasscodeBiometricButtonMinWidth = 96;
const double _kPasscodeBiometricIconSize = 16;
const EdgeInsets _kPasscodeBackspaceInsets = EdgeInsets.fromLTRB(
  2.5,
  4.42,
  1.25,
  4.43,
);

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
                      : colors.background.neutralSubtleOpacity,
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
                    // Figma `Passcode Digits` (4885:23059) sets the message
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
/// (4885:23167). The bottom row carries an optional help action on the
/// left and a delete key on the right that only appears once at least
/// one digit is entered.
class PasscodeNumpad extends StatelessWidget {
  const PasscodeNumpad({
    required this.onDigit,
    required this.onBackspace,
    this.canDelete = false,
    this.onHelp,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  /// Whether any digits are entered; the delete key hides otherwise.
  final bool canDelete;

  /// Shows the (?) action bottom-left when provided (sign-in screens).
  final VoidCallback? onHelp;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget keySlot(Widget child, {VoidCallback? onTap, String? label}) {
      final effectiveTap = enabled ? onTap : null;
      return Semantics(
        button: effectiveTap != null,
        enabled: effectiveTap != null,
        label: label,
        onTap: effectiveTap,
        excludeSemantics: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: effectiveTap == null
              ? null
              : (event) {
                  if (event.buttons != kPrimaryButton) return;
                  effectiveTap();
                },
          child: SizedBox.square(
            dimension: kPasscodeKeySize,
            child: Center(child: child),
          ),
        ),
      );
    }

    Widget digitKey(int digit) => keySlot(
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$digit',
            // Figma `_Passcode Button`: Young Serif 40 / 33 inside
            // an 80px circular neutral-alpha key.
            style: AppTypography.headlineLarge.copyWith(
              fontSize: 40,
              height: 33 / 40,
              color: enabled ? colors.text.accent : colors.text.disabled,
            ),
          ),
        ),
      ),
      onTap: () {
        unawaited(AppHaptics.digit());
        onDigit(digit);
      },
      label: 'Digit $digit',
    );

    final helpKey = onHelp == null
        ? keySlot(const SizedBox.shrink())
        : keySlot(
            // Figma `Help` (4885:21762): a 32px icon-only auxiliary key
            // in the transparent bottom-left slot.
            AppIcon(
              AppIcons.help,
              size: 32,
              color: enabled ? colors.icon.muted : colors.icon.disabled,
            ),
            onTap: onHelp,
            label: 'Passcode help',
          );

    final deleteKey = canDelete
        ? keySlot(
            _PasscodeBackspaceIcon(
              color: enabled ? colors.icon.muted : colors.icon.disabled,
            ),
            onTap: () {
              unawaited(AppHaptics.auxiliaryKey());
              onBackspace();
            },
            label: 'Delete digit',
          )
        : keySlot(const SizedBox.shrink());

    // Figma keypad is a 320px-wide wrap, capped by the caller's width so
    // narrow phone layouts with horizontal padding do not overflow.
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : kPasscodeKeypadWidth;
          return SizedBox(
            width: math.min(kPasscodeKeypadWidth, maxWidth),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                digitKey(1),
                digitKey(2),
                digitKey(3),
                digitKey(4),
                digitKey(5),
                digitKey(6),
                digitKey(7),
                digitKey(8),
                digitKey(9),
                helpKey,
                digitKey(0),
                deleteKey,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bottom Face ID / biometric retry action for the sign-in screen.
/// Figma places it below the keypad as a 36px ghost pill, not inside the
/// keypad's bottom-right auxiliary slot.
class PasscodeBiometricButton extends StatelessWidget {
  const PasscodeBiometricButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    final labelColor = enabled
        ? colors.button.ghost.label
        : colors.text.disabled;
    final labelStyle = AppTypography.labelLarge.copyWith(color: labelColor);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final contentWidth =
            AppSpacing.s * 2 +
            _kPasscodeBiometricIconSize +
            AppSpacing.xxs * 2 +
            textPainter.width;
        final idealWidth = math.max(
          _kPasscodeBiometricButtonMinWidth,
          contentWidth,
        );
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : idealWidth;
        final width = math.min(idealWidth, maxWidth);

        return Center(
          child: Semantics(
            button: enabled,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed == null
                  ? null
                  : () {
                      unawaited(AppHaptics.auxiliaryKey());
                      onPressed?.call();
                    },
              child: SizedBox(
                key: const ValueKey('passcode_biometric_button'),
                width: width,
                height: _kPasscodeBiometricButtonHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme.merge(
                        data: IconThemeData(
                          color: labelColor,
                          size: _kPasscodeBiometricIconSize,
                        ),
                        child: SizedBox.square(
                          dimension: _kPasscodeBiometricIconSize,
                          child: icon,
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PasscodeBackspaceIcon extends StatelessWidget {
  const _PasscodeBackspaceIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('passcode_backspace_slot'),
      width: _kPasscodeBackspaceSlotWidth,
      height: _kPasscodeBackspaceSlotHeight,
      child: Padding(
        padding: _kPasscodeBackspaceInsets,
        child: SizedBox(
          key: const ValueKey('passcode_backspace_glyph'),
          width: _kPasscodeBackspaceGlyphWidth,
          height: _kPasscodeBackspaceGlyphHeight,
          child: SvgPicture.asset(
            'assets/icons/${AppIcons.backspace}.svg',
            width: _kPasscodeBackspaceGlyphWidth,
            height: _kPasscodeBackspaceGlyphHeight,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
