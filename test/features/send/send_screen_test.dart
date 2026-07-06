import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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
    expect(find.bySemanticsLabel('Close contacts'), findsNothing);
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

  testWidgets('invalid recipient colors the send-to field affordances', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_sendHarness());
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _invalidAddress);
    await tester.pumpAndSettle();

    final colors = AppThemeData.light.colors;
    final fieldFinder = find.byKey(const ValueKey('send_address_field'));
    final label = tester.widget<Text>(
      find.descendant(of: fieldFinder, matching: find.text('Send to')),
    );
    final input = tester.widget<EditableText>(
      _editableIn('send_address_field'),
    );
    final leadingIcon = tester.widget<AppIcon>(
      find.descendant(
        of: fieldFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.plane,
        ),
      ),
    );
    final contactsLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('send_contacts_button')),
        matching: find.text('Contacts'),
      ),
    );
    final contactsChevron = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_contacts_button')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.name == AppIcons.chevronForward,
        ),
      ),
    );

    expect(label.style?.color, colors.text.secondary);
    expect(input.style.color, colors.text.destructive);
    expect(leadingIcon.color, colors.icon.destructive);
    expect(contactsLabel.style?.color, colors.text.secondary);
    expect(contactsChevron.color, colors.text.secondary);
    expect(find.text('Invalid address'), findsOneWidget);
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

    expect(find.text('Max: 5 ZEC'), findsOneWidget);

    await tester.tap(find.text('Max: 5 ZEC'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(rustApi.lastEstimateSendMaxToAddress, _transparentAddress);
    expect(rustApi.lastEstimateSendMaxMemo, isNull);
    expect(_fieldText(tester, 'send_amount_field'), isNotEmpty);
    expect(find.text('Max amount unavailable'), findsNothing);
  });

  testWidgets('Max before a valid address does not auto-fill later', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(500000000)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Max: 5 ZEC'));
    await tester.pump();
    await tester.pumpAndSettle();

    final addressField = find.byKey(const ValueKey('send_address_field'));
    final amountField = find.byKey(const ValueKey('send_amount_field'));
    expect(
      find.descendant(
        of: addressField,
        matching: find.text('Enter a valid address to use Max'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: amountField,
        matching: find.text('Enter a valid address to use Max'),
      ),
      findsNothing,
    );
    expect(_fieldText(tester, 'send_amount_field'), isEmpty);
    expect(rustApi.estimateSendMaxCalls, 0);

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid address to use Max'), findsNothing);
    expect(_fieldText(tester, 'send_amount_field'), isEmpty);
    expect(rustApi.estimateSendMaxCalls, 0);

    await tester.tap(find.text('Max: 5 ZEC'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(rustApi.lastEstimateSendMaxToAddress, _shieldedAddress);
    expect(_fieldText(tester, 'send_amount_field'), isNotEmpty);
  });

  testWidgets('Max in USD mode preserves the quote when prices refresh', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(500000000),
        zecUsdUnitPriceBuilder: (ref) => ref.watch(_testZecPriceProvider),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send_amount_currency_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max: 5 ZEC'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(_fieldText(tester, 'send_amount_field'), '349.99');
    expect(find.text('4.9999 ZEC'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SendScreen)),
    );
    container.read(_testZecPriceProvider.notifier).set(71);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(_fieldText(tester, 'send_amount_field'), '354.99');
    expect(find.text('4.9999 ZEC'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeAmountZatoshi, BigInt.from(499990000));
  });

  testWidgets('amount field switches to USD and proposes canonical ZEC', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        zecUsdUnitPrice: 70,
        spendableBalance: BigInt.from(1000000000),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.5');
    await tester.pumpAndSettle();

    expect(find.text(r'$ 105'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send_amount_currency_toggle')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'send_amount_field'), '105.00');
    await tester.enterText(_editableIn('send_amount_field'), '140');
    await tester.pumpAndSettle();

    expect(find.text('2 ZEC'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
    expect(rustApi.lastProposeAmountZatoshi, BigInt.from(200000000));
  });

  testWidgets('amount field shows USD skeleton while pricing entered ZEC', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        spendableBalance: BigInt.from(1000000000),
        zecUsdUnitPrice: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.5');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('send_amount_price_loading')),
      findsOneWidget,
    );
  });

  testWidgets('spendable help icon opens the balance explanation modal', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_sendHarness());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(
        find.byKey(const ValueKey('send_spendable_info_icon_target')),
      ),
      const Size.square(16),
    );
    final helpIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('send_spendable_info_icon_target')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.help,
        ),
      ),
    );
    expect(helpIcon.size, 16);
    expect(helpIcon.color, AppThemeData.light.colors.icon.muted);

    await tester.tap(find.bySemanticsLabel('Spendable balance info'));
    await tester.pumpAndSettle();

    expect(find.text('Spendable vs. Total Balances'), findsOneWidget);
    expect(find.text('Why they may differ'), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Spendable vs. Total Balances'))
          .style
          ?.color,
      AppThemeData.light.colors.text.accent,
    );
    expect(
      tester.widget<Text>(find.text('Why they may differ')).style?.color,
      AppThemeData.light.colors.text.secondary,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Your spendable balance may be lower than\n'
              'your total balance.',
            ),
          )
          .style
          ?.color,
      AppThemeData.light.colors.text.accent,
    );

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('Spendable vs. Total Balances'), findsNothing);
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

    await tester.tap(find.text('Review'));
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
    expect(find.text('Not enough ZEC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send_review_button')));
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
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
  double? zecUsdUnitPrice = 70,
  double? Function(Ref ref)? zecUsdUnitPriceBuilder,
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
      syncProvider.overrideWith(
        () => _FakeSyncNotifier(
          spendableBalance: spendableBalance ?? BigInt.from(500000000),
          transparentBalance: transparentBalance ?? BigInt.zero,
        ),
      ),
      if (addressBookRepository != null)
        addressBookRepositoryProvider.overrideWithValue(addressBookRepository),
      zecHomeUsdUnitPriceProvider.overrideWith(
        zecUsdUnitPriceBuilder ?? (_) => zecUsdUnitPrice,
      ),
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

final _testZecPriceProvider = NotifierProvider<_TestZecPriceNotifier, double?>(
  _TestZecPriceNotifier.new,
);

class _TestZecPriceNotifier extends Notifier<double?> {
  @override
  double? build() => 70;

  void set(double? value) {
    state = value;
  }
}

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
    if (address == _invalidAddress) {
      return const AddressValidationResult(isValid: false, addressType: '');
    }
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
const _invalidAddress = 'not-a-zcash-address';
