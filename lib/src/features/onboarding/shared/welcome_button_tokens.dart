import 'package:flutter/painting.dart';

import '../../../core/theme/primitives.dart';

/// Welcome's fixed dark surface, independent of the app's selected theme.
/// Figma: ButtonAccent / ButtonAccent_Hover and ButtonAccentSecond_Hover.
/// These gradient/effect tokens are separate from the shared primary palette.
abstract final class WelcomeButtonTokens {
  static const border = Color(0x1affffff);
  static const accentLabel = Color(0xd9ffffff);
  static const secondaryLabel = Primitives.p800Dark;
  static const ghostLabel = Primitives.p700Dark;
  static const ghostDisabledLabel = Color(0x73ffffff);
  static const focusRing = Primitives.p800Dark;

  static const secondaryBackground = Color(0x33f7f7f7);
  static const secondaryHighlightedBackground = Color(0x4df7f7f7);
  // Redeem uses the existing Ghost component's dark hover surface.
  static const ghostHighlightedBackground = Primitives.p100Dark;

  static const accentGradient = [
    Color(0xff2c0e19),
    Color(0xff441123),
    Color(0xff5c142e),
    Color(0xff8d1a44),
  ];
  static const accentGradientStops = [0.0, 0.25, 0.5, 1.0];
  static const accentInnerShadow = BoxShadow(
    color: Color(0xffa83861),
    offset: Offset(0, 4),
    blurRadius: 14,
  );
  static const accentHighlightedInnerShadow = BoxShadow(
    color: Color(0xffc64c78),
    offset: Offset(0, 8),
    blurRadius: 25,
  );
  // The default glow follows the actual Welcome screen, whose opacity is 70%.
  static const accentGlow = BoxShadow(
    color: Color(0xb3a83861),
    offset: Offset(0, 25),
    blurRadius: 100,
  );
  static const desktopAccentGlow = BoxShadow(
    color: Color(0x66a83861),
    offset: Offset(0, 25),
    blurRadius: 100,
  );
  static const accentHighlightedGlow = BoxShadow(
    color: Color(0x99a83861),
    offset: Offset(0, 25),
    blurRadius: 100,
    spreadRadius: 15,
  );
  static const accentLabelShadows = [
    Shadow(color: Color(0xffcf517f), blurRadius: 10),
    Shadow(color: Color(0x8ce3b5c5), blurRadius: 2),
  ];
}
