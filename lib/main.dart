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
  // Window transparency test — `flutter_acrylic` only runs on the desktop
  // platforms (Windows / macOS / Linux). Initialize and apply the
  // transparent effect before the window is shown so the first frame
  // already carries the effect; `initializeDesktopWindow` below is what
  // actually brings the window on screen via `window_manager`.
  if (isDesktopLayoutPlatform) {
    log('main: initializing flutter_acrylic + transparent effect');
    await Window.initialize();
    await Window.setEffect(effect: WindowEffect.transparent);
  }
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}
