import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

const onboardingAuthBackgroundAsset =
    'assets/illustrations/onboarding_auth_background.png';

class OnboardingAuthShell extends StatelessWidget {
  const OnboardingAuthShell({super.key, required this.card});

  final Widget card;

  static const double _contentTopInset = 48;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.window,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: _AuthBackgroundIllustration()),
          Positioned.fill(
            top: _contentTopInset,
            child: Center(child: card),
          ),
        ],
      ),
    );
  }
}

class OnboardingAuthCard extends StatelessWidget {
  const OnboardingAuthCard({
    super.key,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.padding,
    required this.child,
  });

  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: child,
    );
  }
}

class _AuthBackgroundIllustration extends StatelessWidget {
  const _AuthBackgroundIllustration();

  static const double _baselineWindowWidth = 1080;
  static const double _baselineWindowHeight = 720;
  static const double _left = -264;
  static const double _top = 0;
  static const double _width = 1344;
  static const double _height = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.max(
          constraints.maxWidth / _baselineWindowWidth,
          constraints.maxHeight / _baselineWindowHeight,
        );
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: _left * scale,
              top: _top * scale,
              width: _width * scale,
              height: _height * scale,
              child: Image.asset(
                onboardingAuthBackgroundAsset,
                fit: BoxFit.fill,
              ),
            ),
          ],
        );
      },
    );
  }
}
