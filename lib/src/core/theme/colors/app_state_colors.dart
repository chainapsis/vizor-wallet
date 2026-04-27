import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Interaction-state colors.
///
/// [hover] and [pressed] are overlay tints layered over a base surface, not
/// standalone backgrounds.
///
/// [focusRing] + [focusGap] form the 2dp focus indicator: a ring with max
/// contrast against the page, separated from the element by a 2dp gap so it
/// reads cleanly on any surface.
///
/// [focusRingBrand] is the brand-cyan variant used when focusing the
/// primary/accent button so the ring blends with the brand color instead of
/// contrasting with it.
class AppStateColors {
  const AppStateColors({
    required this.hover,
    required this.pressed,
    required this.focus,
    required this.selected,
    required this.focusRing,
    required this.focusGap,
    required this.focusRingBrand,
    required this.focusRingDestructive,
  });

  final Color hover;
  final Color pressed;
  final Color focus;
  final Color selected;
  final Color focusRing;
  final Color focusGap;
  final Color focusRingBrand;
  final Color focusRingDestructive;

  static const dark = AppStateColors(
    hover: Color(0x594D5252),
    pressed: Primitives.p150Dark,
    focus: Primitives.p200Dark,
    selected: Primitives.p150Dark,
    focusRing: Primitives.p800Dark,
    focusGap: Primitives.p0Dark,
    focusRingBrand: Color(0xFF3EC4CE),
    focusRingDestructive: Color(0xFFCC88D6),
  );

  static const light = AppStateColors(
    hover: Color(0x33B8B8B8),
    pressed: Primitives.p150Light,
    focus: Primitives.p200Light,
    selected: Primitives.p150Light,
    focusRing: Primitives.p900Light,
    focusGap: Primitives.p0Light,
    focusRingBrand: Color(0xFF56BAC4),
    focusRingDestructive: Color(0xFF93489E),
  );
}
