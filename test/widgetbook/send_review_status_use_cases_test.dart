import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';
import 'package:zcash_wallet/src/core/widgets/review_buttons_stack.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/widgetbook/send_review_status_use_cases.dart';

void main() {
  testWidgets('review address use case renders the review layout', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildSendReviewAddressUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(SendReviewContentView), findsOneWidget);
    expect(find.text('Review send'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Confirm & send'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('review contact use case renders the contact recipient', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildSendReviewContactUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
    expect(find.text(r'$250.12'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('in progress use case renders the spinner status', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildSendStatusInProgressUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Send in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.byType(ReviewButtonsStack), findsNothing);
  });

  testWidgets('completed use case renders the success status', (tester) async {
    await _pumpUseCase(tester, buildSendStatusCompletedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Tx ID'), findsOneWidget);
  });

  testWidgets('failed use case keeps the dark card in the light theme', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildSendStatusFailedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Failed, refunded minus tx fee'), findsOneWidget);
    final card = tester.widget<ReviewWrapCard>(find.byType(ReviewWrapCard));
    expect(card.surfaceColor, Primitives.p50Dark);
    expect(find.byType(SendStatusContentView), findsOneWidget);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
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
