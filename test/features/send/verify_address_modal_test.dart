import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/account_modal_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('VerifyAddressModal unknown variant', () {
    testWidgets('renders header copy, wrapping address, and the Close action', (
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
      expect(find.text(_address), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      // The add-to-contacts flow is deferred: Copy plus Close.
      expect(find.text('Add to contacts'), findsNothing);
      expect(find.byType(AppButton), findsNWidgets(2));

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

    testWidgets('copies the exact address from Copy', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.unknown,
          onClose: () {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('full_address_copy_button')));
      await tester.pump();
      expect(copied, [_address]);
    });

    testWidgets('uses Copy as the primary action', (tester) async {
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.unknown,
          onClose: () {},
        ),
      );

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text(_address), findsOneWidget);
      final addressText = tester.widget<Text>(
        find.byKey(const ValueKey('full_address_text')),
      );
      expect(addressText.style?.fontFamily, 'Geist Mono');
    });
  });

  testWidgets(
    'wrapped contact header clears the address and horizontal actions',
    (tester) async {
      await loadFigmaCompareFonts();
      const name = 'Treasury operating account';
      await _pump(
        tester,
        VerifyAddressModal(
          address: _address,
          variant: VerifyAddressModalVariant.knownContact,
          contactName: name,
          contactProfilePictureId: 'pfp-02',
          previousTransactionCount: 12,
          onClose: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      final titleParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(name), matching: find.byType(RichText)),
      );
      expect(titleParagraph.didExceedMaxLines, isFalse);
      final title = tester.getRect(find.text(name));
      final subtitle = tester.getRect(find.text('12 previous transactions'));
      final address = tester.getRect(find.text(_address));
      expect(title.bottom, lessThanOrEqualTo(subtitle.top));
      expect(subtitle.bottom, lessThan(address.top));
      final close = tester.getRect(
        find.byKey(const ValueKey('verify_address_close_button')),
      );
      final copy = tester.getRect(
        find.byKey(const ValueKey('full_address_copy_button')),
      );
      expect(close.top, moreOrLessEquals(copy.top));
      expect(close.height, moreOrLessEquals(copy.height));
      expect(close.right, lessThan(copy.left));
      expect(find.text('Copy').hitTestable(), findsOneWidget);
    },
  );

  group('VerifyAddressModal knownContact variant', () {
    testWidgets('shows the contact identity and actions', (tester) async {
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
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

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
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(child: child),
      ),
    ),
  );
  await tester.pump();
}
