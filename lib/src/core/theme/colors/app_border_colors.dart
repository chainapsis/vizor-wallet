import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Border / divider weights.
///
/// * [subtle] — Hairline dividers, row separators.
/// * [regular] — Input fields, cards, chips. (Named `regular` instead of
///   `default` because `default` is a reserved word in Dart.)
/// * [strong] — Selected states, active tabs.
/// * [brandCyanSubtle] / [brandCyanStrong] — Brand-accent borders for
///   cyan-tinted surfaces (info panels, selection on cyan brand pages).
class AppBorderColors {
  const AppBorderColors({
    required this.subtle,
    required this.regular,
    required this.strong,
    required this.brandCyanSubtle,
    required this.brandCyanStrong,
  });

  final Color subtle;
  final Color regular;
  final Color strong;
  final Color brandCyanSubtle;
  final Color brandCyanStrong;

  static const dark = AppBorderColors(
    subtle: Primitives.p200Dark,
    regular: Primitives.p300Dark,
    strong: Primitives.p400Dark,
    brandCyanSubtle: CyanPrimitives.p100Dark,
    brandCyanStrong: CyanPrimitives.p300Dark,
  );

  // Light-mode borders sit one step lighter than the symmetric position
  // their dark counterparts occupy. Per the Figma sRGB token export,
  // `subtle → P150 / regular → P200 / strong → P300` on the light face.
  static const light = AppBorderColors(
    subtle: Primitives.p150Light,
    regular: Primitives.p200Light,
    strong: Primitives.p300Light,
    brandCyanSubtle: CyanPrimitives.p50Light,
    brandCyanStrong: CyanPrimitives.p150Light,
  );
}
