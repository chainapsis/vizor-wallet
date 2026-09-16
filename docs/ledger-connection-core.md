# Ledger connection coordination

C03 targets the core collection (`rowan/ledger-core-collection`, PR #693)
after account import and signer dispatch from #696 have merged.
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
- Keep the lower-level Rust UFVK helper: the source implementation has a real
  canary consumer in `ironwood_migration/plan_child.rs`, which belongs to a later
  slice. Removing the duplicate bridge does not remove that Rust-only helper.

## Integration dependencies

C02 account import and signer dispatch (#696), Android BLE (#698), and shared
native BLE protocol (#701) are merged into the collection. C04 Apple (#700),
C06b Windows (#702), and C07 Linux (#703) target the collection independently.
Their native channel implementations consume this contract at runtime; they do
not need C03's Dart sources to compile.

C03 only prepares connections and exports account material. Ledger transaction
signing remains unsupported by the account-signing policy until C08 is added.
The later signing slice consumes C03's connection contract without changing
software or Keystone signer dispatch.

## Validation boundary

Focused tests use fake devices and method channels to exercise readiness,
transport fallback, reconnect, permission/pairing failures, busy retries and
late-result cancellation. Rust tests cover the UFVK plan and response decoder.
Native BLE connectivity, permission prompts, pairing and device approval remain
unverified until the platform adapters are integrated and exercised.
