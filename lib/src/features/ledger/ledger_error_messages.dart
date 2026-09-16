import 'package:flutter/foundation.dart' show TargetPlatform;

String ledgerUsbPermissionMessage(TargetPlatform platform) {
  // Linux hidraw nodes stay root-only until a udev rule grants access.
  return platform == TargetPlatform.linux
      ? "Vizor cannot access your Ledger over USB. Install Ledger's udev rules for Linux (github.com/LedgerHQ/udev-rules), then reconnect your Ledger and try again."
      : 'Vizor cannot access your Ledger over USB. Check USB device permissions, then reconnect and try again.';
}
