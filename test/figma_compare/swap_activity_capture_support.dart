import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void runSwapActivityCaptures(AppFormFactor formFactor) {
  final mobile = formFactor == AppFormFactor.mobile;
  final lane = mobile ? 'mobile' : 'desktop';
  const outputOverride = String.fromEnvironment('ACTIVITY_CAPTURE_OUTPUT');
  const details = bool.fromEnvironment('ACTIVITY_CAPTURE_DETAILS');
  final output = outputOverride.isEmpty
      ? '${Directory.current.path}/build/activity-processing-captures'
      : outputOverride;
  final viewport = mobile ? const Size(393, 852) : const Size(700, 820);
  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    for (final pay in [false, true]) {
      final flow = pay ? 'pay' : 'swap';
      final screen = details ? 'details' : 'progress';
      runFigmaCompareCaptureTest(
        expectedFormFactor: formFactor,
        defaultLogicalSize: viewport,
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'activity-$flow-processing',
          themeMode: theme,
          outputPath: '$output/$lane-$flow-$screen-${theme.name}.png',
          logicalSize: viewport,
          pixelRatio: 1,
        ),
        beforeCapture: (tester) async {
          expect(
            find.text(pay ? 'Payment progress' : 'Swap progress'),
            findsOneWidget,
          );
          expect(find.text('View on NEAR Intents'), findsOneWidget);
          if (!details) return;
          await tester.tap(find.text('Transaction details'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          // Repaint the whole surface: retained header layers can otherwise
          // be absent from a widget image after only the tab body repaints.
          for (final view in tester.binding.renderViews) {
            view.reassemble();
          }
          await tester.pump();
          expect(find.text('Tx ID'), findsOneWidget);
          expect(find.text('View on NEAR Intents'), findsNothing);
        },
      );
    }
  }
}
