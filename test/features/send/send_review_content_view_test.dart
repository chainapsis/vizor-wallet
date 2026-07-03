import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/review_buttons_stack.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _transparentAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';

const _memo = 'Zcash is a privacy-focused ...';

void main() {
  testWidgets('address variant renders the full review layout', (tester) async {
    var confirms = 0;
    var cancels = 0;
    var reveals = 0;
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        fiatText: r'$250.12',
        recipient: const SendReviewAddressRecipient(address: _address),
        memoText: _memo,
        feeText: '0.012 ZEC',
        onConfirm: () => confirms++,
        onCancel: () => cancels++,
        onShowFullAddress: () => reveals++,
      ),
    );

    expect(find.text('Review send'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text(r'$250.12'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text(truncatedAddress(_address)), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_memo), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.012 ZEC'), findsOneWidget);
    expect(find.byType(ReviewWrapDivider), findsOneWidget);

    await tester.tap(find.text('Show full address'));
    await tester.tap(find.text('Confirm & send'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(reveals, 1);
    expect(confirms, 1);
    expect(cancels, 1);
  });

  testWidgets('address variant can render the transparent badge', (
    tester,
  ) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(
          address: _transparentAddress,
        ),
        isShieldedRecipient: false,
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text(truncatedAddress(_transparentAddress)), findsOneWidget);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('address variant can render the TEX badge', (tester) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _texAddress),
        isShieldedRecipient: false,
        recipientAddressType: 'tex',
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text(truncatedAddress(_texAddress)), findsOneWidget);
    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('pins the title to the Figma content top inset', (tester) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(
      tester.getTopLeft(find.text('Review send')).dy,
      moreOrLessEquals(AppSpacing.sm),
    );
  });

  testWidgets('keeps the title pinned inside scroll min-height constraints', (
    tester,
  ) async {
    const contentHeight = 656.0;
    await _pump(
      tester,
      SizedBox(
        width: AppWindowSizing.contentAreaMaxWidth,
        height: contentHeight,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: contentHeight),
            child: SendReviewContentView(
              amountText: '123.12 ZEC',
              recipient: const SendReviewAddressRecipient(address: _address),
              feeText: '0.012 ZEC',
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Review send')).dy,
      moreOrLessEquals(AppSpacing.sm),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('contact variant swaps the recipient row presentation', (
    tester,
  ) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewContactRecipient(
          address: _address,
          name: 'Mike',
          profilePictureId: 'pfp-02',
        ),
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text('Mike'), findsOneWidget);
    expect(find.byType(AppProfilePicture), findsOneWidget);
    // The truncated address moves to the sub-line; the Shielded badge and
    // the wallet icon circle are replaced.
    expect(find.text(truncatedAddress(_address)), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
    expect(find.byType(ReviewInfoIconCircle), findsNothing);
    expect(find.text('Show full address'), findsOneWidget);
  });

  testWidgets('TEX contact recipient keeps a TEX label', (tester) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewContactRecipient(
          address: _texAddress,
          name: 'Mike',
          profilePictureId: 'pfp-02',
        ),
        isShieldedRecipient: false,
        recipientAddressType: 'tex',
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text('Mike'), findsOneWidget);
    expect(find.byType(AppProfilePicture), findsOneWidget);
    expect(find.text('TEX - ${truncatedAddress(_texAddress)}'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
    expect(find.byType(ReviewInfoIconCircle), findsNothing);
  });

  testWidgets('hides the fiat sub-label and memo row when null', (
    tester,
  ) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text(r'$250.12'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.byType(ReviewWrapDivider), findsNothing);
    expect(find.text('Tx fee'), findsOneWidget);
  });

  testWidgets('memo expand affordance fires its callback', (tester) async {
    var expands = 0;
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        memoText: _memo,
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
        onExpandMemo: () => expands++,
      ),
    );

    await tester.tap(find.text(_memo));
    await tester.pump();
    expect(expands, 1);
  });

  testWidgets('expanded memo renders the full text with a collapse toggle', (
    tester,
  ) async {
    var toggles = 0;
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        memoText: _memo,
        memoExpanded: true,
        feeText: '0.012 ZEC',
        onConfirm: () {},
        onCancel: () {},
        onExpandMemo: () => toggles++,
      ),
    );

    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_memo)).maxLines, isNull);

    await tester.tap(find.text('Collapse'));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('hardware props swap the primary CTA label and icon', (
    tester,
  ) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        feeText: '0.012 ZEC',
        confirmLabel: 'Confirm with Keystone',
        confirmLeadingIconName: AppIcons.qr,
        onConfirm: () {},
        onCancel: () {},
      ),
    );

    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Confirm & send'), findsNothing);
    final stack = tester.widget<ReviewButtonsStack>(
      find.byType(ReviewButtonsStack),
    );
    expect(stack.primaryLeadingIconName, AppIcons.qr);
  });

  testWidgets('null onConfirm renders a disabled primary CTA', (tester) async {
    await _pump(
      tester,
      SendReviewContentView(
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        feeText: '0.012 ZEC',
        onConfirm: null,
        onCancel: () {},
      ),
    );

    final stack = tester.widget<ReviewButtonsStack>(
      find.byType(ReviewButtonsStack),
    );
    expect(stack.onPrimaryPressed, isNull);
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
      home: AppTheme(data: AppThemeData.light, child: child),
    ),
  );
  await tester.pump();
}
