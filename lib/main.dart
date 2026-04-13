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

/// Wire the native window for the full transparent effect using
/// flutter_acrylic's own APIs. Mixing window_manager's `TitleBarStyle`
/// with these has produced incorrect colors in practice — the package
/// expects to own the titlebar / background state itself.
///
/// Per-platform recipe lifted from the flutter_acrylic example and
/// README.
Future<void> _configureTransparentWindow() async {
  await Window.initialize();

  if (Platform.isMacOS) {
    // Clear the NSWindow background and fold the Flutter content up into
    // the title strip so it's one continuous transparent surface.
    // `makeTitlebarTransparent` + `enableFullSizeContentView` is the
    // flutter_acrylic-recommended pair for a titlebar-less look on macOS;
    // traffic-light controls stay visible and draggable.
    await Window.setWindowBackgroundColorToClear();
    await Window.makeTitlebarTransparent();
    await Window.enableFullSizeContentView();
    await Window.setEffect(
      effect: WindowEffect.transparent,
      color: Colors.transparent,
    );
  } else if (Platform.isWindows) {
    await Window.hideWindowControls();
    await Window.setEffect(
      effect: WindowEffect.transparent,
      // The example file uses a semi-opaque dark fill for Windows; pure
      // transparent can look washed out with some compositor settings.
      color: const Color(0xCC222222),
      dark: true,
    );
  } else {
    // Linux
    await Window.setEffect(effect: WindowEffect.transparent);
  }
}
