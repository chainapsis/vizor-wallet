import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Button colors grouped by variant.
///
/// Each variant owns its own sub-palette so widgets reference them as
/// `button.primary.bg`, `button.ghost.bgHover`, etc.
class AppButtonColors {
  const AppButtonColors({
    required this.primary,
    required this.secondary,
    required this.ghost,
    required this.disabled,
    required this.destructive,
  });

  final AppPrimaryButtonColors primary;
  final AppSecondaryButtonColors secondary;
  final AppGhostButtonColors ghost;
  final AppDisabledButtonColors disabled;
  final AppDestructiveButtonColors destructive;

  static const dark = AppButtonColors(
    primary: AppPrimaryButtonColors.dark,
    secondary: AppSecondaryButtonColors.dark,
    ghost: AppGhostButtonColors.dark,
    disabled: AppDisabledButtonColors.dark,
    destructive: AppDestructiveButtonColors.dark,
  );

  static const light = AppButtonColors(
    primary: AppPrimaryButtonColors.light,
    secondary: AppSecondaryButtonColors.light,
    ghost: AppGhostButtonColors.light,
    disabled: AppDisabledButtonColors.light,
    destructive: AppDestructiveButtonColors.light,
  );
}

class AppPrimaryButtonColors {
  const AppPrimaryButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.border,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color border;
  final Color label;

  static const dark = AppPrimaryButtonColors(
    bg: Color(0xFF0996A0),
    bgHover: Color(0xFF3EC4CE),
    bgPressed: Color(0xFF3EC4CE),
    border: Color(0x33FFFFFF),
    label: Color(0xFF041316),
  );

  static const light = AppPrimaryButtonColors(
    bg: Color(0xFF0996A0),
    bgHover: Color(0xFF0A7680),
    bgPressed: Color(0xFF0A7680),
    border: Color(0x26FFFFFF),
    label: Color(0xFFE0F3F5),
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
    bg: Primitives.p150Dark,
    bgHover: Primitives.p200Dark,
    bgPressed: Primitives.p200Dark,
    label: Primitives.p800Dark,
  );

  static const light = AppSecondaryButtonColors(
    bg: Primitives.p100Light,
    bgHover: Primitives.p150Light,
    bgPressed: Primitives.p150Light,
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
    label: Primitives.p700Dark,
  );

  static const light = AppGhostButtonColors(
    bg: Primitives.p0Light,
    bgHover: Primitives.p100Light,
    border: Primitives.p300Light,
    label: Color(0xFF2E3232),
  );
}

class AppDisabledButtonColors {
  const AppDisabledButtonColors({required this.bg, required this.label});

  final Color bg;
  final Color label;

  static const dark = AppDisabledButtonColors(
    bg: Primitives.p100Dark,
    label: Primitives.p400Dark,
  );

  static const light = AppDisabledButtonColors(
    bg: Primitives.p150Light,
    label: Primitives.p500Light,
  );
}

class AppDestructiveButtonColors {
  const AppDestructiveButtonColors({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.border,
    required this.label,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color border;
  final Color label;

  static const dark = AppDestructiveButtonColors(
    bg: Color(0xFFB760C4),
    bgHover: Color(0xFFCC88D6),
    bgPressed: Color(0xFFCC88D6),
    border: Color(0x33FFFFFF),
    label: Color(0xFF150A17),
  );

  static const light = AppDestructiveButtonColors(
    bg: Color(0xFFB760C4),
    bgHover: Color(0xFF93489E),
    bgPressed: Color(0xFF93489E),
    border: Color(0x26FFFFFF),
    label: Color(0xFF211223),
  );
}
