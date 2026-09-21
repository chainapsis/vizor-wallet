@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'figma_compare_capture_support.dart';

/// Run with --update-goldens and GIFT_CARD_CAPTURE_DIR outside the repository.
void main() {
  const output = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
  if (output.isEmpty) return;
  for (final scenario in figmaCompareScenarios.where(
    (s) =>
        s.mobile &&
        (s.id.startsWith('mobile-payment-link') ||
            s.id.startsWith('mobile-gift-card') ||
            s.id.startsWith('gift-card-') ||
            s.id.startsWith('activity-gift-card') && s.id.endsWith('-mobile')),
  )) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(393, 852),
        defaultPixelRatio: 3,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: scenario.id,
          themeMode: theme,
          outputPath: '$output/${theme.name}/${scenario.id}.png',
          logicalSize: const Size(393, 852),
          pixelRatio: 3,
        ),
      );
    }
  }
}
