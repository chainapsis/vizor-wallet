@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    ValueChanged<int>? onSubmitted,
    VoidCallback? onCancel,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => showMobileSheet<void>(
                  context: context,
                  builder: (_) => MobileSheetScaffold(
                    title: 'Slippage',
                    formBody: true,
                    child: MobileSwapSlippageStepperModal(
                      slippageBps: 50,
                      onSubmitted: onSubmitted ?? (_) {},
                      onCancel: onCancel ?? () {},
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('slippage opens as a sheet with scaffold chrome + content', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_sheet_grabber')), findsOneWidget);
    // Scaffold supplies the single "Slippage" title (the modal's own header
    // was removed).
    expect(find.text('Slippage'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_swap_slippage_value')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_slippage_update_button')),
      findsOneWidget,
    );
  });

  testWidgets('content-sized sheet hugs its form (not full-screen)', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final grabberTop = tester
        .getTopLeft(find.byKey(const ValueKey('mobile_sheet_grabber')))
        .dy;
    // A hugging sheet sits low; a full-screen one would start near the top.
    expect(grabberTop, greaterThan(screenHeight * 0.35));
  });

  testWidgets('close button dismisses the slippage sheet', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Slippage'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_sheet_close_button')));
    await tester.pumpAndSettle();
    expect(find.text('Slippage'), findsNothing);
  });
}
