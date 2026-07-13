// ignore_for_file: depend_on_referenced_packages
// This is a dev-only entry point and is not reachable from lib/main.dart.

import 'dart:io';

import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'figma_compare/figma_compare_app.dart';
import 'figma_compare/figma_compare_capture.dart';
import 'figma_compare/figma_compare_scenarios.dart';
import 'src/core/layout/app_layout.dart';

const _scenarioId = String.fromEnvironment(
  'FIGMA_COMPARE_SCENARIO',
  defaultValue: 'pay-recipient',
);
const _themeName = String.fromEnvironment(
  'FIGMA_COMPARE_THEME',
  defaultValue: 'dark',
);
const _outputPath = String.fromEnvironment('FIGMA_COMPARE_OUTPUT');
const _pixelRatioText = String.fromEnvironment(
  'FIGMA_COMPARE_PIXEL_RATIO',
  defaultValue: '1',
);
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

  final scenario = findFigmaCompareScenario(_scenarioId);
  if (scenario == null) {
    final available = figmaCompareScenarios.map((item) => item.id).join(', ');
    throw ArgumentError.value(
      _scenarioId,
      'FIGMA_COMPARE_SCENARIO',
      'Unknown scenario. Available: $available',
    );
  }
  if (kAppFormFactor == AppFormFactor.desktop && !scenario.desktop) {
    throw StateError('Scenario ${scenario.id} does not support desktop.');
  }
  if (kAppFormFactor == AppFormFactor.mobile && !scenario.mobile) {
    throw StateError('Scenario ${scenario.id} does not support mobile.');
  }

  // Match the production macOS bootstrap. The comparison entry point omits
  // only Rust, wallet, storage, sync, and network initialization.
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
      themeMode: _themeName == 'light' ? ThemeMode.light : ThemeMode.dark,
      captureBoundaryKey: captureBoundaryKey,
    ),
  );

  if (_outputPath.isEmpty) {
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
  final outputPath = resolveFigmaCompareOutputPath(_outputPath);
  final pixelRatio = double.tryParse(_pixelRatioText);
  if (pixelRatio == null || pixelRatio <= 0) {
    throw ArgumentError.value(
      _pixelRatioText,
      'FIGMA_COMPARE_PIXEL_RATIO',
      'Expected a positive number.',
    );
  }
  await captureController.capture(
    contentOutputPath: outputPath,
    pixelRatio: pixelRatio,
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
