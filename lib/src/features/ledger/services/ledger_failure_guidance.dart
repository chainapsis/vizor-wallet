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
    LedgerRequestFailure.requestRejected => LedgerFailureGuidance(
      _requestRejectedMessage(error, requestKind),
      retryable: false,
    ),
    LedgerRequestFailure.wrongApp ||
    LedgerRequestFailure.appNotInstalled ||
    LedgerRequestFailure.appUpdateRequired => LedgerFailureGuidance(
      failure.message,
      showDeviceAppPrompt: true,
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

  /// The app refused a request Vizor built, or the request exceeds what the
  /// device can sign. Sending the same request again fails the same way.
  requestRejected,
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
        LedgerFailureKind.hostRequestRejected ||
        LedgerFailureKind.capacityExceeded => requestRejected,
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
  bool get retryable => this != requestRejected;

  String get title => switch (this) {
    declined => 'Request declined',
    requestRejected => 'Request could not be accepted',
    deviceLocked => 'Unlock your Ledger',
    pinNotSet => 'Set up a PIN on your Ledger',
    wrongApp => 'Open the Zcash app',
    appNotInstalled => 'Install the Zcash app',
    appUpdateRequired => 'Update the Zcash app',
    appWrongState => 'Reopen the Zcash app',
    busy => 'Your Ledger is busy',
    cancelled => 'Request cancelled',
    transportLost => 'Couldn’t reach your Ledger',
    signatureMismatch => 'This Ledger doesn’t match',
    unexpectedStatus || other => 'Couldn’t complete the request',
  };

  String get message => switch (this) {
    declined =>
      'The request appears to have been declined on your Ledger. Try again when you’re ready.',
    requestRejected => kLedgerHostRequestRejectedMessage,
    deviceLocked => 'Unlock your Ledger, then try again.',
    pinNotSet => 'Set up a PIN on your Ledger, then try again.',
    wrongApp => 'Open the Zcash app on your Ledger, then try again.',
    appNotInstalled =>
      'Install the Zcash app on your Ledger with Ledger Live, then try again.',
    appUpdateRequired =>
      'Update the Zcash app on your Ledger to $kMinimumLedgerZcashAppVersion or newer, then try again.',
    appWrongState =>
      'Close and reopen the Zcash app on your Ledger, then try again.',
    busy => 'Your Ledger is busy. Wait a moment, then try again.',
    cancelled => 'The Ledger request was cancelled. Try again when ready.',
    transportLost => 'Reconnect and unlock your Ledger, then try again.',
    signatureMismatch =>
      'The signatures from this Ledger do not match this account. Connect the Ledger that holds this account, then try again.',
    unexpectedStatus =>
      'Your Ledger returned an unexpected error. Close and reopen the Zcash app, then try again.',
    other =>
      'Check your Ledger and make sure the Zcash app is open, then try again.',
  };
}

const kLedgerHostRequestRejectedMessage =
    'Vizor built a request that the Zcash app on your Ledger could not accept. Go back and create a new request. Nothing was sent.';

const kLedgerViewingKeyRequestRejectedMessage =
    'The Zcash app on your Ledger could not accept this viewing-key request. Check the account number, then try again.';

// Rust rejects a transparent output with several BIP-32 derivations before
// any device exchange; its wallet-built message is the only evidence.
bool _exceedsTransactionFormat(Object error) =>
    error.toString().toLowerCase().contains('ledger supports at most');

String _requestRejectedMessage(Object error, LedgerRequestKind kind) {
  if (classifyLedgerError(error) == LedgerFailureKind.capacityExceeded) {
    return switch (kind) {
      LedgerRequestKind.send || LedgerRequestKind.viewingKey =>
        'This transfer includes more inputs or outputs than your Ledger can sign at once. Go back and try a smaller amount.',
      LedgerRequestKind.swap =>
        'This deposit is too large for your Ledger to sign at once. Start a new swap with a smaller amount and review the new quote. Nothing was sent for this request.',
      LedgerRequestKind.payment =>
        'This payment is too large for your Ledger to sign at once. Go back and arrange a smaller payment or use another payment method. Do not send a smaller amount to this payment address.',
      LedgerRequestKind.shield =>
        'This shielding request includes more inputs than your Ledger can sign at once. Return to your wallet and try again; nothing was shielded for this approval.',
      LedgerRequestKind.migration =>
        'This migration request exceeds your Ledger’s signing limit. Return to review. Retrying the same request will not reduce its size.',
      LedgerRequestKind.voting =>
        'This voting request exceeds your Ledger’s signing limit. Your vote was not signed. Changing a transfer amount will not fix this voting request.',
      LedgerRequestKind.giftCard =>
        'This gift card includes more inputs or outputs than your Ledger can sign at once. Go back and create a gift card with a smaller amount.',
    };
  }
  if (_exceedsTransactionFormat(error)) {
    return 'Your Ledger cannot sign this transaction format. Go back and create a new request.';
  }
  return switch (kind) {
    LedgerRequestKind.voting =>
      'Vizor built a vote request that the Zcash app on your Ledger could not accept. Your vote was not signed.',
    LedgerRequestKind.giftCard =>
      'Vizor built a gift card request that the Zcash app on your Ledger could not accept. Go back and create a new gift card. Nothing was sent.',
    LedgerRequestKind.viewingKey => kLedgerViewingKeyRequestRejectedMessage,
    _ => kLedgerHostRequestRejectedMessage,
  };
}

String _unexpectedStatusMessage(Object error) {
  final status = ledgerStatusWord(error);
  final code = status == null
      ? ''
      : ' (0x${status.toRadixString(16).padLeft(4, '0')})';
  return 'Your Ledger returned an unexpected error$code. Close and reopen the Zcash app, then try again.';
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
