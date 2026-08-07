import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A controlled, two-sided Y-axis flip for payment-link gift cards.
///
/// The parent owns which side is visible through [showBack]. Rebuilding with
/// the opposite value continues from the current animation value, so a second
/// click can reverse an in-progress flip without snapping. The animation only
/// changes the transform; both sides are expected to have the same card size.
class PaymentLinkCardFlip extends StatelessWidget {
  const PaymentLinkCardFlip({
    required this.showBack,
    required this.front,
    required this.back,
    this.animationDuration = duration,
    super.key,
  });

  /// Matches the designer-provided `vizor-card` flip handoff.
  static const Duration duration = Duration(milliseconds: 500);
  static const double edgeBand = 0.13;

  final bool showBack;
  final Widget front;
  final Widget back;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations || !TickerMode.valuesOf(context).enabled) {
      return _side(showBack: showBack, front: front, back: back);
    }

    return TweenAnimationBuilder<double>(
      key: const ValueKey('payment_link_flip_animation'),
      tween: Tween<double>(end: showBack ? 1 : 0),
      duration: animationDuration,
      curve: Curves.easeInOutCubic,
      builder: (context, value, _) {
        final showingBack = value >= 0.5;
        final rawAngle = showingBack
            ? (value * math.pi) - math.pi
            : value * math.pi;
        // Keep a narrow projected width around the face swap instead of
        // rendering a fully edge-on (and therefore invisible) card frame.
        final angle = showingBack
            ? math.max(rawAngle, (-math.pi / 2) + edgeBand)
            : math.min(rawAngle, (math.pi / 2) - edgeBand);
        return Transform(
          key: const ValueKey('payment_link_flip_transform'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: _side(showBack: showingBack, front: front, back: back),
        );
      },
    );
  }

  static Widget _side({
    required bool showBack,
    required Widget front,
    required Widget back,
  }) {
    return KeyedSubtree(
      key: ValueKey(
        showBack ? 'payment_link_flip_back' : 'payment_link_flip_front',
      ),
      child: showBack ? back : front,
    );
  }
}
