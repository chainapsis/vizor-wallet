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
  const paymentProgress = bool.fromEnvironment(
    'ACTIVITY_CAPTURE_PAYMENT_PROGRESS',
  );
  final output = outputOverride.isEmpty
      ? '${Directory.current.path}/build/activity-processing-captures'
      : outputOverride;
  for (final pay in [false, true]) {
    if (paymentProgress && !pay) continue;
    if (details && pay) continue;
    final screen = pay
        ? paymentProgress
              ? mobile
                    ? 'pay-progress'
                    : 'pay-progress-availability'
              : 'pay-processing'
        : details
        ? 'swap-details'
        : 'swap-progress';
    runFigmaCompareCaptureTest(
      expectedFormFactor: formFactor,
      defaultLogicalSize: mobile ? const Size(393, 852) : const Size(700, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'activity-${pay ? 'pay' : 'swap'}-processing',
        themeMode: ThemeMode.dark,
        outputPath: '$output/$lane-$screen.png',
        logicalSize: mobile ? const Size(393, 852) : const Size(700, 720),
        pixelRatio: 1,
      ),
      beforeCapture: (tester) async {
        // Pay opens its details by default. For the additional swap capture,
        // use the same real tab interaction a user performs in Activity.
        if (pay) {
          expect(find.text('Tx ID'), findsOneWidget);
          if (paymentProgress) {
            if (mobile) {
              await tester.tap(find.text('Payment progress'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 100));
              expect(find.text('Tx ID'), findsNothing);
              expect(find.text('ZEC spent'), findsOneWidget);
              expect(find.text('Delivering USDC...'), findsOneWidget);
            } else {
              expect(find.text('Payment progress'), findsNothing);
              expect(find.text('Status'), findsOneWidget);
            }
          }
          return;
        }
        if (!details) return;
        await tester.tap(find.text('Transaction details'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (mobile) expect(find.text('Tx ID'), findsOneWidget);
      },
    );
  }
}
