import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_service.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    test(
      '$platform cancellation reaches both transports after disposal',
      () async {
        var cancelCalls = 0;
        final ble = _CancelBleService();
        final container = ProviderContainer(
          overrides: [
            ledgerTargetPlatformProvider.overrideWithValue(platform),
            ledgerRustOperationCancellerProvider.overrideWithValue(() async {
              cancelCalls++;
            }),
            ledgerMobileBleServiceProvider.overrideWithValue(ble),
          ],
        );
        final cancel = container.read(ledgerOperationCancellerProvider);
        container.dispose();
        await cancel();
        expect(cancelCalls, 1);
        expect(ble.cancelCalls, 1);
      },
    );
  }
}

class _CancelBleService implements LedgerMobileBleService {
  int cancelCalls = 0;

  @override
  Future<void> cancelSigning() async => cancelCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
