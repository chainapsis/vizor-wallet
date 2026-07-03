import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/account_modal_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('VerifyAddressModal unknown variant', () {
    testWidgets('renders header copy, grid, and the Close action', (
      tester,
    ) async {
      var closed = 0;
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.unknown,
          onClose: () => closed++,
        ),
      );

      expect(find.text('Unknown shielded address'), findsOneWidget);
      expect(find.byType(ReviewInfoIconCircle), findsOneWidget);

      // The add-to-contacts flow is deferred: Close is the only action.
      expect(find.text('Add to contacts'), findsNothing);
      expect(find.byType(AppButton), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('leading-aligns the unknown header inside the card', (
      tester,
    ) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.unknown,
          onClose: () {},
        ),
      );

      final cardLeft = tester.getTopLeft(find.byType(AccountModalCard)).dx;
      final iconLeft = tester.getTopLeft(find.byType(ReviewInfoIconCircle)).dx;

      expect(iconLeft - cardLeft, moreOrLessEquals(AppSpacing.sm));
    });

    testWidgets('renders transparent unknown header copy', (tester) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX',
          variant: VerifyAddressModalVariant.unknown,
          unknownAddressKind: VerifyAddressModalAddressKind.transparent,
          onClose: () {},
        ),
      );

      expect(find.text('Unknown transparent address'), findsOneWidget);
      expect(find.text('Unknown shielded address'), findsNothing);
    });

    testWidgets('highlights the fixed head/tail groups in crimson', (
      tester,
    ) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.unknown,
          onClose: () {},
        ),
      );

      final colors = AppThemeData.light.colors;
      final rows = addressVerifyGrid(_address);

      final firstGroup = rows.first.first;
      expect(firstGroup.highlighted, isTrue);
      final firstText = tester.widget<Text>(find.text(firstGroup.text).first);
      expect(firstText.style?.color, colors.text.brandCrimson);
      expect(firstText.style?.fontWeight, FontWeight.w600);

      final lastGroup = rows.last.last;
      expect(lastGroup.highlighted, isTrue);
      final lastText = tester.widget<Text>(find.text(lastGroup.text).last);
      expect(lastText.style?.color, colors.text.brandCrimson);
      expect(lastText.style?.fontWeight, FontWeight.w600);

      // Second group of the first row sits outside the mock's
      // non-consecutive emphasis pattern (0, 2, N-3, N-1).
      final middleGroup = rows.first[1];
      expect(middleGroup.highlighted, isFalse);
      final middleText = tester.widget<Text>(find.text(middleGroup.text).first);
      expect(middleText.style?.color, colors.text.primary);
      expect(middleText.style?.fontWeight, FontWeight.w500);
    });
  });

  group('VerifyAddressModal knownContact variant', () {
    testWidgets('shows the contact identity and Close only', (tester) async {
      var closed = 0;
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.knownContact,
          contactName: 'Mike',
          contactProfilePictureId: 'pfp-02',
          previousTransactionCount: 12,
          onClose: () => closed++,
        ),
      );

      expect(find.text('Mike'), findsOneWidget);
      expect(find.byType(AppProfilePicture), findsOneWidget);
      expect(find.text('12 previous transactions'), findsOneWidget);
      expect(find.text('Unknown shielded address'), findsNothing);
      expect(find.text('Add to contacts'), findsNothing);
      expect(find.byType(AppButton), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('hides the transactions sub-line when the count is null', (
      tester,
    ) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.knownContact,
          contactName: 'Mike',
          contactProfilePictureId: 'pfp-02',
          onClose: () {},
        ),
      );

      expect(find.textContaining('previous transaction'), findsNothing);
    });

    testWidgets('hides the transactions sub-line when the count is zero', (
      tester,
    ) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.knownContact,
          contactName: 'Mike',
          contactProfilePictureId: 'pfp-02',
          previousTransactionCount: 0,
          onClose: () {},
        ),
      );

      expect(find.textContaining('previous transaction'), findsNothing);
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
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
        child: Center(child: child),
      ),
    ),
  );
  await tester.pump();
}
