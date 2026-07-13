// ignore_for_file: depend_on_referenced_packages
// This is a dev-only entry point and is not reachable from lib/main.dart.

import 'dart:io';

import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'figma_compare/figma_compare_app.dart';
import 'figma_compare/figma_compare_capture.dart';
import 'figma_compare/figma_compare_configuration.dart';
import 'src/core/layout/app_layout.dart';

const _settleDelayMs = int.fromEnvironment(
  'FIGMA_COMPARE_SETTLE_MS',
  defaultValue: 350,
);
const _exitAfterCapture = bool.fromEnvironment(
  'FIGMA_COMPARE_EXIT_AFTER_CAPTURE',
  defaultValue: true,
);
const _startMinimized = bool.fromEnvironment('FIGMA_COMPARE_START_MINIMIZED');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configuration = FigmaCompareConfiguration.fromEnvironment();
  final scenario = configuration.resolveScenario(kAppFormFactor);

  // Match the production macOS bootstrap. The comparison entry point omits
  // Rust runtime, wallet, storage, sync, and network initialization.
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    await DesktopWindowBootstrap.initialize(
      visualStyle: DesktopWindowVisualStyle.opaque,
    );
    if (!Platform.isWindows) await showDesktopWindow();
  }

  final captureBoundaryKey = GlobalKey();
  runApp(
    FigmaCompareApp(
      scenario: scenario,
      themeMode: configuration.themeMode,
      captureBoundaryKey: captureBoundaryKey,
    ),
  );

  if (configuration.outputPath.isEmpty) {
    debugPrint(
      'Figma comparison ready: ${scenario.id} (${scenario.description})',
    );
    return;
  }

  if (_startMinimized && Platform.isMacOS) {
    await WidgetsBinding.instance.endOfFrame;
    // AppThemeHost may still be synchronizing native light/dark appearance and
    // restoring the production frame during the first 120 ms after launch.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await windowManager.minimize();
    var minimized = false;
    for (var attempt = 0; attempt < 40; attempt += 1) {
      minimized = await windowManager.isMinimized();
      if (minimized) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!minimized) {
      throw StateError('The comparison window did not minimize for testing.');
    }
  }

  final captureController = FigmaCompareCaptureController(
    captureBoundaryKey: captureBoundaryKey,
  );
  final outputPath = resolveFigmaCompareOutputPath(configuration.outputPath);
  await captureController.capture(
    contentOutputPath: outputPath,
    pixelRatio: configuration.pixelRatio,
    settleDelay: Duration(milliseconds: _settleDelayMs),
  );
  debugPrint('Figma comparison content: $outputPath');
  if (Platform.isMacOS) {
    debugPrint(
      'Figma comparison window: ${figmaCompareWindowCapturePath(outputPath)}',
    );
  }

  if (_exitAfterCapture) exit(0);
}
