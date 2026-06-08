import 'package:flutter/painting.dart';

/// Navigation-panel colors from the redesign `Semantic/Nav Panel` tokens.
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
    badgeBg: Color(0xFF862D4E),
    badgeLabel: Color(0xFFFFFFFF),
    activeBg: Color(0x26A83861),
    activeIcon: Color(0xFFA83861),
    activeLabel: Color(0xFFF5EBEE),
    hoverBg: Color(0x1AFFFFFF),
  );

  static const light = AppNavPanelColors(
    badgeBg: Color(0xFFA83861),
    badgeLabel: Color(0xFFFFFFFF),
    activeBg: Color(0x1AA83861),
    activeIcon: Color(0xFFA83861),
    activeLabel: Color(0xFF19080F),
    hoverBg: Color(0x0D141818),
  );
}
