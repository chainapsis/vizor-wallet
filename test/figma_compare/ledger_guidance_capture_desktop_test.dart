@Tags(['figma-capture'])
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
    'ledger-onboarding-access-preparing',
    'ledger-onboarding-access-restricted',
    'ledger-onboarding-usb-error',
    'ledger-onboarding-viewing-key-approval',
    'ledger-pairing-invalid',
    'ledger-signing-processing',
    'ledger-signing-processing-nano',
  ]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.desktop,
        defaultLogicalSize: const Size(1080, 720),
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: id,
          themeMode: theme,
          outputPath: '$output/desktop/${theme.name}/$id.png',
          logicalSize: const Size(1080, 720),
          pixelRatio: 1,
        ),
      );
    }
  }
}
