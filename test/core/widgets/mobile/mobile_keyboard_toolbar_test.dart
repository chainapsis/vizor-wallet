@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import '../../../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_keyboard_toolbar.dart';

const toolbar = ValueKey('mobile_keyboard_toolbar');
const captureKey = ValueKey('keyboard_capture');

Future<void> pumpHost(
  WidgetTester tester, {
  TextInputType type = TextInputType.number,
  bool dark = false,
  bool readOnly = false,
  ValueChanged<String>? onSubmitted,
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
          child: MobileKeyboardToolbar(child: child!),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextField(
                key: const ValueKey('number'),
                keyboardType: type,
                readOnly: readOnly,
                onSubmitted: onSubmitted,
                maxLines: type == TextInputType.multiline ? 3 : 1,
              ),
              const TextField(key: ValueKey('text')),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: TextField(
                      key: ValueKey('sheet-number'),
                      keyboardType: type,
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
  const channel = MethodChannel('com.zcash.wallet/keyboard_toolbar');
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
    TextInputType.text,
    TextInputType.multiline,
    TextInputType.emailAddress,
    TextInputType.url,
  ]) {
    testWidgets('iOS native dismiss preserves input for $type', (tester) async {
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets(
    'iOS keeps the control across numeric and text focus until dismissal',
    (tester) async {
      await pumpHost(tester, dark: true);
      await tester.enterText(find.byKey(const ValueKey('number')), '1');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'visible': true, 'dark': true});
      await tester.tap(find.byKey(const ValueKey('text')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], true);
      await tester.tap(find.byKey(const ValueKey('number')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], true);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('iOS text field inside sheet uses native control', (
    tester,
  ) async {
    await pumpHost(tester, type: TextInputType.text);
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sheet-number')), '12');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(calls.last.arguments['visible'], true);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'dismissing a multiline keyboard preserves newlines without submitting',
    (tester) async {
      var submissions = 0;
      await pumpHost(
        tester,
        type: TextInputType.multiline,
        onSubmitted: (_) => submissions++,
      );
      await tester.enterText(
        find.byKey(const ValueKey('number')),
        'first\nsecond',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], true);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('dismiss'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('first\nsecond'), findsOneWidget);
      expect(submissions, 0);
      expect(tester.testTextInput.isVisible, false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS refreshes the control after an interruption without losing input',
    (tester) async {
      await pumpHost(tester, type: TextInputType.text);
      await tester.enterText(find.byKey(const ValueKey('number')), 'kept');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final before = calls.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, greaterThan(before));
      expect(calls.last.arguments['visible'], true);
      expect(find.text('kept'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS hides for a read-only field despite a stale keyboard inset',
    (tester) async {
      await pumpHost(tester, type: TextInputType.text, readOnly: true);
      await tester.tap(find.byKey(const ValueKey('number')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(calls.last.arguments['visible'], false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Android relies on system keyboard without an extra control', (
    tester,
  ) async {
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
