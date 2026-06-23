import 'dart:async';

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
    expect(find.text('Alice'), findsNothing);
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
    expect(find.text('Alice'), findsNothing);
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

    await tester.tap(find.textContaining('Max:'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(rustApi.lastEstimateSendMaxToAddress, _transparentAddress);
    expect(rustApi.lastEstimateSendMaxMemo, isNull);
    expect(_fieldText(tester, 'send_amount_field'), isNotEmpty);
    expect(find.text('Max amount unavailable'), findsNothing);
  });

  testWidgets('Max syncing failure asks the user to wait', (tester) async {
    await _setDesktopViewport(tester);
    rustApi.estimateSendMaxError = StateError(
      'sync_in_progress|wallet is still scanning',
    );

    await tester.pumpWidget(
      _sendHarness(spendableBalance: BigInt.from(500000000)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      _editableIn('send_address_field'),
      _transparentAddress,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Max:'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rustApi.estimateSendMaxCalls, 1);
    expect(
      find.text('Still syncing. Try again once sync finishes.'),
      findsOneWidget,
    );
    expect(find.text('Max amount unavailable'), findsNothing);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

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

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(rustApi.proposeSendCalls, 0);
  });

  testWidgets('mid-sync spendable shortfall still reaches proposal', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        syncedToTip: false,
        spendableBalance: BigInt.from(50000000),
        prefill: const SendPrefillArgs(
          id: 'mid-sync-shortfall',
          source: 'ZIP-321',
          address: _shieldedAddress,
          amountText: '1.0',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Insufficient balance'), findsNothing);

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 1);
  });

  testWidgets('fee estimate uses latest spendable balance after sync update', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    rustApi.estimateFeeCompleter = Completer<BigInt>();

    await tester.pumpWidget(
      _sendHarness(syncedToTip: false, spendableBalance: BigInt.from(50000000)),
    );
    await tester.pump();

    await tester.enterText(_editableIn('send_address_field'), _shieldedAddress);
    await tester.pump();
    await tester.enterText(_editableIn('send_amount_field'), '1.0');
    await tester.pump();

    final notifier =
        ProviderScope.containerOf(
              tester.element(find.byType(SendScreen)),
            ).read(syncProvider.notifier)
            as _FakeSyncNotifier;
    notifier.updateSyncState(
      syncedToTip: true,
      spendableBalance: BigInt.from(200000000),
    );
    await tester.pump();

    rustApi.estimateFeeCompleter!.complete(BigInt.from(10000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Insufficient'), findsNothing);
    expect(find.byKey(const ValueKey('send_review_button')), findsOneWidget);
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
  bool syncedToTip = true,
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
          syncedToTip: syncedToTip,
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
    required this.syncedToTip,
  });

  BigInt spendableBalance;
  BigInt transparentBalance;
  bool syncedToTip;

  void updateSyncState({BigInt? spendableBalance, bool? syncedToTip}) {
    this.spendableBalance = spendableBalance ?? this.spendableBalance;
    this.syncedToTip = syncedToTip ?? this.syncedToTip;
    state = AsyncData(_syncState());
  }

  @override
  Future<SyncState> build() async => _syncState();

  SyncState _syncState() => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    isSyncing: !syncedToTip,
    scannedHeight: syncedToTip ? 100 : 80,
    chainTipHeight: 100,
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
  String? lastEstimateSendMaxToAddress;
  String? lastEstimateSendMaxMemo;
  Completer<BigInt>? estimateFeeCompleter;
  Object? estimateSendMaxError;

  void reset() {
    proposeSendCalls = 0;
    estimateSendMaxCalls = 0;
    lastProposeToAddress = null;
    lastProposeMemo = null;
    lastEstimateSendMaxToAddress = null;
    lastEstimateSendMaxMemo = null;
    estimateFeeCompleter = null;
    estimateSendMaxError = null;
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
    final completer = estimateFeeCompleter;
    if (completer != null) return completer.future;
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
    final error = estimateSendMaxError;
    if (error != null) throw error;
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
