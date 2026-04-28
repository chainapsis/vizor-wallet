import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

/// Holds the user's selected [ThemeMode] (system / light / dark).
///
/// Defaults to [ThemeMode.system] so the app follows the OS. This provider
/// owns the *intent*; resolving the intent to a concrete [Brightness] (and
/// thus to `AppThemeData.dark` or `.light`) happens at the `MaterialApp`
/// layer where `MediaQuery.platformBrightness` is available.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static final _store = AppSecureStore.instance;

  @override
  ThemeMode build() => ref.watch(appBootstrapProvider).themeMode;

  Future<void> set(ThemeMode mode) async {
    await _store.writePlain(kThemeModeKey, _encode(mode));
    state = mode;
  }

  static String _encode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
