import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RustApiFake rustApi;

  setUpAll(() {
    rustApi = _RustApiFake();
    RustLib.initMock(api: rustApi);
  });

  setUp(() {
    rustApi.reset();
  });

  tearDownAll(RustLib.dispose);

  testWidgets('uses shell window backing behind the send sidebar and pane', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_sendHarness());
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.light.colors.macosUtility.window,
    );
  });

  testWidgets('prefills imported payment request into send compose', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        prefill: const SendPrefillArgs(
          id: 'zip321-1',
          source: 'ZIP-321',
          address: _shieldedAddress,
          amountText: '1.25',
          memoText: 'Donation note',
          label: 'Invoice #42',
          message: 'Thank you',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The imported-request banner was removed; the prefill applies silently.
    expect(find.byKey(const ValueKey('send_prefill_notice')), findsNothing);
    expect(find.text('Imported request'), findsNothing);
    expect(_fieldText(tester, 'send_address_field'), _shieldedAddress);
    expect(_fieldText(tester, 'send_amount_field'), '1.25');
    expect(find.text('Donation note'), findsOneWidget);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_review_button')), findsOneWidget);
  });

  testWidgets('contacts label fills the send address from zcash contacts', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        addressBookRepository: _FakeAddressBookRepository([
          _contact(
            id: 'alice',
            label: 'Alice',
            network: AddressBookNetwork.zcash,
            address: _shieldedAddress,
          ),
          _contact(
            id: 'sol',
            label: 'Sol Friend',
            network: AddressBookNetwork.solana,
            address: 'solana-address',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send_contacts_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsOneWidget,
    );
    final contactModal = tester.widget<Container>(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
    );
    final contactDecoration = contactModal.decoration as BoxDecoration;
    expect(contactModal.clipBehavior, Clip.antiAlias);
    expect(
      contactModal.padding,
      const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, 0),
    );
    expect(contactDecoration.color, AppThemeData.light.colors.background.base);
    expect(
      contactDecoration.borderRadius,
      BorderRadius.circular(AppRadii.large),
    );
    expect(contactDecoration.boxShadow, _figmaModalSurfaceShadows);
    expect(find.bySemanticsLabel('Close contacts'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    final contactScrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('address_book_contact_picker_scrollbar')),
    );
    expect(contactScrollbar.thickness, 6);
    expect(contactScrollbar.mainAxisMargin, 6);
    expect(contactScrollbar.crossAxisMargin, 6);
    final contactListGutter = tester.widget<Padding>(
      find.byKey(const ValueKey('address_book_contact_picker_list_gutter')),
    );
    expect(contactListGutter.padding, const EdgeInsets.only(right: 22));
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('address_book_contact_picker_contact_alice'),
            ),
          )
          .height,
      44,
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Sol Friend'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_picker_contact_alice')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('address_book_contact_picker_modal')),
      findsNothing,
    );
    expect(_fieldText(tester, 'send_address_field'), _shieldedAddress);
    // The matched contact's name stays visible under the field so the user
    // knows the filled address is the intended one.
    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app-text-field-message-row')),
        matching: find.text('Alice'),
      ),
      findsOneWidget,
    );
    expect(find.text('Contacts'), findsOneWidget);
  });

  testWidgets('keeps contacts label for prefilled and cleared addresses', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        addressBookRepository: _FakeAddressBookRepository([
          _contact(
            id: 'alice',
            label: 'Alice',
            network: AddressBookNetwork.zcash,
            address: _shieldedAddress,
          ),
        ]),
        prefill: const SendPrefillArgs(
          id: 'address-book-alice',
          source: 'address-book',
          address: _shieldedAddress,
          label: 'Alice',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'send_address_field'), _shieldedAddress);
    // Prefilled address matches the saved contact, so the match line names it.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('send_address_field')),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Contacts'), findsOneWidget);
  });

  testWidgets('contact picker shares scrollbar controller for long lists', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        addressBookRepository: _FakeAddressBookRepository([
          for (var index = 0; index < 8; index++)
            _contact(
              id: 'zcash-$index',
              label: 'Contact $index',
              network: AddressBookNetwork.zcash,
              address: '$_shieldedAddress$index',
            ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send_contacts_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('address_book_contact_picker_scrollbar')),
    );
    final listView = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const ValueKey('address_book_contact_picker_modal')),
        matching: find.byType(ListView),
      ),
    );

    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.controller, same(listView.controller));
  });

  testWidgets('memo input only opens after a valid shielded address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_sendHarness());
    await tester.pumpAndSettle();

    expect(find.text('Add a memo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('send_add_memo_card'))),
      const Size(396, 128),
    );

    await tester.tap(find.text('Add a memo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_memo_field')), findsNothing);

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();

    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('Add a memo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('send_add_memo_card'))),
      const Size(396, 128),
    );

    await tester.tap(find.text('Add a memo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_memo_field')), findsOneWidget);
  });

  testWidgets('hides imported memo controls for transparent recipients', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        prefill: const SendPrefillArgs(
          id: 'zip321-transparent',
          source: 'ZIP-321',
          address: _transparentAddress,
          amountText: '0.5',
          memoText: 'Transparent memo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('Transparent memo'), findsNothing);
    expect(find.text('Add a memo'), findsNothing);
    expect(find.text('Encrypted, for shielded addresses only.'), findsNothing);
    expect(find.byKey(const ValueKey('send_add_memo_card')), findsNothing);
    expect(find.byKey(const ValueKey('send_memo_field')), findsNothing);
  });

  testWidgets('transparent recipient Max fills amount without memo', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(500000000)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      _editableIn('send_address_field'),
      _transparentAddress,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use Max'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(rustApi.lastEstimateSendMaxToAddress, _transparentAddress);
    expect(rustApi.lastEstimateSendMaxMemo, isNull);
    expect(_fieldText(tester, 'send_amount_field'), isNotEmpty);
    expect(find.text('Max amount unavailable'), findsNothing);
  });

  testWidgets('amount field keeps the native ticker suffix while editing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_sendHarness());
    await tester.pumpAndSettle();

    _expectAmountIcon(
      tester,
      AppIcons.zcash,
      AppThemeData.light.colors.icon.regular,
    );

    await tester.enterText(_editableIn('send_amount_field'), '1.25');
    await tester.pumpAndSettle();

    _expectAmountIcon(
      tester,
      AppIcons.zcash,
      AppThemeData.light.colors.icon.accent,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.text(kZcashDefaultCurrencyTicker),
      ),
      findsOneWidget,
    );
  });

  testWidgets('zero amount disables review without showing amount error', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(1000000000)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '0');
    await tester.pumpAndSettle();

    expect(find.text('Invalid amount'), findsNothing);
    expect(find.byKey(const ValueKey('send_amount_error_text')), findsNothing);
    final reviewButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('send_review_button')),
    );
    expect(reviewButton.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('send_review_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
    expect(find.text('Review Send'), findsNothing);
  });

  testWidgets('amount error appears before recipient is entered', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(4258463)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_amount_field'), '111111');
    await tester.pumpAndSettle();

    expect(find.text('Insufficient shielded balance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_amount_error_text')),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'send_address_field'), isEmpty);
    expect(find.text('Review'), findsOneWidget);
    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('hides imported memo controls for TEX recipients', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        prefill: const SendPrefillArgs(
          id: 'zip321-tex',
          source: 'ZIP-321',
          address: _texAddress,
          amountText: '0.5',
          memoText: 'TEX memo',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('TEX memo'), findsNothing);
    expect(find.text('Add a message'), findsNothing);
    expect(find.text('Encrypted, for Shielded Addresses only.'), findsNothing);
  });

  testWidgets('TEX review uses shielded balance and raw address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(2000000000),
        transparentBalance: BigInt.from(2000000000),
        prefill: const SendPrefillArgs(
          id: 'zip321-tex-balance',
          source: 'ZIP-321',
          address: _texAddress,
          amountText: '1.0',
          memoText: 'Dropped memo',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Insufficient shielded balance'), findsNothing);
    expect(find.text('Insufficient balance'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('send_review_button')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeToAddress, _texAddress);
    expect(rustApi.lastProposeMemo, isNull);
  });

  testWidgets('TEX ignores transparent balance for availability', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(50000000),
        transparentBalance: BigInt.from(2000000000),
        prefill: const SendPrefillArgs(
          id: 'zip321-tex-transparent-ignored',
          source: 'ZIP-321',
          address: _texAddress,
          amountText: '1.0',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Insufficient balance'), findsOneWidget);
    expect(find.text('Insufficient shielded balance'), findsNothing);
    expect(find.text(r'$ 70.00'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send_review_button')));
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('fee-specific balance error copy is preserved', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(100000000)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '0.99995');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Insufficient shielded balance (fee:'),
      findsOneWidget,
    );
    expect(find.text('Review'), findsOneWidget);
    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('USD amount error stays below the amount field', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(50000000), zecUsdPrice: 100),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send_amount_mode_toggle')));
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_amount_field'), '250');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('send_amount_error_text')),
      findsOneWidget,
    );
    expect(find.text('Insufficient shielded balance'), findsOneWidget);
    expect(find.text('2.5 $kZcashDefaultCurrencyTicker'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send_review_button')));
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('USD amount input proposes the converted canonical amount', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(1000000000), zecUsdPrice: 100),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send_amount_mode_toggle')));
    await tester.pumpAndSettle();
    _expectAmountIcon(
      tester,
      AppIcons.moneyBag,
      AppThemeData.light.colors.icon.regular,
    );

    await tester.enterText(_editableIn('send_amount_field'), '250');
    await tester.pumpAndSettle();

    _expectAmountIcon(
      tester,
      AppIcons.moneyBag,
      AppThemeData.light.colors.icon.accent,
    );
    expect(_fieldText(tester, 'send_amount_field'), '250');
    expect(find.text('2.5 $kZcashDefaultCurrencyTicker'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeAmountZatoshi, BigInt.from(250000000));
  });

  testWidgets('USD amount input recomputes when the ZEC price changes', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final zecUsdPriceProvider =
        NotifierProvider<_TestZecUsdPriceNotifier, double?>(
          _TestZecUsdPriceNotifier.new,
        );

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(1000000000),
        zecUsdPriceProvider: zecUsdPriceProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send_amount_mode_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '250');
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'send_amount_field'), '250');
    expect(find.text('2.5 $kZcashDefaultCurrencyTicker'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SendScreen)),
      listen: false,
    );
    container.read(zecUsdPriceProvider.notifier).setPrice(200);
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'send_amount_field'), '250');
    expect(find.text('1.25 $kZcashDefaultCurrencyTicker'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeAmountZatoshi, BigInt.from(125000000));
  });

  testWidgets('native amount remains reviewable while USD price is loading', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(1000000000),
        zecUsdPrice: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.25');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('send_amount_price_loading')),
      findsOneWidget,
    );

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeAmountZatoshi, BigInt.from(125000000));
  });

  testWidgets('hardware TEX sends are blocked inline before proposal', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        bootstrap: _hardwareBootstrap,
        spendableBalance: BigInt.from(2000000000),
        prefill: const SendPrefillArgs(
          id: 'hardware-tex',
          source: 'ZIP-321',
          address: _texAddress,
          amountText: '0.5',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.text('Keystone does not support TEX sends yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('send_cta_warning')), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('hardware TEX address explains unsupported state before amount', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        bootstrap: _hardwareBootstrap,
        spendableBalance: BigInt.from(2000000000),
        prefill: const SendPrefillArgs(
          id: 'hardware-tex-no-amount',
          source: 'ZIP-321',
          address: _texAddress,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'send_amount_field'), isEmpty);
    expect(
      find.text('Keystone does not support TEX sends yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('send_cta_warning')), findsOneWidget);
    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(rustApi.proposeSendCalls, 0);
  });
}

const _figmaModalSurfaceShadows = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
];

