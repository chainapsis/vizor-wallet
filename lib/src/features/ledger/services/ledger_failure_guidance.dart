import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';
import '../ledger_memo_policy.dart';

/// Device guidance travels with the caught error, never with a previous
/// attempt's global readiness state. Unknown transaction errors stay with the
/// caller so storage, broadcast and proposal recovery retain their own actions.
class LedgerFailureGuidance {
  const LedgerFailureGuidance(
    this.message, {
    this.showDeviceAppPrompt = false,
    this.bluetoothRecovery = false,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
  });

  final bool bluetoothRecovery;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final String message;
  final bool showDeviceAppPrompt;
}

LedgerFailureGuidance? ledgerFailureGuidance(Object error) {
  if (error.toString().contains(ledgerMemoUnsupportedError)) {
    return const LedgerFailureGuidance(ledgerMemoUnsupportedError);
  }
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
      pairingInvalid: true,
      pairingRecovery: true,
    ),
    LedgerMobileFailure.pairingRejected => const LedgerFailureGuidance(
      'Bluetooth pairing was not completed. Reconnect your Ledger and approve the pairing request, then try again.',
      pairingRecovery: true,
    ),
    LedgerMobileFailure.disconnected => const LedgerFailureGuidance(
      'The Bluetooth connection to your Ledger was lost or could not be established. Turn on and unlock your Ledger, keep it nearby, then try again.',
      pairingRecovery: true,
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

/// Two presentations for the general request-failure surface. Pairing evidence
/// and Bluetooth access recovery remain separate from this presentation.
enum LedgerRequestFailure {
  declined,
  other;

  static LedgerRequestFailure fromError(Object error) {
    if (error is LedgerConnectionRequiredException) {
      return error.cause == null ? other : fromError(error.cause!);
    }
    if (error is LedgerAppReadinessException) {
      return error.cause == null
          ? (error.failure == LedgerAppReadinessFailure.rejected
                ? declined
                : other)
          : fromError(error.cause!);
    }
    if (error is LedgerMobileException) {
      return error.failure == LedgerMobileFailure.rejected ? declined : other;
    }
    // Rust APDU parsing currently returns text. This is an estimate, not proof
    // that the user pressed Reject (e.g. 0x6985 can also mean an unfinished PCZT).
    final message = error.toString().toLowerCase();
    return message.contains('rejected') || message.contains('6985')
        ? declined
        : other;
  }

  String get title => switch (this) {
    declined => 'Request declined',
    other => 'Couldn’t complete the request',
  };

  String get message => switch (this) {
    declined =>
      'The request appears to have been declined on your Ledger. Try again when you’re ready.',
    other =>
      'Check your Ledger and make sure the Zcash app is open, then try again.',
  };
}
