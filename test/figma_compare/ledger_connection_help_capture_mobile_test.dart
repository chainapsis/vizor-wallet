@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_connection_help.dart';

import 'figma_compare_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_HELP_CAPTURE_DIR');
  if (output.isEmpty) return;
  for (final stage in ['ledger', 'phone']) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(393, 852),
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'mobile-shield-ledger-connection-help',
          themeMode: theme,
          outputPath: '$output/inline/${theme.name}/$stage.png',
          logicalSize: const Size(393, 852),
          pixelRatio: 1,
        ),
        beforeCapture: (tester) async {
          if (stage == 'phone') {
            await tester.tap(find.text('Next: phone settings'));
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 40));
            }
          }
        },
      );
    }
  }
  for (final platform in ['ios', 'android']) {
    for (final state in [
      'empty',
      'checks',
      'ledger-nano',
      'ledger-flex',
      'phone-nano',
      'phone-flex',
      'search',
    ]) {
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        runFigmaCompareCaptureTest(
          expectedFormFactor: AppFormFactor.mobile,
          defaultLogicalSize: const Size(393, 852),
          defaultPixelRatio: 1,
          overrideConfiguration: FigmaCompareConfiguration(
            scenarioId: 'ledger-mobile-connection-help-$platform',
            themeMode: theme,
            outputPath: '$output/$platform/${theme.name}/$state.png',
            logicalSize: const Size(393, 852),
            pixelRatio: 1,
          ),
          beforeCapture: (tester) async {
            Future<void> press(String label) async {
              await tester.ensureVisible(find.text(label));
              await tester.tap(find.text(label));
              await tester.pumpAndSettle();
            }

            if (state == 'empty') return;
            await press('Connection help');
            if (state == 'checks') return;
            await press('Reset Bluetooth pairing');
            tester
                .widget<DropdownButton<LedgerHelpModel>>(
                  find.byType(DropdownButton<LedgerHelpModel>),
                )
                .onChanged!(
              state.endsWith('nano')
                  ? LedgerHelpModel.nanoX
                  : LedgerHelpModel.flex,
            );
            await tester.pumpAndSettle();
            if (state.startsWith('ledger')) return;
            await press('Next: phone settings');
            if (state.startsWith('phone')) return;
            await press('Next: search in Vizor');
          },
        );
      }
    }
  }
}
