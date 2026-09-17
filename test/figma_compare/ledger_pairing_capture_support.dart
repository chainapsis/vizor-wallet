import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'figma_compare_capture_support.dart';

void runLedgerPairingCaptures({required bool mobile, required String output}) {
  for (final state in [
    'collapsed',
    'expanded',
    'devices',
    'ready',
    'updated',
    'mismatch',
  ]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      final size = mobile ? const Size(393, 852) : const Size(800, 720);
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'ledger-repairing',
          themeMode: theme,
          outputPath:
              '$output/${mobile ? 'mobile' : 'desktop'}/${theme.name}/pairing-$state.png',
          logicalSize: size,
          pixelRatio: 2,
        ),
        beforeCapture: (tester) async {
          Future<void> press(String label) async {
            tester
                .widget<AppButton>(find.widgetWithText(AppButton, label))
                .onPressed!();
            await tester.pumpAndSettle();
          }

          if (state == 'expanded') await press('Did you reset pairing?');
          if (['devices', 'ready', 'updated', 'mismatch'].contains(state)) {
            await press('Find my Ledger');
          }
          if (state == 'ready') {
            await press('Ledger Flex · F52C');
            expect(find.text('Your Ledger is connected'), findsOneWidget);
          }
          if (state == 'updated') {
            await press('Ledger Nano X · A37E');
            expect(
              find.textContaining('saved connection has been updated'),
              findsOneWidget,
            );
          }
          if (state == 'mismatch') {
            await press('Ledger Stax');
            expect(find.text('This Ledger doesn’t match'), findsOneWidget);
          }
        },
      );
    }
  }
}

void runLedgerSelectionCaptures({
  required bool mobile,
  required String output,
}) {
  for (final state in [
    'devices',
    'known-connecting',
    'known-signing',
    'mismatch',
    'signing',
    if (!mobile) 'usb',
  ]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      final size = mobile ? const Size(393, 852) : const Size(800, 720);
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: state == 'known-connecting'
              ? 'ledger-known-device-connecting'
              : 'ledger-device-selection',
          themeMode: theme,
          outputPath:
              '$output/${mobile ? 'mobile' : 'desktop'}/${theme.name}/selection-$state.png',
          logicalSize: size,
          pixelRatio: 2,
        ),
        beforeCapture: (tester) async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.text('Select your Ledger'), findsOneWidget);
          final label = switch (state) {
            'known-connecting' || 'known-signing' => 'Ledger Flex · F52C',
            'mismatch' => 'Ledger Stax',
            'signing' => 'Ledger Nano X · A37E',
            'usb' => 'USB',
            _ => null,
          };
          if (label != null) {
            tester
                .widget<AppButton>(find.widgetWithText(AppButton, label))
                .onPressed!();
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          }
        },
      );
    }
  }
}
