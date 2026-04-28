import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Depth hierarchy for the app shell.
///
/// Layered from deepest to highest:
/// * [ground] — Scaffold background, deepest layer.
/// * [base] — Primary content surface, main panels.
/// * [raised] — Cards, modals, sidebars, drawers.
/// * [overlay] — Dropdowns, popovers, floating elements.
/// * [neutralScrim] / [neutralSubtleOpacity] / [neutralStrongOpacity] —
///   Alpha neutral overlays.
/// * [brandCrimsonSubtle] / [brandCrimsonStrong] — Brand-accent backgrounds.
/// * [brandCrimsonAlpha] — Alpha brand overlay.
/// * [utilityDestructiveSubtle] / [utilitySuccessSubtle] / [utilitySuccessStrong]
///   — Utility backgrounds.
/// * [utilityDestructiveAlpha] / [utilitySuccessAlpha] — Alpha utility overlays.
/// * [homeCard] — Exception surface for the home balance card. Theme-invariant.
class AppBackgroundColors {
  const AppBackgroundColors({
    required this.ground,
    required this.base,
    required this.raised,
    required this.overlay,
    required this.inverse,
    required this.neutralScrim,
    required this.neutralSubtleOpacity,
    required this.neutralStrongOpacity,
    required this.brandCrimsonSubtle,
    required this.brandCrimsonStrong,
    required this.brandCrimsonAlpha,
    required this.utilityDestructiveSubtle,
    required this.utilityDestructiveAlpha,
    required this.utilitySuccessSubtle,
    required this.utilitySuccessStrong,
    required this.utilitySuccessAlpha,
    required this.homeCard,
  });

  final Color ground;
  final Color base;
  final Color raised;
  final Color overlay;
  final Color inverse;
  final Color neutralScrim;
  final Color neutralSubtleOpacity;
  final Color neutralStrongOpacity;
  final Color brandCrimsonSubtle;
  final Color brandCrimsonStrong;
  final Color brandCrimsonAlpha;
  final Color utilityDestructiveSubtle;
  final Color utilityDestructiveAlpha;
  final Color utilitySuccessSubtle;
  final Color utilitySuccessStrong;
  final Color utilitySuccessAlpha;
  final Color homeCard;

  static const dark = AppBackgroundColors(
    ground: Primitives.p0Dark,
    base: Primitives.p50Dark,
    raised: Primitives.p100Dark,
    overlay: Primitives.p150Dark,
    inverse: Primitives.p800Dark,
    neutralScrim: Primitives.p400Alpha20Dark,
    neutralSubtleOpacity: Primitives.p400Alpha35Dark,
    neutralStrongOpacity: Primitives.p300Alpha50Dark,
    brandCrimsonSubtle: CrimsonPrimitives.p100Dark,
    brandCrimsonStrong: CrimsonPrimitives.p400Dark,
    brandCrimsonAlpha: CrimsonPrimitives.p300Alpha35Dark,
    utilityDestructiveSubtle: PlumPrimitives.p50Dark,
    utilityDestructiveAlpha: PlumPrimitives.p400Alpha25Dark,
    utilitySuccessSubtle: GoldPrimitives.p150Dark,
    utilitySuccessStrong: GoldPrimitives.p500Dark,
    utilitySuccessAlpha: GoldPrimitives.p400Alpha25Dark,
    homeCard: Primitives.p100Dark,
  );

  static const light = AppBackgroundColors(
    ground: Primitives.p0Light,
    base: Primitives.p50Light,
    raised: Primitives.p100Light,
    overlay: Primitives.p150Light,
    inverse: Primitives.p800Light,
    neutralScrim: Primitives.p900Alpha20Light,
    neutralSubtleOpacity: Primitives.p400Alpha20Light,
    neutralStrongOpacity: Primitives.p300Alpha35Light,
    brandCrimsonSubtle: CrimsonPrimitives.p0Light,
    brandCrimsonStrong: CrimsonPrimitives.p300Light,
    brandCrimsonAlpha: CrimsonPrimitives.p300Alpha15Light,
    utilityDestructiveSubtle: PlumPrimitives.p0Light,
    utilityDestructiveAlpha: PlumPrimitives.p400Alpha15Light,
    utilitySuccessSubtle: GoldPrimitives.p50Light,
    utilitySuccessStrong: GoldPrimitives.p300Light,
    utilitySuccessAlpha: GoldPrimitives.p300Alpha25Light,
    homeCard: Primitives.p100Dark,
  );
}
