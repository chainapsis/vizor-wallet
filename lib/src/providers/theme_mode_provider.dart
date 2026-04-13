import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the user's selected [ThemeMode] (system / light / dark).
///
/// Defaults to [ThemeMode.system] so the app follows the OS. This provider
/// owns the *intent*; resolving the intent to a concrete [Brightness] (and
/// thus to `AppThemeData.dark` or `.light`) happens at the `MaterialApp`
/// layer where `MediaQuery.platformBrightness` is available.
///
/// Persistence is intentionally deferred — add it alongside a settings UI.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
