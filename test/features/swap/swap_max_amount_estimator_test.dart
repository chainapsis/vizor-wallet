import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_max_amount_estimator.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' show SendMaxEstimateResult;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  final rustApi = _RecordingRustApi();

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    final supportDir = Directory.systemTemp.createTempSync(
      'vizor-swap-max-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDir.path;
          }
          return supportDir.path;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, null);
      supportDir.deleteSync(recursive: true);
    });
  });

  test(
    'RustSwapMaxAmountEstimator estimates hardware max with legacy PCZT',
    () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_hardwareBootstrap),
          syncProvider.overrideWith(
            () => _FakeSwapSyncNotifier(BigInt.from(100)),
          ),
          receiveAddressServiceProvider.overrideWith(
            _FakeReceiveAddressService.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);

      final max = await container
          .read(swapMaxAmountEstimatorProvider)
          .estimateMaxZecSellAmount(accountUuid: 'account-1');

      expect(max, BigInt.from(93));
      expect(rustApi.legacyV5PcztValues, isNotEmpty);
      expect(rustApi.legacyV5PcztValues.toSet(), {true});
    },
  );
}

class _FakeSwapSyncNotifier extends SyncNotifier {
  _FakeSwapSyncNotifier(this.spendableBalance);

  final BigInt spendableBalance;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: spendableBalance,
    totalBalance: spendableBalance,
  );
}

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(super.ref);

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    return 't1testtransparentaddress';
  }
}

class _RecordingRustApi implements RustLibApi {
  final legacyV5PcztValues = <bool>[];

  void reset() {
    legacyV5PcztValues.clear();
  }

  @override
  Future<SendMaxEstimateResult> crateApiSyncEstimateSendMax({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    String? memo,
    required bool legacyV5Pczt,
  }) async {
    legacyV5PcztValues.add(legacyV5Pczt);
    return SendMaxEstimateResult(
      amountZatoshi: BigInt.from(93),
      feeZatoshi: BigInt.from(7),
      needsSaplingParams: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/swap',
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
    activeAddress: 'u1swapaddress',
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
