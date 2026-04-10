import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/core/layout/app_layout.dart';
import 'src/providers/tor_settings_provider.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  log('main: initializing RustLib');
  await RustLib.init();
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  // Push the Tor cache directory into the Rust side and restore the
  // persisted Tor-enabled toggle before any sync can run. Runs before
  // `runApp` so the first widget build observes the correct state.
  await initTorAtStartup();
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}
