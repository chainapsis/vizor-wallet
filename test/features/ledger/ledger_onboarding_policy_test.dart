import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_onboarding_policy.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  test('accepts inclusive onboarding bounds and rejects invalid indices', () {
    for (final text in ['0', '12', '100']) {
      expect(parseLedgerOnboardingAccountIndex(text), int.parse(text));
    }
    for (final text in [
      '',
      '-1',
      '101',
      '2147483647',
      '999999999999999999999999',
      '1.5',
      'abc',
    ]) {
      expect(parseLedgerOnboardingAccountIndex(text), isNull);
    }
  });

  test(
    'USB and Bluetooth reject invalid indices before reading device dependencies',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (final index in [-1, 101, 2147483647]) {
        final error = throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: $kLedgerOnboardingAccountIndexError',
          ),
        );
        await expectLater(
          container.read(ledgerAccountConnectorProvider)(index),
          error,
        );
        await expectLater(
          container.read(ledgerBluetoothAccountConnectorProvider)(
            index,
            const LedgerBleDevice(id: 'test', name: 'Ledger', model: 'Nano X'),
          ),
          error,
        );
      }
    },
  );
}
