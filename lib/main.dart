import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/core/layout/app_layout.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  log('main: initializing RustLib');
  await RustLib.init();
  if (isDesktopLayoutPlatform) {
    log('main: initializing flutter_acrylic + transparent effect');
    await _configureTransparentWindow();
  }
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}

/// Wire the native window for the acrylic blur effect using
/// flutter_acrylic's own APIs. Mixing window_manager's `TitleBarStyle`
/// with these has produced incorrect colors in practice — the package
/// expects to own the titlebar / background state itself.
///
/// Acrylic is a frosted-glass blur that lets the desktop behind show
/// through with a tinted blur. Windows / macOS support it natively;
/// Linux has no matching material so it falls back to plain transparent.
/// Per-platform recipe lifted from the flutter_acrylic example and
/// README.
Future<void> _configureTransparentWindow() async {
  await Window.initialize();

  if (Platform.isMacOS) {
    // Clear the NSWindow background and fold the Flutter content into the
    // title strip so the acrylic material applies to one continuous
    // surface. Traffic-light controls stay visible and draggable.
    await Window.setWindowBackgroundColorToClear();
    await Window.makeTitlebarTransparent();
    await Window.enableFullSizeContentView();
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: Colors.transparent,
    );
  } else if (Platform.isWindows) {
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      // Acrylic needs a tint color to blend with the blur result. Matches
      // the flutter_acrylic example's dark preset.
      color: const Color(0xCC222222),
      dark: true,
    );
  } else {
    // Linux — acrylic is not available; transparent is the closest thing
    // the plugin exposes there.
    await Window.setEffect(effect: WindowEffect.transparent);
  }
}
