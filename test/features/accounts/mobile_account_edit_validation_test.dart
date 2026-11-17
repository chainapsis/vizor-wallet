@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/account_edit_sheets.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../support/app_test_fonts.dart';

const _fieldKey = ValueKey('mobile_account_edit_name');
const _saveKey = ValueKey('mobile_account_edit_save');

void main() {
  setUpAll(loadAppTestFonts);

  for (final language in AppLanguage.values) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final keyboard in [false, true]) {
          testWidgets(
            '${language.tag} name errors fit at width $width scale $scale '
            'keyboard=$keyboard; correction, save and cancel work',
            (tester) async {
              tester.view.physicalSize = Size(width, 800);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              AccountEdits? result;
              await tester.pumpWidget(
                ProviderScope(
                  child: MaterialApp(
                    locale: language.locale,
                    supportedLocales: appSupportedLocales(preview: true),
                    localizationsDelegates: appLocalizationsDelegates,
                    builder: (context, child) => AppTheme(
                      data: AppThemeData.light,
                      child: LocaleTypography(
                        child: MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: TextScaler.linear(scale)),
                          child: child!,
                        ),
                      ),
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () async {
                            result = await showAccountEditSheet(
                              context,
                              account: AccountInfo(
                                uuid: 'fixture',
                                name: 'Knight',
                                order: 0,
                                profilePictureId: kDefaultProfilePictureId,
                              ),
                            );
                          },
                          child: const Text('Open fixture'),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open fixture'));
              await tester.pumpAndSettle();
              final field = find.byKey(_fieldKey);
              final save = find.byKey(_saveKey);
              final l10n = tester.element(field).l10n;

              // With no error, preserve the original 16px reservation and gaps.
              expect(
                tester.getTopLeft(save).dy -
                    tester.getBottomLeft(find.byType(MobileTextField)).dy,
                AppSpacing.xs + AppSpacing.sm + AppSpacing.md,
              );
              if (keyboard) {
                await tester.tap(field);
                tester.view.viewInsets = const FakeViewPadding(bottom: 300);
                await tester.pumpAndSettle();
              }

              for (final (input, message) in [
                ('   ', l10n.accountNameRequired),
                ('abcdefghijklmnopqrstu', l10n.accountNameTooLong),
              ]) {
                await tester.enterText(field, input);
                await tester.ensureVisible(save);
                await tester.tap(save);
                await tester.pumpAndSettle();
                expect(find.byKey(_fieldKey), findsOneWidget);
                expect(result, isNull);
                final error = find.text(message);
                expect(error, findsOneWidget);
                await tester.ensureVisible(error);
                await tester.pumpAndSettle();
                _expectFullParagraph(tester, error);
                final viewport = tester.getRect(
                  find.byKey(const ValueKey('mobile_modal_body_scroll')),
                );
                final errorRect = tester.getRect(error);
                expect(viewport.top, lessThanOrEqualTo(errorRect.top));
                expect(viewport.bottom, greaterThanOrEqualTo(errorRect.bottom));
                if (keyboard) {
                  expect(viewport.bottom, lessThanOrEqualTo(500));
                }
                expect(tester.takeException(), isNull);
              }

              await tester.enterText(field, ' Renamed ');
              await tester.pumpAndSettle();
              expect(find.text(l10n.accountNameRequired), findsNothing);
              expect(find.text(l10n.accountNameTooLong), findsNothing);
              await tester.ensureVisible(save);
              await tester.tap(save);
              await tester.pumpAndSettle();
              expect(result?.name, 'Renamed');
              expect(result?.profilePictureId, isNull);
              expect(find.byKey(_fieldKey), findsNothing);

              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
              await tester.tap(find.text('Open fixture'));
              await tester.pumpAndSettle();
              await tester.enterText(field, '');
              await tester.ensureVisible(save);
              await tester.tap(save);
              await tester.pumpAndSettle();
              final cancel = find.byType(MobileSheetCancel);
              await tester.ensureVisible(cancel);
              await tester.tap(cancel);
              await tester.pumpAndSettle();
              expect(result, isNull);
              expect(find.byKey(_fieldKey), findsNothing);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
}

void _expectFullParagraph(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  // Measure the entire localized message without the widget's line limit.
  final fullText = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.height, greaterThanOrEqualTo(fullText.height));
  fullText.dispose();
}
