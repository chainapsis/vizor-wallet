import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _accountUuid = '550e8400-e29b-41d4-a716-446655440000';
const _address =
    'ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez';
const _prefill = SendPrefillArgs(
  id: 'payment-uri-e2e',
  source: 'zcash-uri',
  address: _address,
  amountText: '0.12345678',
  memoText: 'CP-C6CDB775',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('payment URI prefill survives send route refresh', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final router = GoRouter(
      initialLocation: '/send',
      initialExtra: _prefill,
      routes: [
        GoRoute(
          path: '/send',
          builder: (_, state) {
            final extra = state.extra;
            return SendScreen(prefill: extra is SendPrefillArgs ? extra : null);
          },
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      ],
    );

    await tester.pumpWidget(_harness(router));

    await _waitForFieldText(
      tester,
      const ValueKey('send_address_field'),
      _address,
      description: 'payment URI address prefill',
    );
    expect(
      _fieldText(tester, const ValueKey('send_amount_field')),
      '0.12345678',
    );
    expect(
      _fieldText(tester, const ValueKey('send_memo_field')),
      'CP-C6CDB775',
    );

    router.go('/send');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(_fieldText(tester, const ValueKey('send_address_field')), _address);
    expect(
      _fieldText(tester, const ValueKey('send_amount_field')),
      '0.12345678',
    );
    expect(
      _fieldText(tester, const ValueKey('send_memo_field')),
      'CP-C6CDB775',
    );
  });
}

Widget _harness(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncState)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Future<void> _waitForFieldText(
  WidgetTester tester,
  Key key,
  String expected, {
  required String description,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (tester.any(find.byKey(key)) && _fieldText(tester, key) == expected) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description.');
}

String _fieldText(WidgetTester tester, Key key) {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editable).controller.text;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
    activeAddress: 'u1paymenturiprefillwalletaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _syncState = SyncState(
  accountUuid: _accountUuid,
  hasAccountScopedData: true,
  scannedHeight: 1,
  chainTipHeight: 1,
  spendableBalance: BigInt.zero,
  totalBalance: BigInt.zero,
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
