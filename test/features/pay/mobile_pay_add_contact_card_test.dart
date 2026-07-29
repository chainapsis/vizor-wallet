@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel;
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';

const _address = '0x1111111111111111111111111111111111111111';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Future<void> Function(String label, String picture) onSave,
    Size size = const Size(393, 852),
    double keyboardInset = 0,
    String Function()? profilePictureIdGenerator,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                MobileModalCard(
                  child: MobilePayAddContactCard(
                    network: AddressBookNetwork.ethereum,
                    address: _address,
                    onCancel: () {},
                    onSave: onSave,
                    profilePictureIdGenerator: profilePictureIdGenerator,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('saves a labelled payment recipient', (tester) async {
    String? savedLabel;
    String? savedPicture;
    var generatorCalls = 0;
    await pumpCard(
      tester,
      profilePictureIdGenerator: () {
        generatorCalls += 1;
        return 'pfp-07';
      },
      onSave: (label, picture) async {
        savedLabel = label;
        savedPicture = picture;
      },
    );

    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_card')),
      findsOneWidget,
    );
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.textContaining('0x11111111111111'), findsOneWidget);
    expect(generatorCalls, 1);
    expect(
      tester
          .widget<AppProfilePicture>(find.byType(AppProfilePicture))
          .profilePictureId,
      'pfp-07',
    );

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
    expect(savedPicture, 'pfp-07');
    expect(generatorCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('matches contact form copy, weight, and accessibility', (
    tester,
  ) async {
    await pumpCard(tester, onSave: (_, _) async {});

    final labelField = tester.widget<MobileTextField>(
      find.byType(MobileTextField),
    );
    expect(labelField.hintText, 'Add label 1-20 characters');
    expect(tester.getSize(find.byType(MobileModalScaffold)).width, 361);

    for (final label in ['Address label', 'Chain & address']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontWeight, FontWeight.w500);
      expect(text.style?.fontSize, AppTypography.labelMedium.fontSize);
      expect(text.style?.height, AppTypography.labelMedium.height);
    }

    expect(tester.getSize(find.byType(MobileTextField)).height, 60);
    final addressField = find.byKey(
      const ValueKey('mobile_pay_add_contact_address'),
    );
    expect(tester.getSize(addressField).height, 60);
    final addressDecoration =
        tester.widget<Container>(addressField).decoration! as BoxDecoration;
    expect(addressDecoration.boxShadow, hasLength(4));
    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_cancel')),
      findsOneWidget,
    );
    expect(find.byType(MobileSheetCancel), findsOneWidget);
    final chainRowRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_add_contact_chain_row')),
    );
    expect(
      tester.getRect(find.text('Ethereum')).right,
      closeTo(chainRowRect.right - AppSpacing.xxs, 0.01),
    );

    final avatar = find.bySemanticsLabel('Change contact picture');
    expect(avatar, findsOneWidget);
    expect(tester.getSize(avatar), const Size.square(72));
    final editIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_pay_add_contact_picture')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.edit,
        ),
      ),
    );
    expect(editIcon.size, 14);
    expect(find.bySemanticsLabel('Address $_address'), findsOneWidget);
  });

  testWidgets('shows clear label only for focused non-empty input', (
    tester,
  ) async {
    await pumpCard(tester, onSave: (_, _) async {});

    final field = find.byKey(const ValueKey('mobile_pay_add_contact_label'));
    expect(find.bySemanticsLabel('Clear contact label'), findsNothing);

    await tester.enterText(field, 'Mike');
    await tester.pump();
    expect(find.bySemanticsLabel('Clear contact label'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Clear contact label'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    expect(find.bySemanticsLabel('Clear contact label'), findsNothing);

    await tester.enterText(field, 'Mike');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.bySemanticsLabel('Clear contact label'), findsNothing);
  });

  testWidgets('scrolls inside the card on a compact keyboard viewport', (
    tester,
  ) async {
    await pumpCard(
      tester,
      size: const Size(375, 667),
      keyboardInset: 300,
      onSave: (_, _) async {},
    );

    final scaffold = find.byType(MobileModalScaffold);
    expect(tester.getRect(scaffold).bottom, lessThanOrEqualTo(351));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile_pay_add_contact_cancel')),
    );
    await tester.pump();
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mobile_pay_add_contact_cancel')))
          .bottom,
      lessThanOrEqualTo(tester.getRect(scaffold).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'surfaces save failures and clears the error on input and retry',
    (tester) async {
      var saveCalls = 0;
      await pumpCard(
        tester,
        onSave: (_, _) async {
          saveCalls += 1;
          if (saveCalls < 3) throw StateError('write failed');
        },
      );

      final field = find.byKey(const ValueKey('mobile_pay_add_contact_label'));
      final save = find.byKey(const ValueKey('mobile_pay_add_contact_save'));
      const error = "Couldn't save this contact. Try again.";

      await tester.enterText(field, 'Mike');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saveCalls, 1);
      expect(find.text(error), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(field, 'Michael');
      await tester.pump();
      expect(find.text(error), findsNothing);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(error), findsOneWidget);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(error), findsNothing);
      expect(saveCalls, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
