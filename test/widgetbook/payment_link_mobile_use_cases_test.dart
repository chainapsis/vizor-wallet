@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/widgetbook/payment_link_mobile_use_cases.dart';

void main() {
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
      find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
      findsOneWidget,
    );
    await tester.pump(kMobilePaymentLinkPreviewFiatDelay);
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
    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_card_slot')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(find.text('Start typing...'), findsNothing);

    await tester.enterText(messageEditor, 'Congratulations!');
    await tester.pump();
    final messageContinue = find.byKey(
      const ValueKey('payment_link_mobile_message_continue_button'),
    );
    expect(tester.widget<AppButton>(messageContinue).onPressed, isNotNull);
    await tester.tap(messageContinue);
    await tester.pump();

    expect(find.text('Review Gift Card'), findsOneWidget);
    expect(find.text('Card amount'), findsOneWidget);
    expect(find.text('4.49 ZEC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
