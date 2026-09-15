@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart'
    show kWbPhoneSize;

import 'support/wb_gallery_harness.dart';
import 'playgrounds/flow_capture.dart';

void main() {
  setUpFlowCaptures();
  const mobile = {'Layout': 'Mobile'};

  testWidgets('mobile Pay carries values through review and submitted result', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildPayScreenGalleryCase,
      knobs: mobile,
      theme: AppThemeData.light,
      canvasSize: kWbPhoneSize,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
      '25',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_pay_contact_widgetbook-pay-screen-mike'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_pay_review_content')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay_submitted_status')), findsOneWidget);
  });

  testWidgets('mobile Swap carries composer input through review and result', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapScreenGalleryCase,
      knobs: mobile,
      theme: AppThemeData.light,
      canvasSize: kWbPhoneSize,
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      '0x52908400098527886e0f7030069857d2e4169ee7',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_swap_review_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_swap_review_content')),
      findsOneWidget,
    );
    await captureFlowState(tester, 'swap.mobile.review');
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_activity_detail_page')),
      findsOneWidget,
    );
    await captureFlowState(tester, 'swap.mobile.result');
  });

  testWidgets('mobile Swap supports the real direction control', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapScreenGalleryCase,
      knobs: mobile,
      theme: AppThemeData.light,
      canvasSize: kWbPhoneSize,
    );
    final directionIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.swapArrows,
    );
    await tester.tap(
      find
          .ancestor(of: directionIcon, matching: find.byType(GestureDetector))
          .last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
