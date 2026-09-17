import 'services/ledger_mobile_ble_service.dart';

/// Presentation only: never use this label to identify or verify an account.
String ledgerDeviceLabel(LedgerBleDevice device) {
  String compact(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final modelKey = compact(device.model).replaceFirst(RegExp('^ledger'), '');
  final model = switch (modelKey) {
    'nanox' => 'Ledger Nano X',
    'flex' => 'Ledger Flex',
    'stax' => 'Ledger Stax',
    'flexstax' || 'staxflex' => 'Ledger Flex / Stax',
    'nanogen5' || 'nanogeneration5' || 'apex' => 'Ledger Nano Gen5',
    'nanos' => 'Ledger Nano S',
    'nanosplus' => 'Ledger Nano S Plus',
    _ => 'Ledger',
  };
  final name = device.name.trim();
  final nameKey = compact(name);
  if (name.isEmpty || ['ledger', 'noname', 'unknown'].contains(nameKey)) {
    return model;
  }
  if (model != 'Ledger' && (nameKey == modelKey || nameKey == compact(model))) {
    return model;
  }
  // Preserve custom names that already include the full model designation.
  if (nameKey.contains(compact(model))) return name;
  return '$model · $name';
}
