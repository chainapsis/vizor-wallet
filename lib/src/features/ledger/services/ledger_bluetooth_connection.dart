import 'ledger_bluetooth_access.dart';
import 'ledger_mobile_ble_service.dart';

/// Prepare a fresh selected-device session after the previous request drained.
/// The cached device ID is an identity hint, not proof of a live native link.
Future<void> reconnectLedgerBluetoothDevice({
  required LedgerMobileBleService service,
  required LedgerBleDevice device,
  required void Function() checkCurrent,
}) async {
  checkCurrent();
  await requireLedgerBluetoothAccess(service);
  checkCurrent();
  // Await cleanup even when the device appears disconnected: the native SDK
  // can still own a link, and rejects connect while that link remains alive.
  await service.disconnect();
  checkCurrent();
  await service.connect(device);
  checkCurrent();
}
