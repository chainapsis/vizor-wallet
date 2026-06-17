import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Resolves the user's [ThemeMode] into the app design-system theme and keeps
/// the macOS window chrome aligned with that resolved brightness.
class AppThemeHost extends StatelessWidget {
  const AppThemeHost({required this.themeMode, required this.child, super.key});

  final ThemeMode themeMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = _resolveBrightness(
      themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    final appThemeData = brightness == Brightness.dark
        ? AppThemeData.dark
        : AppThemeData.light;

    return AppTheme(
      data: appThemeData,
      child: _MacOSWindowAppearanceSync(
        brightness: brightness,
        child: _AndroidSystemBarsSync(brightness: brightness, child: child),
      ),
    );
  }

  static Brightness _resolveBrightness(
    ThemeMode themeMode,
    Brightness platformBrightness,
  ) {
    return switch (themeMode) {
      ThemeMode.system => platformBrightness,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
    };
  }
}

class _MacOSWindowAppearanceSync extends StatefulWidget {
  const _MacOSWindowAppearanceSync({
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  State<_MacOSWindowAppearanceSync> createState() =>
      _MacOSWindowAppearanceSyncState();
}

class _MacOSWindowAppearanceSyncState
    extends State<_MacOSWindowAppearanceSync> {
  @override
  void initState() {
    super.initState();
    _MacOSWindowAppearance.sync(widget.brightness);
  }

  @override
  void didUpdateWidget(covariant _MacOSWindowAppearanceSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness == widget.brightness) return;
    _MacOSWindowAppearance.sync(widget.brightness);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Keeps the Android system bars — the status bar and the navigation
/// bar (3-button / gesture) — on the app's themed `background.window`
/// color with matching icon contrast.
///
/// Two OS regimes share this one overlay style:
/// * API <= 34: the bar colors paint directly.
/// * Android 15+ with targetSdk 35+: the OS enforces edge-to-edge and
///   ignores the colors — the transparent bars show the scaffold's
///   `background.window` instead, and disabling contrast enforcement
///   stops the OS from laying its own scrim over them. Only the icon
///   brightness needs setting.
class _AndroidSystemBarsSync extends StatefulWidget {
  const _AndroidSystemBarsSync({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  State<_AndroidSystemBarsSync> createState() => _AndroidSystemBarsSyncState();
}

class _AndroidSystemBarsSyncState extends State<_AndroidSystemBarsSync> {
  @override
  void initState() {
    super.initState();
    _AndroidSystemBars.sync(widget.brightness);
  }

  @override
  void didUpdateWidget(covariant _AndroidSystemBarsSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness == widget.brightness) return;
    _AndroidSystemBars.sync(widget.brightness);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

abstract final class _AndroidSystemBars {
  static Brightness? _lastBrightness;

  static void sync(Brightness brightness) {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    SystemChrome.setSystemUIOverlayStyle(
      androidSystemBarsStyleFor(brightness),
    );
  }
}

/// Overlay style for the resolved app theme brightness — both system
/// bars take the theme's `background.window` (the scaffold background
/// used across the mobile shell, onboarding, and unlock screens) with
/// matching icon contrast. `statusBarBrightness` is the iOS-side field
/// and stays unset; this style only ever applies on Android.
@visibleForTesting
SystemUiOverlayStyle androidSystemBarsStyleFor(Brightness brightness) {
  final window = brightness == Brightness.dark
      ? AppColors.dark.background.window
      : AppColors.light.background.window;
  final icons = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: window,
    statusBarIconBrightness: icons,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: window,
    systemNavigationBarDividerColor: window,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

abstract final class _MacOSWindowAppearance {
  static const _channel = MethodChannel('com.zcash.wallet/window_appearance');

  static Brightness? _lastBrightness;

  static void sync(Brightness brightness) {
    if (kIsWeb || !Platform.isMacOS) return;
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    unawaited(_setBrightness(brightness));
  }

  static Future<void> _setBrightness(Brightness brightness) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', {
        'brightness': brightness == Brightness.dark ? 'dark' : 'light',
      });
    } catch (error) {
      _lastBrightness = null;
      debugPrint('MacOSWindowAppearance: sync failed: $error');
    }
  }
}
