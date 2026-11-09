@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Mobile Settings scrolled to the Zcash names toggle: off, as on a new
/// install, and after the user turns it on. Run with
/// `--dart-define=ZNS_CAPTURE_DIR=<absolute dir>` to write the PNGs.
void main() {
  const output = String.fromEnvironment('ZNS_CAPTURE_DIR');
  for (final (name, turnOn) in [
    ('zns-mobile-settings-off', false),
    ('zns-mobile-settings-on', true),
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.mobile,
      defaultLogicalSize: const Size(393, 852),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'zns-mobile-settings',
        themeMode: ThemeMode.dark,
        logicalSize: const Size(393, 852),
        pixelRatio: 1,
        outputPath: output.isEmpty ? '' : '$output/$name.png',
      ),
      beforeCapture: (tester) async {
        final toggle = find.byKey(
          const ValueKey('mobile_settings_zns_names_row'),
        );
        await tester.pump(const Duration(milliseconds: 200));
        // The settings list builds rows lazily, so scroll the row into
        // existence before centering it.
        await tester.scrollUntilVisible(
          toggle,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Start the shot at the Privacy card's title, so both states frame
        // the same rows.
        await tester.runAsync(
          () => Scrollable.ensureVisible(
            tester.element(find.text('Privacy').last),
            alignment: 0.1,
          ),
        );
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
