import 'package:flutter/foundation.dart' show TargetPlatform;

/// True only for device transaction-shape limits that a smaller proposal can
/// resolve. Other Ledger format restrictions must keep their original error.
bool ledgerRequestExceedsCapacity(Object error) =>
    error.toString().contains('VIZOR_LEDGER_CAPACITY:') ||
    RegExp(
      r'ledger supports at most \d+ (transparent inputs|transparent outputs|shielded actions); found \d+',
    ).hasMatch(error.toString().toLowerCase());

bool ledgerRequestNeedsRebuilding(Object error) {
  final text = error.toString().toLowerCase();
  return ledgerRequestExceedsCapacity(error) ||
      text.contains('ledger supports at most') ||
      text.contains('0x6986');
}

String ledgerUsbPermissionMessage(TargetPlatform platform) {
  // Linux hidraw nodes stay root-only until a udev rule grants access.
  return platform == TargetPlatform.linux
      ? "Vizor cannot access your Ledger over USB. Install Ledger's udev rules for Linux (github.com/LedgerHQ/udev-rules), then reconnect your Ledger and try again."
      : 'Vizor cannot access your Ledger over USB. Check USB device permissions, then reconnect and try again.';
}
