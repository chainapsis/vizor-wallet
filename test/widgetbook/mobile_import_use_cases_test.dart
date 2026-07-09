@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_review_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets(
    'mobile import paste use case renders manual card and paste CTA',
    (tester) async {
      await _pumpUseCase(tester, buildMobileImportPasteUseCase);

      expect(tester.takeException(), isNull);
      expect(find.text('Import Wallet'), findsOneWidget);
      expect(
        find.text('Accept 12, 15, 18, 21, or 24-word\nsecret passphrases'),
        findsOneWidget,
      );
      expect(find.text('Manually Enter\nSecret Passphrase'), findsOneWidget);
      expect(find.text('Word by word.'), findsOneWidget);
      expect(find.text('Or paste from clipboard'), findsOneWidget);
      final manualCard = find.byKey(
        const ValueKey('mobile_import_manual_card'),
      );
      expect(manualCard, findsOneWidget);
      expect(tester.getSize(manualCard), const Size(361, 385));
      final title = tester.widget<Text>(
        find.text('Manually Enter\nSecret Passphrase'),
      );
      expect(title.style?.fontSize, AppTypography.headlineLarge.fontSize);
      expect(title.style?.height, AppTypography.headlineLarge.height);
      final editIcon = tester.widget<AppIcon>(
        find.descendant(of: manualCard, matching: find.byType(AppIcon)).first,
      );
      expect(editIcon.name, AppIcons.edit);
      expect(editIcon.size, AppIconSize.large);
      expect(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_blur')),
        findsNothing,
      );
      final firstIndex = tester.widget<Text>(find.text('01'));
      expect(firstIndex.style?.fontSize, 15);
      expect(firstIndex.style?.height, 21 / 15);
      expect(
        firstIndex.style?.color,
        AppThemeData.dark.colors.text.homeCard.withValues(alpha: 0.5),
      );
      final index1 = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_index_1')),
      );
      final index2 = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_index_2')),
      );
      final index3 = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_index_3')),
      );
      final index4 = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_index_4')),
      );
      expect(index2.dy, closeTo(index1.dy, 0.01));
      expect(index2.dx, greaterThan(index1.dx));
      expect(index3.dy, closeTo(index1.dy, 0.01));
      expect(index3.dx, greaterThan(index2.dx));
      expect(index4.dy, greaterThan(index1.dy));
      expect(index4.dx, closeTo(index1.dx, 0.01));
      final cell1Top = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_cell_1')),
      );
      final line1Top = tester.getTopLeft(
        find.byKey(const ValueKey('mobile_import_manual_placeholder_line_1')),
      );
      expect(line1Top.dx, greaterThan(index1.dx));
      expect(line1Top.dy - cell1Top.dy, closeTo(23, 0.01));
      final pasteButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('mobile_import_paste')),
      );
      expect(pasteButton.variant, AppButtonVariant.primary);
      expect(pasteButton.expand, isTrue);
      final pasteIcon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_import_paste')),
          matching: find.byType(AppIcon),
        ),
      );
      expect(pasteIcon.name, AppIcons.paste);
      expect(pasteIcon.size, 20);
    },
  );

  testWidgets('mobile import cards fill available width on wide phones', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(data: AppThemeData.dark, child: MobileImportScreen()),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_import_manual_card'))),
      const Size(408, 385),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Center(
            child: SizedBox(
              width: 408,
              child: MobileImportReviewSeedCard(
                words: [
                  'caution',
                  'dream',
                  'solar',
                  'agent',
                  'witness',
                  'logic',
                  'hurdle',
                  'focus',
                  'benefit',
                  'rough',
                  'index',
                  'genuine',
                  'puzzle',
                  'sudden',
                  'modify',
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_import_review_seed_card')),
      ),
      const Size(408, 385),
    );
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

  testWidgets('mobile import paste error use case keeps the manual card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportPasteErrorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text("Can't read the clipboard"), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    final toast = find.byType(AppToast);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: toast,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.color,
      AppThemeData.dark.colors.background.utilityDestructiveStrong,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_import_manual_card'))),
      const Size(361, 385),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text("Can't read the clipboard"), findsOneWidget);
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
    expect(find.text('Invalid secret passphrase word.'), findsOneWidget);
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
    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    expect(find.text('Confirm & continue'), findsOneWidget);
    expect(find.text('Clear secret passphrase'), findsOneWidget);
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
      const Size(361, 385),
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

  testWidgets('mobile import review 15-word use case matches Figma state', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReview15UseCase);

    expect(tester.takeException(), isNull);
    expect(_stepsProgress(tester), closeTo(60 / 196, 0.0001));
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_import_review_seed_card')),
      ),
      const Size(361, 385),
    );
    expect(find.text('15'), findsOneWidget);
    expect(find.text('modify'), findsOneWidget);
    expect(find.text('16'), findsNothing);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('mobile_import_review_clear')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('mobile_import_review_continue')),
            )
            .dy,
      ),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_import_review_word_chip_1')),
          )
          .width,
      90,
    );
  });

  testWidgets('mobile import review action aligns with paste action bottom', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportPasteUseCase);
    final pasteBottom = tester
        .getBottomRight(find.byKey(const ValueKey('mobile_import_paste')))
        .dy;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpUseCase(tester, buildMobileImportReview15UseCase);
    final reviewContinueBottom = tester
        .getBottomRight(
          find.byKey(const ValueKey('mobile_import_review_continue')),
        )
        .dy;

    expect(reviewContinueBottom, closeTo(pasteBottom, 0.01));
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

  testWidgets('mobile import review seed card scales long words', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Center(
            child: SizedBox(
              width: 361,
              child: MobileImportReviewSeedCard(
                words: ['quantum', 'question', 'business'],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final longWord = find.byKey(const ValueKey('mobile_import_review_word_1'));
    expect(find.text('quantum'), findsOneWidget);
    expect(
      find.ancestor(of: longWord, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(longWord).overflow,
      isNot(TextOverflow.ellipsis),
    );
  });

  testWidgets(
    'mobile import review seed card keeps three columns when narrow',
    (tester) async {
      const words = [
        'caution',
        'dream',
        'solar',
        'agent',
        'witness',
        'logic',
        'hurdle',
        'focus',
        'benefit',
        'rough',
        'index',
        'genuine',
        'puzzle',
        'sudden',
        'modify',
        'active',
        'effort',
        'merit',
        'fossil',
        'carbon',
        'drift',
        'narrow',
        'across',
        'raise',
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Center(
              child: SizedBox(
                width: 328,
                child: MobileImportReviewSeedCard(words: words),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final card = find.byKey(const ValueKey('mobile_import_review_seed_card'));
      final firstChip = find.byKey(
        const ValueKey('mobile_import_review_word_chip_1'),
      );
      final lastChip = find.byKey(
        const ValueKey('mobile_import_review_word_chip_24'),
      );
      expect(tester.getSize(firstChip).width, closeTo(85.33, 0.01));
      expect(
        tester.getBottomRight(lastChip).dy,
        lessThanOrEqualTo(tester.getBottomRight(card).dy),
      );
    },
  );

  testWidgets('mobile import review use case clears back to paste', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileImportReviewUseCase);

    await tester.tap(find.text('Clear secret passphrase'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);
    expect(find.text('Review Import'), findsNothing);
  });
}

double _stepsProgress(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox).first,
  );
  return fill.widthFactor!;
}

Future<void> _pumpUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  Size size = const Size(393, 852),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
}
