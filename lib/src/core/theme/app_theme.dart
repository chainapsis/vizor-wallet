import 'package:flutter/widgets.dart';

import 'app_theme_data.dart';
import 'colors/app_colors.dart';

export 'app_icon_size.dart';
export 'app_radii.dart';
export 'app_spacing.dart';
export 'app_theme_data.dart';
export 'colors/app_colors.dart';

/// Propagates [AppThemeData] down the widget tree.
///
/// Wrap the root of the app (typically via `MaterialApp.builder`) in this
/// widget so every descendant can read semantic tokens through
/// [AppTheme.of] or the [BuildContext.colors] extension. Switching [data]
/// between [AppThemeData.dark] and [AppThemeData.light] triggers rebuilds
/// on all widgets that consumed the theme.
class AppTheme extends InheritedWidget {
  const AppTheme({super.key, required this.data, required super.child});

  final AppThemeData data;

  /// Returns the ambient [AppThemeData]. Throws in debug if no [AppTheme]
  /// ancestor is found — callers should wire one under their `App` root.
  static AppThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(
      theme != null,
      'AppTheme.of() was called without an AppTheme ancestor. '
      'Wrap MaterialApp.builder with AppTheme(data: ..., child: child!).',
    );
    return theme!.data;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) => data != oldWidget.data;
}

/// Short-hand accessors for the most common theme lookups.
///
/// Prefer `context.colors.text.primary` over `AppTheme.of(context).colors
/// .text.primary` in widget code.
extension AppThemeX on BuildContext {
  AppThemeData get appTheme => AppTheme.of(this);
  AppColors get colors => AppTheme.of(this).colors;
}
