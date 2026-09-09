import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_connection_guide.dart';
import 'package:zcash_wallet/widgetbook/ledger_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final dark in [false, true]) {
    for (final screen in ['Connect Ledger', 'Add another account']) {
      testWidgets(
        '$screen shows version preparation in ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = _mobile
              ? const Size(393, 852)
              : const Size(1080, 692);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: AppTheme(
                data: dark ? AppThemeData.dark : AppThemeData.light,
                child: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: buildLedgerFlowPreview(
                    screen: screen,
                    mobile: _mobile,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Your spending keys stay'), findsNothing);
          if (!_mobile && screen == 'Connect Ledger') {
            final scroll = find.byKey(const ValueKey('ledger_connect_scroll'));
            final scrollState = tester.state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            );
            expect(scrollState.position.maxScrollExtent, 0);
            expect(tester.getRect(scroll).right, greaterThan(1040));
            for (final key in [
              'ledger_connect_button',
              'ledger_desktop_ble_connect_button',
            ]) {
              expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
            }
          }
          expect(find.byType(LedgerConnectionGuide), findsOneWidget);
          expect(
            find.text(
              'Use Zcash app $kMinimumLedgerZcashAppVersion or newer on your Ledger.',
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.text('1. Check the Zcash app version')).dy,
            lessThan(tester.getTopLeft(find.text('2. Prepare to connect')).dy),
          );
          for (final title in [
            '1. Check the Zcash app version',
            '2. Prepare to connect',
          ]) {
            expect(
              find.descendant(
                of: find.byType(LedgerConnectionGuide),
                matching: find.text(title),
              ),
              findsOneWidget,
            );
          }
          final guide = find.byKey(const ValueKey('ledger_app_update_guide'));
          await tester.ensureVisible(guide);
          await tester.pumpAndSettle();
          expect(guide.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          const dir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
          if (dir.isNotEmpty && screen == 'Connect Ledger') {
            await expectLater(
              find.byKey(const ValueKey('capture')),
              matchesGoldenFile(
                Uri.file('$dir/version-${dark ? 'dark' : 'light'}.png'),
              ),
            );
          }
          if (!_mobile && screen == 'Connect Ledger') {
            final disclosure = find.byKey(
              const ValueKey('ledger_advanced_options_disclosure'),
            );
            final cardRect = tester.getRect(find.byType(LedgerConnectionGuide));
            final rowRect = tester.getRect(disclosure);
            final label = find.textContaining('Account index ·');
            final chevron = find.byKey(
              const ValueKey('ledger_advanced_options_chevron'),
            );
            expect(rowRect.left, cardRect.left);
            expect(find.text('Account index · 0'), findsOneWidget);
            expect(rowRect.width, lessThan(cardRect.width));
            expect(tester.getRect(label).left, rowRect.left + AppSpacing.s);
            expect(tester.getRect(chevron).right, rowRect.right - AppSpacing.s);

            final fill = find.descendant(
              of: disclosure,
              matching: find.byType(AnimatedContainer),
            );
            Color? background() =>
                (tester.widget<AnimatedContainer>(fill).decoration
                        as ShapeDecoration)
                    .color;
            expect(background()?.a ?? 0, 0);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            addTearDown(mouse.removePointer);
            await mouse.moveTo(rowRect.center);
            await tester.pumpAndSettle();
            expect(background()?.a ?? 0, greaterThan(0));
            if (dir.isNotEmpty) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  Uri.file(
                    '$dir/advanced-hover-${dark ? 'dark' : 'light'}.png',
                  ),
                ),
              );
            }
            await mouse.moveTo(Offset.zero);
            await tester.tapAt(tester.getCenter(chevron));
            await tester.pumpAndSettle();
            final field = find.byKey(
              const ValueKey('ledger_account_index_field'),
            );
            expect(field, findsOneWidget);
            expect(tester.getRect(field).left, cardRect.left + AppSpacing.sm);
            await tester.enterText(
              find.descendant(of: field, matching: find.byType(EditableText)),
              '2',
            );
            await tester.pumpAndSettle();
            expect(find.text('Account index · 2'), findsOneWidget);
            if (dir.isNotEmpty) {
              await tester.pumpAndSettle();
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  Uri.file(
                    '$dir/advanced-expanded-${dark ? 'dark' : 'light'}.png',
                  ),
                ),
              );
            }
            // The disclosure keeps the shared button's keyboard behavior.
            Focus.of(tester.element(label)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(field, findsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: field,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              '2',
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  if (!_mobile) {
    testWidgets(
      'a short pane scrolls at the page edge and keeps actions reachable',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1080, 500);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: buildLedgerFlowPreview(
                screen: 'Connect Ledger',
                mobile: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final disclosure = find.byKey(
          const ValueKey('ledger_advanced_options_disclosure'),
        );
        await tester.ensureVisible(disclosure);
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        final scroll = find.byKey(const ValueKey('ledger_connect_scroll'));
        final state = tester.state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        );
        expect(state.position.maxScrollExtent, greaterThan(0));
        expect(tester.getRect(scroll).right, greaterThan(1040));
        final bluetooth = find.byKey(
          const ValueKey('ledger_desktop_ble_connect_button'),
        );
        await tester.ensureVisible(bluetooth);
        await tester.pumpAndSettle();
        expect(bluetooth.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
