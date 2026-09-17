import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

/// Device guidance travels with the caught error, never with a previous
/// attempt's global readiness state. Unknown transaction errors stay with the
/// caller so storage, broadcast and proposal recovery retain their own actions.
class LedgerFailureGuidance {
  const LedgerFailureGuidance(
    this.message, {
    this.showDeviceAppPrompt = false,
    this.bluetoothRecovery = false,
  });

  final bool bluetoothRecovery;
  final String message;
  final bool showDeviceAppPrompt;
}

LedgerFailureGuidance? ledgerFailureGuidance(Object error) {
  if (error is LedgerConnectionRequiredException) {
    return (error.cause == null ? null : ledgerFailureGuidance(error.cause!)) ??
        LedgerFailureGuidance(error.message);
  }
  if (error is LedgerAppReadinessException) {
    return (error.cause == null ? null : ledgerFailureGuidance(error.cause!)) ??
        LedgerFailureGuidance(error.message);
  }
  if (error is! LedgerMobileException) return null;
  return switch (error.failure) {
    LedgerMobileFailure.permissionDenied => const LedgerFailureGuidance(
      'Check Bluetooth access below, then try connecting to your Ledger again.',
      bluetoothRecovery: true,
    ),
    LedgerMobileFailure.locationDisabled => const LedgerFailureGuidance(
      'Turn on location services to find your Ledger on this Android version, then try again.',
      bluetoothRecovery: true,
    ),
    LedgerMobileFailure.bluetoothOff => const LedgerFailureGuidance(
      'Turn on Bluetooth, then try again.',
      bluetoothRecovery: true,
    ),
    LedgerMobileFailure.pairingInvalid => const LedgerFailureGuidance(
      kLedgerPairingInvalidMessage,
    ),
    LedgerMobileFailure.pairingRejected => const LedgerFailureGuidance(
      'Bluetooth pairing was not completed. Reconnect your Ledger and approve the pairing request, then try again.',
    ),
    LedgerMobileFailure.disconnected => const LedgerFailureGuidance(
      'The Bluetooth connection to your Ledger was lost or could not be established. Turn on and unlock your Ledger, keep it nearby, then try again.',
    ),
    LedgerMobileFailure.busy => const LedgerFailureGuidance(
      'Another Ledger request is still active. Complete or reject it on your Ledger, then try again.',
    ),
    LedgerMobileFailure.locked => const LedgerFailureGuidance(
      'Unlock your Ledger, then try again.',
    ),
    LedgerMobileFailure.rejected => const LedgerFailureGuidance(
      'The request was rejected on your Ledger. Try again when ready.',
    ),
    LedgerMobileFailure.cancelled => const LedgerFailureGuidance(
      'The Ledger request was cancelled. Try again when ready.',
    ),
    LedgerMobileFailure.wrongApp => LedgerFailureGuidance(
      error.message,
      showDeviceAppPrompt: true,
    ),
    // Native unavailable messages can include instructions to finish a pending
    // device request. Preserve those instead of inventing a pairing diagnosis.
    LedgerMobileFailure.unavailable => LedgerFailureGuidance(error.message),
  };
}
