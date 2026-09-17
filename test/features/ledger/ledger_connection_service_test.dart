import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
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

import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final stage in ['connect', 'readiness', 'sign']) {
      for (final failure in [
        LedgerMobileFailure.permissionDenied,
        LedgerMobileFailure.pairingInvalid,
        LedgerMobileFailure.pairingRejected,
        LedgerMobileFailure.bluetoothOff,
        LedgerMobileFailure.locationDisabled,
      ]) {
        test('$platform preserves $failure guidance at $stage', () async {
          final original = LedgerMobileException(failure, 'native diagnostic');
          final ble = _FakeBleService();
          if (stage == 'connect') ble.connectError = original;
          if (stage == 'readiness') ble.appError = original;
          final container = _container(
            notifier: _FakeAccountNotifier(
              _ledgerAccount(
                preference: LedgerConnectionPreference.bluetooth,
                deviceModel: 'Nano X',
              ),
            ),
            ble: ble,
            platform: platform,
          );
          addTearDown(container.dispose);
          await container.read(accountProvider.future);
          var signs = 0;
          await expectLater(
            container
                .read(ledgerConnectionServiceProvider)
                .run(
                  accountUuid: 'ledger-1',
                  usb: () async => 'usb',
                  bluetooth: (_) async {
                    signs++;
                    throw original;
                  },
                ),
            throwsA(
              predicate<Object>(
                (error) =>
                    ledgerFailureGuidance(error)?.message ==
                    ledgerFailureGuidance(original)!.message,
              ),
            ),
          );
          expect(signs, stage == 'sign' ? 1 : 0);
          expect(ble.connectCalls, 1);
        });
      }
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final failure in [
      LedgerMobileFailure.disconnected,
      LedgerMobileFailure.unavailable,
      LedgerMobileFailure.busy,
    ]) {
      test(
        '$platform recovers failed sessions without replacing busy approval ($failure)',
        () async {
          final ble = _FakeBleService()
            .._connectedDeviceId = 'device-1'
            ..appError = LedgerMobileException(failure, 'probe failed')
            ..clearAppErrorOnConnect = true;
          final container = _container(
            notifier: _FakeAccountNotifier(
              _ledgerAccount(
                preference: LedgerConnectionPreference.bluetooth,
                deviceModel: 'Nano X',
              ),
            ),
            ble: ble,
            platform: platform,
          );
          addTearDown(container.dispose);
          await container.read(accountProvider.future);
          var signs = 0;
          Future<String> run() => container
              .read(ledgerConnectionServiceProvider)
              .run(
                accountUuid: 'ledger-1',
                usb: () async => 'usb',
                bluetooth: (_) async {
                  signs++;
                  return 'signed';
                },
              );
          if (failure == LedgerMobileFailure.disconnected) {
            expect(await run(), 'signed');
            expect(ble.disconnectCalls, 1);
            expect(ble.connectCalls, 1);
          } else {
            await expectLater(run(), throwsA(isA<Exception>()));
            expect(signs, 0);
            expect(ble.disconnectCalls, 0);
            ble.appError = null;
            expect(await run(), 'signed');
            expect(
              ble.disconnectCalls,
              failure == LedgerMobileFailure.busy ? 0 : 1,
            );
            expect(
              ble.connectCalls,
              failure == LedgerMobileFailure.busy ? 0 : 1,
            );
          }
        },
      );
    }
  }

  test(
    'failed cleanup cannot be bypassed and failed connect is not repeated',
    () async {
      final ble = _FakeBleService()
        ..disconnectError = const LedgerMobileException(
          LedgerMobileFailure.disconnected,
          'cleanup failed',
        );
      final container = _container(
        notifier: _FakeAccountNotifier(
          _ledgerAccount(
            preference: LedgerConnectionPreference.bluetooth,
            deviceModel: 'Nano X',
          ),
        ),
        ble: ble,
        platform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      Future<String> run() => container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'usb',
            bluetooth: (_) async => 'signed',
          );
      await expectLater(run(), throwsA(isA<Exception>()));
      expect(ble.disconnectCalls, 1);
      expect(ble.connectCalls, 0);
      ble.disconnectError = null;
      ble.connectError = const LedgerMobileException(
        LedgerMobileFailure.disconnected,
        'connect failed',
      );
      await expectLater(run(), throwsA(isA<Exception>()));
      expect(ble.connectCalls, 1);
      ble.connectError = null;
      expect(await run(), 'signed');
      expect(ble.connectCalls, 2);
    },
  );

  test(
    'APDU failure is not replayed but the next request reconnects',
    () async {
      final ble = _FakeBleService().._connectedDeviceId = 'device-1';
      final container = _container(
        notifier: _FakeAccountNotifier(
          _ledgerAccount(
            preference: LedgerConnectionPreference.bluetooth,
            deviceModel: 'Nano X',
          ),
        ),
        ble: ble,
        platform: TargetPlatform.android,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      var signs = 0;
      Future<String> run() => container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'usb',
            bluetooth: (_) async {
              signs++;
              if (signs == 1) {
                throw const LedgerMobileException(
                  LedgerMobileFailure.disconnected,
                  'lost response',
                );
              }
              return 'signed';
            },
          );
      await expectLater(run(), throwsA(isA<LedgerMobileException>()));
      expect(signs, 1);
      expect(ble.connectCalls, 0);
      expect(await run(), 'signed');
      expect(signs, 2);
      expect(ble.disconnectCalls, 1);
      expect(ble.connectCalls, 1);
    },
  );

  test(
    'cancellation during transport metadata persistence suppresses signed result',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      final notifier =
          _FakeAccountNotifier(
              _ledgerAccount(
                preference: LedgerConnectionPreference.bluetooth,
                deviceModel: 'Flex',
              ),
            )
            ..recordGate = pending.future
            ..recordStarted = started;
      final container = _container(
        notifier: notifier,
        ble: _FakeBleService(),
        platform: TargetPlatform.android,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      final result = container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'unexpected',
            bluetooth: (_) async => 'signed',
          );
      final expectation = expectLater(
        result,
        throwsA(
          isA<LedgerMobileException>().having(
            (e) => e.failure,
            'failure',
            LedgerMobileFailure.cancelled,
          ),
        ),
      );
      await started.future;
      container.read(ledgerDeviceRequestsProvider).cancel();
      pending.complete();
      await expectation;
    },
  );

  for (final stage in ['connect', 'disconnect', 'currentApp']) {
    test('cancellation during $stage prevents signing', () async {
      final pending = Completer<void>();
      final ble = _FakeBleService()
        ..pauseStage = stage
        ..pause = pending.future;
      if (stage == 'disconnect') {
        ble._connectedDeviceId = 'another-device';
      }
      if (stage == 'currentApp') ble._connectedDeviceId = 'device-1';
      final notifier = _FakeAccountNotifier(
        _ledgerAccount(
          preference: LedgerConnectionPreference.bluetooth,
          deviceModel: 'Flex',
        ),
      );
      final container = _container(
        notifier: notifier,
        ble: ble,
        platform: TargetPlatform.android,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      var signed = false;
      final result = container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => 'unexpected',
            bluetooth: (_) async {
              signed = true;
              return 'signed';
            },
          );
      final expectation = expectLater(
        result,
        throwsA(
          isA<LedgerMobileException>().having(
            (e) => e.failure,
            'failure',
            LedgerMobileFailure.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      container.read(ledgerDeviceRequestsProvider).cancel();
      pending.complete();
      await expectation;
      expect(signed, isFalse);
      expect(notifier.recordedTransports, isEmpty);
      if (stage == 'disconnect') expect(ble.connectCalls, 0);
    });
  }

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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform reconnects using bootstrapped pairing metadata', () async {
      final stored = _ledgerAccount(
        preference: LedgerConnectionPreference.bluetooth,
        deviceModel: 'Nano X',
      );
      final restored = mergeBootstrappedAccountInfo(
        rustAccount: const AccountInfo(
          uuid: 'ledger-1',
          name: 'Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        storedAccount: AccountInfo.fromJson(stored.toJson()),
        order: 0,
      );
      final ble = _FakeBleService();
      final container = _container(
        notifier: _FakeAccountNotifier(restored),
        ble: ble,
        platform: platform,
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      final result = await container
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'ledger-1',
            usb: () async => fail('mobile must use Bluetooth'),
            bluetooth: (_) async => 'signed',
          );
      expect(result, 'signed');
      expect(ble.connectedDeviceIds, ['device-1']);
    });
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
      ).overrideWithValue(_ReadyDevice(ble: ble)),
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
  const _ReadyDevice({this.available = true, this.ble});
  final bool available;
  final LedgerMobileBleService? ble;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async {
    if (ble != null) await ble!.currentApp();
    return LedgerDeviceAppSnapshot(
      status: available
          ? LedgerDeviceAppStatus.open
          : LedgerDeviceAppStatus.disconnected,
      version: '3.9.3',
    );
  }

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => queryZcashApp();
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initial);

  final AccountInfo initial;
  bool failRecording = false;
  Future<void>? recordGate;
  Completer<void>? recordStarted;
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
    recordStarted?.complete();
    if (recordGate != null) await recordGate;
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
  Object? appError;
  bool clearAppErrorOnConnect = false;
  Object? disconnectError;
  Object? connectError;
  String? pauseStage;
  Future<void>? pause;
  var connectCalls = 0;
  var disconnectCalls = 0;
  final connectedDeviceIds = <String>[];
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    if (pauseStage == 'connect') await pause;
    if (clearAppErrorOnConnect) appError = null;
    connectedDeviceIds.add(device.id);
    _connectedDeviceId = device.id;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (disconnectError != null) throw disconnectError!;
    if (pauseStage == 'disconnect') await pause;
    _connectedDeviceId = null;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    if (pauseStage == 'currentApp') await pause;
    if (appError != null) throw appError!;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

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
