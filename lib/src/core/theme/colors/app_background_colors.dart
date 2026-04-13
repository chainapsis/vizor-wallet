import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Depth hierarchy for the app shell.
///
/// Layered from deepest to highest:
/// * [ground] — Scaffold background, deepest layer.
/// * [base] — Primary content surface, main panels.
/// * [raised] — Cards, modals, sidebars, drawers.
/// * [overlay] — Dropdowns, popovers, floating elements.
class AppBackgroundColors {
  const AppBackgroundColors({
    required this.ground,
    required this.base,
    required this.raised,
    required this.overlay,
  });

  final Color ground;
  final Color base;
  final Color raised;
  final Color overlay;

  static const dark = AppBackgroundColors(
    ground: Primitives.p0Dark,
    base: Primitives.p50Dark,
    raised: Primitives.p100Dark,
    overlay: Primitives.p150Dark,
  );

  // Light mode collapses ground and base onto the same anchor; layering only
  // starts at `raised`. Matches the Figma spec.
  static const light = AppBackgroundColors(
    ground: Primitives.p0Light,
    base: Primitives.p0Light,
    raised: Primitives.p50Light,
    overlay: Primitives.p100Light,
  );
}
