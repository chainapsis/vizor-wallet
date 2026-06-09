import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Navigation-panel colors from the Figma `Semantic/Nav Panel` tokens.
class AppNavPanelColors {
  const AppNavPanelColors({
    required this.badgeBg,
    required this.badgeLabel,
    required this.activeBg,
    required this.activeIcon,
    required this.activeLabel,
    required this.hoverBg,
  });

  final Color badgeBg;
  final Color badgeLabel;
  final Color activeBg;
  final Color activeIcon;
  final Color activeLabel;
  final Color hoverBg;

  static const dark = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Dark,
    badgeLabel: Primitives.p900Dark,
    activeBg: CrimsonPrimitives.p400Alpha15Dark,
    activeIcon: CrimsonPrimitives.p400Dark,
    activeLabel: CrimsonPrimitives.p900Dark,
    hoverBg: Primitives.p900Alpha10Dark,
  );

  static const light = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Light,
    badgeLabel: Primitives.p0Light,
    activeBg: CrimsonPrimitives.p300Alpha10Light,
    activeIcon: CrimsonPrimitives.p300Light,
    activeLabel: CrimsonPrimitives.p800Light,
    hoverBg: Primitives.p900Alpha5Light,
  );
}
