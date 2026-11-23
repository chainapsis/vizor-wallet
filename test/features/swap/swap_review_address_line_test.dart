import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/address_line_text.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_plan.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_review_page_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

// The desktop swap review and status summaries name the counterparty address
// beside a Copy action. A saved contact's name or a longer translation must
// never cut the address's tail ("0x9aDFd23 ... E48…").

const _externalAddress = '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2';
const _walletAddress =
    'u1q6g2k3r4s5t6u7v8w9x0yzaabbccddeeff00112233445566778899';
const _labels = [null, 'Mike', 'Rowan Ledger'];
const _locales = ['en', 'ko', 'zh'];

AddressBookContact _contact(String label) => AddressBookContact(
  id: 'contact',
  label: label,
  network: AddressBookNetwork.ethereum,
  address: _externalAddress,
  profilePictureId: 'default',
  createdAtMs: 0,
  updatedAtMs: 0,
);

Future<void> _pump(
  WidgetTester tester,
  Widget Function(BuildContext context) builder, {
  required String locale,
  required double width,
  double textScale = 1,
}) async {
  await loadFigmaCompareFonts();
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: appSupportedLocales(preview: true),
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppTheme(
          data: AppThemeData.light,
          // The language's own fonts, as the app sets them.
          child: LocaleTypography(child: navigator!),
        ),
      ),
      home: SingleChildScrollView(child: Builder(builder: builder)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectAddressWhole(WidgetTester tester, String address, {String? name}) {
  final lines = [
    for (final element in find.byType(RichText).evaluate())
      if ((element.renderObject! as RenderParagraph).text
          .toPlainText()
          .contains(address))
        element.renderObject! as RenderParagraph,
  ];
  expect(lines, isNotEmpty, reason: 'No line shows $address');
  for (final line in lines) {
    expect(
      line.didExceedMaxLines,
      isFalse,
      reason: '"${line.text.toPlainText()}" is cut short',
    );
    if (name != null) expect(line.text.toPlainText(), contains(name));
  }
}

void main() {
  final compact = truncatedAddress(_externalAddress);

  for (final direction in SwapDirection.values) {
    for (final locale in _locales) {
      for (final label in _labels) {
        testWidgets(
          'review, ${direction.name}, $locale, ${label ?? 'no contact'}',
          (tester) async {
            await _pump(
              tester,
              (_) => SwapReviewPageContent(
                quote: SwapQuote.estimate(
                  direction: direction,
                  externalAsset: SwapAsset.usdc,
                  amount: 1.12,
                ),
                addressPlan: SwapAddressPlan.fromUserInput(
                  direction: direction,
                  externalAsset: SwapAsset.usdc,
                  userExternalAddress: _externalAddress,
                  walletZecAddress: _walletAddress,
                  oneTimeZecAddress: false,
                ),
                onCopy: (_) {},
                addressBookContacts: [if (label != null) _contact(label)],
                expired: false,
                amountWarning: null,
                startError: null,
              ),
              locale: locale,
              // The review panel's width (swap_screen.dart).
              width: 420,
            );
            _expectAddressWhole(tester, compact, name: label);
          },
        );
      }
    }
  }

  for (final paymentMode in const [false, true]) {
    for (final locale in _locales) {
      for (final label in _labels) {
        testWidgets('status${paymentMode ? ' (Pay)' : ''}, $locale, '
            '${label ?? 'no contact'}', (tester) async {
          await _pump(
            tester,
            (context) {
              final recipient = AddressLine.inTemplate(
                (address) => context.l10n.commonToAddressOnChain(
                  address,
                  SwapAsset.usdc.chainLabel,
                ),
                address: compact,
                label: label,
              );
              return SwapStatusPageContent(
                title: 'Swap completed',
                payAsset: SwapAsset.zec,
                receiveAsset: SwapAsset.usdc,
                payAmountText: '1.12 ZEC',
                receiveAmountText: '100.12 USDC',
                payDetailText: r'$250.12',
                receiveDetailText: recipient.text,
                receiveDetailAddress: recipient,
                receiveDetailCopyText: _externalAddress,
                statusLabel: 'Completed',
                badgeKind: SwapStatusBadgeKind.completed,
                paymentMode: paymentMode,
                showTabs: false,
                onCopy: (_) {},
              );
            },
            locale: locale,
            width: 400,
          );
          _expectAddressWhole(tester, compact, name: label);
        });
      }
    }
  }

  // The Pay review's recipient pill shortens a long chain name, never the
  // address.
  for (final chain in const ['bsc', 'hood']) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('Pay review pill, $chain, ${scale}x', (tester) async {
        final asset = SwapAsset.live(
          assetId: 'pay-$chain',
          symbol: 'USDC',
          blockchain: chain,
          decimals: 6,
        );
        const direction = SwapDirection.zecToExternal;
        await _pump(
          tester,
          (_) => SwapReviewPageContent(
            quote: SwapQuote.estimate(
              direction: direction,
              externalAsset: asset,
              amount: 1.12,
            ),
            addressPlan: SwapAddressPlan.fromUserInput(
              direction: direction,
              externalAsset: asset,
              userExternalAddress: _externalAddress,
              walletZecAddress: _walletAddress,
              oneTimeZecAddress: false,
            ),
            onCopy: (_) {},
            payMode: true,
            expired: false,
            amountWarning: null,
            startError: null,
          ),
          locale: 'en',
          width: 420,
          textScale: scale,
        );
        _expectAddressWhole(tester, compact);
      });
    }
  }
}
