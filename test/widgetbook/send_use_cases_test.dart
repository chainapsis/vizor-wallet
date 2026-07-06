import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, TextAlignVertical, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_compose_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_spendable_info_modal.dart';
import 'package:zcash_wallet/widgetbook/send_use_cases.dart';

void main() {
  testWidgets('send empty use case renders desktop compose shell', (
    tester,
  ) async {
    await _pumpSendUseCase(tester, buildSendEmptyUseCase);

    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.light.colors.macosUtility.window,
    );
    expect(find.byType(SendComposeView), findsOneWidget);
    expect(find.text('Send ZEC'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Use Max'), findsOneWidget);
    expect(find.text(r'$ 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_amount_clear_button')),
      findsNothing,
    );
    final amountFieldFinder = find.byKey(const ValueKey('send_amount_field'));
    final zcashIcon = tester.widget<AppIcon>(
      find.descendant(
        of: amountFieldFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.zcash,
        ),
      ),
    );
    expect(zcashIcon.size, 20);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('send_spendable_info_icon_target')),
      ),
      const Size.square(16),
    );
    final helpIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_spendable_info_icon_target')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.help,
        ),
      ),
    );
    expect(helpIcon.size, 16);
    expect(helpIcon.color, AppThemeData.light.colors.icon.muted);
    final suffixFinder = find.byKey(const ValueKey('send_amount_zec_suffix'));
    expect(suffixFinder, findsOneWidget);
    final amountInputFinder = find.descendant(
      of: amountFieldFinder,
      matching: find.byType(TextField),
    );
    final amountInput = tester.widget<TextField>(amountInputFinder);
    expect(amountInput.textAlignVertical, TextAlignVertical.center);
    expect(amountInput.decoration, isNull);
    expect(
      tester.getTopLeft(suffixFinder).dx -
          tester.getTopRight(amountInputFinder).dx,
      moreOrLessEquals(2, epsilon: 0.1),
    );
    final amountFieldRight = tester
        .getTopRight(find.byKey(const ValueKey('send_amount_field')))
        .dx;
    final suffixRight = tester.getTopRight(suffixFinder).dx;
    expect(amountFieldRight - suffixRight, greaterThan(120));
    expect(find.text('Add a memo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('send_add_memo_card'))),
      const Size(396, 128),
    );
    final backLabelFinder = find.descendant(
      of: find.byKey(const ValueKey('send_preview_pane_back_button')),
      matching: find.text('Home'),
    );
    final backLabelStyle = tester.widget<Text>(backLabelFinder).style;
    expect(backLabelStyle?.fontSize, 14);
    expect(backLabelStyle?.height, 16 / 14);
    expect(backLabelStyle?.color, AppThemeData.light.colors.button.ghost.label);
    expect(
      tester.getTopLeft(backLabelFinder).dx,
      moreOrLessEquals(316, epsilon: 0.1),
    );
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('send filled use cases keep the contacts picker label stable', (
    tester,
  ) async {
    await _pumpSendUseCase(tester, buildSendUsdFetchedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('125.12'), findsOneWidget);
    expect(find.text(r'$ 512'), findsOneWidget);
    final filledAmountFieldFinder = find.byKey(
      const ValueKey('send_amount_field'),
    );
    final filledSuffixFinder = find.byKey(
      const ValueKey('send_amount_zec_suffix'),
    );
    final filledAmountInputFinder = find.descendant(
      of: filledAmountFieldFinder,
      matching: find.byType(TextField),
    );
    final filledAmountInput = tester.widget<TextField>(filledAmountInputFinder);
    expect(filledAmountInput.textAlignVertical, TextAlignVertical.center);
    expect(filledAmountInput.decoration, isNull);
    expect(
      tester.getTopLeft(filledSuffixFinder).dx -
          tester.getTopRight(filledAmountInputFinder).dx,
      moreOrLessEquals(2, epsilon: 0.1),
    );

    await _pumpSendUseCase(tester, buildSendTransparentUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('Add a memo'), findsNothing);
    expect(find.text('Encrypted, for shielded addresses only.'), findsNothing);

    await _pumpSendUseCase(tester, buildSendContactSelectedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Mike'), findsNothing);
    expect(find.text('Contacts'), findsOneWidget);
  });

  testWidgets('amount field focuses from the empty shell area', (tester) async {
    await _pumpSendUseCase(tester, buildSendEmptyUseCase);

    final amountFieldFinder = find.byKey(const ValueKey('send_amount_field'));
    final amountInputFinder = find.descendant(
      of: amountFieldFinder,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(amountInputFinder).focusNode?.hasFocus,
      isFalse,
    );

    final fieldRect = tester.getRect(amountFieldFinder);
    await tester.tapAt(Offset(fieldRect.right - 24, fieldRect.center.dy));
    await tester.pump();

    expect(
      tester.widget<TextField>(amountInputFinder).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('send Figma parity states render loading and modal surfaces', (
    tester,
  ) async {
    await _pumpSendUseCase(tester, buildSendFetchingUsdUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('send_amount_price_loading')),
      findsOneWidget,
    );

    await _pumpSendUseCase(tester, buildSendInputValuesSwitchedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text(r'$'), findsOneWidget);
    expect(find.text('125.12 ZEC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_amount_clear_button')),
      findsOneWidget,
    );
    final clearIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_clear_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.cross,
        ),
      ),
    );
    expect(clearIcon.size, 20);

    await tester.tap(find.byKey(const ValueKey('send_amount_clear_button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final clearedInput = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.byType(TextField),
      ),
    );
    expect(clearedInput.controller?.text, isEmpty);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.moneyBag,
        ),
      ),
      findsOneWidget,
    );
    final switchedMoneyBagIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.moneyBag,
        ),
      ),
    );
    expect(switchedMoneyBagIcon.size, 20);

    await _pumpSendUseCase(tester, buildSendNotEnoughZecUseCase);

    expect(tester.takeException(), isNull);
    final destructiveColor = AppThemeData.light.colors.text.destructive;
    final destructiveIconColor = AppThemeData.light.colors.icon.destructive;
    final usdPrefix = tester.widget<Text>(
      find.byKey(const ValueKey('send_amount_usd_prefix')),
    );
    expect(usdPrefix.style?.color, destructiveColor);
    final moneyBagIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.moneyBag,
        ),
      ),
    );
    expect(moneyBagIcon.color, destructiveIconColor);

    await _pumpSendUseCase(tester, buildSendContactsModalUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsOneWidget,
    );
    expect(find.text('Mike'), findsOneWidget);

    await _pumpSendUseCase(tester, buildSendSpendableModalUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Spendable vs. Total Balances'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('send_spendable_info_modal'))),
      SendSpendableInfoModal.size,
    );
    expect(find.text('I Understand'), findsOneWidget);
  });
}

Future<void> _pumpSendUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 1080,
            height: 720,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
