import 'package:flutter/painting.dart';

import 'colors/app_colors.dart';

/// Figma "Shadow Surface" style — four layered drop-shadows, all painted with
/// the `Semantic/Shadows/Subtle` token (alpha-zero in dark mode, so raised
/// surfaces drop their shadow automatically when the theme switches).
///
/// Shared by raised light-mode surfaces: settings cards, text fields, the
/// swap widget shell.
List<BoxShadow> appSurfaceShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}
