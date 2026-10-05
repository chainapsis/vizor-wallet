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
    for (final scale in [1.0, 1.3]) {
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
                          onSubmitted: (value) => submittedBps = value,
                          onCancel: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            await tester.pumpAndSettle();
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pumpAndSettle();
            final scrollViewport = tester.getRect(
              find.byType(SingleChildScrollView),
            );
            for (final key in [
              'mobile_swap_slippage_value',
              'mobile_swap_slippage_minus',
              'mobile_swap_slippage_plus',
            ]) {
              final target = find.byKey(ValueKey(key));
              final rect = tester.getRect(target);
              expect(rect.top, greaterThanOrEqualTo(scrollViewport.top));
              expect(rect.bottom, lessThanOrEqualTo(scrollViewport.bottom));
              expect(target.hitTestable(), findsOneWidget);
            }
            await tester.tap(
              find.byKey(const ValueKey('mobile_swap_slippage_plus')),
            );
            await tester.pumpAndSettle();
            expect(find.text('0.6'), findsOneWidget);
            final guidance = find.text(
              paymentMode
                  ? 'Allows this much extra ZEC for quote movement before execution fails. Network fees are separate.'
                  : "Sets the maximum rate change you'll accept. Network fees are separate.",
            );
            await tester.ensureVisible(guidance);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(guidance).top,
              greaterThanOrEqualTo(scrollViewport.top - 0.1),
            );

            final fieldFinder = find.byKey(
              const ValueKey('mobile_swap_slippage_value'),
            );
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
}
