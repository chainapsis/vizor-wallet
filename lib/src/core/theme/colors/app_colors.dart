import 'app_background_colors.dart';
import 'app_border_colors.dart';
import 'app_button_colors.dart';
import 'app_icon_colors.dart';
import 'app_state_colors.dart';
import 'app_surface_colors.dart';
import 'app_text_colors.dart';

export 'app_background_colors.dart';
export 'app_border_colors.dart';
export 'app_button_colors.dart';
export 'app_icon_colors.dart';
export 'app_state_colors.dart';
export 'app_surface_colors.dart';
export 'app_text_colors.dart';

/// Aggregated semantic color palette for the app. Sourced from the Zcash
/// design system Figma spec; organized into seven categories that mirror the
/// Figma sheet structure (Background / Surface / Border / Text / Icon /
/// Button / State).
///
/// Do not read [AppColors] directly from widgets — it will be surfaced via an
/// [AppTheme] InheritedWidget wired up in a later step.
class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.icon,
    required this.button,
    required this.state,
  });

  final AppBackgroundColors background;
  final AppSurfaceColors surface;
  final AppBorderColors border;
  final AppTextColors text;
  final AppIconColors icon;
  final AppButtonColors button;
  final AppStateColors state;

  static const dark = AppColors(
    background: AppBackgroundColors.dark,
    surface: AppSurfaceColors.dark,
    border: AppBorderColors.dark,
    text: AppTextColors.dark,
    icon: AppIconColors.dark,
    button: AppButtonColors.dark,
    state: AppStateColors.dark,
  );

  static const light = AppColors(
    background: AppBackgroundColors.light,
    surface: AppSurfaceColors.light,
    border: AppBorderColors.light,
    text: AppTextColors.light,
    icon: AppIconColors.light,
    button: AppButtonColors.light,
    state: AppStateColors.light,
  );
}
