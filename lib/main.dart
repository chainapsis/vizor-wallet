import 'package:flutter/material.dart';
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
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}
