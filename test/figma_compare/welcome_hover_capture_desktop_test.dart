@Tags(['figma-capture'])
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void main() {
  runFigmaCompareCaptureTest(
    expectedFormFactor: AppFormFactor.desktop,
    defaultLogicalSize: const Size(1080, 720),
    defaultPixelRatio: 1,
    overrideConfiguration: FigmaCompareConfiguration.fromEnvironment(
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      defaultScenarioId: 'desktop-onboarding-welcome-hover',
    ),
    beforeCapture: (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Activate gift card')));
      await tester.pump(const Duration(milliseconds: 200));
      addTearDown(mouse.removePointer);
    },
  );
}
