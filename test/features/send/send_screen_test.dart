import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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

  testWidgets('prefills imported payment request into send compose', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _sendHarness(
        const SendPrefillArgs(
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
}

Widget _sendHarness(SendPrefillArgs prefill) {
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
      appBootstrapProvider.overrideWithValue(_bootstrap),
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

String _fieldText(WidgetTester tester, String keyValue) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(keyValue)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
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
