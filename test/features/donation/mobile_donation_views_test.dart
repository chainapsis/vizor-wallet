@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/donation/widgets/mobile/mobile_donation_views.dart';
import 'package:zcash_wallet/widgetbook/mobile_donation_use_cases.dart';

void main() {
  testWidgets(
    'insufficient balance preview uses its displayed amount for fiat conversion',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Builder(builder: buildMobileDonationInsufficientUseCase),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$ 800.00'), findsOneWidget);
      expect(find.text(r'$ 16.00'), findsNothing);
    },
  );
  testWidgets('full donation review fits a narrow phone at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Builder(builder: buildMobileDonationReviewLargeTextUseCase),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile_send_confirm'))).right,
      lessThanOrEqualTo(320),
    );
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('donation review keeps precise fees visible at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: MobileDonationReviewContent(
                      amountText: '12345678.12345678 ZEC',
                      fiatText: r'$123,456.78',
                      feeText: '0.12345678 ZEC',
                      totalText: '12345678.24691356 ZEC',
                      onFullAddress: () {},
                      onFeeInfo: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final fee = tester.widget<Text>(find.text('0.12345678 ZEC'));
      expect(fee.maxLines, isNull);
      expect(fee.overflow, isNull);
      // Totals reach the card's right inset; loose labels must not strand
      // unused horizontal space before the value column.
      final totalRect = tester.getRect(find.text('12345678.24691356 ZEC'));
      expect(totalRect.right, closeTo(304, .1));
    });
  }
}
