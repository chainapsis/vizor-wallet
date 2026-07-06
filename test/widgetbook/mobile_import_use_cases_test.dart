@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets('mobile import paste use case renders clipboard card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportPasteUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.text('Paste from clipboard'), findsOneWidget);
    expect(find.text('Enter Secret Passphrase manually'), findsOneWidget);
    final manualButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    expect(manualButton.variant, AppButtonVariant.ghost);
    expect(manualButton.expand, isTrue);
    expect(
      find.byKey(const ValueKey('mobile_import_paste_card')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_import_paste_card'))),
      const Size(361, 390),
    );
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('mobile import paste use case opens manual entry', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportPasteUseCase);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
    expect(find.text('Accept 12, 15, 18, 21 or 24 words'), findsOneWidget);
  });

  testWidgets('mobile import paste error use case renders retry card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportPasteErrorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text("Can't read clipboard data"), findsOneWidget);
    expect(
      find.text('Accept 12, 15, 18, 21 or 24-length Secret Passphrases'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_import_paste_card'))),
      const Size(361, 390),
    );
  });

  testWidgets('mobile import manual empty use case renders first slot', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportManualEmptyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('Next word'), findsOneWidget);
    expect(find.text('Finish & review'), findsNothing);
  });

  testWidgets('mobile import manual typing use case renders suggestions', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportManualTypingUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Ag'), findsOneWidget);
    expect(find.text('age'), findsOneWidget);
    expect(find.text('agent'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_import_manual_suggestions')),
      ),
      const Size(361, 60),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_import_manual_suggestion_age')),
          )
          .height,
      36,
    );
  });

  testWidgets('mobile import manual error use case renders invalid word', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportManualErrorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text(r'Secr$'), findsOneWidget);
    expect(find.text('Invalid Secret Passphrase word.'), findsOneWidget);
  });

  testWidgets('mobile import manual done use case exposes review action', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportManualDoneUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
    expect(find.text('Accept 12, 15, 18, 21 or 24 words'), findsOneWidget);
    expect(find.text('Finish & review'), findsOneWidget);
    expect(find.text('Next word'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
  });

  testWidgets('mobile import review 12-word use case renders seed card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReview12UseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Review Import'), findsOneWidget);
    expect(find.text('Confirm & continue'), findsOneWidget);
    expect(find.text('Clear secret phrase'), findsOneWidget);
    final clearButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_review_clear')),
    );
    expect(clearButton.variant, AppButtonVariant.ghost);
    expect(clearButton.expand, isTrue);
    expect(
      find.byKey(const ValueKey('mobile_import_review_seed_card')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_import_review_seed_card')),
      ),
      const Size(361, 360),
    );
    expect(find.text('01 caution'), findsNothing);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('caution'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('genuine'), findsOneWidget);
    expect(find.text('13'), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_import_review_word_chip_1')),
          )
          .width,
      90,
    );
  });

  testWidgets('mobile import review 18-word use case renders all words', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReview18UseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('merit'), findsOneWidget);
    expect(find.text('19'), findsNothing);
  });

  testWidgets('mobile import review 24-word use case renders all words', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReview24UseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('raise'), findsOneWidget);
  });

  testWidgets('mobile import review use case clears back to paste', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReviewUseCase);

    await tester.tap(find.text('Clear secret phrase'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.text('Paste from clipboard'), findsOneWidget);
    expect(find.text('Review Import'), findsNothing);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(data: AppThemeData.dark, child: Builder(builder: builder)),
    ),
  );
  await tester.pump();
}
