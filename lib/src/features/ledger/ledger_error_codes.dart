import 'services/ledger_app_readiness_service.dart';
import 'services/ledger_connection_service.dart';
import 'services/ledger_mobile_ble_service.dart';

/// Why a Ledger request failed. Status-word kinds come from the stable
/// `ledger_status_xxxx:` prefix Rust puts on every device status error.
enum LedgerFailureKind {
  /// 0x6985, 0x5501: the user declined on the device.
  userRejected,

  /// 0x5515, 0x6982, 0x5303.
  deviceLocked,

  /// 0x5502.
  pinNotSet,

  /// 0x6807.
  appNotInstalled,

  /// 0x6601, 0x6901.
  deviceBusy,

  /// 0xb007.
  appWrongState,

  /// 0x6a80, 0x6986: the app refused data Vizor built, not a user decision.
  hostRequestRejected,

  /// 0x6e00, 0x6d00: the running app does not know the command, so another
  /// app or the dashboard is open instead of Zcash.
  wrongApp,

  /// The Zcash app is older than Vizor supports. Only the typed readiness
  /// check reports this; no device status word means it.
  appUpdateRequired,

  /// 0x5223.
  deviceInternalError,

  /// Any other status word.
  unknownStatus,
  cancelled,
  capacityExceeded,

  /// The signatures verify against keys other than this account's.
  signatureMismatch,
  usbPermission,
  transportLost,
  saplingUnsupported,
  other,
}

final _statusWordPattern = RegExp(r'ledger_status_([0-9a-f]{4}):');

/// The device status word carried by [error], including wrapped causes.
int? ledgerStatusWord(Object error) {
  final cause = _cause(error);
  if (cause != null) return ledgerStatusWord(cause);
  final match = _statusWordPattern.firstMatch(error.toString());
  return match == null ? null : int.parse(match.group(1)!, radix: 16);
}

LedgerFailureKind ledgerFailureKindForStatusWord(int status) =>
    switch (status) {
      0x6985 || 0x5501 => LedgerFailureKind.userRejected,
      0x5515 || 0x6982 || 0x5303 => LedgerFailureKind.deviceLocked,
      0x5502 => LedgerFailureKind.pinNotSet,
      0x6807 => LedgerFailureKind.appNotInstalled,
      0x6601 || 0x6901 => LedgerFailureKind.deviceBusy,
      0xb007 => LedgerFailureKind.appWrongState,
      0x6a80 || 0x6986 => LedgerFailureKind.hostRequestRejected,
      0x6e00 || 0x6d00 => LedgerFailureKind.wrongApp,
      0x5223 => LedgerFailureKind.deviceInternalError,
      _ => LedgerFailureKind.unknownStatus,
    };

LedgerFailureKind classifyLedgerError(Object error) {
  if (error is LedgerConnectionRequiredException) {
    final cause = error.cause;
    final kind = cause == null ? null : classifyLedgerError(cause);
    return kind == null || kind == LedgerFailureKind.other
        ? LedgerFailureKind.transportLost
        : kind;
  }
  if (error is LedgerAppReadinessException) {
    final cause = error.cause;
    if (cause != null) return classifyLedgerError(cause);
    return switch (error.failure) {
      LedgerAppReadinessFailure.busy => LedgerFailureKind.deviceBusy,
      LedgerAppReadinessFailure.rejected => LedgerFailureKind.userRejected,
      LedgerAppReadinessFailure.locked => LedgerFailureKind.deviceLocked,
      LedgerAppReadinessFailure.disconnected => LedgerFailureKind.transportLost,
      LedgerAppReadinessFailure.unsupportedVersion =>
        LedgerFailureKind.appUpdateRequired,
      LedgerAppReadinessFailure.unavailable => LedgerFailureKind.other,
    };
  }
  if (error is LedgerMobileException) {
    return switch (error.failure) {
      LedgerMobileFailure.busy => LedgerFailureKind.deviceBusy,
      LedgerMobileFailure.permissionDenied ||
      LedgerMobileFailure.bluetoothOff ||
      LedgerMobileFailure.pairingRejected ||
      LedgerMobileFailure.pairingInvalid ||
      LedgerMobileFailure.disconnected => LedgerFailureKind.transportLost,
      LedgerMobileFailure.locked => LedgerFailureKind.deviceLocked,
      LedgerMobileFailure.rejected => LedgerFailureKind.userRejected,
      LedgerMobileFailure.cancelled => LedgerFailureKind.cancelled,
      LedgerMobileFailure.wrongApp => LedgerFailureKind.wrongApp,
      LedgerMobileFailure.unavailable => LedgerFailureKind.other,
    };
  }

  final status = ledgerStatusWord(error);
  if (status != null) return ledgerFailureKindForStatusWord(status);

  final raw = error.toString();
  if (raw.contains('ledger_cancelled:')) return LedgerFailureKind.cancelled;
  if (raw.contains('ledger_capacity:')) {
    return LedgerFailureKind.capacityExceeded;
  }
  if (raw.contains('ledger_signature_mismatch:')) {
    return LedgerFailureKind.signatureMismatch;
  }
  if (raw.contains('ledger_linux_usb_access')) {
    return LedgerFailureKind.usbPermission;
  }

  // Device decisions always carry a code; wording such as "rejected" or
  // "not found" also appears in wallet and network failures.
  if (raw.toLowerCase().contains('sapling')) {
    return LedgerFailureKind.saplingUnsupported;
  }
  if (isLedgerUsbTransportError(error)) return LedgerFailureKind.transportLost;
  return LedgerFailureKind.other;
}

/// Whether [error] is a USB HID transport failure: prefixed by Rust, or HID
/// wording from builds before the prefix that no network error uses.
bool isLedgerUsbTransportError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('ledger_transport:') ||
      lower.contains('ledger_linux_usb_access') ||
      lower.contains('no ledger device') ||
      lower.contains('ledger hid') ||
      lower.contains('hidapi');
}

Object? _cause(Object error) => switch (error) {
  LedgerConnectionRequiredException(:final cause) => cause,
  LedgerAppReadinessException(:final cause) => cause,
  _ => null,
};
