import 'colors/app_colors.dart';

/// Top-level theme data for the app design system.
///
/// Currently carries [AppColors]; typography and misc style slots will be
/// added here as the system expands. Instances are const so the precomputed
/// [dark] / [light] values can be embedded with zero runtime cost.
class AppThemeData {
  const AppThemeData({required this.colors});

  final AppColors colors;

  static const dark = AppThemeData(colors: AppColors.dark);
  static const light = AppThemeData(colors: AppColors.light);
}
