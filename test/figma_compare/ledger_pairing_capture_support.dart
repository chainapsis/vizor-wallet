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
            expect(find.text('Ledger saved'), findsOneWidget);
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
    if (!mobile) ...['choice', 'usb', 'usb-checking', 'usb-failed'],
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
            'known-connecting' ||
            'usb-checking' => 'ledger-known-device-connecting',
            'usb-failed' => 'ledger-request-failed',
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
          if (!mobile) {
            expect(find.text('How would you like to connect?'), findsOneWidget);
            if (state == 'choice') return;
            await _chooseTransport(
              tester,
              state.startsWith('usb') ? 'usb' : 'bluetooth',
            );
            if (state.startsWith('usb')) {
              expect(
                find.text(switch (state) {
                  'usb-checking' => 'Checking your Ledger',
                  'usb-failed' => 'Couldn’t connect to your Ledger',
                  _ => 'Check your Ledger',
                }),
                findsOneWidget,
              );
              return;
            }
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
          }
          if (state == 'signing') {
            expect(find.text('Ledger saved'), findsOneWidget);
            tester
                .widget<AppButton>(
                  find.widgetWithText(AppButton, 'Find my Ledger'),
                )
                .onPressed!();
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            tester
                .widget<AppButton>(
                  find.widgetWithText(AppButton, 'Ledger Nano X · A37E'),
                )
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
          if (!mobile) await _chooseTransport(tester, 'bluetooth');
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

void runLedgerSavedCaptures({required bool mobile, required String output}) {
  for (final largeText in [false, if (mobile) true]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      final size = mobile ? const Size(393, 852) : const Size(800, 720);
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: largeText ? 'ledger-mobile-large-text' : 'ledger-saved',
          themeMode: theme,
          outputPath:
              '$output/${mobile ? 'mobile' : 'desktop'}/${theme.name}/saved${largeText ? '-large-text' : ''}.png',
          logicalSize: size,
          pixelRatio: 2,
        ),
        beforeCapture: (tester) async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (!mobile) await _chooseTransport(tester, 'bluetooth');
          tester
              .widget<AppButton>(
                find.widgetWithText(AppButton, 'Ledger Nano X · A37E'),
              )
              .onPressed!();
          await tester.pumpAndSettle();
          expect(find.text('Ledger saved'), findsOneWidget);
          expect(find.text('Ledger Nano X · A37E'), findsOneWidget);
          expect(find.text('Find my Ledger'), findsOneWidget);
          expect(find.text('Go back'), findsNothing);
          expect(find.text('Continue signing'), findsNothing);
        },
      );
    }
  }
}

Future<void> _chooseTransport(WidgetTester tester, String transport) async {
  tester
      .widget<AppButton>(find.byKey(ValueKey('ledger_choose_$transport')))
      .onPressed!();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
