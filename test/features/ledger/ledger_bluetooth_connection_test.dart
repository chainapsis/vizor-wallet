import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_connection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

import '../../support/ledger_discovery_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LedgerDiscoveryChannel native;
  const device = LedgerBleDevice(
    id: 'stax',
    name: 'A37E',
    model: 'Ledger Stax',
  );
  setUp(() => native = LedgerDiscoveryChannel());
  tearDown(() => native.dispose());

  test('failed native cleanup never connects or reads the device', () async {
    await native.service.connect(device);
    native.disconnectError = PlatformException(code: 'busy');
    final requests = LedgerDeviceRequests();
    await expectLater(
      reconnectLedgerBluetoothDevice(
        service: native.service,
        device: device,
        checkCurrent: requests.capture(),
      ),
      throwsA(
        isA<LedgerMobileException>().having(
          (error) => error.failure,
          'failure',
          LedgerMobileFailure.busy,
        ),
      ),
    );
    expect(native.calls.where((call) => call == 'connect'), hasLength(1));
    expect(native.calls, isNot(contains('currentApp')));
  });

  test('cancellation during native cleanup prevents reconnection', () async {
    await native.service.connect(device);
    final cleanup = Completer<void>();
    native.disconnecting = cleanup.future;
    final requests = LedgerDeviceRequests();
    final result = reconnectLedgerBluetoothDevice(
      service: native.service,
      device: device,
      checkCurrent: requests.capture(),
    );
    final cancelled = expectLater(
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
    expect(native.calls.last, 'disconnect');
    requests.cancel();
    cleanup.complete();
    await cancelled;
    expect(native.calls.where((call) => call == 'connect'), hasLength(1));
  });

  test('cancelled native connect cannot publish a usable session', () async {
    final connection = Completer<void>();
    native.connecting = connection.future;
    final requests = LedgerDeviceRequests();
    var prepared = false;
    final cancelled = expectLater(
      reconnectLedgerBluetoothDevice(
        service: native.service,
        device: device,
        checkCurrent: requests.capture(),
      ).then((_) => prepared = true),
      throwsA(isA<LedgerMobileException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(native.calls.last, 'connect');
    requests.cancel();
    await native.service.cancelSigning();
    connection.complete();
    await cancelled;
    expect(prepared, isFalse);
    expect(native.service.connectedDeviceId, isNull);
  });
}
