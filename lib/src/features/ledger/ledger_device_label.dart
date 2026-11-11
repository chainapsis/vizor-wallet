import 'services/ledger_mobile_ble_service.dart';

/// Presentation only: never use this label to identify or verify an account.
String ledgerDeviceLabel(LedgerBleDevice device) {
  String compact(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final modelKey = compact(device.model).replaceFirst(RegExp('^ledger'), '');
  final model = switch (modelKey) {
    'nanox' => 'Ledger Nano X', // l10n-ignore: product name
    'flex' => 'Ledger Flex', // l10n-ignore: product name
    'stax' => 'Ledger Stax', // l10n-ignore: product name
    'flexstax' ||
    'staxflex' => 'Ledger Flex / Stax', // l10n-ignore: product name
    'nanogen5' ||
    'nanogeneration5' ||
    'apex' => 'Ledger Nano Gen5', // l10n-ignore: product name
    'nanos' => 'Ledger Nano S', // l10n-ignore: product name
    'nanosplus' => 'Ledger Nano S Plus', // l10n-ignore: product name
    _ => 'Ledger', // l10n-ignore: product name
  };
  final name = device.name.trim();
  final nameKey = compact(name);
  if (name.isEmpty || ['ledger', 'noname', 'unknown'].contains(nameKey)) {
    return model;
  }
  const genericModel = 'Ledger'; // l10n-ignore: device model name
  if (model != genericModel &&
      (nameKey == modelKey || nameKey == compact(model))) {
    return model;
  }
  // Preserve custom names that already include the full model designation.
  if (nameKey.contains(compact(model))) return name;
  return '$model · $name';
}
