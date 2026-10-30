@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_window_policy.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/services/native_modal_corners.dart';

const _content = ValueKey('modal_width_content');

enum _Presentation { sheet, controlled, transparent, dialog, inline }

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeModalCorners.channel,
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModalCorners.channel, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final presentation in _Presentation.values) {
      testWidgets('$platform $presentation follows the live root window', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(466, 852);
        addTearDown(tester.view.reset);
        final dismissible = ValueNotifier(true);
        addTearDown(dismissible.dispose);
        await tester.pumpWidget(
          _app(presentation: presentation, dismissible: dismissible),
        );
        if (presentation != _Presentation.inline) {
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
        }
        final outerMargins = presentation == _Presentation.transparent ? 0 : 32;
        expect(tester.getSize(find.byKey(_content)).width, 466 - outerMargins);

        final field = find.byType(TextField);
        final fieldState = tester.state(field);
        await tester.enterText(field, 'Keep this draft');
        await tester.pump();
        final route = ModalRoute.of(tester.element(field));

        tester.view.physicalSize = const Size(951, 669);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(_content)).width, 440 - outerMargins);
        expect(tester.state(field), same(fieldState));
        expect(find.text('Keep this draft'), findsOneWidget);
        expect(ModalRoute.of(tester.element(field)), same(route));

        // The keyboard must not change the root aspect-ratio decision.
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(_content)).width, 440 - outerMargins);
        expect(tester.state(field), same(fieldState));

        // Square and portrait windows restore the old route/theme limits.
        tester.view.viewInsets = const FakeViewPadding();
        tester.view.physicalSize = const Size(690, 829);
        await tester.pumpAndSettle();
        final sheet =
            presentation != _Presentation.dialog &&
            presentation != _Presentation.inline;
        expect(
          tester.getSize(find.byKey(_content)).width,
          (sheet ? 640 : 690) - outerMargins,
        );
        tester.view.physicalSize = const Size(800, 800);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(_content)).width,
          (sheet ? 640 : 800) - outerMargins,
        );
        expect(tester.state(field), same(fieldState));
        expect(find.text('Keep this draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  testWidgets('root safe area prevents a false wide result inside a sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(650, 500);
    tester.view.padding = const FakeViewPadding(right: 84);
    tester.view.viewPadding = const FakeViewPadding(right: 84);
    addTearDown(tester.view.reset);
    final dismissible = ValueNotifier(true);
    addTearDown(dismissible.dispose);
    await tester.pumpWidget(
      _app(presentation: _Presentation.sheet, dismissible: dismissible),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final element = tester.element(find.byKey(_content));
    expect(MobileWindowPolicyScope.of(element).usesWideLayout, isFalse);
    // SafeArea inside the sheet has consumed the right inset. Recomputing
    // from these local metrics would incorrectly enable the 440-point cap.
    expect(
      MobileWindowPolicy.resolve(MediaQuery.of(element)).usesWideLayout,
      isTrue,
    );
    expect(tester.getSize(find.byKey(_content)).width, 650 - 84 - 32);
  });

  testWidgets(
    'existing portrait sheet theme constraints remain authoritative',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(690, 829);
      addTearDown(tester.view.reset);
      final dismissible = ValueNotifier(true);
      addTearDown(dismissible.dispose);
      await tester.pumpWidget(
        _app(
          presentation: _Presentation.sheet,
          dismissible: dismissible,
          sheetConstraints: const BoxConstraints(maxWidth: 520),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_content)).width, 520 - 32);
    },
  );

  testWidgets(
    'wide root barrier covers the window and dismissal stays guarded',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(951, 669);
      addTearDown(tester.view.reset);
      final dismissible = ValueNotifier(false);
      addTearDown(dismissible.dispose);
      await tester.pumpWidget(
        _app(presentation: _Presentation.controlled, dismissible: dismissible),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final barrier = find.byType(ModalBarrier).last;
      expect(tester.getRect(barrier).size, const Size(951, 669));
      expect(tester.getSize(find.byKey(_content)).width, 408);
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(_content), findsOneWidget);
      expect(find.text('Underlying tapped'), findsNothing);
      dismissible.value = true;
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(_content), findsNothing);
      expect(find.text('Underlying tapped'), findsNothing);
    },
  );
}

Widget _app({
  required _Presentation presentation,
  required ValueNotifier<bool> dismissible,
  BoxConstraints? sheetConstraints,
}) {
  var underlyingTapped = false;
  const content = SizedBox(key: _content, height: 140, child: TextField());
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      bottomSheetTheme: BottomSheetThemeData(constraints: sheetConstraints),
    ),
    builder: (context, child) => MobileWindowPolicyScope(
      policy: MobileWindowPolicy.resolve(MediaQuery.of(context)),
      child: AppTheme(data: AppThemeData.light, child: child!),
    ),
    home: presentation == _Presentation.inline
        ? const Scaffold(
            body: MobileModalOverlay(background: SizedBox(), child: content),
          )
        : StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => underlyingTapped = true),
                child: MediaQuery(
                  // Opening from a narrow wallet pane must not reclassify the
                  // full-window modal as portrait.
                  data: MediaQuery.of(
                    context,
                  ).copyWith(size: const Size(320, 900)),
                  child: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        child: Text(
                          underlyingTapped ? 'Underlying tapped' : 'Open',
                        ),
                        onPressed: () {
                          if (presentation == _Presentation.dialog) {
                            showGeneralDialog<void>(
                              context: context,
                              barrierLabel: 'Dismiss',
                              barrierDismissible: true,
                              pageBuilder: (_, _, _) => const Align(
                                alignment: Alignment.bottomCenter,
                                child: MobileModalCard(child: content),
                              ),
                            );
                          } else {
                            showAppMobileSheet<void>(
                              context: context,
                              canDismiss:
                                  presentation == _Presentation.controlled
                                  ? dismissible
                                  : null,
                              transparentBackground:
                                  presentation == _Presentation.transparent,
                              builder: (_) => content,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
