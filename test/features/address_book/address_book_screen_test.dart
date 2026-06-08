import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/screens/address_book_screen.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('does not show a loading spinner while contacts load', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _DelayedAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts yet'), findsOneWidget);

    repo.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts yet'), findsOneWidget);
  });

  testWidgets('renders empty state and creates a contact from the form', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    expect(find.text('No contacts yet'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      'u1alice',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('u1alice'), findsOneWidget);
    expect(find.text('No contacts yet'), findsNothing);
  });

  testWidgets('creates a Zcash contact for a TEX address without warning', (
    tester,
  ) async {
    const texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Exchange',
    );
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      texAddress,
    );
    await tester.pump();

    expect(find.text('Invalid Zcash address'), findsNothing);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('address_book_contact_submit_button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(repo.contacts.single.network, AddressBookNetwork.zcash);
    expect(repo.contacts.single.address, texAddress);
  });

  testWidgets('warns about a malformed address but still allows saving', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Eve',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'ethereu',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      '0xnope',
    );
    await tester.pump();

    expect(find.text("Invalid EVM address"), findsOneWidget);
    // Soft warning: the save button stays enabled.
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('address_book_contact_submit_button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(repo.contacts.single.address, '0xnope');
  });

  testWidgets('edit contact label x clears the draft label', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit contact'));
    await tester.pumpAndSettle();

    final labelFieldFinder = find.descendant(
      of: find.byKey(const ValueKey('address_book_contact_label_field')),
      matching: find.byType(TextField),
    );
    TextField labelField() => tester.widget<TextField>(labelFieldFinder);

    expect(labelField().controller?.text, 'Mike');

    await tester.tap(find.bySemanticsLabel('Clear contact label'));
    await tester.pumpAndSettle();

    expect(labelField().controller?.text, isEmpty);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Save changes'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('filters contacts into the empty search state', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_search_field')),
      'nothing',
    );
    await tester.pumpAndSettle();

    expect(find.text('No contacts found'), findsOneWidget);
    expect(find.text('Mike'), findsNothing);
  });

  testWidgets('avatar picker requires a changed selection before update', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Change contact picture'));
    await tester.pumpAndSettle();

    AppButton updateButton() {
      return tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Use this picture'),
      );
    }

    expect(updateButton().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('address_book_avatar_samurai')));
    await tester.pumpAndSettle();

    expect(updateButton().onPressed, isNotNull);
  });

  testWidgets('network selector shows empty state when search has no matches', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'Value',
    );
    await tester.pumpAndSettle();

    expect(find.text('No networks found'), findsOneWidget);
    expect(find.text('Zcash'), findsNothing);
  });

  testWidgets('opens address scanner as an in-pane modal', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Alice',
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Scan address QR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('address_scan_modal')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      findsNothing,
    );
    expect(find.text('scan route'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('address_scan_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('address_scan_modal')), findsNothing);
    expect(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('sends Zcash contacts with a send prefill', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);
    SendPrefillArgs? sentPrefill;

    await tester.pumpWidget(
      _addressBookHarness(
        repo,
        onSendRoute: (prefill) => sentPrefill = prefill,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send ZEC'));
    await tester.pumpAndSettle();

    expect(sentPrefill?.source, 'address-book');
    expect(sentPrefill?.address, 'u1mike');
    expect(sentPrefill?.label, 'Mike');
    expect(find.text('send route'), findsOneWidget);
  });

  testWidgets('omits send action for non-Zcash contacts', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(
        id: 'solana',
        label: 'Solana Contact',
        address: '43123',
        network: AddressBookNetwork.solana,
      ),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_solana')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit contact'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsNothing);
  });

  testWidgets('dismisses contact menu from outside the address list', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit contact'), findsOneWidget);

    await tester.tapAt(const Offset(80, 120));
    await tester.pumpAndSettle();

    expect(find.text('Edit contact'), findsNothing);
    expect(find.text('Copy address'), findsNothing);
  });
}

Widget _addressBookHarness(
  AddressBookRepository repo, {
  ValueChanged<SendPrefillArgs?>? onSendRoute,
}) {
  final router = GoRouter(
    initialLocation: '/address-book',
    routes: [
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const AddressBookScreen(),
      ),
      GoRoute(
        path: '/send',
        builder: (_, state) {
          final prefill = state.extra is SendPrefillArgs
              ? state.extra as SendPrefillArgs
              : null;
          onSendRoute?.call(prefill);
          return const Text('send route');
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive')),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/about', builder: (_, _) => const Text('about')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      accountProvider.overrideWith(() => _FakeAccountNotifier(_accountState)),
      addressBookRepositoryProvider.overrideWithValue(repo),
      syncProvider.overrideWith(() => _FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

AddressBookContact _contact({
  required String id,
  required String label,
  String address = 'u1address',
  AddressBookNetwork network = AddressBookNetwork.zcash,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: network,
    address: address,
    profilePictureId: kDefaultProfilePictureId,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

final _accountState = const AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1activeaddress',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/address-book',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
  }
}

class _DelayedAddressBookRepository implements AddressBookRepository {
  final _loadCompleter = Completer<List<AddressBookContact>>();
  var contacts = <AddressBookContact>[];

  void complete(List<AddressBookContact> contacts) {
    this.contacts = [...contacts];
    _loadCompleter.complete(this.contacts);
  }

  @override
  Future<List<AddressBookContact>> loadContacts() => _loadCompleter.future;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
