@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/slide_to_shield.dart';
import 'figma_compare_capture_support.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/keystone_shield_scanner_surface.dart';

Future<void> _advance(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  const output = String.fromEnvironment('KEYSTONE_CAPTURE_DIR');
  for (final shot in [
    (
      name: 'qr-contour',
      camera: null,
      seconds: 2.2,
      size: const Size(393, 852),
    ),
    (name: 'qr-fill', camera: null, seconds: 2.4, size: const Size(393, 852)),
    (
      name: 'qr-settling',
      camera: null,
      seconds: 2.55,
      size: const Size(393, 852),
    ),
    (
      name: 'qr-forming',
      camera: null,
      seconds: 2.3,
      size: const Size(393, 852),
    ),
    (name: 'qr-hold', camera: null, seconds: 3.5, size: const Size(393, 852)),
    (
      name: 'qr-buttons-entering',
      camera: null,
      seconds: 2.5,
      size: const Size(393, 852),
    ),
    (name: 'qr-small', camera: null, seconds: 3.5, size: const Size(320, 568)),
    (
      name: 'camera-buttons-changing',
      camera: 0.09,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'camera-forming',
      camera: 0.225,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'camera-clearing',
      camera: 0.15,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'camera-brackets',
      camera: 0.30,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'camera-settling',
      camera: 0.375,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'camera-ready',
      camera: 1.1,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'qr-return-forming',
      camera: 1.1,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'qr-return-ready',
      camera: 1.1,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'returning',
      camera: 8.225,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (
      name: 'buttons-leaving',
      camera: 8.07,
      seconds: 3.5,
      size: const Size(393, 852),
    ),
    (name: 'cloud', camera: 9.3, seconds: 3.5, size: const Size(393, 852)),
    (name: 'success', camera: 15.4, seconds: 3.5, size: const Size(393, 852)),
  ]) {
    group(shot.name, () {
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: shot.size,
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'mobile-keystone-shield-home-flow',
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
          for (var i = 0; i < 15; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 17));
          }
          final slider = find.byType(SlideToShield);
          final gesture = await tester.startGesture(
            tester.getTopLeft(slider) + const Offset(30, 25),
          );
          await gesture.moveBy(Offset(tester.getSize(slider).width - 60, 0));
          await gesture.up();
          await tester.pump();
          await _advance(tester, shot.seconds);
          if (shot.camera != null) {
            await tester.tap(find.text('Next step'));
            await tester.pump();
            await _advance(tester, shot.camera!);
          }
          if (shot.name.startsWith('qr-return-')) {
            await tester.tap(find.text('Show QR'));
            await tester.pump();
            await _advance(
              tester,
              shot.name == 'qr-return-forming' ? 0.3 : 0.9,
            );
            expect(find.text('Approve with Keystone'), findsOneWidget);
            if (shot.name == 'qr-return-ready') {
              final next = find.ancestor(
                of: find.text('Next step'),
                matching: find.byType(AppButton),
              );
              expect(tester.widget<AppButton>(next).onPressed, isNotNull);
            }
          }
          if (shot.name == 'qr-buttons-entering' ||
              shot.name == 'buttons-leaving') {
            final footer = tester.widget<Opacity>(
              find.byKey(const ValueKey('mobile_keystone_footer_visibility')),
            );
            expect(footer.opacity, inExclusiveRange(0.0, 1.0));
          }
          if (shot.name == 'camera-forming' || shot.name == 'returning') {
            final morph = tester
                .widget<KeystoneShieldScannerSurface>(
                  find.byType(KeystoneShieldScannerSurface),
                )
                .morph;
            expect(morph.scannerOpacity, inExclusiveRange(0.0, 1.0));
            expect(morph.cloudReady, isFalse);
          }
          if (shot.name == 'qr-hold' || shot.name == 'qr-small') {
            final black = tester.widget<ColoredBox>(
              find.byKey(const ValueKey('mobile_keystone_black_background')),
            );
            expect(black.color, Colors.black);
            expect(find.text('Approve with Keystone'), findsOneWidget);
            final next = find.ancestor(
              of: find.text('Next step'),
              matching: find.byType(AppButton),
            );
            expect(tester.widget<AppButton>(next).onPressed, isNotNull);
          }
          if (shot.name == 'success') {
            expect(
              find.byKey(const ValueKey('mobile_shield_complete')),
              findsOneWidget,
            );
          }
        },
      );
    });
  }
}
