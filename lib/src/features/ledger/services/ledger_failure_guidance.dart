import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../ledger_capability.dart';
import '../ledger_error_codes.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

/// The request a Ledger failure belongs to, for copy that names it.
enum LedgerRequestKind {
  send,
  swap,
  payment,
  shield,
  migration,
  voting,
  giftCard,
  viewingKey,
}

/// Device guidance travels with the caught error, never with a previous
/// attempt's global readiness state. Declines, cancellations, transport loss
/// and unknown transaction errors stay with the caller so storage, broadcast
/// and proposal recovery retain their own actions.
class LedgerFailureGuidance {
  const LedgerFailureGuidance(
    this.message, {
    this.showDeviceAppPrompt = false,
    this.bluetoothRecovery = false,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
    this.retryable = true,
  });

  final bool bluetoothRecovery;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final String message;
  final bool showDeviceAppPrompt;

  /// False when retrying the same request fails the same way on the device;
  /// the caller must build a new request instead of offering a retry.
  final bool retryable;
}

LedgerFailureGuidance? ledgerFailureGuidance(
  Object error, {
  LedgerRequestKind requestKind = LedgerRequestKind.send,
}) {
  if (error is LedgerConnectionRequiredException) {
    return (error.cause == null
            ? null
            : ledgerFailureGuidance(error.cause!, requestKind: requestKind)) ??
        LedgerFailureGuidance(error.message);
  }
  if (error is LedgerAppReadinessException) {
    return (error.cause == null
            ? null
            : ledgerFailureGuidance(error.cause!, requestKind: requestKind)) ??
        LedgerFailureGuidance(error.message);
  }
  if (error is LedgerMobileException) return _mobileGuidance(error);

  final failure = LedgerRequestFailure.fromError(error);
  return switch (failure) {
    LedgerRequestFailure.requestRejected ||
    LedgerRequestFailure.requestTooLarge => LedgerFailureGuidance(
      _rebuildMessage(error, requestKind),
      retryable: false,
    ),
    // Only a running other app is fixed by opening Zcash; install and update
    // failures need Ledger Live, so the open-app card would contradict them.
    LedgerRequestFailure.wrongApp => LedgerFailureGuidance(
      failure.message,
      showDeviceAppPrompt: true,
    ),
    LedgerRequestFailure.appNotInstalled ||
    LedgerRequestFailure.appUpdateRequired => LedgerFailureGuidance(
      failure.message,
    ),
    LedgerRequestFailure.unexpectedStatus => LedgerFailureGuidance(
      _unexpectedStatusMessage(error),
    ),
    LedgerRequestFailure.deviceLocked ||
    LedgerRequestFailure.pinNotSet ||
    LedgerRequestFailure.appWrongState ||
    LedgerRequestFailure.busy ||
    LedgerRequestFailure.signatureMismatch => LedgerFailureGuidance(
      failure.message,
    ),
    LedgerRequestFailure.declined ||
    LedgerRequestFailure.cancelled ||
    LedgerRequestFailure.transportLost ||
    LedgerRequestFailure.other => null,
  };
}

LedgerFailureGuidance _mobileGuidance(
  LedgerMobileException error,
) => switch (error.failure) {
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
  // Native unavailable messages can include instructions to finish a
  // pending device request. Preserve those instead of inventing a pairing
  // diagnosis.
  LedgerMobileFailure.unavailable => LedgerFailureGuidance(error.message),
};

/// How a failed Ledger request is presented, derived from the stable codes
/// [classifyLedgerError] reads. Pairing evidence and Bluetooth access
/// recovery remain separate from this presentation.
enum LedgerRequestFailure {
  declined,

  /// The app refused or could not parse a request Vizor built. Sending the
  /// same request again fails the same way.
  requestRejected,

  /// The request exceeds what the device can sign or hold in memory. Sending
  /// the same request again fails the same way.
  requestTooLarge,
  deviceLocked,
  pinNotSet,
  wrongApp,
  appNotInstalled,
  appUpdateRequired,
  appWrongState,
  busy,
  cancelled,
  transportLost,
  signatureMismatch,
  unexpectedStatus,
  other;

  static LedgerRequestFailure fromError(Object error) =>
      switch (classifyLedgerError(error)) {
        LedgerFailureKind.userRejected => declined,
        LedgerFailureKind.hostRequestRejected => requestRejected,
        LedgerFailureKind.capacityExceeded => requestTooLarge,
        LedgerFailureKind.deviceLocked => deviceLocked,
        LedgerFailureKind.pinNotSet => pinNotSet,
        LedgerFailureKind.wrongApp => wrongApp,
        LedgerFailureKind.appNotInstalled => appNotInstalled,
        LedgerFailureKind.appUpdateRequired => appUpdateRequired,
        LedgerFailureKind.appWrongState => appWrongState,
        LedgerFailureKind.deviceBusy => busy,
        LedgerFailureKind.cancelled => cancelled,
        LedgerFailureKind.transportLost ||
        LedgerFailureKind.usbPermission => transportLost,
        LedgerFailureKind.signatureMismatch => signatureMismatch,
        LedgerFailureKind.deviceInternalError ||
        LedgerFailureKind.unknownStatus => unexpectedStatus,
        LedgerFailureKind.saplingUnsupported || LedgerFailureKind.other =>
          _exceedsTransactionFormat(error) ? requestRejected : other,
      };

  /// Whether sending the same request again can succeed.
  bool get retryable => this != requestRejected && this != requestTooLarge;

