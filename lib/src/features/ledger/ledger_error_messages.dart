import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'ledger_capability.dart';
import 'ledger_error_codes.dart';
import 'services/ledger_mobile_ble_service.dart';

/// Messages for failures that opening the app or changing transport cannot fix.
/// Status codes stay in Rust errors; the UI shows one only in the
/// unexpected-error fallback.
enum LedgerRequestKind {
  send,
  swap,
  payment,
  shield,
  migration,
  voting,
  giftCard,
}

const kLedgerSmallerTransferTitle = 'Ledger requires a smaller transfer';

const kLedgerHostRequestRejectedMessage =
    'Vizor built a request that the Zcash app on your Ledger could not accept. Go back and create a new request. Nothing was sent.';

const kLedgerViewingKeyRequestRejectedMessage =
    'The Zcash app on your Ledger could not accept this viewing-key request. Check the account number, then try again.';

/// Only transaction capacity limits are amount-related. For example, the
/// single BIP32 derivation limit cannot be fixed by reducing a payment.
bool ledgerRequestExceedsCapacity(Object error) =>
    classifyLedgerError(error) == LedgerFailureKind.capacityExceeded;

String? ledgerActionableErrorMessage(
  Object error, {
  LedgerRequestKind requestKind = LedgerRequestKind.send,
}) {
  if (ledgerPairingNeedsReset(error)) return kLedgerPairingInvalidMessage;
  final kind = classifyLedgerError(error);
  if (kind == LedgerFailureKind.capacityExceeded) {
    return switch (requestKind) {
      LedgerRequestKind.send =>
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
  if (kind == LedgerFailureKind.signatureMismatch) {
    return 'The signatures from this Ledger do not match this account. Connect the Ledger that holds this account, then try again.';
  }
  if (error.toString().toLowerCase().contains('ledger supports at most')) {
    return 'Your Ledger cannot sign this transaction format. Go back and create a new request.';
  }
  return switch (kind) {
    LedgerFailureKind.hostRequestRejected => switch (requestKind) {
      LedgerRequestKind.voting =>
        'Vizor built a vote request that the Zcash app on your Ledger could not accept. Your vote was not signed.',
      LedgerRequestKind.giftCard =>
        'Vizor built a gift card request that the Zcash app on your Ledger could not accept. Go back and create a new gift card. Nothing was sent.',
      _ => kLedgerHostRequestRejectedMessage,
    },
    LedgerFailureKind.appWrongState =>
      'Close and reopen the Zcash app on your Ledger, then try again.',
    LedgerFailureKind.deviceBusy =>
      'Your Ledger is busy. Wait a moment, then try again.',
    LedgerFailureKind.appNotInstalled =>
      'Install the Zcash app on your Ledger with Ledger Live, then try again.',
    LedgerFailureKind.pinNotSet =>
      'Set up a PIN on your Ledger, then try again.',
    LedgerFailureKind.appUpdateRequired =>
      'Update the Zcash app on your Ledger to $kMinimumLedgerZcashAppVersion or newer, then try again.',
    LedgerFailureKind.deviceInternalError ||
    LedgerFailureKind.unknownStatus => _unexpectedStatusMessage(error),
    _ => null,
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

/// Retrying the same request cannot succeed; the caller must build a new one
/// instead of offering a retry.
bool ledgerRequestNeedsRebuilding(Object error) {
  return switch (classifyLedgerError(error)) {
    LedgerFailureKind.hostRequestRejected ||
    LedgerFailureKind.capacityExceeded => true,
    _ => error.toString().toLowerCase().contains('ledger supports at most'),
  };
}
