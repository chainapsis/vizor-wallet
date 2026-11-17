@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_address_edit_modal.dart';

import '../../support/app_test_fonts.dart';

const _address = '0x52908400098527886e0f7030069857d2e4169ee7';
const _fieldKey = ValueKey('swap_destination_field');
const _updateKey = ValueKey('swap_address_update_button');

void main() {
  setUpAll(loadAppTestFonts);
  for (final language in AppLanguage.values) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final direction in SwapDirection.values) {
          for (final keyboard in [false, true]) {
            testWidgets(
              '${language.tag} ${direction.name} feedback fits at $width '
              'scale=$scale keyboard=$keyboard and validation still works',
              (tester) async {
                tester.view.physicalSize = Size(width, 800);
                tester.view.devicePixelRatio = 1;
                if (keyboard) {
                  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
                }
                addTearDown(tester.view.reset);
                (String, bool)? submitted;
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
                        child: MobileSwapAddressEditModal(
                          state: SwapState(
                            direction: direction,
                            amountText: '',
                            receiveAmountText: '',
                            destinationText: '',
                            externalAsset: SwapAsset.usdc,
                            reviewVisible: false,
                            intents: const [],
                          ),
                          contacts: const [
                            AddressBookContact(
                              id: 'fixture',
                              label: 'Treasury',
                              network: AddressBookNetwork.ethereum,
                              address: _address,
                              profilePictureId: 'default',
                              createdAtMs: 0,
                              updatedAtMs: 0,
                            ),
                          ],
                          onSubmitted: (value, remember) =>
                              submitted = (value, remember),
                          onScan: (_, _) {},
                          onOpenContacts: (_, _) {},
                          onCancel: () => cancelled = true,
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final field = find.byKey(_fieldKey);
                final error = find.byKey(
                  const ValueKey('swap_destination_format_error'),
                );
                final update = find.byKey(_updateKey);
                final remember = find.byKey(
                  const ValueKey('swap_address_remember_toggle'),
                );
                final scroll = find.byKey(
                  const ValueKey('mobile_modal_body_scroll'),
                );
                final originalRememberRect = tester.getRect(remember);

                await tester.enterText(field, 'invalid');
                await tester.pumpAndSettle();
                expect(error, findsOneWidget);
                expect(tester.widget<AppButton>(update).onPressed, isNull);
                await tester.testTextInput.receiveAction(TextInputAction.done);
                await tester.pumpAndSettle();
                expect(submitted, isNull);
                await Scrollable.ensureVisible(
                  tester.element(error),
                  alignment: 0.5,
                );
                await tester.pumpAndSettle();
                _expectFullParagraph(tester, error, scroll);

                await tester.enterText(field, _address);
                await tester.pumpAndSettle();
                expect(error, findsNothing);
                final contact = find.descendant(
                  of: find.byKey(
                    const ValueKey('swap_destination_contact_match'),
                  ),
                  matching: find.byType(Text),
                );
                expect(contact, findsOneWidget);
                await Scrollable.ensureVisible(
                  tester.element(contact),
                  alignment: 0.5,
                );
                await tester.pumpAndSettle();
                _expectFullParagraph(tester, contact, scroll);

                // Clearing feedback restores the initial no-feedback geometry.
                await tester.enterText(field, '');
                await tester.pumpAndSettle();
                final scrollable = tester.state<ScrollableState>(
                  find
                      .descendant(of: scroll, matching: find.byType(Scrollable))
                      .first,
                );
                scrollable.position.jumpTo(0);
                await tester.pumpAndSettle();
                expect(error, findsNothing);
                expect(contact, findsNothing);
                expect(tester.getRect(remember), originalRememberRect);

                await tester.enterText(field, ' $_address ');
                await tester.pumpAndSettle();
                await tester.ensureVisible(remember);
                await tester.tap(remember);
                await tester.pumpAndSettle();
                await tester.ensureVisible(update);
                await tester.tap(update);
                await tester.pumpAndSettle();
                expect(submitted, (_address, true));
                final cancel = find.byKey(
                  const ValueKey('swap_address_cancel_button'),
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
}

void _expectFullParagraph(WidgetTester tester, Finder finder, Finder scroll) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.height, greaterThanOrEqualTo(painter.height));
  final viewport = tester.getRect(scroll);
  final rect = tester.getRect(finder);
  expect(viewport.top, lessThanOrEqualTo(rect.top));
  expect(viewport.bottom, greaterThanOrEqualTo(rect.bottom));
  painter.dispose();
}
