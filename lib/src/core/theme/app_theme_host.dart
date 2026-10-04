import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Resolves the user's [ThemeMode] into the app design-system theme and keeps
/// native platform chrome aligned with that resolved brightness.
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
        child: _IOSWindowAppearanceSync(
          themeMode: themeMode,
          brightness: brightness,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: appSystemBarsStyleFor(brightness),
            child: child,
          ),
        ),
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

class _IOSWindowAppearanceSync extends StatefulWidget {
  const _IOSWindowAppearanceSync({
    required this.themeMode,
    required this.brightness,
    required this.child,
  });

  final ThemeMode themeMode;
  final Brightness brightness;
  final Widget child;

  @override
  State<_IOSWindowAppearanceSync> createState() =>
      _IOSWindowAppearanceSyncState();
}

class _IOSWindowAppearanceSyncState extends State<_IOSWindowAppearanceSync> {
  @override
  void initState() {
    super.initState();
    _IOSWindowAppearance.sync(widget.themeMode, widget.brightness);
  }

  @override
  void didUpdateWidget(covariant _IOSWindowAppearanceSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode == widget.themeMode &&
        oldWidget.brightness == widget.brightness) {
      return;
    }
    _IOSWindowAppearance.sync(widget.themeMode, widget.brightness);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Theme-level system-bar style. A screen (such as Welcome) can override it
/// with a nested AnnotatedRegion; leaving that screen restores this style.
/// Android 15+ ignores bar colors under edge-to-edge, but still uses icon
/// brightness and contrast enforcement. iOS uses statusBarBrightness.
@visibleForTesting
SystemUiOverlayStyle appSystemBarsStyleFor(Brightness brightness) {
  final window = brightness == Brightness.dark
      ? AppColors.dark.background.window
      : AppColors.light.background.window;
  final icons = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: window,
    statusBarBrightness: brightness,
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

abstract final class _IOSWindowAppearance {
  static const _channel = MethodChannel('com.zcash.wallet/window_appearance');

  static ThemeMode? _lastThemeMode;
  static Brightness? _lastResolvedBrightness;

  static void sync(ThemeMode themeMode, Brightness resolvedBrightness) {
    if (kIsWeb || !Platform.isIOS) return;
    if (_lastThemeMode == themeMode &&
        _lastResolvedBrightness == resolvedBrightness) {
      return;
    }
    _lastThemeMode = themeMode;
    _lastResolvedBrightness = resolvedBrightness;
    unawaited(_setBrightness(themeMode, resolvedBrightness));
  }

  static Future<void> _setBrightness(
    ThemeMode themeMode,
    Brightness resolvedBrightness,
  ) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', {
        'brightness': switch (themeMode) {
          ThemeMode.system => 'system',
          ThemeMode.dark => 'dark',
          ThemeMode.light => 'light',
        },
      });
    } catch (error) {
      _lastThemeMode = null;
      _lastResolvedBrightness = null;
      debugPrint('IOSWindowAppearance: sync failed: $error');
    }
  }
}
