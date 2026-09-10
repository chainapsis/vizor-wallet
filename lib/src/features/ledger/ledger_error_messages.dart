import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Messages for failures that opening the app or changing transport cannot fix.
/// Keep status codes in the Rust error for diagnostics, not in the UI copy.
enum LedgerRequestKind { send, swap, payment, shield, migration, voting }

const kLedgerSmallerTransferTitle = 'Ledger requires a smaller transfer';

/// The connected device is a different Ledger wallet; checked before any
/// approval is requested.
const kLedgerWrongWalletMessage =
    'This Ledger does not hold this account. Connect the Ledger that holds this account, then try again.';

/// Only transaction capacity limits are amount-related. For example, the
/// single BIP32 derivation limit cannot be fixed by reducing a payment.
bool ledgerRequestExceedsCapacity(Object error) =>
    error.toString().contains('VIZOR_LEDGER_CAPACITY:') ||
    RegExp(
      r'ledger supports at most \d+ (transparent inputs|transparent outputs|shielded actions); found \d+',
    ).hasMatch(error.toString().toLowerCase());

String? ledgerActionableErrorMessage(
  Object error, {
  LedgerRequestKind requestKind = LedgerRequestKind.send,
}) {
  final text = error.toString().toLowerCase();
  if (ledgerRequestExceedsCapacity(error)) {
    return switch (requestKind) {
      LedgerRequestKind.send =>
        'This transfer includes more inputs or outputs than your Ledger can sign at once. Go back and try a smaller amount.',
      LedgerRequestKind.swap =>
        'This deposit is too large for your Ledger to sign at once. Start a new swap with a smaller amount and review the new quote. Nothing was sent for this request.',
      LedgerRequestKind.payment =>
        'This payment is too large for your Ledger to sign at once. Go back and arrange a smaller payment or use another payment method. Do not send a smaller amount to this payment address.',
      LedgerRequestKind.shield =>
        'This shielding request includes more inputs than your Ledger can sign at once. Vizor cannot split this request yet. Return to your wallet; nothing was shielded for this request.',
      LedgerRequestKind.migration =>
        'This migration request exceeds your Ledger’s signing limit. Return to review. Retrying the same request will not reduce its size.',
      LedgerRequestKind.voting =>
        'This voting request exceeds your Ledger’s signing limit. Your vote was not signed. Changing a transfer amount will not fix this voting request.',
    };
  }
  if (text.contains('does not hold this account')) {
    return kLedgerWrongWalletMessage;
  }
  if ((text.contains('apply ledger') && text.contains('signature at action')) ||
      text.contains('validate ledger transparent signature')) {
    // The device signed, but its keys are not this account's keys.
    return 'The signatures from this Ledger do not match this account. Connect the Ledger that holds this account, then try again.';
  }
  if (text.contains('ledger supports at most')) {
    return 'Your Ledger cannot sign this transaction format. Go back and create a new request.';
  }
  if (text.contains('0x6986')) {
    return 'Ledger could not approve this transaction. Check the selected account, then go back and create a new request.';
  }
  if (text.contains('0x6f01')) {
    return 'Vizor could not read the Zcash app version. Close and reopen the app on your Ledger, then try again.';
  }
  if (text.contains('0x6f03')) {
    return 'The Zcash app could not prepare this request. Close and reopen the app on your Ledger, then try again.';
  }
  return null;
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
  final text = error.toString().toLowerCase();
  if (text.contains('no ledger device found')) {
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
  if (text.contains('ledger hid')) {
    return 'The USB connection to your Ledger was interrupted. Reconnect and unlock your Ledger, then try again.';
  }
  return null;
}

/// Shown on the home card while a Ledger account holds more transparent
/// inputs than one device approval can sign; shielding then asks for the
/// approvals one after another.
String ledgerShieldingInputLimitMessage({
  required int inputCount,
  required int limit,
}) {
  final approvals = (inputCount + limit - 1) ~/ limit;
  return 'Ledger shields up to $limit transparent inputs per approval. '
      'Shielding all $inputCount inputs takes $approvals approvals in a row on your Ledger.';
}

bool ledgerRequestNeedsRebuilding(Object error) {
  final text = error.toString().toLowerCase();
  return ledgerRequestExceedsCapacity(error) ||
      text.contains('ledger supports at most') ||
      text.contains('0x6986');
}
