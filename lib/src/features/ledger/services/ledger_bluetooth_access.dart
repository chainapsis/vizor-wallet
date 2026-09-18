import 'ledger_mobile_ble_service.dart';

enum LedgerBluetoothPermission { granted, requestable, settings, restricted }

class LedgerBluetoothAccessStatus {
  const LedgerBluetoothAccessStatus(
    this.permission, {
    this.locationPermission = false,
    this.macOS = false,
    this.bluetoothEnabled,
    this.locationEnabled,
  });

  factory LedgerBluetoothAccessStatus.fromMap(Map<Object?, Object?> value) =>
      LedgerBluetoothAccessStatus(
        switch (value['permission']) {
          'granted' => LedgerBluetoothPermission.granted,
          'requestable' => LedgerBluetoothPermission.requestable,
          'restricted' => LedgerBluetoothPermission.restricted,
          _ => LedgerBluetoothPermission.settings,
        },
        locationPermission: value['permissionKind'] == 'location',
        macOS: value['platform'] == 'macOS',
        bluetoothEnabled: value['bluetoothEnabled'] as bool?,
        locationEnabled: value['locationEnabled'] as bool?,
      );

  final LedgerBluetoothPermission permission;
  final bool locationPermission;
  final bool macOS;
  final bool? bluetoothEnabled;
  final bool? locationEnabled;
  bool get granted => permission == LedgerBluetoothPermission.granted;
  String get message {
    final kind = locationPermission ? 'Location' : 'Bluetooth';
    if (granted && bluetoothEnabled == false) {
      return 'Turn on Bluetooth, then check access again.';
    }
    if (granted && locationEnabled == false) {
      return 'Turn on location services, then check access again.';
    }
    if (granted) return 'Permission is allowed. Try again when ready.';
    if (permission == LedgerBluetoothPermission.restricted) {
      return '$kind access is restricted by your device settings or administrator.';
    }
    if (permission == LedgerBluetoothPermission.requestable) {
      return locationPermission
          ? 'This Android version needs location permission to find your Ledger. Choose Allow permission, or open Settings if no prompt appears.'
          : 'Choose Allow permission to connect to your Ledger. If no prompt appears, open Settings.';
    }
    return locationPermission
        ? 'This Android version needs location permission to find your Ledger. Allow location access for Vizor in Settings.'
        : macOS
        ? 'Open System Settings > Privacy & Security > Bluetooth and allow access for Vizor.'
        : 'Allow Bluetooth access for Vizor in your device settings.';
  }
}

/// Optional so custom/test transports can retain their own permission handling.
abstract interface class LedgerBluetoothAccess {
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus();
  Future<bool> openBluetoothSettings();
}

Future<void> requireLedgerBluetoothAccess(
  LedgerMobileBleService service,
) async {
  if (service is! LedgerBluetoothAccess) return;
  final status = await (service as LedgerBluetoothAccess)
      .bluetoothAccessStatus();
  if (!status.granted) {
    throw LedgerMobileException(
      LedgerMobileFailure.permissionDenied,
      status.message,
    );
  }
  if (status.bluetoothEnabled == false) {
    throw LedgerMobileException(
      LedgerMobileFailure.bluetoothOff,
      status.message,
    );
  }
  if (status.locationEnabled == false) {
    throw LedgerMobileException(
      LedgerMobileFailure.locationDisabled,
      status.message,
    );
  }
}

Future<bool> prepareLedgerBluetoothDiscovery(
  LedgerMobileBleService service,
) async {
  if (service is LedgerBluetoothAccess) {
    await requireLedgerBluetoothAccess(service);
    return true;
  }
  return service.requestPermissions();
}

/// Pairing settings are separate from the app's permission settings.
abstract interface class LedgerBluetoothPairingSettings {
  Future<bool> openBluetoothPairingSettings();
}
