import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Depth hierarchy for the app shell.
///
/// Layered from deepest to highest:
/// * [ground] — Scaffold background, deepest layer.
/// * [base] — Primary content surface, main panels.
/// * [raised] — Cards, modals, sidebars, drawers.
/// * [overlay] — Dropdowns, popovers, floating elements.
/// * [brandCyanSubtle] / [brandCyanStrong] — Brand-accent backgrounds
///   for cyan-tinted surfaces (info banners, onboarding highlights).
class AppBackgroundColors {
  const AppBackgroundColors({
    required this.ground,
    required this.base,
    required this.raised,
    required this.overlay,
    required this.brandCyanSubtle,
    required this.brandCyanStrong,
  });

  final Color ground;
  final Color base;
  final Color raised;
  final Color overlay;
  final Color brandCyanSubtle;
  final Color brandCyanStrong;

  static const dark = AppBackgroundColors(
    ground: Primitives.p0Dark,
    base: Primitives.p50Dark,
    raised: Primitives.p100Dark,
    overlay: Primitives.p150Dark,
    brandCyanSubtle: CyanPrimitives.p0Dark,
    brandCyanStrong: CyanPrimitives.p300Dark,
  );

  static const light = AppBackgroundColors(
    ground: Primitives.p0Light,
    base: Primitives.p50Light,
    raised: Primitives.p100Light,
    overlay: Primitives.p150Light,
    brandCyanSubtle: CyanPrimitives.p0Light,
    brandCyanStrong: CyanPrimitives.p150Light,
  );
}
