@Tags(['mobile'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import '../../../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_numeric_keyboard_toolbar.dart';

const toolbar = ValueKey('mobile_numeric_keyboard_toolbar');
const captureKey = ValueKey('numeric_keyboard_capture');

Future<void> pumpHost(
  WidgetTester tester, {
  TextInputType type = TextInputType.number,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLegacyLightTheme(),
      builder: (context, child) => AppTheme(
        data: AppThemeData.light,
        child: RepaintBoundary(
          key: captureKey,
          child: MobileNumericKeyboardToolbar(child: child!),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextField(key: const ValueKey('number'), keyboardType: type),
              const TextField(key: ValueKey('text')),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: const TextField(
                      key: ValueKey('sheet-number'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final type in [
    TextInputType.number,
    const TextInputType.numberWithOptions(decimal: true),
    TextInputType.phone,
  ]) {
    testWidgets('Done dismisses $type and reserves toolbar space', (
      tester,
    ) async {
      await pumpHost(tester, type: type);
      await tester.enterText(find.byKey(const ValueKey('number')), '123');
      await tester.pump();
      expect(find.byKey(toolbar), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(toolbar), findsOneWidget);
      const captureDirectory = String.fromEnvironment(
        'NUMERIC_KEYBOARD_CAPTURE_DIR',
      );
      if (captureDirectory.isNotEmpty) {
        final output = File('$captureDirectory/numeric-keyboard.png');
        output.parent.createSync(recursive: true);
        await expectLater(
          find.byKey(captureKey),
          matchesGoldenFile(output.uri),
        );
      }
      expect(
        tester.getRect(find.byKey(toolbar)),
        const Rect.fromLTWH(0, 500, 390, 44),
      );
      expect(
        MediaQuery.viewInsetsOf(tester.element(find.byType(Scaffold))).bottom,
        344,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(toolbar), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('123'), findsOneWidget);
    });
  }

  testWidgets('text focus and OS dismissal hide the toolbar', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const ValueKey('number')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('text')));
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('number')));
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsNothing);
  });

  testWidgets('numeric field in modal sheet gets Done too', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sheet-number')), '10');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsNothing);
    expect(find.text('10'), findsOneWidget);
  });
}
