import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import 'welcome_button_tokens.dart';

class WelcomeAccentButton extends StatelessWidget {
  const WelcomeAccentButton({
    required this.onPressed,
    this.height,
    this.glow = WelcomeButtonTokens.accentGlow,
    this.semanticKey,
    super.key,
  });

  final double? height;
  final BoxShadow glow;
  final Key? semanticKey;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    key: semanticKey,
    button: true,
    child: AppButton(
      expand: true,
      height: height,
      focusRingColor: WelcomeButtonTokens.focusRing,
      growWithContent: true,
      constrainContent: true,
      enabledBackgroundColor: const Color(0x00000000),
      pressedBackgroundColor: const Color(0x00000000),
      enabledBorderColor: WelcomeButtonTokens.border,
      enabledLabelColor: WelcomeButtonTokens.accentLabel,
      pressedLabelColor: WelcomeButtonTokens.accentLabel,
      decorationBuilder: (context, states, child) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: highlighted ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: child,
          builder: (context, progress, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.full),
              boxShadow: [
                BoxShadow.lerp(
                  glow,
                  WelcomeButtonTokens.accentHighlightedGlow,
                  progress,
                )!,
              ],
            ),
            child: CustomPaint(
              painter: _WelcomeAccentPainter(progress),
              child: child,
            ),
          ),
        );
      },
      onPressed: onPressed,
      child: const Text(
        'Get started',
        style: TextStyle(shadows: WelcomeButtonTokens.accentLabelShadows),
      ),
    ),
  );
}

/// The Figma accent's elliptical gradient and state-dependent inner shadow.
class _WelcomeAccentPainter extends CustomPainter {
  const _WelcomeAccentPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadii.full),
    );
    final centerX = size.width / 2;
    final transform = Matrix4.identity()
      ..setEntry(0, 0, 7.2812)
      ..setEntry(0, 3, centerX * (1 - 7.2812));
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(centerX, 0),
          size.height,
          WelcomeButtonTokens.accentGradient,
          WelcomeButtonTokens.accentGradientStops,
          TileMode.clamp,
          transform.storage,
        ),
    );
    final shadow = BoxShadow.lerp(
      WelcomeButtonTokens.accentInnerShadow,
      WelcomeButtonTokens.accentHighlightedInnerShadow,
      progress,
    )!;
    // Blur the area outside an offset pill into its interior. Clipping keeps
    // the effect inside the button, as Figma's INNER_SHADOW does.
    final shadowMask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(shadow.blurRadius * 4))
      ..addRRect(shape.shift(shadow.offset));
    canvas.drawPath(
      shadowMask,
      Paint()
        ..color = shadow.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WelcomeAccentPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