Widget _sendHarness({
  SendPrefillArgs? prefill,
  AddressBookRepository? addressBookRepository,
  AppBootstrapState? bootstrap,
  BigInt? spendableBalance,
  BigInt? transparentBalance,
  double? zecUsdPrice = 70,
  NotifierProvider<_TestZecUsdPriceNotifier, double?>? zecUsdPriceProvider,
}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => SendScreen(prefill: prefill),
      ),
      GoRoute(path: '/send/review', builder: (_, _) => const SizedBox.shrink()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap),
      sendWalletDbPathProvider.overrideWithValue(() async => '/tmp/test.db'),
      zecUsdPriceProvider == null
          ? zecHomeUsdUnitPriceProvider.overrideWithValue(zecUsdPrice)
          : zecHomeUsdUnitPriceProvider.overrideWith(
              (ref) => ref.watch(zecUsdPriceProvider),
            ),
      syncProvider.overrideWith(
        () => _FakeSyncNotifier(
          spendableBalance: spendableBalance ?? BigInt.from(500000000),
          transparentBalance: transparentBalance ?? BigInt.zero,
        ),
      ),
      if (addressBookRepository != null)
        addressBookRepositoryProvider.overrideWithValue(addressBookRepository),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AddressBookContact _contact({
  required String id,
  required String label,
  required AddressBookNetwork network,
  required String address,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: network,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository(List<AddressBookContact> contacts)
    : contacts = [...contacts];

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts
      ..clear()
      ..addAll(contacts);
  }
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

String _fieldText(WidgetTester tester, String keyValue) {
  final editable = tester.widget<EditableText>(_editableIn(keyValue));
  return editable.controller.text;
}

Finder _editableIn(String keyValue) {
  return find.descendant(
    of: find.byKey(ValueKey(keyValue)),
    matching: find.byType(EditableText),
  );
}

void _expectAmountIcon(WidgetTester tester, String name, Color color) {
  final icon = tester.widget<AppIcon>(
    find.descendant(
      of: find.byKey(const ValueKey('send_amount_field')),
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == name,
      ),
    ),
  );

  expect(icon.name, name);
  expect(icon.size, 20);
  expect(icon.color, color);
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier({
    required this.spendableBalance,
    required this.transparentBalance,
  });

  final BigInt spendableBalance;
  final BigInt transparentBalance;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: spendableBalance,
    transparentBalance: transparentBalance,
    totalBalance: spendableBalance + transparentBalance,
  );
}

