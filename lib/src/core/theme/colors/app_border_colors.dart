import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Border / divider weights.
///
/// * [subtle] — Hairline dividers, row separators.
/// * [subtleOpacity] — Alpha border used on strong filled controls.
/// * [inverseOpacity] — Alpha border used over inverted / strong fills.
/// * [regular] — Default field/card/chip border. (Named `regular` instead of
///   Figma's `default` because `default` is a reserved word in Dart.)
/// * [medium] — Active/filled field border.
/// * [strong] — Max-contrast border.
/// * [utilityDestructive] — Validation / destructive emphasis.
/// * [utilityDestructiveSubtle] — Soft destructive border.
/// * [utilitySuccess] — Success emphasis.
/// * [brandCrimsonStrong] — Brand feedback / accent border.
class AppBorderColors {
  const AppBorderColors({
    required this.subtle,
    required this.subtleOpacity,
    required this.inverseOpacity,
    required this.regular,
    required this.medium,
    required this.strong,
    required this.utilityDestructive,
    required this.utilityDestructiveSubtle,
    required this.utilitySuccess,
    required this.brandCrimsonStrong,
  });

  final Color subtle;
  final Color subtleOpacity;
  final Color inverseOpacity;
  final Color regular;
  final Color medium;
  final Color strong;
  final Color utilityDestructive;
  final Color utilityDestructiveSubtle;
  final Color utilitySuccess;
  final Color brandCrimsonStrong;

  static const dark = AppBorderColors(
    subtle: Primitives.p150Dark,
    subtleOpacity: Primitives.p900Alpha10Dark,
    inverseOpacity: Primitives.p150Alpha15Dark,
    regular: Primitives.p300Dark,
    medium: Primitives.p400Dark,
    strong: Primitives.p800Dark,
    utilityDestructive: PlumPrimitives.p400Dark,
    utilityDestructiveSubtle: PlumPrimitives.p100Dark,
    utilitySuccess: GoldPrimitives.p500Dark,
    brandCrimsonStrong: CrimsonPrimitives.p400Dark,
  );

  static const light = AppBorderColors(
    subtle: Primitives.p150Light,
    subtleOpacity: Primitives.p900Alpha5Light,
    inverseOpacity: Primitives.p0Alpha10Light,
    regular: Primitives.p200Light,
    medium: Primitives.p300Light,
    strong: Primitives.p900Light,
    utilityDestructive: PlumPrimitives.p300Light,
    utilityDestructiveSubtle: PlumPrimitives.p100Light,
    utilitySuccess: GoldPrimitives.p400Light,
    brandCrimsonStrong: CrimsonPrimitives.p300Light,
  );
}
