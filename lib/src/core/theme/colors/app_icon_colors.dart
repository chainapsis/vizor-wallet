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
/// * [warning] — Caution icons. Backed by the current gold utility token for
///   compatibility with existing warning call sites.
/// * [destructive] — Destructive-state icons.
/// * [success] — Positive / success utility icons.
/// * [brandCrimson] — Brand-colored icons.
class AppIconColors {
  const AppIconColors({
    required this.accent,
    required this.regular,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.onPrimary,
    required this.warning,
    required this.destructive,
    required this.success,
    required this.brandCrimson,
  });

  final Color accent;
  final Color regular;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color onPrimary;
  final Color warning;
  final Color destructive;
  final Color success;
  final Color brandCrimson;

  static const dark = AppIconColors(
    accent: Primitives.p800Dark,
    regular: Primitives.p700Dark,
    muted: Primitives.p500Dark,
    disabled: Primitives.p300Dark,
    inverse: Primitives.p0Dark,
    onPrimary: Primitives.p0Dark,
    warning: GoldPrimitives.p600Dark,
    destructive: PlumPrimitives.p400Dark,
    success: GoldPrimitives.p600Dark,
    brandCrimson: CrimsonPrimitives.p300Dark,
  );

  static const light = AppIconColors(
    accent: Primitives.p900Light,
    regular: Primitives.p700Light,
    muted: Primitives.p500Light,
    disabled: Primitives.p300Light,
    inverse: Primitives.p0Light,
    onPrimary: Primitives.p0Light,
    warning: GoldPrimitives.p300Light,
    destructive: PlumPrimitives.p300Light,
    success: GoldPrimitives.p300Light,
    brandCrimson: CrimsonPrimitives.p400Light,
  );
}
