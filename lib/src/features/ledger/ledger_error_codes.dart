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

  /// 0x6e00, 0x6d00.
  unsupportedCommand,

  /// 0x5223.
  deviceInternalError,

  /// Any other status word.
  unknownStatus,
  cancelled,
  capacityExceeded,
  usbPermission,
  transportLost,
  saplingUnsupported,
  other,
}

final _statusWordPattern = RegExp(r'ledger_status_([0-9a-f]{4}):');

// Transaction-count limits only; the per-output derivation limit is not one.
final _legacyCapacityPattern = RegExp(
  r'ledger supports at most \d+ (transparent inputs|transparent outputs|shielded actions); found \d+',
);

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
      0x6e00 || 0x6d00 => LedgerFailureKind.unsupportedCommand,
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
        LedgerFailureKind.unsupportedCommand,
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
      LedgerMobileFailure.wrongApp ||
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
  if (raw.contains('ledger_linux_usb_access')) {
    return LedgerFailureKind.usbPermission;
  }

  // Unprefixed text from older builds, native layers, and test doubles.
  final lower = raw.toLowerCase();
  if (_legacyCapacityPattern.hasMatch(lower)) {
    return LedgerFailureKind.capacityExceeded;
  }
  if (lower.contains('0x6a80') ||
      lower.contains('pczt data') ||
      lower.contains('0x6986')) {
    return LedgerFailureKind.hostRequestRejected;
  }
  if (lower.contains('sapling')) return LedgerFailureKind.saplingUnsupported;
  if (lower.contains('rejected') || lower.contains('6985')) {
    return LedgerFailureKind.userRejected;
  }
  if (lower.contains('locked') || lower.contains('5515')) {
    return LedgerFailureKind.deviceLocked;
  }
  if (lower.contains('no ledger') ||
      lower.contains('not found') ||
      lower.contains('no device') ||
      lower.contains('hid') ||
      lower.contains('disconnect') ||
      lower.contains('bluetooth')) {
    return LedgerFailureKind.transportLost;
  }
  if (lower.contains('denied')) return LedgerFailureKind.userRejected;
  return LedgerFailureKind.other;
}

Object? _cause(Object error) => switch (error) {
  LedgerConnectionRequiredException(:final cause) => cause,
  LedgerAppReadinessException(:final cause) => cause,
  _ => null,
};
