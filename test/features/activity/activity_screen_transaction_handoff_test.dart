// The platform-interface fakes stub path_provider / flutter_secure_storage
// so the tap-through can resolve the wallet DB path under test. These are
// transitive deps, hence the ignore.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

void main() {
  setUp(() {
    // The handoff resolves the wallet DB path before it pushes; stub both
    // platform interfaces so that await completes and the FFI detail lookup
    // then fails fast, which is what a real tap on a cold cache also does.
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    addTearDown(() => PathProviderPlatform.instance = previousPathProvider);
    final previousSecureStorage = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(const {
      'zcash_wallet_db_name': 'zcash_wallet_test.db',
    });
    addTearDown(
      () => FlutterSecureStoragePlatform.instance = previousSecureStorage,
    );
  });

  testWidgets('an account switch during the detail load cancels the handoff', (
    tester,
  ) async {
    final accountNotifier = await _pumpActivityScreen(tester);

    // The detail load suspends on its first await; switching now lands before
    // it resumes, which is the race the receipt cannot see from its own side.
    await tester.tap(find.text('Received'));
    accountNotifier.setActiveAccount('account-2');
    await _settleRealAsync(tester);

    expect(find.text('transaction status route'), findsNothing);
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('the handoff still happens while the account holds', (
    tester,
  ) async {
    await _pumpActivityScreen(tester);

    await tester.tap(find.text('Received'));
    await _settleRealAsync(tester);

    expect(find.text('transaction status route'), findsOneWidget);
  });
}

/// The handoff awaits real file-system work for the wallet DB path, which the
/// fake-async test clock never delivers on its own.
Future<void> _settleRealAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<_SwitchableAccountNotifier> _pumpActivityScreen(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final accountNotifier = _SwitchableAccountNotifier();
  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(
        path: '/activity',
        builder: (_, _) =>
            ActivityScreen(historyLoader: (_) async => [_transaction]),
      ),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => const Text('transaction status route'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(() => accountNotifier),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Received'), findsOneWidget);
  return accountNotifier;
}

class _SwitchableAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
      AccountInfo(
        uuid: 'account-2',
        name: 'Account 2',
        order: 1,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activityaddress',
  );

  void setActiveAccount(String uuid) {
    state = AsyncData(
      state.requireValue.copyWith(activeAccountUuid: uuid, activeAddress: null),
    );
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.path;

  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _FakeSecureStoragePlatform(Map<String, String> seed)
    : _store = Map<String, String>.of(seed);

  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _store[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map<String, String>.of(_store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }
}

final _transaction = rust_sync.TransactionInfo(
  txidHex: 'a' * 64,
  minedHeight: BigInt.from(3000000),
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  blockTime: BigInt.from(1764150000),
  isTransparent: false,
  txKind: 'received',
  displayAmount: BigInt.from(100000000),
  displayPool: 'shielded',
  createdTime: BigInt.from(1764150000),
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
