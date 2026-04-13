import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Border / divider weights.
///
/// * [subtle] — Hairline dividers, row separators.
/// * [regular] — Input fields, cards, chips. (Named `regular` instead of
///   `default` because `default` is a reserved word in Dart.)
/// * [strong] — Selected states, active tabs.
class AppBorderColors {
  const AppBorderColors({
    required this.subtle,
    required this.regular,
    required this.strong,
  });

  final Color subtle;
  final Color regular;
  final Color strong;

  static const dark = AppBorderColors(
    subtle: Primitives.p200Dark,
    regular: Primitives.p300Dark,
    strong: Primitives.p400Dark,
  );

  // Light-mode borders sit one step lighter than the symmetric position
  // their dark counterparts occupy. Per the Figma sRGB token export,
  // `subtle → P150 / regular → P200 / strong → P300` on the light face.
  static const light = AppBorderColors(
    subtle: Primitives.p150Light,
    regular: Primitives.p200Light,
    strong: Primitives.p300Light,
  );
}
