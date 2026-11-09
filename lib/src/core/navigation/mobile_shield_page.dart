import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// One fade owns both the blurred backdrop and the shielding content.
/// Particle choreography runs independently after the user commits.
class MobileShieldPage<T> extends CustomTransitionPage<T> {
  const MobileShieldPage({required super.key, required super.child})
    : super(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: _fade,
      );

  static Widget _fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
