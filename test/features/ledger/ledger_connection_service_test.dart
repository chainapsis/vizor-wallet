import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  test(
    'Automatic falls back from unavailable USB to verified Bluetooth',
    () async {
      final notifier = _FakeAccountNotifier(
        _ledgerAccount(
          preference: LedgerConnectionPreference.automatic,
          deviceModel: 'Nano X',
        ),
      );
      final ble = _FakeBleService();
      final container = _container(notifier: notifier, ble: ble);
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      final result = await container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () => throw StateError('No Ledger HID device'),
            bluetooth: (_) async => 'signed-over-ble',
          );

      expect(result, 'signed-over-ble');
      expect(ble.connectCalls, 1);
      expect(notifier.recordedTransports, [
        LedgerConnectionTransport.bluetooth,
      ]);
    },
  );

  test('explicit USB never probes Bluetooth', () async {
    final notifier = _FakeAccountNotifier(
      _ledgerAccount(
        preference: LedgerConnectionPreference.usb,
        deviceModel: 'Nano X',
      ),
    );
    final ble = _FakeBleService();
    final container = _container(notifier: notifier, ble: ble);
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    final result = await container
        .read(ledgerConnectionServiceProvider)
        .run(
          accountUuid: 'ledger-1',
          usb: () async => 'signed-over-usb',
          bluetooth: (_) async => 'unexpected',
        );

    expect(result, 'signed-over-usb');
    expect(ble.connectCalls, 0);
    expect(notifier.recordedTransports, [LedgerConnectionTransport.usb]);
  });

  test('known USB-only Ledger model cannot use Bluetooth', () async {
    final notifier = _FakeAccountNotifier(
      _ledgerAccount(
        preference: LedgerConnectionPreference.bluetooth,
        deviceModel: 'Nano S Plus',
      ),
    );
    final ble = _FakeBleService();
    final container = _container(notifier: notifier, ble: ble);
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await expectLater(
      container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'unexpected',
            bluetooth: (_) async => 'unexpected',
          ),
      throwsA(
        isA<LedgerConnectionRequiredException>().having(
          (error) => error.message,
          'message',
          contains('does not support Bluetooth'),
        ),
      ),
    );
    expect(ble.connectCalls, 0);
    expect(notifier.recordedTransports, isEmpty);
  });
}

ProviderContainer _container({
  required _FakeAccountNotifier notifier,
  required _FakeBleService ble,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(notifier.initial)),
      accountProvider.overrideWith(() => notifier),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerAppReadinessDeviceForTransportProvider(
        LedgerConnectionTransport.usb,
      ).overrideWithValue(const _ReadyDevice()),
      ledgerAppReadinessDeviceForTransportProvider(
        LedgerConnectionTransport.bluetooth,
      ).overrideWithValue(const _ReadyDevice()),
    ],
  );
}

AccountInfo _ledgerAccount({
  required LedgerConnectionPreference preference,
  required String deviceModel,
}) {
  return AccountInfo(
    uuid: 'ledger-1',
    name: 'Ledger',
    order: 0,
    isHardware: true,
    hardwareSignerKind: HardwareSignerKind.ledger,
    ledgerConnectionPreference: preference,
    ledgerDeviceId: 'device-1',
    ledgerDeviceName: 'Rowan Ledger',
    ledgerDeviceModel: deviceModel,
  );
}

AppBootstrapState _bootstrap(AccountInfo account) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: AccountState(
    accounts: [account],
    activeAccountUuid: account.uuid,
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

class _ReadyDevice implements LedgerAppReadinessDevice {
  const _ReadyDevice();

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async =>
      const LedgerDeviceAppSnapshot(
        status: LedgerDeviceAppStatus.open,
        version: '3.9.2',
      );

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => queryZcashApp();
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initial);

  final AccountInfo initial;
  final recordedTransports = <LedgerConnectionTransport>[];

  @override
  FutureOr<AccountState> build() =>
      AccountState(accounts: [initial], activeAccountUuid: initial.uuid);

  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {
    recordedTransports.add(transport);
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        accounts: [
          initial.copyWith(
            ledgerLastTransport: transport,
            ledgerDeviceId: deviceId,
            ledgerDeviceName: deviceName,
            ledgerDeviceModel: deviceModel,
          ),
        ],
      ),
    );
  }
}

class _FakeBleService implements LedgerMobileBleService {
  var connectCalls = 0;

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<LedgerMobileAppInfo> currentApp() async =>
      const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.2');

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() => currentApp();

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => const Stream.empty();

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) async =>
      const [];

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<LedgerApduCommand> commands,
  ) async => const [];

  @override
  Future<void> cancelSigning() async {}
}
