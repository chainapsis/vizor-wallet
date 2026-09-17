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
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));

  test('cancel during UFVK plan construction prevents device export', () async {
    final pending = Completer<LedgerUfvkApduPlan>();
    api.plan = pending.future;
    api.started = Completer<void>();
    final mobile = _Mobile();
    final container = ProviderContainer(
      overrides: [
        ledgerStaticCapabilityProvider.overrideWithValue(
          const LedgerCapability.supported(),
        ),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.android),
        rpcEndpointProvider.overrideWith(_Endpoint.new),
        ledgerMobileBleServiceProvider.overrideWithValue(mobile),
        ledgerAppReadinessDeviceForTransportProvider(
          LedgerConnectionTransport.bluetooth,
        ).overrideWithValue(_Ready()),
      ],
    );
    addTearDown(container.dispose);
    final result = container.read(ledgerBluetoothAccountConnectorProvider)(
      0,
      const LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Flex'),
    );
    final expectation = expectLater(
      result,
      throwsA(isA<LedgerMobileException>()),
    );
    await api.started.future;
    container.read(ledgerDeviceRequestsProvider).cancel();
    final command = LedgerApduCommand(
      cla: 0,
      ins: 0,
      p1: 0,
      p2: 0,
      data: Uint8List(0),
    );
    pending.complete(LedgerUfvkApduPlan(first: command, continuation: command));
    await expectation;
    expect(mobile.exports, 0);
  });

  for (final full in [false, true]) {
    test(
      'cancel during ${full ? 'full' : 'action'} signer DB lookup stops connection preparation',
      () async {
        final path = Completer<String>();
        final container = ProviderContainer(
          overrides: [
            ledgerStaticCapabilityProvider.overrideWithValue(
              const LedgerCapability.supported(),
            ),
            rpcEndpointProvider.overrideWith(_Endpoint.new),
            ledgerWalletDbPathProvider.overrideWithValue(() => path.future),
          ],
        );
        addTearDown(container.dispose);
        final result = full
            ? container.read(ledgerPcztTransportSignerProvider)('unused', [1])
            : container.read(ledgerActionPcztSignerProvider)('unused', [1]);
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
        container.read(ledgerDeviceRequestsProvider).cancel();
        path.complete('/unused');
        await expectation;
      },
    );
  }
}

class _Api extends RustLibApi {
  late Future<LedgerUfvkApduPlan> plan;
  late Completer<void> started;
  @override
  Future<LedgerUfvkApduPlan> crateApiLedgerLedgerBuildUfvkApduPlan({
    required int accountIndex,
  }) {
    started.complete();
    return plan;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ready implements LedgerAppReadinessDevice {
  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async =>
      const LedgerDeviceAppSnapshot(
        status: LedgerDeviceAppStatus.open,
        version: '3.9.3',
      );
  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() =>
      throw UnimplementedError();
}

class _Mobile implements LedgerMobileBleService {
  int exports = 0;
  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) async {
    exports++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Endpoint extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
}
