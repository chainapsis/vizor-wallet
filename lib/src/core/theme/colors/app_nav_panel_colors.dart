import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Navigation-panel colors from the Figma `Semantic/Nav Panel` tokens.
class AppNavPanelColors {
  const AppNavPanelColors({
    required this.badgeBg,
    required this.activeBg,
    required this.activeIcon,
    required this.activeLabel,
  });

  final Color badgeBg;
  final Color activeBg;
  final Color activeIcon;
  final Color activeLabel;

  static const dark = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Dark,
    activeBg: CrimsonPrimitives.p400Alpha15Dark,
    activeIcon: CrimsonPrimitives.p400Dark,
    activeLabel: CrimsonPrimitives.p900Dark,
  );

  static const light = AppNavPanelColors(
    badgeBg: CrimsonPrimitives.p300Light,
    activeBg: CrimsonPrimitives.p300Alpha10Light,
    activeIcon: CrimsonPrimitives.p300Light,
    activeLabel: CrimsonPrimitives.p800Light,
  );
}
