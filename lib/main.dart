import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_desktop_window/zcash_desktop_window.dart';

import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'src/core/layout/app_layout.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  log('main: initializing RustLib');
  await RustLib.init();
  // Order matters: window_manager creates and shows the NSWindow inside
  // `initializeDesktopWindow`; the acrylic setup is only effective once
  // that window exists.
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('main: initializing desktop window visuals');
    await ZcashDesktopWindow.initialize();
    // On macOS the full-size content view is now enabled natively before the
    // first show, so window_manager's aspect-ratio branch needs a post-bootstrap
    // refresh to land on the correct NSWindow property.
    await reapplyDesktopWindowConstraints();
    await windowManager.setSize(
      AppLayoutMode.large.defaultSize,
      animate: false,
    );
    await showDesktopWindow();
  }
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}
