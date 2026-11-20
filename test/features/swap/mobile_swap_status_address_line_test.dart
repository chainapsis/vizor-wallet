@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/address_line_text.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

// The mobile swap status summary names the counterparty address under each
// amount. Whatever gives way on a phone, the address keeps its head and tail.

const _external = '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2';
const _wallet = 'u1q6g2k3r4s5t6u7v8w9x0yzaabbccddeeff00112233445566778899';

SwapIntent _intent(SwapDirection direction, {bool privateAddress = false}) {
  final sendsZec = direction == SwapDirection.zecToExternal;
  return SwapIntent(
    id: 'status-address-line',
    pair: sendsZec ? 'ZEC -> USDC' : 'USDC -> ZEC',
    sellAmount: sendsZec ? '1.12 ZEC' : '100.12 USDC',
    receiveEstimate: sendsZec ? '100.12 USDC' : '1.12 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: 'Swap completed',
    direction: direction,
    externalAsset: SwapAsset.usdc,
    depositAddress: sendsZec ? 't1deposit' : _external,
    depositTxHash: 'deposit-txid',
    oneClickRecipient: sendsZec ? _external : _wallet,
    oneClickRefundTo: sendsZec ? _wallet : _external,
    userExternalContactId: 'contact',
    privateAddress: privateAddress,
    createdAt: DateTime.utc(2026, 5, 20, 13, 20),
    completedAt: DateTime.utc(2026, 5, 20, 13, 21),
  );
}

/// The shown text of every summary line naming an address.
List<({String shown, bool cut})> _addressLines(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byType(AddressLineText),
            matching: find.byType(RichText),
          )
          .evaluate())
    (
      shown: (element.renderObject! as RenderParagraph).text.toPlainText(),
      cut: (element.renderObject! as RenderParagraph).didExceedMaxLines,
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  required SwapIntent intent,
  required String locale,
  required String? contact,
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  await loadFigmaCompareFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = SwapState(
    direction: intent.direction!,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [intent],
    selectedIntentId: intent.id,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWith(_AccountNotifier.new),
        addressBookProvider.overrideWith(() => _AddressBookNotifier(contact)),
        swapStateProvider.overrideWith(() => _SwapNotifier(state)),
        syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, navigator) => AppTheme(
          data: AppThemeData.light,
          // The language's own fonts, as the app sets them.
          child: LocaleTypography(child: navigator!),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          // The panel applies the page's side margins itself.
          child: SizedBox(
            height: size.height,
            child: SwapActivityDetailPagePanel(
              state: state,
              intent: intent,
              layout: SwapActivityDetailLayout.mobile,
              depositChecking: false,
              depositCheckWarning: null,
              onRefreshStatus: () {},
              onMarkDeposited: () {},
              onDepositTxHashChanged: (_) {},
              onSubmitDepositTransaction: () {},
              onReviewFreshQuote: () {},
              onSignZecDeposit: (_) {},
              intentIsHardware: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The refund line's localized lead-in ("Refund to:").
String _refundTo(String locale) =>
    lookupAppLocalizations(Locale(locale)).commonRefundToAddress('').trim();

void _expectLines(
  WidgetTester tester, {
  required SwapDirection direction,
  required String locale,
  required String? contact,
  bool largeText = false,
}) {
  final lines = _addressLines(tester);
  final sendsZec = direction == SwapDirection.zecToExternal;
  expect(lines, hasLength(sendsZec ? 1 : 2));
  for (final line in lines) {
    expect(line.cut, isFalse, reason: '"${line.shown}" is cut short');
  }
  // A saved contact stays named, on its own line when the row is narrow; a
  // long name or very large text may shorten it to its first characters.
  final name = contact == null
      ? null
      : (largeText || contact.length > 8 ? contact.substring(0, 3) : contact);
  if (sendsZec) {
    expect(lines.single.shown, contains(truncatedAddress(_external)));
    if (name != null) expect(lines.single.shown, contains(name));
    return;
  }
  // The refund line keeps saying what the address is for: under the amount
  // paid, a bare address would read as the payee.
  final refund = lines.first.shown;
  expect(refund, startsWith(_refundTo(locale)));
  expect(refund, contains(truncatedAddress(_external)));
  if (name != null) expect(refund, contains(name));
  expect(lines.last.shown, contains(truncatedAddress(_wallet)));
}

void main() {
  for (final direction in SwapDirection.values) {
    for (final privateAddress in const [false, true]) {
      for (final locale in const ['en', 'ko', 'zh']) {
        for (final contact in const [null, 'Mike', 'Rowan Ledger']) {
          testWidgets(
            '${direction.name}${privateAddress ? ' one-time' : ''}, $locale, '
            '${contact ?? 'no contact'}',
            (tester) async {
              await _pump(
                tester,
                intent: _intent(direction, privateAddress: privateAddress),
                locale: locale,
                contact: contact,
              );
              expect(tester.takeException(), isNull);
              _expectLines(
                tester,
                direction: direction,
                locale: locale,
                contact: contact,
              );
            },
          );
        }
      }
    }
  }

  testWidgets('larger text on a narrow phone wraps instead of cutting', (
    tester,
  ) async {
    for (final direction in SwapDirection.values) {
      await _pump(
        tester,
        intent: _intent(direction, privateAddress: true),
        locale: 'ko',
        contact: 'Rowan Ledger',
        size: const Size(320, 900),
        textScale: 1.3,
      );
      _expectLines(
        tester,
        direction: direction,
        locale: 'ko',
        contact: 'Rowan Ledger',
        largeText: true,
      );
    }
  });
}

class _SwapNotifier extends SwapNotifier {
  _SwapNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;
}

class _AccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: _wallet,
  );
}

class _AddressBookNotifier extends AddressBookNotifier {
  _AddressBookNotifier(this.label);

  final String? label;

  @override
  AddressBookState build() => AddressBookState(
    contacts: [
      if (label case final label?)
        AddressBookContact(
          id: 'contact',
          label: label,
          network: AddressBookNetwork.ethereum,
          address: _external,
          profilePictureId: 'pfp-01',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
    ],
  );
}
