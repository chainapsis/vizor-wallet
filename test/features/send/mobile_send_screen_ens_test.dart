@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/ens_resolver_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _resolvedShielded =
    'u1resolvedzcashaddress0000000000000000000000000000000000000000000000000';
const _ensName = 'alice.eth';

int _proposeSendCalls = 0;
String? _lastProposeToAddress;

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    _proposeSendCalls = 0;
    _lastProposeToAddress = null;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('recipient hint advertises .eth names', (tester) async {
    await tester.pumpWidget(_app(resolver: _FakeEnsResolver()));
    await tester.pumpAndSettle();

    expect(find.text('Zcash address or .eth'), findsOneWidget);
    expect(find.text('Zcash Address'), findsNothing);
  });

  testWidgets('resolves a .eth recipient and pins the resolved address', (
    tester,
  ) async {
    final resolver = _FakeEnsResolver(result: _resolvedShielded);
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await _enterAddress(tester, _ensName);
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(resolver.calls, 1);
    expect(resolver.lastName, _ensName);

    // We are on the amount step now; drive to review and confirm.
    await _enterAmount(tester, '1.5');
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    // The review pins the ENS name headline over the resolved Zcash address.
    expect(find.text(_ensName), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(_proposeSendCalls, 1);
    // The RESOLVED Zcash address — never the name — reaches propose.
    expect(_lastProposeToAddress, _resolvedShielded);
    expect(_lastProposeToAddress, isNot(_ensName));
  });

  testWidgets('resolve failure keeps the recipient step and shows a message', (
    tester,
  ) async {
    final resolver = _FakeEnsResolver(
      error: const EnsResolutionException(
        EnsResolutionFailure.noRecord,
        'Name has no usable Zcash address record',
      ),
    );
    await tester.pumpWidget(_app(resolver: resolver));
    await tester.pumpAndSettle();

    await _enterAddress(tester, _ensName);
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(_proposeSendCalls, 0);
    // Still on the recipient step (amount step not shown yet).
    expect(find.byKey(const ValueKey('mobile_send_review_button')), findsNothing);
    expect(
      find.text('Name has no usable Zcash address record'),
      findsOneWidget,
    );
  });
}

Future<void> _enterAddress(WidgetTester tester, String address) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('mobile_send_address_field')),
      matching: find.byType(EditableText),
    ),
    address,
  );
  await tester.pumpAndSettle();
}

Future<void> _enterAmount(WidgetTester tester, String amount) async {
  await tester.enterText(
    find.byKey(const ValueKey('mobile_send_amount_input')),
    amount,
  );
  await tester.pumpAndSettle();
}

Widget _app({required EnsNameResolver resolver}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => MobileSendScreen(
          loadWalletDbPath: () async => '/tmp/zcash-test',
          openScanner: (_) async => null,
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(
        path: '/send/status',
        builder: (_, _) => const Text('send status'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      ensResolverProvider.overrideWithValue(resolver),
      zecHomeUsdUnitPriceProvider.overrideWithValue(70),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(const []),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => const {}),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _DummyTransport implements EnsRpcTransport {
  @override
  Future<String> ethCall({required String to, required String data}) async =>
      throw UnimplementedError();

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) async => throw UnimplementedError();
}

class _FakeEnsResolver extends EnsNameResolver {
  _FakeEnsResolver({this.result, this.error}) : super(_DummyTransport());

  String? result;
  Object? error;
  int calls = 0;
  String? lastName;

  @override
  Future<String> resolveZcashAddress(String name) async {
    calls++;
    lastName = name;
    final err = error;
    if (err != null) throw err;
    return result!;
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _RustApiFake implements RustLibApi {
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}

  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
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
  Future<ProposalResult> crateApiSyncProposeSend({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String sendFlowId,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    _proposeSendCalls++;
    _lastProposeToAddress = toAddress;
    return ProposalResult(
      proposalId: BigInt.one,
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
