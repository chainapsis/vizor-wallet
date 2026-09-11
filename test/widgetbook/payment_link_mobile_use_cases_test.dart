@Tags(['mobile'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_flip.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_motion.dart';
import 'package:zcash_wallet/widgetbook/payment_link_mobile_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('Redeem opens the shared scanner and can return to paste', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePaymentLinkRedeemPasteUseCase);
    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_scan_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan the gift card QR code'), findsOneWidget);
    expect(find.text('Choose from photos'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Close scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from photos'), findsNothing);
    expect(find.text('Paste card link'), findsOneWidget);
  });

  testWidgets('camera denial offers cancellation without photo input', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePaymentLinkScanDeniedUseCase);
    expect(find.text("You've denied camera access"), findsOneWidget);
    expect(find.text('Choose from photos'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home matches the mobile device and action geometry', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePaymentLinkHomeEmptyUseCase);

    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('mobile_payment_link_preview_frame')),
      ),
      const Offset(0, 55),
    );

    final redeem = find.byKey(
      const ValueKey('payment_links_mobile_redeem_button'),
    );
    final create = find.byKey(
      const ValueKey('payment_links_mobile_create_button'),
    );
    expect(tester.getRect(redeem), const Rect.fromLTWH(16, 716, 361, 50));
    expect(tester.getRect(create), const Rect.fromLTWH(16, 778, 361, 50));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon && widget.name == AppIcons.giftCardOutline,
      ),
      findsOneWidget,
    );
  });

  testWidgets('home help icon opens the Gift Card explanation sheet', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePaymentLinkHomeEmptyUseCase);

    expect(find.text('How Gift Cards work'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('payment_links_mobile_help_action')),
    );
    await tester.pumpAndSettle();

    expect(find.text('How Gift Cards work'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_mobile_help_close_button')),
      findsOneWidget,
    );
  });

  testWidgets('received Gift Card flips to its message', (tester) async {
    await _pumpUseCase(tester, buildMobilePaymentLinkReceivedUseCase);

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.settleDuration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_back')),
      findsOneWidget,
    );
    expect(
      find.text('Hey there! Welcome to the Shielded World ;)'),
      findsOneWidget,
    );
  });

  for (final entry in <String, WidgetBuilder>{
    'ready': buildMobilePaymentLinkReadyUseCase,
    'received': buildMobilePaymentLinkReceivedUseCase,
  }.entries) {
    testWidgets('${entry.key} card follows touch without flipping on drag', (
      tester,
    ) async {
      await _pumpUseCase(tester, entry.value);
      await tester.pump(PaymentLinkCardMotion.settleDuration);

      final card = find.byKey(const ValueKey('payment_link_tilt_mouse_region'));
      Matrix4 tiltMatrix() => tester
          .widget<Transform>(
            find.byKey(const ValueKey('payment_link_reveal_transform')),
          )
          .transform;
      final rest = tiltMatrix().clone();
      final bounds = tester.getRect(card);
      final gesture = await tester.startGesture(
        bounds.topLeft + const Offset(40, 40),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await gesture.moveTo(bounds.bottomRight - const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tiltMatrix(), isNot(equals(rest)));
      expect(
        find.byKey(const ValueKey('payment_link_holo_shine')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_link_metallic_shine')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tiltMatrix(), equals(rest));
      expect(
        find.byKey(const ValueKey('payment_link_flip_front')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_link_holo_shine')),
        findsNothing,
      );

      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payment_link_flip_back')),
        findsOneWidget,
      );

      final cancelledTouch = await tester.startGesture(
        bounds.topLeft + const Offset(40, 40),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tiltMatrix(), isNot(equals(rest)));
      await cancelledTouch.cancel();
      await tester.pumpAndSettle();
      expect(tiltMatrix(), equals(rest));
      expect(
        find.byKey(const ValueKey('payment_link_flip_back')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long sync warning uses the standard mobile sheet', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentLinkRedeemLongSyncWarningUseCase,
    );

    expect(
      find.byKey(const ValueKey('payment_link_long_sync_warning_sheet')),
      findsOneWidget,
    );
    expect(find.text('This gift card may take a while'), findsOneWidget);
    expect(find.text('Check gift card'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    expect(find.textContaining('100000'), findsNothing);
  });

  testWidgets('interactive preview accepts amount and message input', (
    tester,
  ) async {
    await _pumpInteractivePreview(tester);

    final amountEditor = find.byKey(
      const ValueKey('mobile_payment_link_interactive_amount_editor'),
    );
    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_card_slot')),
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(amountEditor).focusNode.hasFocus,
      isTrue,
    );

    await tester.enterText(amountEditor, '4.45');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('payment_link_max_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
      findsOneWidget,
    );
    await tester.pump(kMobilePaymentLinkPreviewFiatDelay);
    expect(find.text(r'$1,210.40'), findsOneWidget);

    for (final amount in ['0', '2', '', '4.45']) {
      await tester.enterText(amountEditor, amount);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
        findsNothing,
      );
      if (amount == '2') expect(find.text(r'$544.00'), findsOneWidget);
    }
    expect(find.text(r'$1,210.40'), findsOneWidget);

    final amountContinue = find.byKey(
      const ValueKey('payment_link_mobile_amount_continue_button'),
    );
    expect(tester.widget<AppButton>(amountContinue).onPressed, isNotNull);
    await tester.tap(amountContinue);
    await tester.pump();

    expect(find.text('Enter a message'), findsOneWidget);
    final messageEditor = find.byKey(
      const ValueKey('mobile_payment_link_interactive_message_editor'),
    );
    await tester.pump();
    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(messageEditor).decoration?.hintText,
      isNull,
    );

    await tester.enterText(messageEditor, 'Congratulations!');
    await tester.pump();
    final messageContinue = find.byKey(
      const ValueKey('payment_link_mobile_message_continue_button'),
    );
    expect(tester.widget<AppButton>(messageContinue).onPressed, isNotNull);
    await tester.tap(messageContinue);
    await tester.pump();

    expect(find.text('Review a Card'), findsOneWidget);
    expect(find.text(r'$1,210.40'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
      findsNothing,
    );
    expect(find.text('Card amount'), findsOneWidget);
    expect(find.text('4.49 ZEC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpInteractivePreview(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(393, 773)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final primary = FocusManager.instance.primaryFocus;
            if (primary != null && primary is! FocusScopeNode) {
              primary.unfocus();
            }
          },
          child: Builder(builder: buildMobilePaymentLinkInteractiveUseCase),
        ),
      ),
    ),
  );
  await tester.pump();
}
