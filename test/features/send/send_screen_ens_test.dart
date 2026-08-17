import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/ens_resolver_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

// Resolved Zcash unified address the fake ENS resolver returns.
const _resolvedShielded =
    'u1resolvedzcashaddress0000000000000000000000000000000000000000000000000';
const _resolvedShielded2 =
    'u1resolvedzcashaddress2222222222222222222222222222222222222222222222222';
const _ensName = 'alice.eth';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RustApiFake rustApi;

  setUpAll(() {
    rustApi = _RustApiFake();
    RustLib.initMock(api: rustApi);
  });

  setUp(() => rustApi.reset());

  tearDownAll(RustLib.dispose);

  testWidgets('recipient hint advertises .eth names', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(resolver: _FakeEnsResolver()));
    await tester.pumpAndSettle();

    expect(find.text('Zcash address or .eth'), findsOneWidget);
    expect(find.text('Zcash address'), findsNothing);
  });

  testWidgets('a well-formed .eth name is not marked invalid', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(resolver: _FakeEnsResolver()));
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _ensName);
    await tester.pumpAndSettle();

    expect(find.text('Invalid address'), findsNothing);
  });

  testWidgets('Review pins the resolved Zcash address into the propose path', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final resolver = _FakeEnsResolver(result: _resolvedShielded);
    await tester.pumpWidget(_harness(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _ensName);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.25');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(resolver.calls, 1);
    expect(resolver.lastName, _ensName);
    expect(rustApi.proposeSendCalls, 1);
    // The RESOLVED Zcash address — never the .eth name — reaches propose.
    expect(rustApi.lastProposeToAddress, _resolvedShielded);
    expect(rustApi.lastProposeToAddress, isNot(_ensName));
  });

  testWidgets('resolve failure blocks review and shows the mapped message', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final resolver = _FakeEnsResolver(
      error: const EnsResolutionException(
        EnsResolutionFailure.noRecord,
        'Name has no usable Zcash address record',
      ),
    );
    await tester.pumpWidget(_harness(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _ensName);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.25');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rustApi.proposeSendCalls, 0);
    expect(
      find.text('Name has no usable Zcash address record'),
      findsOneWidget,
    );
  });

  testWidgets('editing the recipient after a resolve clears the pin', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final resolver = _FakeEnsResolver(result: _resolvedShielded);
    await tester.pumpWidget(_harness(resolver: resolver));
    await tester.pumpAndSettle();

    await tester.enterText(_editableIn('send_address_field'), _ensName);
    await tester.pumpAndSettle();
    await tester.enterText(_editableIn('send_amount_field'), '1.25');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(rustApi.lastProposeToAddress, _resolvedShielded);

    // Return to the compose screen to edit the recipient.
    _router!.pop();
    await tester.pumpAndSettle();

    // Edit to a different .eth name; the pin must clear so it re-resolves.
    resolver.result = _resolvedShielded2;
    await tester.enterText(_editableIn('send_address_field'), 'bob.eth');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(resolver.calls, 2);
    expect(resolver.lastName, 'bob.eth');
    expect(rustApi.lastProposeToAddress, _resolvedShielded2);
  });
}

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

GoRouter? _router;

Widget _harness({required EnsNameResolver resolver}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(path: '/send', builder: (_, _) => const SendScreen()),
      GoRoute(path: '/send/review', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  _router = router;

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      sendWalletDbPathProvider.overrideWithValue(() async => '/tmp/test.db'),
      ensResolverProvider.overrideWithValue(resolver),
      zecHomeUsdUnitPriceProvider.overrideWithValue(70),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
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
  int proposeSendCalls = 0;
  String? lastProposeToAddress;

  void reset() {
    proposeSendCalls = 0;
    lastProposeToAddress = null;
  }

  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
    // Any resolved Zcash string validates as a unified address here; a .eth
    // name should never reach this call.
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
    proposeSendCalls++;
    lastProposeToAddress = toAddress;
    return ProposalResult(
      proposalId: BigInt.one,
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
