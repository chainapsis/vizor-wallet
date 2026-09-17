import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_codes.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

String _status(int status, String text) =>
    'ledger_status_${status.toRadixString(16).padLeft(4, '0')}: $text';

void main() {
  test('every mapped status word resolves to its failure kind', () {
    const table = {
      0x6985: LedgerFailureKind.userRejected,
      0x5501: LedgerFailureKind.userRejected,
      0x5515: LedgerFailureKind.deviceLocked,
      0x6982: LedgerFailureKind.deviceLocked,
      0x5303: LedgerFailureKind.deviceLocked,
      0x5502: LedgerFailureKind.pinNotSet,
      0x6807: LedgerFailureKind.appNotInstalled,
      0x6601: LedgerFailureKind.deviceBusy,
      0x6901: LedgerFailureKind.deviceBusy,
      0xb007: LedgerFailureKind.appWrongState,
      0x6a80: LedgerFailureKind.hostRequestRejected,
      0x6986: LedgerFailureKind.hostRequestRejected,
      0x6e00: LedgerFailureKind.unsupportedCommand,
      0x6d00: LedgerFailureKind.unsupportedCommand,
      0x5223: LedgerFailureKind.deviceInternalError,
      0x670a: LedgerFailureKind.unknownStatus,
      0x6f01: LedgerFailureKind.unknownStatus,
    };
    for (final MapEntry(key: status, value: kind) in table.entries) {
      final error = StateError(_status(status, 'device text'));
      expect(ledgerStatusWord(error), status);
      expect(ledgerFailureKindForStatusWord(status), kind);
      expect(classifyLedgerError(error), kind, reason: '0x$status');
    }
  });

  test('status code wins over rejection wording in the message text', () {
    const error =
        'ledger_status_6a80: Ledger rejected the PCZT data or key path';
    expect(classifyLedgerError(error), LedgerFailureKind.hostRequestRejected);
    expect(
      classifyLedgerError(
        'Ledger did not become ready in Zcash after switching apps: '
        'ledger_status_6601: Ledger device is busy switching apps; retry shortly',
      ),
      LedgerFailureKind.deviceBusy,
    );
    expect(ledgerStatusWord('ledger_status_6A80: uppercase'), isNull);
    expect(ledgerStatusWord('ledger_status_6a8: short'), isNull);
  });

  test('cancellation, capacity, and USB access prefixes are classified', () {
    expect(
      classifyLedgerError(
        'ledger_cancelled: Ledger operation was cancelled. Retry when ready.',
      ),
      LedgerFailureKind.cancelled,
    );
    expect(
      classifyLedgerError(
        'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33',
      ),
      LedgerFailureKind.capacityExceeded,
    );
    expect(
      classifyLedgerError(
        'ledger_linux_usb_access: No Ledger device found. Check the Ledger udev rules and reconnect the device.',
      ),
      LedgerFailureKind.usbPermission,
    );
  });

  test('typed exceptions classify by their failure, not their text', () {
    const mobile = {
      LedgerMobileFailure.busy: LedgerFailureKind.deviceBusy,
      LedgerMobileFailure.permissionDenied: LedgerFailureKind.transportLost,
      LedgerMobileFailure.bluetoothOff: LedgerFailureKind.transportLost,
      LedgerMobileFailure.pairingRejected: LedgerFailureKind.transportLost,
      LedgerMobileFailure.pairingInvalid: LedgerFailureKind.transportLost,
      LedgerMobileFailure.disconnected: LedgerFailureKind.transportLost,
      LedgerMobileFailure.locked: LedgerFailureKind.deviceLocked,
      LedgerMobileFailure.rejected: LedgerFailureKind.userRejected,
      LedgerMobileFailure.wrongApp: LedgerFailureKind.other,
      LedgerMobileFailure.cancelled: LedgerFailureKind.cancelled,
      LedgerMobileFailure.unavailable: LedgerFailureKind.other,
    };
    expect(mobile.keys, containsAll(LedgerMobileFailure.values));
    for (final MapEntry(key: failure, value: kind) in mobile.entries) {
      expect(
        classifyLedgerError(LedgerMobileException(failure, 'rejected 6985')),
        kind,
      );
    }

    const readiness = {
      LedgerAppReadinessFailure.busy: LedgerFailureKind.deviceBusy,
      LedgerAppReadinessFailure.rejected: LedgerFailureKind.userRejected,
      LedgerAppReadinessFailure.locked: LedgerFailureKind.deviceLocked,
      LedgerAppReadinessFailure.disconnected: LedgerFailureKind.transportLost,
      LedgerAppReadinessFailure.unsupportedVersion:
          LedgerFailureKind.unsupportedCommand,
      LedgerAppReadinessFailure.unavailable: LedgerFailureKind.other,
    };
    expect(readiness.keys, containsAll(LedgerAppReadinessFailure.values));
    for (final MapEntry(key: failure, value: kind) in readiness.entries) {
      expect(
        classifyLedgerError(LedgerAppReadinessException(failure, 'message')),
        kind,
      );
    }
  });

  test('wrapped exceptions classify by the error they were built from', () {
    const notInstalled =
        'ledger_status_6807: The Zcash app is not installed on this Ledger';
    const readiness = LedgerAppReadinessException(
      LedgerAppReadinessFailure.unavailable,
      'Install the Zcash app on your Ledger with Ledger Live, then try again.',
      cause: notInstalled,
    );
    expect(classifyLedgerError(readiness), LedgerFailureKind.appNotInstalled);
    expect(ledgerStatusWord(readiness), 0x6807);
    expect(
      classifyLedgerError(
        const LedgerConnectionRequiredException('Reconnect.', cause: readiness),
      ),
      LedgerFailureKind.appNotInstalled,
    );
    expect(
      classifyLedgerError(
        const LedgerAppReadinessException(
          LedgerAppReadinessFailure.rejected,
          'The Ledger operation was cancelled.',
          cause: LedgerMobileException(
            LedgerMobileFailure.cancelled,
            'The Ledger operation was cancelled.',
          ),
        ),
      ),
      LedgerFailureKind.cancelled,
    );
    expect(
      classifyLedgerError(const LedgerConnectionRequiredException('Connect.')),
      LedgerFailureKind.transportLost,
    );
    expect(
      classifyLedgerError(
        const LedgerConnectionRequiredException(
          'Connect.',
          cause: LedgerAppReadinessException(
            LedgerAppReadinessFailure.unavailable,
            'Open the Zcash app on your Ledger, then try again.',
          ),
        ),
      ),
      LedgerFailureKind.transportLost,
    );
  });

  test('unprefixed legacy text keeps its established classification', () {
    const legacy = {
      'User rejected (0x6985)': LedgerFailureKind.userRejected,
      '6985 rejected': LedgerFailureKind.userRejected,
      'Ledger request rejected on device': LedgerFailureKind.userRejected,
      'Ledger rejected the PCZT data or key path':
          LedgerFailureKind.hostRequestRejected,
      'Ledger signing preconditions were not met (0x6986)':
          LedgerFailureKind.hostRequestRejected,
      'status 0x6a80': LedgerFailureKind.hostRequestRejected,
      'Ledger supports at most 32 shielded actions; found 33':
          LedgerFailureKind.capacityExceeded,
      'This Ledger preview does not support Sapling outputs':
          LedgerFailureKind.saplingUnsupported,
      'Ledger device is locked': LedgerFailureKind.deviceLocked,
      'No Ledger device found. Connect and unlock your Ledger.':
          LedgerFailureKind.transportLost,
      "Open Ledger HID device: hidapi error: Failed to open a device with path '/dev/hidraw3': Permission denied":
          LedgerFailureKind.transportLost,
      'Read Ledger HID packet: hidapi error: device disconnected':
          LedgerFailureKind.transportLost,
      'request denied': LedgerFailureKind.userRejected,
      'Ledger supports at most one BIP-32 derivation per transparent output; found 2':
          LedgerFailureKind.other,
      'Ledger Zcash app returned status 0x6f01': LedgerFailureKind.other,
      'network unavailable': LedgerFailureKind.other,
    };
    for (final MapEntry(key: error, value: kind) in legacy.entries) {
      expect(classifyLedgerError(StateError(error)), kind, reason: error);
      expect(ledgerStatusWord(error), isNull, reason: error);
    }
  });
}