  String get title => switch (this) {
    declined => 'Request declined',
    requestRejected => 'Request not accepted',
    requestTooLarge => 'Request too large',
    deviceLocked => 'Ledger locked',
    pinNotSet => 'PIN required',
    wrongApp => 'Open the Zcash app',
    appNotInstalled => 'Zcash app missing',
    appUpdateRequired => 'Update the Zcash app',
    appWrongState => 'Reopen the Zcash app',
    busy => 'Ledger is busy',
    cancelled => 'Request cancelled',
    transportLost => 'Ledger not reachable',
    signatureMismatch => 'Wrong Ledger',
    unexpectedStatus => 'Ledger error',
    other => 'Request failed',
  };

  String get message => switch (this) {
    declined => 'Declined on your Ledger. Try again when ready.',
    requestRejected => kLedgerHostRequestRejectedMessage,
    requestTooLarge => 'Too many inputs for your Ledger. Try a smaller amount.',
    deviceLocked => 'Unlock your Ledger, then try again.',
    pinNotSet => 'Set up a PIN on your Ledger, then try again.',
    wrongApp => 'Open the Zcash app on your Ledger.',
    appNotInstalled => 'Install the Zcash app with Ledger Live.',
    appUpdateRequired =>
      'Update the Zcash app to $kMinimumLedgerZcashAppVersion or newer.',
    appWrongState => 'Close and reopen the Zcash app.',
    busy => 'Your Ledger is busy. Try again in a moment.',
    cancelled => 'Request cancelled. Try again when ready.',
    transportLost => 'Reconnect and unlock your Ledger.',
    signatureMismatch => 'Connect the Ledger that holds this account.',
    unexpectedStatus =>
      'Unexpected Ledger error. Reopen the Zcash app and try again.',
    other => 'Check your Ledger and open the Zcash app, then try again.',
  };
}

const kLedgerHostRequestRejectedMessage =
    'Your Ledger couldn’t accept this request. Create a new one. Nothing was sent.';

const kLedgerViewingKeyRequestRejectedMessage =
    'Your Ledger couldn’t accept this viewing-key request. Check the account number.';

const kLedgerSaplingRecipientMessage =
    'Your Ledger can’t send to a Sapling address. Create a new request.';

// Rust rejects a transparent output with several BIP-32 derivations before
// any device exchange; its wallet-built message is the only evidence.
bool _exceedsTransactionFormat(Object error) =>
    error.toString().toLowerCase().contains('ledger supports at most');

String _rebuildMessage(Object error, LedgerRequestKind kind) {
  if (classifyLedgerError(error) == LedgerFailureKind.capacityExceeded) {
    return switch (kind) {
      LedgerRequestKind.send || LedgerRequestKind.viewingKey =>
        LedgerRequestFailure.requestTooLarge.message,
      LedgerRequestKind.swap =>
        'Start a new swap with a smaller amount. This one is discarded.',
      LedgerRequestKind.payment =>
        'Start a new payment. Don’t send a smaller amount to this address.',
      LedgerRequestKind.shield =>
        'Too many inputs for your Ledger. Try again. Nothing was shielded.',
      // The planner does not size steps by Ledger limits, and retrying sends
      // the same step.
      LedgerRequestKind.migration =>
        'This migration step is too large for your Ledger to sign. Vizor can’t split it yet.',
      // The round's bundle policy fixes the vote's size.
      LedgerRequestKind.voting =>
        'This vote is too large for your Ledger to sign.',
      LedgerRequestKind.giftCard =>
        'Too large for your Ledger. Create a gift card with a smaller amount.',
    };
  }
  if (_exceedsTransactionFormat(error)) {
    return 'Your Ledger can’t sign this transaction type. Create a new request.';
  }
  return switch (kind) {
    LedgerRequestKind.voting =>
      'Your Ledger couldn’t accept this vote request. Your vote was not signed.',
    LedgerRequestKind.giftCard =>
      'Your Ledger couldn’t accept this request. Create a new gift card. Nothing was sent.',
    LedgerRequestKind.viewingKey => kLedgerViewingKeyRequestRejectedMessage,
    _ => kLedgerHostRequestRejectedMessage,
  };
}

String _unexpectedStatusMessage(Object error) {
  final status = ledgerStatusWord(error);
  final code = status == null
      ? ''
      : ' (0x${status.toRadixString(16).padLeft(4, '0')})';
  return 'Unexpected Ledger error$code. Reopen the Zcash app and try again.';
}

String ledgerUsbPermissionMessage(TargetPlatform platform) {
  // Linux hidraw nodes stay root-only until a udev rule grants access.
  return platform == TargetPlatform.linux
      ? "Vizor cannot access your Ledger over USB. Install Ledger's udev rules for Linux (github.com/LedgerHQ/udev-rules), then reconnect your Ledger and try again."
      : 'Vizor cannot access your Ledger over USB. Check USB device permissions, then reconnect and try again.';
}

/// Tells the Rust USB transport's failures apart, so "no Ledger plugged in"
/// never reads as "Vizor cannot open the Ledger" or as a device rejection.
String? ledgerUsbErrorMessage(
  Object error, {
  required String appInstruction,
  TargetPlatform? platform,
}) {
  if (!isLedgerUsbTransportError(error)) return null;
  final text = error.toString().toLowerCase();
  if (text.contains('no ledger device')) {
    return 'Connect and unlock your Ledger. $appInstruction';
  }
  if (text.contains('open ledger hid device')) {
    if (text.contains('permission denied') ||
        text.contains('access is denied') ||
        text.contains('access denied')) {
      return ledgerUsbPermissionMessage(platform ?? defaultTargetPlatform);
    }
    return 'Vizor found your Ledger but could not open it. Close other wallet apps that use the Ledger, reconnect it, then try again.';
  }
  if (text.contains('initialize ledger hid')) {
    return 'Vizor could not start USB access for your Ledger. Reconnect the device, then try again.';
  }
  return 'The USB connection to your Ledger was interrupted. Reconnect and unlock your Ledger, then try again.';
}
