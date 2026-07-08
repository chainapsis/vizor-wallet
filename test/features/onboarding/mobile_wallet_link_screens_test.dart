@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/providers/mobile_wallet_link_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

class _WalletLinkController extends MobileWalletLinkController {
  _WalletLinkController(this.initialState);

  final MobileWalletLinkState initialState;

  @override
  MobileWalletLinkState build() => initialState;
}

Widget _app(Widget child, {required MobileWalletLinkState state}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      mobileWalletLinkControllerProvider.overrideWith(
        () => _WalletLinkController(state),
      ),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: child,
    ),
  );
}

Widget _routerApp(
  Widget child, {
  required MobileWalletLinkState state,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      mobileWalletLinkControllerProvider.overrideWith(
        () => _WalletLinkController(state),
      ),
      ...overrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

MobileWalletLinkState _state({
  required bool submitting,
  bool contacts = false,
}) {
  const account = WalletLinkTransferAccount(
    uuid: 'software-account',
    name: 'Desktop account',
    order: 0,
    isHardware: false,
    isSeedAnchor: true,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 120000,
    zip32AccountIndex: 0,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: 'abandon ability able about above absent absorb abstract',
  );
  const contact = AddressBookContact(
    id: 'contact-1',
    label: 'Desktop contact',
    network: AddressBookNetwork.zcash,
    address: 'u1desktopcontactaddress',
    profilePictureId: 'profile_1',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
  final payload = WalletLinkTransferPayload(
    version: 1,
    exportedAt: DateTime.utc(2026, 7, 8),
    network: 'main',
    activeAccountUuid: account.uuid,
    accounts: const [account],
    contacts: contacts ? const [contact] : const [],
  );
  return MobileWalletLinkState(
    payload: payload,
    packageId: '550e8400-e29b-41d4-a716-446655440000',
    completionToken: 'completion-token',
    keyBytes: List<int>.filled(32, 1),
    selectedAccountUuids: const {'software-account'},
    selectedContactIds: contacts ? const {'contact-1'} : const {},
    submitting: submitting,
  );
}

MobileWalletLinkState _contactsOnlyState() {
  const contact = AddressBookContact(
    id: 'contact-1',
    label: 'Desktop contact',
    network: AddressBookNetwork.zcash,
    address: 'u1desktopcontactaddress',
    profilePictureId: 'profile_1',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
  final payload = WalletLinkTransferPayload(
    version: 1,
    exportedAt: DateTime.utc(2026, 7, 8),
    network: 'test',
    activeAccountUuid: null,
    accounts: const [],
    contacts: const [contact],
  );
  return MobileWalletLinkState(
    payload: payload,
    packageId: '550e8400-e29b-41d4-a716-446655440000',
    completionToken: 'completion-token',
    keyBytes: List<int>.filled(32, 1),
    selectedContactIds: const {'contact-1'},
  );
}

MobileWalletLinkState _alreadyImportedState() {
  const importedAccount = WalletLinkTransferAccount(
    uuid: 'imported-account',
    name: 'Imported account',
    order: 0,
    isHardware: false,
    isSeedAnchor: true,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 120000,
    zip32AccountIndex: 0,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: 'abandon ability able about above absent absorb abstract',
  );
  const freshAccount = WalletLinkTransferAccount(
    uuid: 'fresh-account',
    name: 'Fresh account',
    order: 1,
    isHardware: false,
    isSeedAnchor: false,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 120000,
    zip32AccountIndex: 1,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: 'abandon ability able about above absent absorb abstract',
  );
  const importedContact = AddressBookContact(
    id: 'imported-contact',
    label: 'Imported contact',
    network: AddressBookNetwork.zcash,
    address: 'u1importedcontactaddress',
    profilePictureId: 'profile_1',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
  const freshContact = AddressBookContact(
    id: 'fresh-contact',
    label: 'Fresh contact',
    network: AddressBookNetwork.zcash,
    address: 'u1freshcontactaddress',
    profilePictureId: 'profile_2',
    createdAtMs: 2,
    updatedAtMs: 2,
  );
  final payload = WalletLinkTransferPayload(
    version: 1,
    exportedAt: DateTime.utc(2026, 7, 8),
    network: 'main',
    activeAccountUuid: importedAccount.uuid,
    accounts: const [importedAccount, freshAccount],
    contacts: const [importedContact, freshContact],
  );
  return MobileWalletLinkState(
    payload: payload,
    packageId: '550e8400-e29b-41d4-a716-446655440000',
    completionToken: 'completion-token',
    keyBytes: List<int>.filled(32, 1),
    selectedAccountUuids: const {'fresh-account'},
    selectedContactIds: const {'fresh-contact'},
    alreadyImportedAccountUuids: const {'imported-account'},
    alreadyImportedContactIds: const {'imported-contact'},
  );
}

bool _hasIcon(WidgetTester tester, String name) {
  return tester
      .widgetList<AppIcon>(find.byType(AppIcon))
      .any((icon) => icon.name == name);
}

bool _canPop(WidgetTester tester) {
  return tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('account selection shows importing progress while submitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectAccountsScreen(),
        state: _state(submitting: true),
      ),
    );
    await tester.pump();

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('Link 1 account'), findsNothing);
    expect(_hasIcon(tester, AppIcons.loader), isTrue);
    expect(_hasIcon(tester, AppIcons.chevronBackward), isFalse);
    expect(_canPop(tester), isFalse);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();

    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('contact selection shows importing progress while submitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectContactsScreen(),
        state: _state(submitting: true, contacts: true),
      ),
    );
    await tester.pump();

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('Import 1 contact'), findsNothing);
    expect(_hasIcon(tester, AppIcons.loader), isTrue);
    expect(_hasIcon(tester, AppIcons.chevronBackward), isFalse);
    expect(_canPop(tester), isFalse);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();

    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('already imported accounts are disabled and sorted last', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectAccountsScreen(),
        state: _alreadyImportedState(),
      ),
    );
    await tester.pump();

    expect(find.text('1 account found'), findsOneWidget);
    expect(find.text('1 already imported'), findsOneWidget);
    expect(find.text('Account already imported'), findsNothing);
    expect(find.text('Link 1 account'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Fresh account')).dy,
      lessThan(tester.getTopLeft(find.text('Imported account')).dy),
    );

    await tester.tap(find.text('Imported account'));
    await tester.pump();

    expect(find.text('Link 1 account'), findsOneWidget);
  });

  testWidgets('already imported contacts are disabled and sorted last', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectContactsScreen(),
        state: _alreadyImportedState(),
      ),
    );
    await tester.pump();

    expect(find.text('1 contact found'), findsOneWidget);
    expect(find.text('1 already imported'), findsOneWidget);
    expect(find.text('Contact already imported'), findsNothing);
    expect(find.text('Import 1 contact'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Fresh contact')).dy,
      lessThan(tester.getTopLeft(find.text('Imported contact')).dy),
    );

    await tester.tap(find.text('Imported contact'));
    await tester.pump();

    expect(find.text('Import 1 contact'), findsOneWidget);
  });

  testWidgets('contacts-only import validates the wallet link network', (
    tester,
  ) async {
    final accountNotifier = _ValidatingAccountNotifier(
      validationError: StateError(
        'Linked wallet network does not match the current wallet.',
      ),
    );
    final addressBookNotifier = _RecordingAddressBookNotifier();

    await tester.pumpWidget(
      _routerApp(
        const MobileWalletLinkSelectContactsScreen(),
        state: _contactsOnlyState(),
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          addressBookProvider.overrideWith(() => addressBookNotifier),
          appSecurityProvider.overrideWith(_ConfiguredSecurityNotifier.new),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Import 1 contact'));
    await tester.pumpAndSettle();

    expect(accountNotifier.validatedNetworks, ['test']);
    expect(addressBookNotifier.importCalls, 0);
    expect(
      find.textContaining('Linked wallet network does not match'),
      findsOneWidget,
    );
    expect(find.text('home route'), findsNothing);
  });
}

class _ValidatingAccountNotifier extends AccountNotifier {
  _ValidatingAccountNotifier({this.validationError});

  final Object? validationError;
  final validatedNetworks = <String>[];

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> validateLinkedWalletNetwork(String network) async {
    validatedNetworks.add(network);
    final error = validationError;
    if (error != null) throw error;
  }

  @override
  Future<LinkedWalletAccountsImportResult> importLinkedWalletAccounts({
    required String network,
    required List<LinkedWalletAccountImport> accountsToImport,
  }) async {
    throw StateError('Account import should not run for contacts-only import.');
  }
}

class _RecordingAddressBookNotifier extends AddressBookNotifier {
  int importCalls = 0;

  @override
  FutureOr<AddressBookState> build() => const AddressBookState();

  @override
  Future<int> importContacts(Iterable<AddressBookContact> imported) async {
    importCalls += 1;
    return imported.length;
  }
}

class _ConfiguredSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }
}
