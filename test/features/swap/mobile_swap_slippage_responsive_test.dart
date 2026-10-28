@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final size in const [Size(320, 568), Size(375, 667), Size(393, 852)]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final paymentMode in [false, true]) {
        testWidgets(
          '${paymentMode ? 'Pay' : 'Swap'} slippage fits ${size.width.toInt()}px at ${scale}x with keyboard',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            final inset = size.height < 700 ? 216.0 : 300.0;
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetViewInsets);
            var submittedBps = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: buildLegacyLightTheme(),
                builder: (context, child) => AppTheme(
                  data: AppThemeData.light,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
                home: Scaffold(
                  resizeToAvoidBottomInset: false,
                  body: SafeArea(
                    bottom: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: MobileModalCard(
                        child: MobileSwapSlippageStepperModal(
                          slippageBps: 50,
                          paymentMode: paymentMode,
                          confidential: false,
                          onSubmitted: (value, _) => submittedBps = value,
                          onCancel: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();
            final guidance = find.byKey(
              const ValueKey('mobile_swap_slippage_guidance'),
            );
            final initialScrollViewport = tester.getRect(
              find.byType(SingleChildScrollView),
            );
            expect(
              find.text('Price changes may cause a refund.'),
              findsOneWidget,
            );
            // Below the confidential setting, small screens and large text
            // can start the guidance past the fold. The scrollbar shows there
            // is more, and the guidance scrolls into view.
            if (tester.getRect(guidance).bottom >
                initialScrollViewport.bottom + 0.1) {
              expect(
                tester
                    .widget<Scrollbar>(find.byType(Scrollbar))
                    .thumbVisibility,
                isTrue,
              );
              await tester.ensureVisible(guidance);
              await tester.pumpAndSettle();
            }
            expect(
              tester.getRect(guidance).top,
              greaterThanOrEqualTo(initialScrollViewport.top - 0.1),
            );
            expect(
              tester.getRect(guidance).bottom,
              lessThanOrEqualTo(initialScrollViewport.bottom + 0.1),
            );
            final initialField = find.byKey(
              const ValueKey('mobile_swap_slippage_value'),
            );
            final guidanceRect = tester.getRect(guidance);
            final initialFieldRect = tester.getRect(initialField);
            if (paymentMode) {
              expect(guidanceRect.top, greaterThan(initialFieldRect.bottom));
            } else {
              expect(guidanceRect.bottom, lessThan(initialFieldRect.top));
            }
            final editableValue = find.descendant(
              of: initialField,
              matching: find.byType(EditableText),
            );
            final rowCenterY = tester
                .getCenter(
                  find.byKey(const ValueKey('mobile_swap_slippage_minus')),
                )
                .dy;
            expect(tester.getCenter(initialField).dy, closeTo(rowCenterY, 0.1));
            expect(
              tester.getCenter(editableValue).dy,
              closeTo(rowCenterY, 0.1),
            );
            expect(
              tester.getCenter(find.text(' %')).dy,
              closeTo(rowCenterY, 0.1),
            );

            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pumpAndSettle();
            final scrollViewport = tester.getRect(
              find.byType(SingleChildScrollView),
            );
            expect(
              tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
              isTrue,
            );
            for (final key in [
              'mobile_swap_slippage_value',
              'mobile_swap_slippage_minus',
              'mobile_swap_slippage_plus',
            ]) {
              final target = find.byKey(ValueKey(key));
              final rect = tester.getRect(target);
              if (rect.height <= scrollViewport.height) {
                expect(rect.top, greaterThanOrEqualTo(scrollViewport.top));
                expect(rect.bottom, lessThanOrEqualTo(scrollViewport.bottom));
              } else {
                // At 200% the text field is taller than the compact keyboard
                // viewport. It remains centered, editable and scrollable.
                expect(rect.top, lessThan(scrollViewport.bottom));
                expect(rect.bottom, greaterThan(scrollViewport.top));
              }
              expect(target.hitTestable(), findsOneWidget);
            }
            await tester.tap(
              find.byKey(const ValueKey('mobile_swap_slippage_plus')),
            );
            await tester.pumpAndSettle();
            expect(find.text('0.6'), findsOneWidget);
            await tester.ensureVisible(guidance);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(guidance).top,
              greaterThanOrEqualTo(scrollViewport.top - 0.1),
            );

            final fieldFinder = find.byKey(
              const ValueKey('mobile_swap_slippage_value'),
            );
            await tester.enterText(fieldFinder, '');
            await tester.pump();
            await tester.ensureVisible(fieldFinder);
            await tester.pump();
            expect(find.text('Slippage must be 0.1 - 5%'), findsOneWidget);
            expect(tester.takeException(), isNull);
            for (final text in ['0.1', '1.25', '4.99', '5.00']) {
              await tester.enterText(fieldFinder, text);
              await tester.pump();
              await tester.ensureVisible(fieldFinder);
              await tester.pump();
              final field = tester.widget<TextField>(fieldFinder);
              final painter = TextPainter(
                text: TextSpan(text: text, style: field.style),
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.linear(scale),
              )..layout();
              expect(
                painter.width,
                lessThanOrEqualTo(tester.getSize(fieldFinder).width),
              );
              painter.dispose();
              expect(tester.takeException(), isNull);
            }
            await tester.enterText(fieldFinder, '9.99');
            await tester.pump();
            expect(find.text('Slippage must be 0.1 - 5%'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.enterText(fieldFinder, '1.25');
            await tester.pumpAndSettle();
            for (final key in [
              'swap_slippage_update_button',
              'swap_slippage_cancel_button',
            ]) {
              final button = find.byKey(ValueKey(key));
              expect(
                tester.getRect(button).bottom,
                lessThanOrEqualTo(size.height - inset),
              );
              expect(button.hitTestable(), findsOneWidget);
            }
            await tester.tap(
              find.byKey(const ValueKey('swap_slippage_update_button')),
            );
            expect(submittedBps, 125);
          },
        );
      }
    }
  }

  for (final scale in [1.0, 2.0]) {
    for (final paymentMode in [false, true]) {
      testWidgets(
        '${paymentMode ? 'Pay' : 'Swap'} 2 to 1.9 percent keeps compact ${scale}x modal geometry stable',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 568);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildLegacyLightTheme(),
              builder: (context, child) => AppTheme(
                data: AppThemeData.light,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: MobileModalCard(
                      child: MobileSwapSlippageStepperModal(
                        slippageBps: 200,
                        confidential: false,
                        paymentMode: paymentMode,
                        onSubmitted: (_, _) {},
                        onCancel: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final modal = find.byType(MobileModalCard);
          final guidance = find.byKey(
            const ValueKey('mobile_swap_slippage_guidance'),
          );
          final stepper = find.byKey(
            const ValueKey('mobile_swap_slippage_stepper_area'),
          );
          final field = find.byKey(
            const ValueKey('mobile_swap_slippage_value'),
          );
          final minus = find.byKey(
            const ValueKey('mobile_swap_slippage_minus'),
          );
          final plus = find.byKey(const ValueKey('mobile_swap_slippage_plus'));
          final stableRects = [
            tester.getRect(modal),
            tester.getRect(guidance),
            tester.getRect(stepper),
            tester.getRect(minus),
            tester.getRect(plus),
          ];
          final fieldTop = tester.getTopLeft(field).dy;
          final fieldBottom = tester.getBottomLeft(field).dy;

          for (final control in [minus, plus]) {
            await tester.tap(control);
            await tester.pump();
            final currentRects = [
              tester.getRect(modal),
              tester.getRect(guidance),
              tester.getRect(stepper),
              tester.getRect(minus),
              tester.getRect(plus),
            ];
            expect(currentRects, stableRects);
            expect(tester.getTopLeft(field).dy, fieldTop);
            expect(tester.getBottomLeft(field).dy, fieldBottom);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
