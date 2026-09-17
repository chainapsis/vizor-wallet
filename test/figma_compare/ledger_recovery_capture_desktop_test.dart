@Tags(['figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
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
  runLedgerSelectionCaptures(mobile: false, output: output);
  runLedgerPairingCaptures(mobile: false, output: output);
  for (final scenario in figmaCompareScenarios.where(
    (s) => s.desktop && s.id.startsWith('ledger-recovery-'),
  )) {
    for (final theme in [ThemeMode.dark, ThemeMode.light]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.desktop,
        defaultLogicalSize: const Size(800, 640),
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: scenario.id,
          themeMode: theme,
          outputPath: '$output/desktop/${theme.name}/${scenario.id}.png',
          logicalSize: const Size(800, 640),
          pixelRatio: 2,
        ),
      );
    }
  }
  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(800, 640),
      defaultPixelRatio: 2,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'ledger-recovery-permission',
        themeMode: theme,
        outputPath: '$output/desktop/${theme.name}/ledger-recovery-usb.png',
        logicalSize: const Size(800, 640),
        pixelRatio: 2,
      ),
      beforeCapture: (tester) async {
        // Capture scenes intentionally ignore pointers; invoke the same action.
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('ledger_recovery_usb')),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        expect(find.text('Connect your Ledger via USB'), findsOneWidget);
        expect(find.text('Open settings'), findsNothing);
      },
    );
  }
}
