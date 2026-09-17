@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
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
  const channel = MethodChannel('com.zcash.wallet/numeric_keyboard');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final type in [
    TextInputType.number,
    const TextInputType.numberWithOptions(decimal: true),
    TextInputType.phone,
  ]) {
    testWidgets(
      'iOS native dismiss preserves input for $type',
      (tester) async {
        await pumpHost(tester, type: type);
        await tester.enterText(find.byKey(const ValueKey('number')), '123');
        await tester.pumpAndSettle();
        expect(calls.last.arguments['visible'], false);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(calls.last.arguments, {'visible': true, 'dark': false});
        expect(find.byKey(toolbar), findsNothing);
        expect(
          MediaQuery.viewInsetsOf(tester.element(find.byType(Scaffold))).bottom,
          300,
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('dismiss'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, false);
        expect(calls.last.arguments['visible'], false);
        expect(find.text('123'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'iOS hides for text focus and keyboard dismissal',
    (tester) async {
      await pumpHost(tester, dark: true);
      await tester.enterText(find.byKey(const ValueKey('number')), '1');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'visible': true, 'dark': true});
      await tester.tap(find.byKey(const ValueKey('text')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], false);
      await tester.tap(find.byKey(const ValueKey('number')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], true);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS numeric field inside sheet uses native control',
    (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('sheet-number')), '12');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], true);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android relies on system keyboard without an extra control',
    (tester) async {
      await pumpHost(tester);
      await tester.enterText(find.byKey(const ValueKey('number')), '123');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(toolbar), findsNothing);
      expect(calls, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, false);
      expect(find.text('123'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
