import 'package:flutter/widgets.dart';

/// Motion tokens for the onboarding route transitions.
///
/// Pulled into its own file so the route-level page builders in
/// `lib/app.dart` and the per-pane `SlideTransition` / `FadeTransition`
/// inside `IntroZcashScreen` can share a single source of truth without
/// creating a circular import between the two files.
///
/// Timing is asymmetric on purpose: push forward is longer so the
/// sidebar slide has room to decelerate visibly; pop back is snappier
/// so back-navigation doesn't feel laggy. The curve pair
/// (easeOutCubic forward, easeInCubic reverse) expresses the same idea
/// — content settles into place on entrance, accelerates out on exit.

/// Entrance duration. Applies to both the `CustomTransitionPage`
/// `transitionDuration` and the `IntroZcashScreen` internal motion.
const Duration kOnboardingForwardDuration = Duration(milliseconds: 320);

/// Exit / pop duration. Shorter than the entrance — see the token-file
/// docstring above.
const Duration kOnboardingReverseDuration = Duration(milliseconds: 260);

/// Applied when a route is entering or a pane is sliding / fading in.
const Curve kOnboardingForwardCurve = Curves.easeOutCubic;

/// Applied when a route is exiting or a pane is sliding / fading out.
const Curve kOnboardingReverseCurve = Curves.easeInCubic;
