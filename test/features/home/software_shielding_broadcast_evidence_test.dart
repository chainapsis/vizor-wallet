// path_provider supplies an isolated wallet path for the mocked Rust call.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  final api = _ShieldApi();
  late Directory support;
  late PathProviderPlatform originalPaths;
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp(
      'software-shield-evidence-',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    await support.delete(recursive: true);
  });

  for (final status in [
    'broadcasted',
    'partial_broadcast',
    'pending_broadcast',
  ]) {
    testWidgets(
      'software shielding records only successful broadcasts: $status',
      (tester) async {
        api.status = status;
        final sync = FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            canShieldTransparentBalance: true,
          ),
        );
        late WidgetRef widgetRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(_bootstrap()),
              accountProvider.overrideWith(_Accounts.new),
              appSecurityProvider.overrideWith(_Security.new),
              syncProvider.overrideWith(() => sync),
            ],
            child: Consumer(
              builder: (_, ref, _) {
                widgetRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final container = ProviderScope.containerOf(widgetRef.context);
        await container.read(accountProvider.future);
        await container.read(syncProvider.future);
        final result = await tester.runAsync(
          () => shieldTransparentSoftwareBalance(
            ref: widgetRef,
            accountUuid: 'account-1',
          ),
        );
        expect(result?.status, status);
        expect(sync.balanceRefreshes, 1);
        expect(
          container.read(pendingActivityEvidenceProvider).observedAt.keys,
          status == 'broadcasted'
              ? unorderedEquals([
                  ('account-1', 'first-txid'),
                  ('account-1', 'second-txid'),
                ])
              : isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _Accounts extends AccountNotifier {
  @override
  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) async =>
      Uint8List.fromList([1, 2, 3]);
}

class _Security extends AppSecurityNotifier {
  @override
  String requireSessionPasswordForNativeSecretUse() => 'test-password';
}

class _ShieldApi extends RustLibApi {
  String status = 'broadcasted';
  ShieldTransparentResult get result => ShieldTransparentResult(
    txids: 'first-txid,second-txid',
    status: status,
    broadcastedCount: status == 'broadcasted'
        ? 2
        : status == 'partial_broadcast'
        ? 1
        : 0,
    totalCount: 2,
    feeZatoshi: BigInt.from(10000),
    shieldedZatoshi: BigInt.from(90000),
  );

  @override
  Future<ShieldTransparentResult>
  crateApiSyncShieldTransparentBalanceWithMacosStoredMnemonic({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String password,
  }) async => result;

  @override
  Future<ShieldTransparentResult> crateApiSyncShieldTransparentBalance({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required List<int> mnemonicBytes,
  }) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Software', order: 0)],
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
