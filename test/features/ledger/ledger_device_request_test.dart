import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  test(
    'native cancellation blocks new preparation until all cancellations drain',
    () async {
      final requests = LedgerDeviceRequests();
      final first = Completer<void>();
      final second = Completer<void>();
      final old = requests.capture();
      final one = requests.cancelWhile(() => first.future);
      final two = requests.cancelWhile(() => second.future);
      expect(old, throwsA(isA<LedgerMobileException>()));
      expect(requests.capture, throwsA(isA<LedgerMobileException>()));
      first.complete();
      await one;
      expect(requests.capture, throwsA(isA<LedgerMobileException>()));
      second.complete();
      await two;
      requests.capture()();
      expect(old, throwsA(isA<LedgerMobileException>()));
    },
  );

  test('failed native cancellation releases preparation gate', () async {
    final requests = LedgerDeviceRequests();
    await expectLater(
      requests.cancelWhile(() async => throw StateError('failed')),
      throwsStateError,
    );
    requests.capture()();
  });
}
