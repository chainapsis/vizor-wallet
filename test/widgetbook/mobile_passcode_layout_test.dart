@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/widgetbook/mobile_passcode_use_cases.dart';
import '../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  testWidgets('extra height preserves the keypad bottom clearance', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<Rect> keypadAt(double height) async {
      tester.view.physicalSize = Size(393, height);
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(393, height),
                padding: const EdgeInsets.only(top: 55, bottom: 24),
                viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
              ),
              child: const PasscodeLayoutPreview(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.getRect(
        find.byKey(const ValueKey('passcode_layout_keypad')),
      );
    }

    final reference = await keypadAt(852);
    final taller = await keypadAt(952);
    expect(reference.top, 412);
    expect(taller.top - reference.top, closeTo(100, 0.01));
    expect(taller.size, reference.size);
  });
  Future<void> pumpPreview(
    WidgetTester tester, {
    required Size size,
    required EdgeInsets padding,
    double scale = 1,
    PasscodePreviewState state = PasscodePreviewState.create,
    bool showError = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: padding,
              viewPadding: padding,
              textScaler: TextScaler.linear(scale),
            ),
            child: PasscodeLayoutPreview(state: state, showError: showError),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  double titleSize(WidgetTester tester) => tester
      .renderObject<RenderParagraph>(
        find.byKey(const ValueKey('passcode_layout_title')),
      )
      .text
      .style!
      .fontSize!;

  Rect keypadRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('passcode_layout_keypad')));

  testWidgets('screens the regular layout fits keep it', (tester) async {
    addTearDown(tester.view.reset);
    // 375 x 812 iPhones fit the regular layout; iPad mini's window does not.
    await pumpPreview(
      tester,
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 50, bottom: 34),
    );
    expect(titleSize(tester), AppTypography.displayLarge.fontSize);
    expect(keypadRect(tester).width, kPasscodeKeypadWidth);

    final ipad = PasscodePreviewViewport.ipad;
    await pumpPreview(tester, size: ipad.size, padding: ipad.padding);
    expect(titleSize(tester), lessThan(AppTypography.displayLarge.fontSize!));
  });

  for (final viewport in [
    PasscodePreviewViewport.design,
    PasscodePreviewViewport.ipad,
  ]) {
    testWidgets('${viewport.name} errors never move the keypad', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final scale in [1.0, 1.353]) {
        await pumpPreview(
          tester,
          size: viewport.size,
          padding: viewport.padding,
          scale: scale,
          state: PasscodePreviewState.remove,
        );
        final withoutError = keypadRect(tester);
        await pumpPreview(
          tester,
          size: viewport.size,
          padding: viewport.padding,
          scale: scale,
          state: PasscodePreviewState.remove,
          showError: true,
        );
        expect(keypadRect(tester), withoutError, reason: 'scale $scale');
      }
    });
  }

  testWidgets('scrolling copy reveals a new error', (tester) async {
    addTearDown(tester.view.reset);
    final ipad = PasscodePreviewViewport.ipad;
    await pumpPreview(
      tester,
      size: ipad.size,
      padding: ipad.padding,
      scale: 2,
      state: PasscodePreviewState.remove,
    );
    final scroll = find.byKey(const ValueKey('passcode_copy_scroll'));
    expect(scroll, findsOneWidget);
    await pumpPreview(
      tester,
      size: ipad.size,
      padding: ipad.padding,
      scale: 2,
      state: PasscodePreviewState.remove,
      showError: true,
    );
    final error = tester.getRect(
      find.byKey(const ValueKey('passcode_layout_error')),
    );
    final area = tester.getRect(scroll);
    expect(error.top, greaterThanOrEqualTo(area.top));
    expect(error.bottom, lessThanOrEqualTo(area.bottom));
  });

  for (final viewport in PasscodePreviewViewport.values) {
    for (final state in PasscodePreviewState.values) {
      for (final variant in [0, 1, 2]) {
        final large = variant == 2;
        final extras = variant != 0;
        testWidgets('${viewport.name} ${state.name} variant: $variant', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: AppTheme(
                data: large ? AppThemeData.dark : AppThemeData.light,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: viewport.size,
                    padding: viewport.padding,
                    viewPadding: viewport.padding,
                    textScaler: TextScaler.linear(large ? 3 : 1),
                  ),
                  child: PasscodeLayoutPreview(
                    state: state,
                    biometric: extras,
                    showError: extras,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final keypad = find.byKey(const ValueKey('passcode_layout_keypad'));
          if (viewport == PasscodePreviewViewport.design &&
              !extras &&
              state == PasscodePreviewState.create) {
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('passcode_layout_title')))
                  .top,
              177,
            );
            expect(tester.getRect(keypad).top, 412);
          }

          final safeBottom = viewport.size.height - viewport.padding.bottom;
          expect(
            tester.getRect(keypad).top,
            greaterThanOrEqualTo(viewport.padding.top),
          );
          expect(
            tester.getRect(keypad).bottom,
            lessThanOrEqualTo(safeBottom + 0.1),
          );
          final dots = find.byKey(const ValueKey('passcode_layout_dots'));
          expect(
            tester.getRect(dots).top,
            greaterThanOrEqualTo(viewport.padding.top),
          );
          expect(tester.getRect(dots).bottom, lessThanOrEqualTo(safeBottom));
          final copyScroll = find.byKey(const ValueKey('passcode_copy_scroll'));
          if (copyScroll.evaluate().isNotEmpty) {
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(of: copyScroll, matching: find.byType(Scrollable))
                  .first,
            );
            if (!large) expect(scrollable.position.maxScrollExtent, 0);
            if (scrollable.position.maxScrollExtent > 0) {
              final before = tester.getRect(keypad);
              expect(
                tester
                    .widget<RawScrollbar>(
                      find.byKey(const ValueKey('passcode_copy_scrollbar')),
                    )
                    .thumbVisibility,
                isTrue,
              );
              await tester.drag(copyScroll, const Offset(0, -150));
              await tester.pumpAndSettle();
              expect(tester.getRect(keypad), before);
            }
          }
          final first = find.bySemanticsLabel('Digit 1');
          final third = find.bySemanticsLabel('Digit 3');
          expect(tester.getRect(first).top, tester.getRect(third).top);
          expect(tester.getRect(first).width, greaterThanOrEqualTo(48));
          expect(first.hitTestable(), findsOneWidget);
          await tester.tap(first);
          await tester.pump();
          expect(
            tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled,
            1,
          );
          final delete = find.bySemanticsLabel('Delete digit');
          expect(delete.hitTestable(), findsOneWidget);
          await tester.tap(delete);
          await tester.pump();
          expect(
            tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled,
            0,
          );
          expect(
            find.bySemanticsLabel('Passcode help'),
            state == PasscodePreviewState.unlock
                ? findsOneWidget
                : findsNothing,
          );
          if (extras && state != PasscodePreviewState.remove) {
            final footer = find.text('Sign in with Face ID');

            expect(footer.hitTestable(), findsOneWidget);
          } else {
            expect(find.text('Sign in with Face ID'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
