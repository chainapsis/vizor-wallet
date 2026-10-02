@Tags(['mobile', 'figma-capture'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'figma_compare_font_loader.dart';

void main() {
  const output = String.fromEnvironment('PASSCODE_CAPTURE_DIR');
  const baseline = bool.fromEnvironment('PASSCODE_CAPTURE_BASELINE');
  if (output.isEmpty) return;
  setUpAll(loadFigmaCompareFonts);
  for (final viewport in <String, Size>{
    'phone': const Size(393, 852),
    'ipad-mini': const Size(375, 667),
    'ipad-pro13': const Size(390, 844),
  }.entries) {
    for (final screen in ['unlock', 'create', 'confirm']) {
      testWidgets('${viewport.key} $screen', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const appearance = MethodChannel('com.zcash.wallet/window_appearance');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(appearance, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(appearance, null));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = viewport.value;
        addTearDown(tester.view.reset);
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          if (baseline &&
              details.exceptionAsString().contains('A RenderFlex overflowed')) {
            errors.add(details.exceptionAsString());
          } else {
            original?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = original);
        final boundary = GlobalKey();
        final id = screen == 'unlock'
            ? 'passcode-review-unlock'
            : 'passcode-review-create';
        await tester.pumpWidget(
          FigmaCompareApp(
            scenario: figmaCompareScenarios.firstWhere((s) => s.id == id),
            themeMode: ThemeMode.dark,
            captureBoundaryKey: boundary,
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'confirm') {
          for (var i = 0; i < 6; i++) {
            tester
                .widget<PasscodeNumpad>(find.byType(PasscodeNumpad))
                .onDigit(1);
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(find.text('Confirm Passcode'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory(output)..createSync(recursive: true);
          File(
            '${dir.path}/${viewport.key}-$screen.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          File('${dir.path}/${viewport.key}-$screen.json').writeAsStringSync(
            jsonEncode({'errors': errors, 'size': '${viewport.value}'}),
          );
          image.dispose();
        });
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
