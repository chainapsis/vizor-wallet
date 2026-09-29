@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
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
