@Tags(['figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'figma_compare_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_CAPTURE_DIR');
  if (output.isEmpty) return;
  for (final state in ['default', 'usb-hover', 'bluetooth-hover']) {
    group('connection picker $state', () {
      for (final theme in [ThemeMode.dark, ThemeMode.light]) {
        runFigmaCompareCaptureTest(
          expectedFormFactor: AppFormFactor.desktop,
          defaultLogicalSize: const Size(1080, 720),
          defaultPixelRatio: 1,
          overrideConfiguration: FigmaCompareConfiguration(
            scenarioId: 'ledger-device-selection',
            themeMode: theme,
            outputPath: '$output/connection-picker-$state-${theme.name}.png',
            logicalSize: const Size(1080, 720),
            pixelRatio: 1,
          ),
          beforeCapture: (tester) async {
            expect(
              find.text('Connect the Ledger for this account.'),
              findsOneWidget,
            );
            if (state == 'default') return;
            final target = find
                .byKey(
                  ValueKey(
                    state == 'usb-hover'
                        ? 'ledger_choose_usb'
                        : 'ledger_choose_bluetooth',
                  ),
                )
                .hitTestable();
            expect(target, findsOneWidget);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            addTearDown(mouse.removePointer);
            await mouse.moveTo(tester.getCenter(target));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));
          },
        );
      }
    });
  }
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
    'proofs-pending',
    'declined',
    'tex-declined',
    'save-failed',
    'cancelling',
  ]) {
    for (final theme in [
      ThemeMode.dark,
      if (state == 'processing') ThemeMode.light,
    ]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.desktop,
        defaultLogicalSize: const Size(1080, 720),
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'ledger-signing-$state',
          themeMode: theme,
          outputPath:
              '$output/desktop-$state${theme == ThemeMode.light ? "-light" : ""}.png',
          logicalSize: const Size(1080, 720),
          pixelRatio: 1,
        ),
      );
    }
  }
  for (final id in [
    'ledger-recovery-permission',
    'ledger-searching-devices',
    'ledger-known-device-connecting',
    'ledger-request-declined',
    'ledger-pairing-invalid',
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: id,
        themeMode: ThemeMode.dark,
        outputPath: '$output/$id.png',
        logicalSize: const Size(1080, 720),
        pixelRatio: 1,
      ),
      beforeCapture: (tester) async {
        if (id == 'ledger-searching-devices' ||
            id == 'ledger-known-device-connecting' ||
            id == 'ledger-request-declined') {
          await tester.tap(
            find.byKey(const ValueKey('ledger_choose_bluetooth')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          if (id == 'ledger-searching-devices') {
            expect(find.text('Searching for nearby Ledgers…'), findsOneWidget);
          } else {
            await tester.tap(find.text('Ledger Flex · F52C'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(
              find.text(
                id == 'ledger-request-declined'
                    ? 'Request declined'
                    : 'Unlock Ledger and confirm opening Zcash if prompted.',
              ),
              findsOneWidget,
            );
          }
        }
      },
    );
  }
}