class _TestZecUsdPriceNotifier extends Notifier<double?> {
  @override
  double? build() => 100;

  void setPrice(double? price) {
    state = price;
  }
}

class _RustApiFake implements RustLibApi {
  int proposeSendCalls = 0;
  int estimateSendMaxCalls = 0;
  String? lastProposeToAddress;
  String? lastProposeMemo;
  BigInt? lastProposeAmountZatoshi;
  String? lastEstimateSendMaxToAddress;
  String? lastEstimateSendMaxMemo;

  void reset() {
    proposeSendCalls = 0;
    estimateSendMaxCalls = 0;
    lastProposeToAddress = null;
    lastProposeMemo = null;
    lastProposeAmountZatoshi = null;
    lastEstimateSendMaxToAddress = null;
    lastEstimateSendMaxMemo = null;
  }

  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
    if (address == _texAddress) {
      return const AddressValidationResult(isValid: true, addressType: 'tex');
    }
    if (address == _transparentAddress) {
      return const AddressValidationResult(
        isValid: true,
        addressType: 'transparent',
      );
    }
    return const AddressValidationResult(isValid: true, addressType: 'unified');
  }

  @override
  Future<BigInt> crateApiSyncEstimateFee({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    return BigInt.from(10000);
  }

  @override
  Future<SendMaxEstimateResult> crateApiSyncEstimateSendMax({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    String? memo,
  }) async {
    estimateSendMaxCalls++;
    lastEstimateSendMaxToAddress = toAddress;
    lastEstimateSendMaxMemo = memo;
    return SendMaxEstimateResult(
      amountZatoshi: BigInt.from(499990000),
      feeZatoshi: BigInt.from(10000),
      needsSaplingParams: false,
    );
  }

  @override
  Future<ProposalResult> crateApiSyncProposeSend({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String sendFlowId,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    proposeSendCalls++;
    lastProposeToAddress = toAddress;
    lastProposeMemo = memo;
    lastProposeAmountZatoshi = amountZatoshi;
    return ProposalResult(
      proposalId: BigInt.one,
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _shieldedAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000000';
const _transparentAddress = 't1transparentdestination0000000000000000000';
const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
