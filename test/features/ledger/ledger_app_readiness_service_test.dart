import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  test('already-open app passes the minimum version gate', () async {
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

    expect(await service.ensureReady(), '3.9.2');
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
            version: '3.9.2',
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

      expect(await service.ensureReady(), '3.9.2');
      expect(states.last.phase, LedgerAppReadinessPhase.ready);
    },
  );

  test('rejects a Zcash app older than 3.9.2', () async {
    final states = <LedgerAppReadinessState>[];
    final service = LedgerAppReadinessService(
      device: _FakeDevice([
        const LedgerDeviceAppSnapshot(
          status: LedgerDeviceAppStatus.open,
          version: '3.9.1',
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
            .having((error) => error.message, 'message', contains('3.9.2')),
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
        '3.9.2',
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

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    currentAppCalls++;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.2');
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => const Stream.empty();

  @override
  Future<void> disconnect() async {}

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
