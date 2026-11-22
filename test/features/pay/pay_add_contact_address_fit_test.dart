import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_add_contact_modal.dart';

import '../../support/app_test_fonts.dart';

const _address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';

// With the app's fonts, the saved address drops to its short form when larger
// text would cut the long one.
void main() {
  setUpAll(loadAppTestFonts);

  for (final scale in [1.0, 1.15, 1.3]) {
    testWidgets('the address is never cut at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) => AppTheme(
            data: AppThemeData.light,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Material(
            child: SingleChildScrollView(
              child: Center(
                child: PayAddContactModal(
                  network: AddressBookNetwork.ethereum,
                  address: _address,
                  onCancel: () {},
                  onSave: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      );

      final address = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const ValueKey('pay_add_contact_address_field')),
          matching: find.byType(RichText),
        ),
      );
      expect(address.didExceedMaxLines, isFalse);
      expect(
        address.text.toPlainText(),
        scale == 1 && kAppFormFactor == AppFormFactor.desktop
            ? truncatedLongAddress(_address)
            : truncatedAddress(_address),
      );
      expect(find.bySemanticsLabel('Address $_address'), findsOneWidget);
    });
  }
}
