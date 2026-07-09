import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Depth hierarchy for the app shell.
///
/// Layered from deepest to highest:
/// * [window] — Desktop window backing and matching onboarding pane background.
/// * [ground] — Scaffold background, deepest layer.
/// * [base] — Primary content surface, main panels.
/// * [raised] — Cards, modals, sidebars, drawers.
/// * [overlay] — Dropdowns, popovers, floating elements.
/// * [neutralScrim] / [neutralSubtleOpacity] / [neutralStrongOpacity] —
///   Alpha neutral overlays.
/// * [brandCrimsonSubtle] / [brandCrimsonStrong] — Brand-accent backgrounds.
/// * [brandCrimsonAlpha] — Alpha brand overlay.
/// * [utilityDestructiveSubtle] / [utilityDestructiveStrong] /
///   [utilitySuccessSubtle] / [utilitySuccessStrong] — Utility backgrounds.
/// * [utilityDestructiveAlphaSubtle] / [utilityDestructiveAlpha] /
///   [utilitySuccessAlpha] — Alpha utility overlays.
/// * [homeCard] — Exception surface for the home balance card. Theme-invariant.
class AppBackgroundColors {
  const AppBackgroundColors({
    required this.window,
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
    required this.utilityDestructiveStrong,
    required this.utilityDestructiveAlphaSubtle,
    required this.utilityDestructiveAlpha,
    required this.utilitySuccessSubtle,
    required this.utilitySuccessStrong,
    required this.utilitySuccessAlpha,
    required this.homeCard,
  });

  final Color window;
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
  final Color utilityDestructiveStrong;
  final Color utilityDestructiveAlphaSubtle;
  final Color utilityDestructiveAlpha;
  final Color utilitySuccessSubtle;
  final Color utilitySuccessStrong;
  final Color utilitySuccessAlpha;
  final Color homeCard;

  static const dark = AppBackgroundColors(
    window: Color(0xFF0F0F0F),
    ground: Primitives.p50Dark,
    base: Primitives.p100Dark,
    raised: Primitives.p150Dark,
    overlay: Primitives.p200Dark,
    inverse: Primitives.p800Dark,
    neutralScrim: Primitives.p0Alpha50Dark,
    neutralSubtleOpacity: Primitives.p400Alpha20Dark,
    neutralStrongOpacity: Primitives.p300Alpha50Dark,
    brandCrimsonSubtle: CrimsonPrimitives.p100Dark,
    brandCrimsonStrong: CrimsonPrimitives.p400Dark,
    brandCrimsonAlpha: CrimsonPrimitives.p300Alpha35Dark,
    utilityDestructiveSubtle: PlumPrimitives.p50Dark,
    utilityDestructiveStrong: PlumPrimitives.p300Dark,
    utilityDestructiveAlphaSubtle: PlumPrimitives.p400Alpha8Dark,
    utilityDestructiveAlpha: PlumPrimitives.p400Alpha25Dark,
    utilitySuccessSubtle: GoldPrimitives.p150Dark,
    utilitySuccessStrong: GoldPrimitives.p500Dark,
    utilitySuccessAlpha: GreenPrimitives.p300Alpha15Dark,
    homeCard: Primitives.p50Dark,
  );

  static const light = AppBackgroundColors(
    window: Color(0xFFF7F7F7),
    ground: Primitives.p0Light,
    base: Primitives.p50Light,
    raised: Primitives.p100Light,
    overlay: Primitives.p150Light,
    inverse: Primitives.p800Light,
    neutralScrim: Primitives.p900Alpha50Light,
    neutralSubtleOpacity: Primitives.p300Alpha20Light,
    neutralStrongOpacity: Primitives.p300Alpha35Light,
    brandCrimsonSubtle: CrimsonPrimitives.p0Light,
    brandCrimsonStrong: CrimsonPrimitives.p300Light,
    brandCrimsonAlpha: CrimsonPrimitives.p300Alpha15Light,
    utilityDestructiveSubtle: PlumPrimitives.p0Light,
    utilityDestructiveStrong: PlumPrimitives.p400Light,
    utilityDestructiveAlphaSubtle: PlumPrimitives.p400Alpha8Light,
    utilityDestructiveAlpha: PlumPrimitives.p400Alpha15Light,
    utilitySuccessSubtle: GoldPrimitives.p50Light,
    utilitySuccessStrong: GoldPrimitives.p300Light,
    utilitySuccessAlpha: GreenPrimitives.p300Alpha15Light,
    homeCard: Primitives.p800Light,
  );
}
