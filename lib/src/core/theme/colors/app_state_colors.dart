import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Interaction-state colors from the Figma `OLDSemantic/State` group.
///
/// [hover] is the alpha overlay layered over a base surface. [pressed] and
/// [selected] are standalone neutral backgrounds.
/// [selectedOpacity] is the matching alpha overlay token for selected states
/// that need to preserve the underlying surface.
///
/// [focusRing] + [focusGap] form the 2dp focus indicator: a ring with max
/// contrast against the page, separated from the element by a 2dp gap so it
/// reads cleanly on any surface.
///
/// [focusRingBrand] is the brand-crimson variant used when focusing the
/// primary/accent button so the ring blends with the brand color instead of
/// contrasting with it.
class AppStateColors {
  const AppStateColors({
    required this.hover,
    required this.pressed,
    required this.focus,
    required this.selected,
    required this.selectedOpacity,
    required this.focusRing,
    required this.focusGap,
    required this.focusRingBrand,
    required this.focusRingDestructive,
  });

  final Color hover;
  final Color pressed;
  final Color focus;
  final Color selected;
  final Color selectedOpacity;
  final Color focusRing;
  final Color focusGap;
  final Color focusRingBrand;
  final Color focusRingDestructive;

  static const dark = AppStateColors(
    hover: Primitives.p0Alpha15Dark,
    pressed: Primitives.p150Dark,
    focus: Primitives.p200Dark,
    selected: Primitives.p150Dark,
    selectedOpacity: Primitives.p0Alpha30Dark,
    focusRing: Primitives.p800Dark,
    focusGap: Primitives.p0Dark,
    focusRingBrand: CrimsonPrimitives.p400Dark,
    focusRingDestructive: PlumPrimitives.p500Dark,
  );

  static const light = AppStateColors(
    hover: Primitives.p900Alpha5Light,
    pressed: Primitives.p150Light,
    focus: Primitives.p200Light,
    selected: Primitives.p150Light,
    selectedOpacity: Primitives.p900Alpha5Light,
    focusRing: Primitives.p900Light,
    focusGap: Primitives.p0Light,
    focusRingBrand: CrimsonPrimitives.p300Light,
    focusRingDestructive: PlumPrimitives.p400Light,
  );
}
