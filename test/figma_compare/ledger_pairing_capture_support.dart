import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'figma_compare_capture_support.dart';

void runLedgerPairingCaptures({required bool mobile, required String output}) {
  for (final state in [
    'failed',
    'pairing-invalid',
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
          scenarioId: state == 'pairing-invalid'
              ? 'ledger-pairing-invalid'
              : 'ledger-repairing',
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

          if (['devices', 'ready', 'updated', 'mismatch'].contains(state)) {
            await press('Try again');
          }
          if (state == 'ready') {
            await press('Ledger Flex · F52C');
            expect(find.text('Your Ledger is connected'), findsOneWidget);
          }
          if (state == 'updated') {
            await press('Ledger Nano X · A37E');
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
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
    'searching',
    'searching-devices',
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
          scenarioId: switch (state) {
            'searching' => 'ledger-searching',
            'searching-devices' => 'ledger-searching-devices',
            'known-connecting' => 'ledger-known-device-connecting',
            _ => 'ledger-device-selection',
          },
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
          expect(
            find.text(
              state == 'searching'
                  ? 'Finding your Ledger'
                  : 'Select your Ledger',
            ),
            findsOneWidget,
          );
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
            if (state == 'signing') {
              await tester.pump(const Duration(seconds: 1));
              await tester.pump();
            }
          }
        },
      );
    }
  }
}

void runLedgerRequestFailureCaptures({
  required bool mobile,
  required String output,
}) {
  for (final kind in ['declined', 'failed']) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      final size = mobile ? const Size(393, 852) : const Size(800, 720);
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'ledger-request-$kind',
          themeMode: theme,
          outputPath:
              '$output/${mobile ? 'mobile' : 'desktop'}/${theme.name}/request-$kind.png',
          logicalSize: size,
          pixelRatio: 2,
        ),
        beforeCapture: (tester) async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          tester
              .widget<AppButton>(
                find.widgetWithText(AppButton, 'Ledger Flex · F52C'),
              )
              .onPressed!();
          await tester.pumpAndSettle();
          expect(
            find.text(
              kind == 'declined'
                  ? 'Request declined'
                  : 'Couldn’t complete the request',
            ),
            findsOneWidget,
          );
          expect(find.text('Did you reset pairing?'), findsNothing);
          expect(find.text('Try again'), findsOneWidget);
        },
      );
    }
  }
}
