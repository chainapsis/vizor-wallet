# Ledger Bluetooth on Linux

Vizor's Linux runner connects to Ledger devices through BlueZ over the system
D-Bus. The handler provides discovery, pairing confirmation, connection state,
Zcash app preparation, UFVK exchange, cancellation, and disconnect draining for
the shared Dart Ledger connection flow.

## Runtime requirements

- A Bluetooth LE adapter and a running BlueZ service are required.
- Pairing uses a scoped `org.bluez.Agent1` and asks the user to compare the
  six-digit code shown by Vizor with the code on the Ledger.
- Discovery lists Ledgers seen during the current scan or already connected.
- Cancelling an operation wakes the blocked BlueZ worker but keeps the operation
  gate occupied until cleanup finishes. Disconnect waits for that drain before
  reporting success.

This extraction supports app discovery and UFVK import. Generic multi-APDU
signing remains outside this change and is added with the Ledger signing flow.

## Host tests

`linux/runner/tests/run_ledger_ble_tests.sh` builds the transport and channel
tests against a private fake BlueZ D-Bus. It can run on Linux or macOS with
GLib, GIO, and `dbus-daemon` installed. These tests do not verify a full Linux
desktop build, distribution packaging, a real BlueZ service, or physical Ledger
hardware.
