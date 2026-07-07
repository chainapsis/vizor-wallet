@Tags(['mobile'])
library;

import 'package:flutter/material.dart'
    show MaterialApp, SingleChildScrollView, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations_en.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_address_formatting.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates:
        AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, navigator) =>
        AppTheme(data: AppThemeData.light, child: navigator!),
    home: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

MobileSwapReviewContent _content({
  Iterable<AddressBookContact> addressBookContacts = const [],
  SwapDirection direction = SwapDirection.zecToExternal,
}) {
  const externalAddress = '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2';
  const walletAddress =
      'u1q6g2k3r4s5t6u7v8w9x0yzaabbccddeeff00112233445566778899';
  final quote = SwapQuote.estimate(
    direction: direction,
    externalAsset: SwapAsset.usdc,
    amount: 1.12,
  );
  final addressPlan = SwapAddressPlan.fromUserInput(
    direction: direction,
    externalAsset: SwapAsset.usdc,
    userExternalAddress: externalAddress,
    walletZecAddress: walletAddress,
  );

  return MobileSwapReviewContent(
    quote: quote,
    addressPlan: addressPlan,
    accountLabel: 'Main account',
    accountProfilePictureId: 'default',
    addressBookContacts: addressBookContacts,
    expired: false,
    amountWarning: null,
    startError: null,
  );
}

void main() {
  testWidgets(
    'review card omits account destination and price protection rows',
    (tester) async {
      await tester.pumpWidget(_harness(_content()));

      expect(find.text('From'), findsNothing);
      expect(find.text('To'), findsNothing);
      expect(find.text('Price protection'), findsNothing);
      expect(find.text('Minimum receive'), findsNothing);
      expect(find.text('Tx fee'), findsNothing);

      expect(find.text('Slippage tolerance'), findsOneWidget);
      expect(find.text('Guaranteed minimum'), findsOneWidget);
      expect(find.text('Swap fee'), findsOneWidget);
    },
  );

  testWidgets('review card omits saved address book identity', (tester) async {
    await tester.pumpWidget(
      _harness(
        _content(
          addressBookContacts: const [
            AddressBookContact(
              id: 'treasury',
              label: 'Treasury',
              network: AddressBookNetwork.ethereum,
              address: '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2',
              profilePictureId: 'default',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Saved recipient'), findsNothing);
    expect(find.text('Treasury'), findsNothing);
    expect(find.text('Slippage tolerance'), findsOneWidget);
  });

  testWidgets('header To: line names a matched saved contact', (tester) async {
    await tester.pumpWidget(
      _harness(
        _content(
          addressBookContacts: const [
            AddressBookContact(
              id: 'treasury',
              label: 'Treasury',
              network: AddressBookNetwork.ethereum,
              address: '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2',
              profilePictureId: 'default',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ],
        ),
      ),
    );

    final compactAddress = compactSwapAddress(
      '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2',
      prefixLength: 6,
      suffixLength: 5,
      separator: ' ... ',
    );
    expect(find.text('To: Treasury ($compactAddress)'), findsOneWidget);
  });

  testWidgets('review detail help icons use desktop tooltip copy', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    expect(
      _tooltipWithMessage(swapMinimumReceiveTooltip(AppLocalizationsEn(), 'USDC')),
      findsOneWidget,
    );
    expect(_tooltipWithMessage(swapFeeTooltip(AppLocalizationsEn())), findsOneWidget);
  });

  testWidgets('external address compact text keeps a single middle ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content()));

    final compactAddress = compactSwapAddress(
      '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2',
      prefixLength: 6,
      suffixLength: 5,
      separator: ' ... ',
    );
    expect(find.text('To: $compactAddress'), findsOneWidget);
    expect(compactAddress.endsWith('...'), isFalse);
  });

  testWidgets('external pay review omits the refund address line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_content(direction: SwapDirection.externalToZec)),
    );

    expect(find.text("You're paying"), findsOneWidget);
    expect(find.textContaining('From:'), findsNothing);
    expect(find.textContaining('Refund to:'), findsNothing);
    expect(find.text('Full address'), findsNothing);
  });

  testWidgets('full address sheet uses shared modal chunk layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const address =
        '111112222233333444445555566666777778888899999AAAAABBBBBCCCCC';
    await tester.pumpWidget(
      _harness(
        MobileSwapReviewHeader(
          pay: MobileSwapReviewHeaderRow(
            label: "You're paying",
            amountText: '1.12 ZEC',
            asset: SwapAsset.zec,
            bottomText: r'$250.12',
          ),
          receive: MobileSwapReviewHeaderRow(
            label: "You're receiving",
            amountText: '100.12 SOL',
            asset: SwapAsset.sol,
            bottomText: 'To: 11111 ... CCCCC',
            fullAddress: address,
            addressNetworkLabel: 'Solana address',
          ),
        ),
      ),
    );

    await tester.tap(find.text('Full address'));
    await tester.pumpAndSettle();

    expect(find.text('Solana address'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Solana address'));
    expect(title.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(title.style?.fontWeight, FontWeight.w600);

    final chunkScope = find.byKey(
      const ValueKey('mobile_address_verify_chunks'),
    );
    expect(chunkScope, findsOneWidget);
    final chunkScopeRect = tester.getRect(chunkScope);
    expect(chunkScopeRect.width, moreOrLessEquals(329));
    expect(
      find.descendant(of: chunkScope, matching: find.text('11111')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chunkScope, matching: find.text('22222')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chunkScope, matching: find.text('CCCCC')),
      findsOneWidget,
    );
    final firstChunk = tester.widget<Text>(find.text('11111'));
    expect(firstChunk.style?.fontSize, 14);
    expect(firstChunk.style?.height, 16 / 14);
    final firstLineScope = find.byKey(
      const ValueKey('mobile_address_verify_line_0'),
    );
    final lastLineScope = find.byKey(
      const ValueKey('mobile_address_verify_line_2'),
    );
    final firstLine = tester.widget<Row>(
      find.descendant(of: firstLineScope, matching: find.byType(Row)),
    );
    final lastLine = tester.widget<Row>(
      find.descendant(of: lastLineScope, matching: find.byType(Row)),
    );
    expect(firstLine.mainAxisAlignment, MainAxisAlignment.start);
    expect(lastLine.mainAxisAlignment, MainAxisAlignment.start);
    final firstDivider = find.byKey(
      const ValueKey('mobile_address_verify_divider_0'),
    );
    expect(tester.getSize(firstDivider).width, moreOrLessEquals(305));
    expect(
      tester.getRect(find.text('11111')).left,
      moreOrLessEquals(chunkScopeRect.left + 22, epsilon: 1),
    );
    final thirdChunk = tester.widget<Text>(find.text('33333'));
    expect(
      thirdChunk.style?.color,
      AppThemeData.light.colors.text.brandCrimson,
    );
    final secondChunk = tester.widget<Text>(find.text('22222'));
    expect(secondChunk.style?.color, AppThemeData.light.colors.text.primary);
    expect(
      tester.getRect(find.text('BBBBB')).left,
      moreOrLessEquals(tester.getRect(find.text('66666')).left, epsilon: 1),
    );
    expect(find.text('DDDDD'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

Finder _tooltipWithMessage(String message) {
  return find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
  );
}
