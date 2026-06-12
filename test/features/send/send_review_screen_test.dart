// path_provider / plugin platform fakes back the Keystone PCZT preparation
// flow (wallet DB path + Sapling params status).
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final rustApi = _RustApiFake();

  setUpAll(() {
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() async {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    // Real-IO fakes for the Keystone PCZT preparation flow. Created here
    // because file system futures cannot complete inside the FakeAsync test
    // body.
    final tempDir = await Directory.systemTemp.createTemp('send_review_test');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  testWidgets('renders the address-variant review layout', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'unified', memo: _longMemo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review send'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('15.12 ZEC'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text(truncatedAddress(_longAddress)), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_longMemo), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00012 ZEC'), findsOneWidget);
    expect(find.text('Confirm & send'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('renders the contact variant for an address-book match', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mike'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SendReviewContentView),
        matching: find.byType(AppProfilePicture),
      ),
      findsOneWidget,
    );
    expect(find.text(truncatedAddress(_longAddress)), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
    expect(find.text('Show full address'), findsOneWidget);
  });

  testWidgets('message expand toggles between truncated and full memo', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'sapling', memo: _veryLongMemo)),
    );
    await tester.pumpAndSettle();

    final collapsedMemo = tester.widget<Text>(find.text(_veryLongMemo));
    expect(collapsedMemo.maxLines, 1);
    expect(find.text('Collapse'), findsNothing);

    await tester.tap(find.text(_veryLongMemo));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsOneWidget);
    final expandedMemo = tester.widget<Text>(find.text(_veryLongMemo));
    expect(expandedMemo.maxLines, isNull);

    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsNothing);
    expect(tester.widget<Text>(find.text(_veryLongMemo)).maxLines, 1);
  });

  testWidgets('confirm pushes the status route without discarding', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'unified'), statusExtras: statusExtras),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm & send'));
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    expect(statusExtras.single, isA<SendReviewArgs>());
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('cancel discards the proposal and returns to send', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs(addressType: 'unified')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('send-route'), findsOneWidget);
    expect(rustApi.discardCalls, hasLength(1));
    expect(rustApi.discardCalls.single, (BigInt.one, 'test-send-flow'));
  });

  testWidgets('dispose discards an unconsumed proposal exactly once', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs(addressType: 'unified')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(rustApi.discardCalls, hasLength(1));
  });

  testWidgets('verify modal shows the full address grid for unknown address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsOneWidget);
    // The add-to-contacts flow is deferred; verification is display-only.
    expect(find.text('Add to contacts'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('verify_address_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyAddressModal), findsNothing);
  });

  testWidgets('verify modal marks an unknown transparent address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'transparent', address: _transparentAddress),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown transparent address'), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
  });

  testWidgets('verify modal shows the contact header for a saved address', (
    tester,
  ) async {
    rustApi.previousTransactionCount = 12;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
    // Contact name in the modal header AND on the review screen behind it.
    expect(find.text('Mike'), findsNWidgets(2));
    expect(find.text('12 previous transactions'), findsOneWidget);
  });

  testWidgets('verify modal hides a zero previous transaction count', (
    tester,
  ) async {
    rustApi.previousTransactionCount = 0;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Mike'), findsNWidgets(2));
    expect(find.textContaining('previous transaction'), findsNothing);
  });

  testWidgets('verify modal shows own-account header without tx count', (
    tester,
  ) async {
    rustApi
      ..unifiedAddress = _longAddress
      ..previousTransactionCount = 4;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(VerifyAddressModal),
        matching: find.text('Account 1'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('previous transaction'), findsNothing);
  });

  testWidgets(
    'transparent own-account address resolves to the account header',
    (tester) async {
      rustApi.transparentAddress = _transparentAddress;
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          _reviewArgs(addressType: 'transparent', address: _transparentAddress),
          addressBookRepository: _FakeAddressBookRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();
      await _flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(VerifyAddressModal),
          matching: find.text('Account 1'),
        ),
        findsOneWidget,
      );
      expect(find.text('Unknown transparent address'), findsNothing);
      expect(find.textContaining('previous transaction'), findsNothing);
    },
  );

  testWidgets('hardware confirm opens the Keystone signing modal', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Confirm & send'), findsNothing);

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);

    expect(find.byType(KeystoneSigningModal), findsOneWidget);
    // The review confirm button behind the scrim shares the same label, so
    // scope the title assertion to the modal.
    expect(
      find.descendant(
        of: find.byType(KeystoneSigningModal),
        matching: find.text('Confirm with Keystone'),
      ),
      findsOneWidget,
    );
    expect(find.text('Get signature'), findsOneWidget);
    expect(find.text('status-route'), findsNothing);
    expect(rustApi.createPcztCalls, 1);
  });

  testWidgets('Keystone handoff carries proofs and signatures to status', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();

    expect(find.text('keystone-scan-route'), findsOneWidget);
    await tester.tap(find.text('keystone-scan-route'));
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    final extra = statusExtras.single;
    expect(extra, isA<KeystoneBroadcastArgs>());
    final keystoneArgs = extra! as KeystoneBroadcastArgs;
    expect(keystoneArgs.pcztWithProofsBytes, _fakeProofsBytes);
    expect(keystoneArgs.pcztWithSignaturesBytes, _fakeSignatureBytes);
    expect(keystoneArgs.reviewArgs.proposalId, BigInt.one);

    // The proposal was consumed by createPcztFromProposal; the handoff must
    // not discard it.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('Keystone reject while preparing discards the proposal', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
      ),
    );
    await tester.pumpAndSettle();

    // Cancel before the PCZT preparation consumed the proposal (real-IO
    // futures are still pending at this point). The review screen behind the
    // scrim has its own Cancel, so scope the tap to the modal.
    await tester.tap(find.text('Confirm with Keystone'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(KeystoneSigningModal),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('send-route'), findsOneWidget);
    expect(rustApi.discardCalls, hasLength(1));
    expect(rustApi.createPcztCalls, 0);
  });

  testWidgets(
    'Keystone reject after PCZT creation does not discard the consumed '
    'proposal',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          _reviewArgs(addressType: 'unified'),
          bootstrap: _bootstrap(isHardware: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm with Keystone'));
      await _flushRealAsync(tester);
      expect(rustApi.createPcztCalls, 1);

      await tester.tap(
        find.descendant(
          of: find.byType(KeystoneSigningModal),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('send-route'), findsOneWidget);
      // createPcztFromProposal is consume-on-entry in Rust; a discard here
      // would be a replayable-ID regression.
      expect(rustApi.discardCalls, isEmpty);
    },
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

/// Lets real-IO futures (wallet DB path, Sapling params status) resolve —
/// they cannot complete inside the FakeAsync test zone on their own.
/// Several rounds because the chain interleaves real-IO awaits with
/// fake-zone microtasks that only run during pump; bounded pumps because
/// repeating loader animations would hang pumpAndSettle.
Future<void> _flushRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Widget _harness(
  SendReviewArgs args, {
  AppBootstrapState? bootstrap,
  AddressBookRepository? addressBookRepository,
  List<Object?>? statusExtras,
}) {
  final router = GoRouter(
    initialLocation: '/send/review',
    routes: [
      GoRoute(path: '/send', builder: (_, _) => const Text('send-route')),
      GoRoute(
        path: '/send/review',
        builder: (_, _) => SendReviewScreen(args: args),
      ),
      GoRoute(
        path: '/send/keystone/scan',
        builder: (context, _) => GestureDetector(
          onTap: () => context.pop(Uint8List.fromList(_fakeSignatureBytes)),
          child: const Text('keystone-scan-route'),
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          statusExtras?.add(state.extra);
          return const Text('status-route');
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap()),
      addressBookRepositoryProvider.overrideWithValue(
        addressBookRepository ?? _FakeAddressBookRepository(),
      ),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap({bool isHardware = false}) {
  return AppBootstrapState(
    initialLocation: '/send/review',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: 'test-account',
          name: 'Account 1',
          order: 0,
          isHardware: isHardware,
        ),
      ],
      activeAccountUuid: 'test-account',
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
}

AddressBookContact _contact({
  required String id,
  required String label,
  required String address,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: AddressBookNetwork.zcash,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
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

SendReviewArgs _reviewArgs({
  required String addressType,
  String? memo,
  String address = _longAddress,
  BigInt? amountZatoshi,
}) {
  return SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'test-send-flow',
    proposalAccountUuid: 'test-account',
    address: address,
    addressType: addressType,
    amountZatoshi: amountZatoshi ?? BigInt.from(1512000000),
    feeZatoshi: BigInt.from(12000),
    needsSaplingParams: false,
    memo: memo,
  );
}

const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs.';

const _longAddress =
    'u1tvg4akwn3gk64h6dfe0000000000000000005j3eds7qfhzek6scgcn8fh5';

const _transparentAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _veryLongMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin. This message should be visible after '
    'the preview expands.';

const _fakeProofsBytes = <int>[3, 3, 3];
const _fakeSignatureBytes = <int>[9, 9];

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'test-account',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
  );
}

class _RustApiFake implements RustLibApi {
  final discardCalls = <(BigInt, String)>[];
  int createPcztCalls = 0;
  int previousTransactionCount = 0;
  String unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
  String transparentAddress = 't1ownaccountaddressnotmatchingrecipient';

  void reset() {
    discardCalls.clear();
    createPcztCalls = 0;
    previousTransactionCount = 0;
    unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
    transparentAddress = 't1ownaccountaddressnotmatchingrecipient';
  }

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add((proposalId, sendFlowId));
  }

  @override
  Future<int> crateApiSyncGetPreviousTransactionCountForAddress({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String address,
  }) async {
    return previousTransactionCount;
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return unifiedAddress;
  }

  @override
  Future<String> crateApiWalletGetTransparentAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return transparentAddress;
  }

  @override
  Future<Uint8List> crateApiSyncCreatePcztFromProposal({
    required String dbPath,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    createPcztCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Uint8List> crateApiSyncRedactPcztForSigner({
    required List<int> pcztBytes,
  }) async {
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async {
    return const ['UR:ZCASH-PCZT/TESTPART'];
  }

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return Uint8List.fromList(_fakeProofsBytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
