@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/scaled_mobile_rows_capture.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';

import '../../support/app_test_fonts.dart';
import '../../support/scaled_row_text_checks.dart';

void main() {
  setUpAll(loadAppTestFonts);
  for (final language in AppLanguage.values) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final network in [
          AddressBookNetwork.ethereum,
          AddressBookNetwork.binanceSmartChain,
        ]) {
          for (final keyboard in [false, true]) {
            testWidgets(
              '${language.tag} chain ${network.id} width=$width scale=$scale keyboard=$keyboard',
              (tester) async {
                tester.view.physicalSize = Size(width, 800);
                tester.view.devicePixelRatio = 1;
                if (keyboard) {
                  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
                }
                addTearDown(tester.view.reset);
                (String, String)? saved;
                var cancelled = false;
                await tester.pumpWidget(
                  MaterialApp(
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
                    home: Scaffold(
                      resizeToAvoidBottomInset: false,
                      body: MobileModalOverlay(
                        background: const SizedBox.expand(),
                        child: MobilePayAddContactCard(
                          network: network,
                          address: '0x1111111111111111111111111111111111111111',
                          profilePictureIdGenerator: () => 'pfp-07',
                          onSave: (label, picture) async =>
                              saved = (label, picture),
                          onCancel: () => cancelled = true,
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final row = find.byKey(
                  const ValueKey('mobile_pay_add_contact_chain_row'),
                );
                final l10n = tester.element(row).l10n;
                await Scrollable.ensureVisible(
                  tester.element(row),
                  alignment: 0.5,
                );
                await tester.pumpAndSettle();
                final rect = tester.getRect(row);
                for (final label in [
                  l10n.commonChainAndAddress,
                  network.label,
                ]) {
                  expectUnclippedRowText(tester, find.text(label), rect);
                }
                final viewport = tester.getRect(
                  find.byKey(const ValueKey('mobile_modal_body_scroll')),
                );
                expect(viewport.top, lessThanOrEqualTo(rect.top));
                expect(viewport.bottom, greaterThanOrEqualTo(rect.bottom));
                if (scale == 1 && network == AddressBookNetwork.ethereum) {
                  expect(rect.height, AppSpacing.base);
                }
                final save = find.byKey(
                  const ValueKey('mobile_pay_add_contact_save'),
                );
                expect(tester.widget<AppButton>(save).onPressed, isNull);
                await tester.enterText(
                  find.byKey(const ValueKey('mobile_pay_add_contact_label')),
                  ' Alice ',
                );
                await tester.pumpAndSettle();
                await tester.ensureVisible(save);
                await tester.tap(save);
                await tester.pumpAndSettle();
                expect(saved, ('Alice', 'pfp-07'));
                final cancel = find.byKey(
                  const ValueKey('mobile_pay_add_contact_cancel'),
                );
                await tester.ensureVisible(cancel);
                await tester.tap(cancel);
                expect(cancelled, isTrue);
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox.shrink());
              },
            );
          }
        }
      }
    }
  }

  for (final scale in [1.5, 2.0]) {
    testWidgets('bold accessibility text reflows without clipping at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) => AppTheme(
            data: AppThemeData.light,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale), boldText: true),
              child: child!,
            ),
          ),
          home: const MobileContactChainCapture(),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey('mobile_pay_add_contact_chain_row'),
      );
      final rect = tester.getRect(row);
      final l10n = tester.element(row).l10n;
      expectUnclippedRowText(
        tester,
        find.text(l10n.commonChainAndAddress),
        rect,
      );
      expectUnclippedRowText(tester, find.text('Ethereum'), rect);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
