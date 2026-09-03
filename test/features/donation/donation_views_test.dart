import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_host.dart';
import 'package:zcash_wallet/src/features/donation/widgets/donation_views.dart';

Widget _host(Widget child) => MaterialApp(
  home: AppThemeHost(
    themeMode: ThemeMode.light,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('composer exposes presets and disables empty continue', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 672,
          child: DonationComposeView(
            controller: controller,
            mode: DonationAmountMode.zec,
            conversionText: r'$ 0',
            selectedPreset: null,
            onAmountChanged: (_) {},
            onToggleMode: () {},
            onPresetSelected: (_) {},
            onContinue: null,
          ),
        ),
      ),
    );

    expect(find.text('Support Vizor'), findsOneWidget);
    expect(find.text('0.05 ZEC'), findsOneWidget);
    expect(find.text('0.25 ZEC'), findsOneWidget);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(
      tester
          .widget<GestureDetector>(
            find
                .ancestor(
                  of: find.text('Continue'),
                  matching: find.byType(GestureDetector),
                )
                .last,
          )
          .onTap,
      isNull,
    );
  });

  testWidgets('donation review uses dedicated recipient and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DonationReviewContentView(
          amountText: '0.05 ZEC',
          fiatText: r'$2.50',
          feeText: '0.0001 ZEC',
          confirmLabel: 'Confirm donation',
          confirmIcon: 'donation',
          onConfirm: () {},
        ),
      ),
    );

    expect(find.text('Review Amount'), findsOneWidget);
    expect(find.text('Vizor Wallet'), findsOneWidget);
    expect(find.text('Confirm donation'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('success view thanks the donor', (tester) async {
    await tester.pumpWidget(
      _host(SizedBox.expand(child: DonationSuccessView(onDone: () {}))),
    );
    expect(find.text('Thank you for supporting Vizor'), findsOneWidget);
    expect(find.text('Your support keeps Vizor going.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
