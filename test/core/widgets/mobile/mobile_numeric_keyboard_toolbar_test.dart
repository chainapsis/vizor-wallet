@Tags(['mobile'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? buildLegacyDarkTheme() : buildLegacyLightTheme(),
      builder: (context, child) => AppTheme(
        data: dark ? AppThemeData.dark : AppThemeData.light,
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
  testWidgets('iOS uses native control and dismisses through channel', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('com.zcash.wallet/numeric_keyboard');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await pumpHost(tester);
    await tester.enterText(find.byKey(const ValueKey('number')), '123');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'visible': true, 'dark': false});
    expect(find.byKey(toolbar), findsNothing);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('dismiss')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(calls.last.arguments['visible'], isFalse);
    expect(find.text('123'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final type in [
    TextInputType.number,
    const TextInputType.numberWithOptions(decimal: true),
    TextInputType.phone,
  ]) {
    testWidgets('Done dismisses $type without resizing content', (
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
        const Rect.fromLTWH(326, 480, 48, 48),
      );
      expect(
        MediaQuery.viewInsetsOf(tester.element(find.byType(Scaffold))).bottom,
        300,
      );
      await tester.tap(find.byKey(toolbar));
      await tester.pumpAndSettle();
      expect(find.byKey(toolbar), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('123'), findsOneWidget);
    });
  }

  testWidgets('dark floating button retains accessible Done action', (
    tester,
  ) async {
    await pumpHost(tester, dark: true);
    await tester.enterText(find.byKey(const ValueKey('number')), '123');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Done'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    const outputDir = String.fromEnvironment('NUMERIC_KEYBOARD_CAPTURE_DIR');
    if (outputDir.isNotEmpty) {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(File('$outputDir/numeric-keyboard-dark.png').uri),
      );
    }
    await tester.tap(find.byKey(toolbar));
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsNothing);
  });

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
    await tester.tap(find.byKey(toolbar));
    await tester.pumpAndSettle();
    expect(find.byKey(toolbar), findsNothing);
    expect(find.text('10'), findsOneWidget);
  });
}
