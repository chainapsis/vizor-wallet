import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Icon color hierarchy.
///
/// * [accent] — Active, selected, primary icons.
/// * [regular] — Standard UI icons. (Named `regular` instead of `default`
///   because `default` is a reserved word in Dart.)
/// * [muted] — Inactive, decorative icons. Theme-invariant.
/// * [disabled] — Icons on disabled controls.
/// * [inverse] — Icons on inverted surfaces.
/// * [onPrimary] — Icons placed inside a primary button.
/// * [brandPurple] / [brandCyan] — Brand-colored icons.
class AppIconColors {
  const AppIconColors({
    required this.accent,
    required this.regular,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.onPrimary,
    required this.brandPurple,
    required this.brandCyan,
  });

  final Color accent;
  final Color regular;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color onPrimary;
  final Color brandPurple;
  final Color brandCyan;

  static const dark = AppIconColors(
    accent: Primitives.p800Dark,
    regular: Primitives.p700Dark,
    muted: Primitives.p500Dark,
    disabled: Primitives.p300Dark,
    inverse: Primitives.p0Dark,
    onPrimary: Primitives.p0Dark,
    brandPurple: PurplePrimitives.p500Dark,
    brandCyan: CyanPrimitives.p500Dark,
  );

  static const light = AppIconColors(
    accent: Primitives.p900Light,
    regular: Primitives.p700Light,
    muted: Primitives.p500Light,
    disabled: Primitives.p300Light,
    inverse: Primitives.p0Light,
    onPrimary: Primitives.p0Light,
    brandPurple: PurplePrimitives.p200Light,
    brandCyan: CyanPrimitives.p150Light,
  );
}
