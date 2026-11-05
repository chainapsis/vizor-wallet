import '../../../core/l10n/l10n.dart' show AppLocalizations;
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
  String message(AppLocalizations l10n) {
    final kind = locationPermission
        ? l10n.ledgerBtAccessKindLocation
        : l10n.ledgerTransportBluetooth;
    if (granted && bluetoothEnabled == false) {
      return l10n.ledgerBtAccessTurnOnBluetooth;
    }
    if (granted && locationEnabled == false) {
      return l10n.ledgerBtAccessTurnOnLocation;
    }
    if (granted) return l10n.ledgerBtAccessAllowed;
    if (permission == LedgerBluetoothPermission.restricted) {
      return l10n.ledgerBtAccessRestricted(kind);
    }
    if (permission == LedgerBluetoothPermission.requestable) {
      return locationPermission
          ? l10n.ledgerBtAccessLocationRequestable
          : l10n.ledgerBtAccessBluetoothRequestable;
    }
    return locationPermission
        ? l10n.ledgerBtAccessLocationSettings
        : macOS
        ? l10n.ledgerBtAccessMacosSettings
        : l10n.ledgerBtAccessBluetoothSettings;
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
      'Bluetooth access is not granted.', // l10n-ignore: exception text
    );
  }
  if (status.bluetoothEnabled == false) {
    throw LedgerMobileException(
      LedgerMobileFailure.bluetoothOff,
      'Bluetooth is turned off.', // l10n-ignore: exception text
    );
  }
  if (status.locationEnabled == false) {
    throw LedgerMobileException(
      LedgerMobileFailure.locationDisabled,
      'Location services are turned off.', // l10n-ignore: exception text
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
