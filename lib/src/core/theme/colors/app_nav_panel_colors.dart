import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Navigation-panel colors from the Figma `Semantic/Nav Panel` tokens.
///
/// [tabBarActiveBg] is the mobile tab bar's active pill: a neutral tint, so
/// the crimson icon carries the selection's colour. Light mode darkens the
/// bar; dark mode lightens it with white, so the pill stands out from the
/// dark bar. The sidebars keep [activeBg].
///
/// [tabBarActiveIcon] is that crimson icon: [activeIcon], the saturated brand
/// crimson the shielded marks use, in both themes. On the dark pill it
/// measures about 2.2:1, under the 3:1 non-text guideline; a design choice
/// for the saturated tint, with the pill also marking the selection.
class AppNavPanelColors {
  const AppNavPanelColors({
    required this.badgeBg,
    required this.activeBg,
    required this.activeIcon,
    required this.activeLabel,
    required this.tabBarActiveBg,
    required this.tabBarActiveIcon,
  });

  final Color badgeBg;
  final Color activeBg;
  final Color activeIcon;
  final Color activeLabel;
  final Color tabBarActiveBg;
  final Color tabBarActiveIcon;

  static const dark = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Dark,
    activeBg: CrimsonPrimitives.p400Alpha15Dark,
    activeIcon: CrimsonPrimitives.p400Dark,
    activeLabel: CrimsonPrimitives.p900Dark,
    tabBarActiveBg: Primitives.p900Alpha10Dark,
    tabBarActiveIcon: CrimsonPrimitives.p400Dark,
  );

  static const light = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Light,
    activeBg: CrimsonPrimitives.p300Alpha10Light,
    activeIcon: CrimsonPrimitives.p300Light,
    activeLabel: CrimsonPrimitives.p800Light,
    tabBarActiveBg: Primitives.p900Alpha10Light,
    tabBarActiveIcon: CrimsonPrimitives.p300Light,
  );
}
