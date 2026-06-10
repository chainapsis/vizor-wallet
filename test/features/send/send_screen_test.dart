import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
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

    expect(find.byKey(const ValueKey('send_prefill_notice')), findsOneWidget);
    expect(find.text('Imported request'), findsOneWidget);
    expect(find.text('ZIP-321 / Invoice #42 / Thank you'), findsOneWidget);
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
    expect(find.text('Alice'), findsOneWidget);
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

    expect(find.text('Shielded → Shielded'), findsOneWidget);
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

    expect(find.text('Shielded → Transparent'), findsOneWidget);
    expect(find.text('Transparent memo'), findsNothing);
    expect(find.text('Add a memo'), findsNothing);
    expect(find.text('Encrypted, for shielded addresses only.'), findsNothing);
    expect(find.byKey(const ValueKey('send_add_memo_card')), findsNothing);
    expect(find.byKey(const ValueKey('send_memo_field')), findsNothing);
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
}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(path: '/send', builder: (_, _) => SendScreen(prefill: prefill)),
      GoRoute(path: '/send/review', builder: (_, _) => const SizedBox.shrink()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
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
    profilePictureId: 'knight',
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

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
  );
}

class _RustApiFake implements RustLibApi {
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _shieldedAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000000';
const _transparentAddress = 't1transparentdestination0000000000000000000';
