@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/slide_to_shield.dart';

import 'figma_compare_capture_support.dart';

void main() {
  const output = String.fromEnvironment('SHIELD_CAPTURE_DIR');
  for (final shot in [
    (name: 'review', seconds: 0.0, size: const Size(393, 852)),
    (name: 'cloud', seconds: 2.4, size: const Size(393, 852)),
    (name: 'wave', seconds: 5.72, size: const Size(393, 852)),
    (name: 'resolve', seconds: 6.9, size: const Size(393, 852)),
    (name: 'result', seconds: 8.6, size: const Size(393, 852)),
    (name: 'review-small', seconds: 0.0, size: const Size(320, 568)),
  ]) {
    group(shot.name, () {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: shot.size,
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'mobile-shield-home-flow',
          themeMode: ThemeMode.light,
          logicalSize: shot.size,
          pixelRatio: 1,
          outputPath: output.isEmpty ? '' : '$output/${shot.name}.png',
        ),
        beforeCapture: (tester) async {
          tester.view.padding = FakeViewPadding(
            top: shot.size.width == 320 ? 24 : 59,
            bottom: shot.size.width == 320 ? 0 : 34,
          );
          addTearDown(tester.view.resetPadding);
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('mobile_home_shield_balance_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 17));
          }
          expect(find.text('Transparent Balance'), findsOneWidget);
          if (shot.seconds == 0) return;
          final slider = find.byType(SlideToShield);
          final gesture = await tester.startGesture(
            tester.getTopLeft(slider) + const Offset(30, 25),
          );
          await gesture.moveBy(Offset(tester.getSize(slider).width - 60, 0));
          await gesture.up();
          await tester.pump();
          final frames = (shot.seconds * 60).round();
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(microseconds: 16667));
          }
          if (shot.name == 'result') {
            expect(find.text('Shielded successfully'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('mobile_shield_complete')),
              findsOneWidget,
            );
          } else {
            expect(
              find.byKey(const ValueKey('mobile_shield_complete')),
              findsNothing,
            );
          }
        },
      );
    });
  }
}
