import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';
import 'package:zcash_wallet/src/core/widgets/review_buttons_stack.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/widgetbook/review_components_use_cases.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('review info row gallery renders all variants', (tester) async {
    await _pumpUseCase(tester, buildReviewInfoRowGalleryUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReviewInfoRow), findsNWidgets(4));
    expect(find.text('123.12 ZEC'), findsOneWidget);
    // To-row headline, failed-row headline, and the contact sub-address all
    // render the same canonical truncation.
    expect(find.text('u195091 ... 190591'), findsNWidgets(3));
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Shielded'), findsNWidgets(2));
    expect(find.text('Show full address'), findsNWidgets(3));
  });

  testWidgets('completed wrap card renders the detail rows', (tester) async {
    await _pumpUseCase(tester, buildReviewWrapCardCompletedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReviewWrapCard), findsOneWidget);
    expect(find.byType(ReviewWrapDivider), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('25 May, 13:30'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);

    final statusText = tester.widget<Text>(find.text('Completed'));
    expect(
      statusText.style?.color,
      AppThemeData.light.colors.text.positiveStrong,
    );
  });

  testWidgets('failed wrap card keeps the dark surface in light theme', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildReviewWrapCardFailedUseCase);

    expect(tester.takeException(), isNull);
    final card = tester.widget<ReviewWrapCard>(find.byType(ReviewWrapCard));
    expect(card.surfaceColor, Primitives.p50Dark);
    expect(find.text('Failed, refunded minus tx fee'), findsOneWidget);
  });

  testWidgets('list row gallery renders the status variants', (tester) async {
    await _pumpUseCase(tester, buildReviewListRowGalleryUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReviewListRow), findsNWidgets(5));
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Failed, refunded minus tx fee'), findsOneWidget);
  });

  testWidgets('buttons stack renders confirm and cancel', (tester) async {
    await _pumpUseCase(tester, buildReviewButtonsStackUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReviewButtonsStack), findsOneWidget);
    expect(find.text('Confirm & send'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
