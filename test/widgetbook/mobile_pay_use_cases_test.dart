@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_amount_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_review_content.dart';
import 'package:zcash_wallet/widgetbook/mobile_pay_use_cases.dart';

void main() {
  testWidgets('amount preview uses the production 393x852 mobile layout', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePayAmountUseCase, AppThemeData.light);

    expect(find.byType(MobilePayAmountStep), findsOneWidget);
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_pay_preview_frame'))),
      const Size(393, 852),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recipient previews expose initial, new, and matched states', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePayRecipientUseCase,
      AppThemeData.dark,
    );
    expect(find.byType(MobilePayRecipientStep), findsOneWidget);
    expect(find.text('Recently sent'), findsOneWidget);
    expect(find.text('2 contacts'), findsOneWidget);

    await _pumpUseCase(
      tester,
      buildMobilePayRecipientNewAddressUseCase,
      AppThemeData.dark,
    );
    expect(find.text('New address detected.'), findsOneWidget);
    expect(find.text('Add to contacts'), findsOneWidget);

    await _pumpUseCase(
      tester,
      buildMobilePayRecipientMatchedUseCase,
      AppThemeData.dark,
    );
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review previews expose active and expired actions', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobilePayReviewUseCase, AppThemeData.light);
    expect(find.byType(MobilePayReviewContent), findsOneWidget);
    expect(find.text('Review Payment'), findsOneWidget);
    expect(find.text('Confirm & pay'), findsOneWidget);

    await _pumpUseCase(
      tester,
      buildMobilePayReviewExpiredUseCase,
      AppThemeData.dark,
    );
    expect(find.text('Quote expired'), findsOneWidget);
    expect(find.text('Refresh quote'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitted preview uses the theme-specific production asset', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaySubmittedUseCase,
      AppThemeData.dark,
    );

    expect(find.byType(MobilePaySubmittedScreen), findsOneWidget);
    expect(find.text('Payment\nSubmitted'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/pay_submitted_background_dark.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
  AppThemeData theme,
) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: theme,
        child: Align(
          alignment: Alignment.topLeft,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
  await tester.pump();
}
