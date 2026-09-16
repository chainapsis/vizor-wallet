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
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    for (final preference in LedgerConnectionPreference.values) {
      for (final usbReady in [true, false]) {
        test(
          '$platform uses USB for saved $preference (ready: $usbReady)',
          () async {
            final notifier = _FakeAccountNotifier(
              _ledgerAccount(
                preference: preference,
                deviceModel: 'Nano X',
              ).copyWith(
                ledgerLastTransport: LedgerConnectionTransport.bluetooth,
              ),
            );
            final ble = _FakeBleService();
            final container = _container(
              notifier: notifier,
              ble: ble,
              platform: platform,
              usbReady: usbReady,
            );
            addTearDown(container.dispose);
            await container.read(accountProvider.future);
            final operation = container
                .read(ledgerConnectionServiceProvider)
                .run(
                  accountUuid: 'ledger-1',
                  usb: () async => 'usb',
                  bluetooth: (_) async =>
                      fail('unsupported native BLE must never be called'),
                );
            if (usbReady) {
              expect(await operation, 'usb');
            } else {
              await expectLater(
                operation,
                throwsA(
                  isA<LedgerConnectionRequiredException>()
                      .having(
                        (e) => e.message,
                        'USB instructions',
                        contains('with USB'),
                      )
                      .having(
                        (e) => e.message,
                        'no BLE instructions',
                        isNot(contains('Bluetooth')),
                      ),
                ),
              );
            }
            expect(ble.connectCalls, 0);
          },
        );
      }
    }
  }

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
      final container = _container(
        notifier: notifier,
        ble: ble,
        usbReady: false,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      final result = await container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () => throw StateError('operation must not start'),
            bluetooth: (_) async => 'signed-over-ble',
          );

      expect(result, 'signed-over-ble');
      expect(ble.connectCalls, 1);
      expect(notifier.recordedTransports, [
        LedgerConnectionTransport.bluetooth,
      ]);
    },
  );

  for (final metadataFailure in [false, true]) {
    test(
      'does not replay an operation (metadata failure: $metadataFailure)',
      () async {
        final notifier = _FakeAccountNotifier(
          _ledgerAccount(
            preference: LedgerConnectionPreference.automatic,
            deviceModel: 'Nano X',
          ),
        )..failRecording = metadataFailure;
        final ble = _FakeBleService();
        final container = _container(notifier: notifier, ble: ble);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final operation = container
            .read(ledgerConnectionServiceProvider)
            .run(
              accountUuid: 'ledger-1',
              usb: () async {
                if (!metadataFailure) {
                  throw StateError(
                    'Ledger HID disconnected after signing started',
                  );
                }
                return 'signed';
              },
              bluetooth: (_) async => fail('must not replay'),
            );
        if (metadataFailure) {
          expect(await operation, 'signed');
        } else {
          await expectLater(operation, throwsStateError);
        }
        expect(ble.connectCalls, 0);
      },
    );
  }

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

  test(
    'mobile switches from the retained Ledger to the selected account device',
    () async {
      final notifier = _FakeAccountNotifier(
        _ledgerAccount(
          preference: LedgerConnectionPreference.bluetooth,
          deviceModel: 'Nano X',
        ),
      );
      final ble = _FakeBleService().._connectedDeviceId = 'previous-device';
      final container = _container(
        notifier: notifier,
        ble: ble,
        platform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      final result = await container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'unexpected',
            bluetooth: (_) async => 'signed-over-selected-ledger',
          );

      expect(result, 'signed-over-selected-ledger');
      expect(ble.disconnectCalls, 1);
      expect(ble.connectedDeviceIds, ['device-1']);
      expect(ble.connectedDeviceId, 'device-1');
    },
  );
}

ProviderContainer _container({
  required _FakeAccountNotifier notifier,
  required _FakeBleService ble,
  TargetPlatform platform = TargetPlatform.macOS,
  bool usbReady = true,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(notifier.initial)),
      accountProvider.overrideWith(() => notifier),
      ledgerTargetPlatformProvider.overrideWithValue(platform),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerAppReadinessDeviceForTransportProvider(
        LedgerConnectionTransport.usb,
      ).overrideWithValue(_ReadyDevice(available: usbReady)),
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
  const _ReadyDevice({this.available = true});
  final bool available;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async =>
      LedgerDeviceAppSnapshot(
        status: available
            ? LedgerDeviceAppStatus.open
            : LedgerDeviceAppStatus.disconnected,
        version: '3.9.2',
      );

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => queryZcashApp();
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initial);

  final AccountInfo initial;
  bool failRecording = false;
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
    if (failRecording) throw StateError('metadata write failed');
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
  var disconnectCalls = 0;
  final connectedDeviceIds = <String>[];
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
    connectedDeviceIds.add(device.id);
    _connectedDeviceId = device.id;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _connectedDeviceId = null;
  }

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
