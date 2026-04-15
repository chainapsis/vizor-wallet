import 'package:flutter/painting.dart';

import '../primitives.dart';

// Primary button uses the brand purple ladder (not the neutral ladder). Keep
// this import grouped with the neutral primitives above for clarity.

/// Button colors grouped by variant.
///
/// Each variant owns its own sub-palette so widgets reference them as
/// `button.primary.bg`, `button.ghost.border`, etc. The destructive variant
/// currently shares fill/label values with primary in this monochrome spec;
/// that is intentional in the Figma source.
class AppButtonColors {
  const AppButtonColors({
    required this.primary,
    required this.secondary,
    required this.ghost,
    required this.destructive,
  });

  final AppPrimaryButtonColors primary;
  final AppSecondaryButtonColors secondary;
  final AppGhostButtonColors ghost;
  final AppDestructiveButtonColors destructive;

  static const dark = AppButtonColors(
    primary: AppPrimaryButtonColors.dark,
    secondary: AppSecondaryButtonColors.dark,
    ghost: AppGhostButtonColors.dark,
    destructive: AppDestructiveButtonColors.dark,
  );

  static const light = AppButtonColors(
    primary: AppPrimaryButtonColors.light,
    secondary: AppSecondaryButtonColors.light,
    ghost: AppGhostButtonColors.light,
    destructive: AppDestructiveButtonColors.light,
  );
}

class AppPrimaryButtonColors {
  const AppPrimaryButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color label;

  // Primary button is the brand accent — uses the purple ladder in both
  // modes. Different step numbers per mode because the designer picked visual
  // anchors manually (they don't fall on a strict mirror pair).
  static const dark = AppPrimaryButtonColors(
    bg: PurplePrimitives.p500Dark,
    bgHover: PurplePrimitives.p400Dark,
    bgPressed: PurplePrimitives.p300Dark,
    label: PurplePrimitives.p0Dark,
  );

  static const light = AppPrimaryButtonColors(
    bg: PurplePrimitives.p150Light,
    bgHover: PurplePrimitives.p300Light,
    bgPressed: PurplePrimitives.p400Light,
    label: PurplePrimitives.p900Light,
  );
}

class AppSecondaryButtonColors {
  const AppSecondaryButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color label;

  static const dark = AppSecondaryButtonColors(
    bg: Primitives.p100Dark,
    bgHover: Primitives.p150Dark,
    bgPressed: Primitives.p200Dark,
    label: Primitives.p800Dark,
  );

  static const light = AppSecondaryButtonColors(
    bg: Primitives.p100Light,
    bgHover: Primitives.p150Light,
    bgPressed: Primitives.p200Light,
    label: Primitives.p900Light,
  );
}

class AppGhostButtonColors {
  const AppGhostButtonColors({
    required this.bg,
    required this.bgHover,
    required this.border,
    required this.label,
  });

  // Transparent-looking base; the concrete token equals ground so the fill
  // reads as "no fill" against Scaffold.
  final Color bg;
  final Color bgHover;
  final Color border;
  final Color label;

  static const dark = AppGhostButtonColors(
    bg: Primitives.p0Dark,
    bgHover: Primitives.p100Dark,
    border: Primitives.p300Dark,
    label: Primitives.p800Dark,
  );

  static const light = AppGhostButtonColors(
    bg: Primitives.p0Light,
    bgHover: Primitives.p100Light,
    border: Primitives.p300Light,
    // Softer than the max-contrast `p900Light` accent — matches the
    // Figma ghost variant, which sits one step lighter than the primary
    // text tone so the button reads as secondary at rest.
    label: Primitives.p800Light,
  );
}

class AppDestructiveButtonColors {
  const AppDestructiveButtonColors({required this.bg, required this.label});

  final Color bg;
  final Color label;

  static const dark = AppDestructiveButtonColors(
    bg: Primitives.p800Dark,
    label: Primitives.p0Dark,
  );

  static const light = AppDestructiveButtonColors(
    bg: Primitives.p900Light,
    label: Primitives.p0Light,
  );
}
