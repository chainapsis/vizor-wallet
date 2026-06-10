import 'package:flutter/painting.dart';

/// macOS utility colors from the Desktop color-token export.
class AppMacosUtilityColors {
  const AppMacosUtilityColors({
    required this.scrollBar,
    required this.window,
    required this.windowTransparent,
    required this.navPanel,
    required this.disabledStopLight,
    required this.font,
    required this.thinBorder,
    required this.innerBorder,
  });

  final Color scrollBar;
  final Color window;
  final Color windowTransparent;
  final Color navPanel;
  final Color disabledStopLight;
  final Color font;
  final Color thinBorder;
  final Color innerBorder;

  static const dark = AppMacosUtilityColors(
    scrollBar: Color(0x1FFFFFFF),
    window: Color(0xFF0F0F0F),
    windowTransparent: Color(0x000F0F0F),
    navPanel: Color(0x4D1A1A1A),
    disabledStopLight: Color(0x1AFFFFFF),
    font: Color(0xCCFFFFFF),
    thinBorder: Color(0x3B1A1A1A),
    innerBorder: Color(0x3B1A1A1A),
  );

  static const light = AppMacosUtilityColors(
    scrollBar: Color(0x1F1A1A1A),
    window: Color(0xFFF7F7F7),
    windowTransparent: Color(0x00F5F5F5),
    navPanel: Color(0x4DFFFFFF),
    disabledStopLight: Color(0x1A1A1A1A),
    font: Color(0xD91A1A1A),
    thinBorder: Color(0x8CFFFFFF),
    innerBorder: Color(0x3B1A1A1A),
  );
}
