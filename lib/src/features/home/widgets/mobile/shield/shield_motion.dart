import 'dart:math' as math;
import 'package:flutter/animation.dart';
import '../../../../../core/theme/app_theme.dart';

abstract final class VText {
  static const geist = 'Geist';
  static final display = AppTypography.displayLarge.copyWith(
    fontFamily: 'Shielding Serif',
  );
  static final labelL = AppTypography.bodyMedium.copyWith(
    color: const Color(0xFFFFFFFF),
  );
}

/// Motion vocabulary. Curves are the strong variants, never the built-ins.
abstract final class VMotion {
  /// Entering / exiting / responding to the user.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Colour and light changes.
  static const ease = Cubic(0.25, 0.1, 0.25, 1);

  /// Things already on screen moving from A to B.
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// Apple-style spring: [response] is roughly the time to reach the target,
  /// [dampingRatio] 1.0 means no overshoot.
  static SpringDescription spring({
    double response = 0.4,
    double dampingRatio = 1.0,
  }) {
    final omega = 2 * math.pi / response;
    return SpringDescription(
      mass: 1,
      stiffness: omega * omega,
      damping: 2 * dampingRatio * omega,
    );
  }

  /// Apple's momentum projection: where a flick would come to rest.
  static double project(double velocity, {double decelerationRate = 0.99}) {
    return velocity / 1000 * decelerationRate / (1 - decelerationRate);
  }

  /// iOS-style rubber band: the further past the edge, the less it follows.
  static double rubberBand(double overshoot, double dimension) {
    const c = 0.55;
    final sign = overshoot.sign;
    final o = overshoot.abs();
    return sign * (o * dimension * c) / (dimension + c * o);
  }
}
