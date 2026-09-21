import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_device_label.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  for (final (name, model, expected) in [
    ('F52C', 'Nano X', 'Ledger Nano X · F52C'),
    ('A37E', 'FLEX', 'Ledger Flex · A37E'),
    ('A37E', 'Ledger Flex / Stax', 'Ledger Flex / Stax · A37E'),
    ('Ledger Flex', 'Flex', 'Ledger Flex'),
    ('Flex', 'Ledger Flex', 'Ledger Flex'),
    ('My Ledger Flex', 'Flex', 'My Ledger Flex'),
    ('Ledger Nano X F52C', 'Nano X', 'Ledger Nano X F52C'),
    ('F52C', 'F52C', 'Ledger · F52C'),
    ('F52C', '', 'Ledger · F52C'),
    ('내 렛저', 'Flex', 'Ledger Flex · 내 렛저'),
    ('🔐', '', 'Ledger · 🔐'),
    ('F52C', 'Unknown', 'Ledger · F52C'),
    ('', 'Stax', 'Ledger Stax'),
    ('No Name', 'Nano X', 'Ledger Nano X'),
    (' Ledger ', '', 'Ledger'),
    ('A37E', 'nano_gen5', 'Ledger Nano Gen5 · A37E'),
    (
      'Office Ledger with a very long custom Bluetooth name',
      'Stax',
      'Ledger Stax · Office Ledger with a very long custom Bluetooth name',
    ),
  ]) {
    test('$name / $model', () {
      expect(
        ledgerDeviceLabel(LedgerBleDevice(id: 'id', name: name, model: model)),
        expected,
      );
    });
  }
}
