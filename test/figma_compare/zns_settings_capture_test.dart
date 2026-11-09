@Tags(['figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Desktop Settings scrolled to the Zcash names toggle: off, as on a new
/// install, and after the user turns it on. Run with
/// `--dart-define=ZNS_CAPTURE_DIR=<absolute dir>` to write the PNGs.
void main() {
  const output = String.fromEnvironment('ZNS_CAPTURE_DIR');
  for (final (name, turnOn) in [
    ('zns-desktop-settings-off', false),
    ('zns-desktop-settings-on', true),
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'zns-desktop-settings',
        themeMode: ThemeMode.dark,
        logicalSize: const Size(1080, 720),
        pixelRatio: 1,
        outputPath: output.isEmpty ? '' : '$output/$name.png',
      ),
      beforeCapture: (tester) async {
        final toggle = find.byKey(const ValueKey('settings_zns_names_toggle'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.ensureVisible(toggle);
        await tester.pump(const Duration(milliseconds: 400));
        if (turnOn) {
          await tester.tap(toggle);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );
  }
}
