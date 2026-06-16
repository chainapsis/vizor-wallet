@Tags(['mobile'])
library;

import 'package:flutter/material.dart'
    show BorderRadius, BoxDecoration, MaterialApp, SingleChildScrollView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_timeout_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';

Widget _harness(
  Widget child, {
  Size mediaSize = const Size(393, 852),
  double width = 361,
}) {
  return MaterialApp(
    builder: (_, navigator) =>
        AppTheme(data: AppThemeData.dark, child: navigator!),
    home: MediaQuery(
      data: MediaQueryData(size: mediaSize),
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mobile deposit layout matches the Figma QR card metrics', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    final card = find.byKey(const ValueKey('swap_deposit_qr_card'));
    final qr = find.byKey(const ValueKey('swap_deposit_tokens_qr_code'));
    final details = find.byKey(const ValueKey('swap_deposit_details'));
    final expiry = find.byKey(const ValueKey('swap_deposit_expiry_label'));

    expect(tester.getSize(card).width, 337);
    expect(tester.getSize(qr), const Size(313, 313));
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_deposit_qr_logo'))),
      const Size(57, 57),
    );
    expect(
      tester.getRect(details).top - tester.getRect(card).bottom,
      AppSpacing.lg,
    );

    final cardDecoration =
        tester.widget<Container>(card).decoration! as BoxDecoration;
    expect(_radius(cardDecoration), 48);

    final qrDecoration =
        tester.widget<Container>(qr).decoration! as BoxDecoration;
    expect(_radius(qrDecoration), AppRadii.xLarge);

    final label = tester.widget<Text>(
      find.descendant(of: expiry, matching: find.text('Deposit within')),
    );
    final time = tester.widget<Text>(
      find.descendant(of: expiry, matching: find.text('2hrs')),
    );
    expect(label.style?.color, time.style?.color);
  });

  testWidgets('mobile deposit button has Figma copy and no trailing icon', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    final button = find.byKey(const ValueKey('swap_deposit_confirm_button'));
    expect(
      find.descendant(of: button, matching: find.text('I’ve deposited tokens')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.name == AppIcons.arrowForwardIos,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('mobile deposit QR uses the Figma smooth rounded modules', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    final decoration = _qrDecoration(tester);
    expect(decoration.quietZone, PrettyQrQuietZone.zero);
    final shape = decoration.shape;
    expect(shape, isA<PrettyQrSmoothSymbol>());
    expect((shape as PrettyQrSmoothSymbol).roundFactor, 0.75);
  });

  testWidgets('mobile deposit QR card fits a 360dp Android viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_content(), mediaSize: const Size(360, 800), width: 328),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_deposit_qr_card'))).width,
      328,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_deposit_tokens_qr_code'))),
      const Size(304, 304),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('swap_deposit_qr_logo'))).width,
      lessThanOrEqualTo(57),
    );
  });

  testWidgets('mobile deposit copy icons match the Figma size', (tester) async {
    await tester.pumpWidget(_harness(_content()));

    final copyIcons = tester.widgetList<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.copy,
      ),
    );
    expect(copyIcons, isNotEmpty);
    for (final icon in copyIcons) {
      expect(icon.size, 20);
    }
  });

  testWidgets('mobile deposit detail rows reserve the Figma value area', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    const addressValue = '0x123kjhc ... 4x98g20';
    final addressText = find.text(addressValue);
    final addressRight = find.byKey(
      const ValueKey('swap_deposit_address_right_item'),
    );
    final copyButton = find.byKey(const ValueKey('swap_copy_deposit_address'));

    expect(addressText, findsOneWidget);
    expect(tester.getSize(addressRight).width, greaterThanOrEqualTo(190));
    expect(tester.getSize(copyButton), const Size(20, 20));
    expect(tester.widget<Text>(addressText).overflow, TextOverflow.visible);
    expect(
      find.ancestor(of: addressText, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
  });

  testWidgets('mobile swap failed screen matches the Figma frame metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(MobileSwapTimeoutContent(onRestart: () {})),
    );

    final content = find.byKey(const ValueKey('mobile_swap_timeout_content'));
    final illustration = find.byKey(
      const ValueKey('mobile_swap_timeout_illustration'),
    );
    final message = find.byKey(const ValueKey('mobile_swap_timeout_message'));
    final button = find.byKey(const ValueKey('mobile_swap_timeout_restart'));
    final title = find.text('This deposit address is no longer valid');

    expect(tester.getSize(content).width, 340);
    expect(tester.getSize(illustration), const Size(340, 220));
    expect(
      (tester.widget<Image>(illustration).image as AssetImage).assetName,
      'assets/illustrations/swap_failed_illustration.png',
    );
    expect(tester.getSize(message).width, 300);
    expect(
      tester.getRect(message).top - tester.getRect(illustration).bottom,
      AppSpacing.base,
    );
    expect(
      tester.getRect(button).top - tester.getRect(message).bottom,
      AppSpacing.base,
    );
    expect(tester.getSize(button).height, 36);
    expect(title, findsOneWidget);
    expect(find.text('This deposit address\nis no longer valid'), findsNothing);

    final titleText = tester.widget<Text>(title);
    expect(titleText.style?.fontSize, 24);
    expect(titleText.style?.height, 28 / 24);
    expect(
      tester
          .widget<AppIcon>(
            find.byWidgetPredicate(
              (widget) => widget is AppIcon && widget.name == AppIcons.time,
            ),
          )
          .size,
      20,
    );
    expect(
      tester
          .widget<AppIcon>(
            find.byWidgetPredicate(
              (widget) => widget is AppIcon && widget.name == AppIcons.renew,
            ),
          )
          .size,
      20,
    );
  });
}

SwapDepositTokensPageContent _content() {
  return SwapDepositTokensPageContent(
    asset: SwapAsset.usdc,
    amountText: '999.99 USDC',
    depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
    expiresInLabel: '2hrs',
    onDeposited: () {},
    mobile: true,
  );
}

double _radius(BoxDecoration decoration) {
  return (decoration.borderRadius! as BorderRadius).topLeft.x;
}

PrettyQrDecoration _qrDecoration(WidgetTester tester) {
  final qrDataView = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'PrettyQrDataView',
  );
  expect(qrDataView, findsOneWidget);
  final dynamic widget = tester.widget(qrDataView);
  return widget.decoration as PrettyQrDecoration;
}
