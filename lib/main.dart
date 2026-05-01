import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';

import 'app.dart';
import 'src/app_bootstrap.dart';
import 'src/core/layout/app_layout.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  log('main: initializing RustLib');
  await RustLib.init();
  // Order matters: window_manager creates and shows the NSWindow inside
  // `initializeDesktopWindow`; the acrylic setup is only effective once
  // that window exists.
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('main: initializing desktop window visuals');
    await DesktopWindowBootstrap.initialize();
    if (!Platform.isWindows) {
      await showDesktopWindow();
    }
  }
  final bootstrap = await loadAppBootstrap();
  log('main: launching app');
  runApp(
    ProviderScope(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
      child: const ZcashWalletApp(),
    ),
  );
  if (isDesktopLayoutPlatform && Platform.isWindows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(showDesktopWindow());
    });
  }
}
