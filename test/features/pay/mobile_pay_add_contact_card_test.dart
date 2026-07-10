@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';

const _address = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets('saves a labelled payment recipient', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? savedLabel;
    String? savedPicture;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                MobileModalCard(
                  child: MobilePayAddContactCard(
                    network: AddressBookNetwork.ethereum,
                    address: _address,
                    onCancel: () {},
                    onSave: (label, picture) async {
                      savedLabel = label;
                      savedPicture = picture;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_card')),
      findsOneWidget,
    );
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.textContaining('0x11111111111111'), findsOneWidget);

    final saveButton = find.byKey(
      const ValueKey('mobile_pay_add_contact_save'),
    );
    expect(tester.widget<AppButton>(saveButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_add_contact_label')),
      'Mike',
    );
    await tester.pump();
    expect(tester.widget<AppButton>(saveButton).onPressed, isNotNull);

    await tester.tap(saveButton);
    await tester.pump();

    expect(savedLabel, 'Mike');
    expect(savedPicture, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
