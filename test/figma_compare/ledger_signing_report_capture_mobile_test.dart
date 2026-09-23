@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'figma_compare_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_CAPTURE_DIR');
  if (output.isEmpty) return;
  for (final state in [
    'preparing',
    'checking',
    'opening',
    'processing',
    'processing-nano',
    'reviewing',
    'finishing',
    'processing-multiple',
    'voting-processing',
  ]) {
    for (final theme in [
      ThemeMode.dark,
      if (state == 'processing') ThemeMode.light,
    ]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(393, 852),
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'ledger-signing-$state',
          themeMode: theme,
          outputPath:
              '$output/mobile-$state${theme == ThemeMode.light ? "-light" : ""}.png',
          logicalSize: const Size(393, 852),
          pixelRatio: 1,
        ),
      );
    }
  }
}
