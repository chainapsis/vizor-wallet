import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void main() {
  for (final scenario in [
    'caps-lock-unlock',
    'caps-lock-set-password',
    'caps-lock-confirm-password',
    'caps-lock-settings',
    'caps-lock-remove-account',
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: scenario,
        themeMode: ThemeMode.dark,
        outputPath: '',
        logicalSize: const Size(1080, 720),
        pixelRatio: 1,
      ),
      beforeCapture: (tester) async {
        expect(find.text('Caps Lock is on'), findsOneWidget);
      },
    );
  }
}
