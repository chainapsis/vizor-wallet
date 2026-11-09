@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_GUIDANCE_CAPTURE_DIR');
  if (output.isEmpty) return;
  for (final id in [
    'ledger-recovery-permission-restricted',
    'ledger-recovery-restricted-android',
    'ledger-recovery-restricted-location',
  ]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(393, 852),
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: id,
          themeMode: theme,
          outputPath: '$output/mobile/${theme.name}/$id.png',
          logicalSize: const Size(393, 852),
          pixelRatio: 1,
        ),
        beforeCapture: (tester) async {
          expect(find.text('Close'), findsOneWidget);
          expect(find.text('Open settings'), findsOneWidget);
          expect(
            find.textContaining(
              id == 'ledger-recovery-restricted-android'
                  ? 'Check Nearby devices access'
                  : id == 'ledger-recovery-restricted-location'
                  ? 'Check location access'
                  : 'Check Vizor’s Bluetooth access',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
}
