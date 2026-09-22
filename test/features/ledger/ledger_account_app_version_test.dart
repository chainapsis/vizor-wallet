import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _device = LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Flex');

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(api.reset);

  ProviderContainer containerFor(String appVersion) {
    final container = ProviderContainer(
      overrides: [
        ledgerStaticCapabilityProvider.overrideWithValue(
          const LedgerCapability.supported(),
        ),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.android),
        rpcEndpointProvider.overrideWith(_Endpoint.new),
        ledgerMobileBleServiceProvider.overrideWithValue(_Mobile()),
        for (final transport in LedgerConnectionTransport.values)
          ledgerAppReadinessDeviceForTransportProvider(
            transport,
          ).overrideWithValue(_Ready(appVersion)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Waits until the connector asks for the viewing key, then cancels so the
  /// test does not need a device to answer.
  Future<void> expectViewingKeyRequested(
    ProviderContainer container,
    Future<LedgerDeviceAccount> result,
  ) async {
    final settled = expectLater(result, throwsA(anything));
    await api.planRequested.future;
    container.read(ledgerDeviceRequestsProvider).cancel();
    api.completePlan();
    await settled;
  }

  // 3.9.2 is already refused by readiness, which names the signing minimum.
  for (final version in ['3.9.2', '3.9.3']) {
    for (final transport in LedgerConnectionTransport.values) {
      test('a new ${transport.name} account on $version is refused before the '
          'viewing-key request', () async {
        final container = containerFor(version);

        await expectLater(
          transport == LedgerConnectionTransport.usb
              ? container.read(ledgerAccountConnectorProvider)(0)
              : container.read(ledgerBluetoothAccountConnectorProvider)(
                  0,
                  _device,
                ),
          throwsA(
            isA<LedgerAppReadinessException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  LedgerAppReadinessFailure.unsupportedVersion,
                )
                .having(
                  (e) => e.message,
                  'message',
                  'Update the Ledger Zcash app to version '
                      '$kMinimumLedgerZcashAppVersionForNewAccounts or newer.',
                ),
          ),
        );
        // Neither the Bluetooth plan nor the USB export was requested.
        expect(api.planRequested.isCompleted, isFalse);
      });
    }
  }

  test('a new account on 3.9.4 goes on to the viewing-key request', () async {
    final container = containerFor('3.9.4');
    await expectViewingKeyRequested(
      container,
      container.read(ledgerBluetoothAccountConnectorProvider)(0, _device),
    );
  });

  test('confirming an existing account still accepts 3.9.3', () async {
    final container = containerFor('3.9.3');
    await expectViewingKeyRequested(
      container,
      container.read(ledgerBluetoothExistingAccountConnectorProvider)(
        0,
        _device,
      ),
    );
  });
}

class _Api extends RustLibApi {
  late Completer<void> planRequested;
  late Completer<LedgerUfvkApduPlan> _plan;

  void reset() {
    planRequested = Completer<void>();
    _plan = Completer<LedgerUfvkApduPlan>();
  }

  void completePlan() {
    final command = LedgerApduCommand(
      cla: 0,
      ins: 0,
      p1: 0,
      p2: 0,
      data: Uint8List(0),
    );
    _plan.complete(LedgerUfvkApduPlan(first: command, continuation: command));
  }

  @override
  Future<LedgerUfvkApduPlan> crateApiLedgerLedgerBuildUfvkApduPlan({
    required int accountIndex,
  }) {
    planRequested.complete();
    return _plan.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ready implements LedgerAppReadinessDevice {
  _Ready(this.version);

  final String version;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async =>
      LedgerDeviceAppSnapshot(
        status: LedgerDeviceAppStatus.open,
        version: version,
      );

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() =>
      throw UnimplementedError();
}

class _Mobile implements LedgerMobileBleService {
  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Endpoint extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
}
