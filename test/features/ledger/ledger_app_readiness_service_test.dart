import 'dart:async';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  for (final phase in ['query', 'open']) {
    for (final fails in [false, true]) {
      test(
        'cancel during $phase suppresses late ${fails ? 'failure' : 'success'} and state',
        () async {
          final requests = LedgerDeviceRequests();
          final pending = Completer<LedgerDeviceAppSnapshot>();
          final states = <LedgerAppReadinessState>[];
          var openCalls = 0;
          final service = LedgerAppReadinessService(
            requests: requests,
            onState: states.add,
            device: _ControlledDevice(
              query: () async => phase == 'query'
                  ? pending.future
                  : const LedgerDeviceAppSnapshot(
                      status: LedgerDeviceAppStatus.dashboard,
                    ),
              open: () {
                openCalls++;
                return pending.future;
              },
            ),
          );
          final result = service.ensureReady();
          final expectation = expectLater(
            result,
            throwsA(
              isA<LedgerMobileException>().having(
                (error) => error.failure,
                'failure',
                LedgerMobileFailure.cancelled,
              ),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          requests.cancel();
          final stateCount = states.length;
          if (fails) {
            pending.completeError(StateError('late SDK error'));
          } else {
            pending.complete(
              const LedgerDeviceAppSnapshot(
                status: LedgerDeviceAppStatus.dashboard,
              ),
            );
          }
          await expectation;
          expect(states.length, stateCount);
          expect(openCalls, phase == 'query' ? 0 : 1);
        },
      );
    }
  }

  test(
    'older readiness request cannot overwrite the latest transport state',
    () async {
      final requests = LedgerDeviceRequests();
      final pending = Completer<LedgerDeviceAppSnapshot>();
      final states = <LedgerAppReadinessState>[];
      final old = LedgerAppReadinessService(
        requests: requests,
        onState: states.add,
        device: _ControlledDevice(
          query: () => pending.future,
          open: () => throw StateError('unexpected'),
        ),
      );
      final latest = LedgerAppReadinessService(
        requests: requests,
        onState: states.add,
        device: _FakeDevice([
          const LedgerDeviceAppSnapshot(
            status: LedgerDeviceAppStatus.open,
            version: '3.9.3',
          ),
        ]),
      );
      final expectation = expectLater(
        old.ensureReady(),
        throwsA(isA<LedgerMobileException>()),
      );
      expect(await latest.ensureReady(), '3.9.3');
      final last = states.last;
      pending.completeError(StateError('old failure'));
      await expectation;
      expect(states.last, same(last));
      expect(states.last.phase, LedgerAppReadinessPhase.ready);
    },
  );

  test(
    'Linux USB permission failure is not mistaken for device rejection',
    () async {
      final service = LedgerAppReadinessService(
        device: _ErrorDevice(
          StateError(
            'ledger_linux_usb_access: Open Ledger HID device: Permission denied',
          ),
        ),
        onState: (_) {},
      );
      await expectLater(
        service.ensureReady(),
        throwsA(
          isA<LedgerAppReadinessException>()
              .having(
                (e) => e.failure,
                'failure',
                LedgerAppReadinessFailure.unavailable,
              )
              .having((e) => e.message, 'instructions', contains('udev')),
        ),
      );
    },
  );

  test('already-open app passes the minimum version gate', () async {
    final states = <LedgerAppReadinessState>[];
    final service = LedgerAppReadinessService(
      device: _FakeDevice([
        const LedgerDeviceAppSnapshot(
          status: LedgerDeviceAppStatus.open,
          version: '3.9.3',
        ),
      ]),
      onState: states.add,
    );

    expect(await service.ensureReady(), '3.9.3');
    expect(states.map((state) => state.phase), [
      LedgerAppReadinessPhase.checkingDevice,
      LedgerAppReadinessPhase.ready,
    ]);
  });

  test(
    'dashboard request opens Zcash and verifies after reconnecting',
    () async {
      final states = <LedgerAppReadinessState>[];
      final device = _FakeDevice([
        const LedgerDeviceAppSnapshot(status: LedgerDeviceAppStatus.dashboard),
        const LedgerDeviceAppSnapshot(
          status: LedgerDeviceAppStatus.open,
          version: '3.10.0',
        ),
      ]);
      final service = LedgerAppReadinessService(
        device: device,
        onState: states.add,
      );

      expect(await service.ensureReady(), '3.10.0');
      expect(device.openRequests, 1);
      expect(states.map((state) => state.phase), [
        LedgerAppReadinessPhase.checkingDevice,
        LedgerAppReadinessPhase.confirmOpening,
        LedgerAppReadinessPhase.ready,
      ]);
    },
  );

  test(
    'rejection becomes a stable typed failure and a retry can succeed',
    () async {
      final states = <LedgerAppReadinessState>[];
      final device = _FakeDevice(
        [
          const LedgerDeviceAppSnapshot(
            status: LedgerDeviceAppStatus.dashboard,
          ),
          const LedgerDeviceAppSnapshot(
            status: LedgerDeviceAppStatus.dashboard,
          ),
          const LedgerDeviceAppSnapshot(
            status: LedgerDeviceAppStatus.open,
            version: '3.9.3',
          ),
        ],
        openErrors: [StateError('request rejected 6985'), null],
      );
      final service = LedgerAppReadinessService(
        device: device,
        onState: states.add,
      );

      await expectLater(
        service.ensureReady(),
        throwsA(
          isA<LedgerAppReadinessException>().having(
            (error) => error.failure,
            'failure',
            LedgerAppReadinessFailure.rejected,
          ),
        ),
      );
      expect(states.last.phase, LedgerAppReadinessPhase.failed);
      expect(states.last.failure, LedgerAppReadinessFailure.rejected);

      expect(await service.ensureReady(), '3.9.3');
      expect(states.last.phase, LedgerAppReadinessPhase.ready);
    },
  );

  test('rejects a Zcash app older than 3.9.3', () async {
    final states = <LedgerAppReadinessState>[];
    final service = LedgerAppReadinessService(
      device: _FakeDevice([
        const LedgerDeviceAppSnapshot(
          status: LedgerDeviceAppStatus.open,
          version: '3.9.2',
        ),
      ]),
      onState: states.add,
    );

    await expectLater(
      service.ensureReady(),
      throwsA(
        isA<LedgerAppReadinessException>()
            .having(
              (error) => error.failure,
              'failure',
              LedgerAppReadinessFailure.unsupportedVersion,
            )
            .having((error) => error.message, 'message', contains('3.9.3')),
      ),
    );
    expect(states.last.failure, LedgerAppReadinessFailure.unsupportedVersion);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform readiness uses the retained mobile BLE service', () async {
      final mobile = _FakeMobileBleService();
      final container = ProviderContainer(
        overrides: [
          ledgerTargetPlatformProvider.overrideWithValue(platform),
          ledgerMobileBleServiceProvider.overrideWithValue(mobile),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(ledgerAppReadinessServiceProvider).ensureReady(),
        '3.9.3',
      );
      expect(mobile.currentAppCalls, 1);
      expect(mobile.connectCalls, 0);
    });
  }

  test(
    'Bluetooth permission denial is not classified as device rejection',
    () async {
      final service = LedgerAppReadinessService(
        device: const _ErrorDevice(
          LedgerMobileException(
            LedgerMobileFailure.permissionDenied,
            'Bluetooth permission denied.',
          ),
        ),
        onState: (_) {},
      );

      await expectLater(
        service.ensureReady(),
        throwsA(
          isA<LedgerAppReadinessException>().having(
            (error) => error.failure,
            'failure',
            LedgerAppReadinessFailure.unavailable,
          ),
        ),
      );
    },
  );

  test('missing Ledger is classified as a disconnected device', () async {
    final states = <LedgerAppReadinessState>[];
    final service = LedgerAppReadinessService(
      device: _ErrorDevice(
        StateError('No Ledger device found. Connect and unlock the Nano S+.'),
      ),
      onState: states.add,
    );

    await expectLater(
      service.ensureReady(),
      throwsA(
        isA<LedgerAppReadinessException>()
            .having(
              (error) => error.failure,
              'failure',
              LedgerAppReadinessFailure.disconnected,
            )
            .having(
              (error) => error.message,
              'message',
              'Reconnect and unlock your Ledger, then try again.',
            ),
      ),
    );
    expect(states.last.failure, LedgerAppReadinessFailure.disconnected);
  });
}

class _FakeDevice implements LedgerAppReadinessDevice {
  _FakeDevice(this.snapshots, {this.openErrors = const []});

  final List<LedgerDeviceAppSnapshot> snapshots;
  final List<Object?> openErrors;
  var queryIndex = 0;
  var openRequests = 0;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async {
    return snapshots[queryIndex++];
  }

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() async {
    final error = openRequests < openErrors.length
        ? openErrors[openRequests]
        : null;
    openRequests++;
    if (error != null) throw error;
    return snapshots[queryIndex++];
  }
}

class _ErrorDevice implements LedgerAppReadinessDevice {
  const _ErrorDevice(this.error);

  final Object error;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() => Future.error(error);

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => Future.error(error);
}

class _FakeMobileBleService implements LedgerMobileBleService {
  var currentAppCalls = 0;
  var connectCalls = 0;
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
    _connectedDeviceId = device.id;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    currentAppCalls++;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => const Stream.empty();

  @override
  Future<void> disconnect() async {
    _connectedDeviceId = null;
  }

  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) {
    throw UnimplementedError();
  }

  @override
  Future<List<Uint8List>> exchangeApdus(List<LedgerApduCommand> commands) =>
      throw UnimplementedError();

  @override
  Future<void> cancelSigning() async {}

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() {
    throw UnimplementedError();
  }

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> stopDiscovery() async {}
}

class _ControlledDevice implements LedgerAppReadinessDevice {
  _ControlledDevice({required this.query, required this.open});
  final Future<LedgerDeviceAppSnapshot> Function() query;
  final Future<LedgerDeviceAppSnapshot> Function() open;
  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() => query();
  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => open();
}
