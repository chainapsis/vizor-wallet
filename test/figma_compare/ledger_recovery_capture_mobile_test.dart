@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'figma_compare_capture_support.dart';
import 'ledger_pairing_capture_support.dart';

// Supply an absolute output directory outside the repository.
void main() {
  const output = String.fromEnvironment('LEDGER_CAPTURE_DIR');
  if (output.isEmpty) return;
  runLedgerPairingCaptures(mobile: true, output: output);
  for (final scenario in figmaCompareScenarios.where(
    (s) => s.mobile && s.id.startsWith('ledger-recovery-'),
  )) {
    for (final theme in [ThemeMode.dark, ThemeMode.light]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(393, 852),
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: scenario.id,
          themeMode: theme,
          outputPath: '$output/mobile/${theme.name}/${scenario.id}.png',
          logicalSize: const Size(393, 852),
          pixelRatio: 2,
        ),
      );
    }
  }
}
