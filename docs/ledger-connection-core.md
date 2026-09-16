# Ledger connection coordination

C03 is a stacked draft on C02 (`rowan/ledger-core-accounts`, PR #696).
It adds the transport-neutral Dart contracts that the native BLE adapters and
later signing flows consume. It does not add a native adapter or a screen.

## Behavior

- USB and Bluetooth account connectors check the static platform/network policy,
  ensure the Zcash app is ready, and request the selected account's UFVK.
- Rust builds the UFVK APDU plan and validates status-bearing BLE responses,
  UFVK encoding, mainnet and account index. Both transports return the same C02
  account metadata. The native side is responsible for transport byte exchange.
- Existing-account operations honor the stored preference. Automatic desktop
  mode tries the last transport first, then eligible alternatives. Mobile uses
  Bluetooth and rechecks permission before connecting.
- Fallback is allowed only while establishing readiness. Once a caller's
  operation begins, its failure propagates without replay on another transport.
- Reconnect refreshes the connection and app state; it does not invoke signing
  or broadcast. Callers must initiate their next operation separately.
- Readiness reports open/dashboard/locked/disconnected/other-app states and
  enforces the source's development app-version baseline. This is not a claim
  that the baseline is publicly installable on every Ledger model.
- Pairing-invalid failures remain distinct from ordinary disconnects. The shared
  Linux pairing-code provider carries a pending code and accept/reject command;
  OS-specific handling lands with the native adapters.

## Cancellation and retry

The cancellation provider captures its dependencies before caller disposal. It
invokes C01's synchronous atomic USB cancellation and best-effort cancellation
of the BLE channel. BLE exchange generations reject results arriving after
cancel/disconnect and prevent a delayed busy retry from restarting the request.
Only the initial UFVK command rejected with `0x6901` is retried, at most three
attempts with 200 ms delays. No successful request is replayed.

This does not promise interruption of native I/O or dismissal of a device
prompt. Native adapters own completion/drain behavior. Signing cooldown and
PCZT exchange are C08; they are not pulled into C03 as unused scaffolding.

## Cleanup included

- Remove the unused string-only `ledger_export_ufvk` bridge; account export uses
  `ledger_export_account`. Source application callers already use the latter.
- Remove the generic default-platform readiness provider wrappers. Production
  callers use explicit transport family providers; the only generic consumer
  was a test, which now exercises the same family as production.
- Keep transaction-capacity messages, migration capability, PCZT signing methods
  and signing-status cooldown out of this slice. They have later consumers and
  are not classified as dead code merely because C03 does not use them.
- Keep the lower-level Rust UFVK helper for the planned diagnostic/canary paths.

## Parallel work proposal

C04 Apple and C05 Android can be prepared/reviewed independently once this Dart
channel contract is fixed: their native implementations, registrations,
dependencies and tests live in separate platform directories. Both depend on
C03; neither depends on the other. C08 signer work can also progress alongside
those adapters, with its own Rust/FRB changes and hardware-free tests.

C06 Windows and C07 Linux share `native/ledger/ble_protocol.h` and
`ble_operation_gate.h`. Keep those common files in one prerequisite slice before
parallelizing the two OS adapters; Linux should not independently duplicate them.
These are proposals, not additional PRs opened by C03.

## Validation boundary

Focused tests use fake devices and method channels to exercise readiness,
transport fallback, reconnect, permission/pairing failures, busy retries and
late-result cancellation. Rust tests cover the UFVK plan and response decoder.
Native BLE connectivity, permission prompts, pairing and device approval remain
unverified until the platform adapters are integrated and exercised.
