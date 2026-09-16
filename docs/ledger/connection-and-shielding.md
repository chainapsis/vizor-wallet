# Ledger connection and shielding behavior

## Mobile account setup

Mobile Ledger onboarding adds accounts only to an existing wallet with a
configured passcode and an unlocked session. The Ledger routes and account
import enforce this policy even when opened directly; first-account setup must
use another supported onboarding method. Desktop Ledger password setup is
unchanged.

## Connection and cancellation

Automatic transport fallback is limited to device readiness. Once the caller's
operation starts, a failure is returned without replaying it over another
transport. Failure to save the last successful transport does not turn a
completed operation into failure.

Ledger metadata setters merge their fields into the current account state after
saving. This applies on all platforms so an asynchronous connection-preference
write cannot restore an address cleared by a wallet lock or undo an account
switch. It does **not** enable Linux's keyring recovery, mutation gate, or secret
session-generation policy on macOS. The keyring coordinator remains a no-op on
other platforms. This is deliberately narrower than general storage-session
isolation.

USB cancellation is a synchronous FRB call to an atomic cancellation flag; it
does not perform device I/O on the Dart thread. BLE generations invalidate late
responses and scheduled busy retries. Apple transports retain ownership while
native callbacks drain, and prevent discovery/reconnection from overlapping that
work. Signing, app preparation and UFVK exchange share the native operation slot.
Cancelling the host does not promise dismissal of the device's approval prompt.

The device's post-signing screen can drop commands. USB operations and Apple BLE
APDUs wait for that screen to clear before sending follow-up commands. Dart also
waits before preparing the next Bluetooth signing connection. Pairing-invalid,
locked-device and app-unavailable failures remain distinct.

## Consecutive shielding approvals

Each approval still uses at most **10 transparent inputs**. The UI keeps one
shielding session open and requests a new approval after each successful
checkpoint and broadcast. Every round is a separate transaction and pays its own
network fee. The displayed number of rounds is recalculated from currently
eligible inputs; it is not a promise about future deposits or fees.

`get_ledger_shielding_progress` reads the local wallet DB only. It performs no
network RPC or address discovery. It requires completed transparent recovery and
uses the same address selection, confirmation policy, lock filtering and input
ordering as the transaction builder. The planner verifies remaining rounds can
actually be built. The existing Home shielding eligibility API is unchanged.

- No currently eligible inputs: complete this session.
- Remaining value below the shielding threshold: pause with an explanation.
- DB/planner/discovery failure: do not interpret the failure as zero funds.
- No decrease in eligible input count after broadcast: pause rather than sign
  potentially conflicting inputs again.
- Account/network changes: stop before retrying or preparing another round.
- Checkpoint retry: retain the signed bytes and operation ID without asking the
  Ledger to approve again.
- Broadcast retry: reuse the checkpoint; uncertain broadcast results use the
  existing durable recovery flow and do not advance to another round.

Completion concerns currently eligible inputs, not future external-wallet use,
unconfirmed/unavailable funds or future discoveries. External/internal discovery,
original derivation paths and the bounded old-address sync policy are unchanged.

## Mobile TEX

The mobile recipient and Max steps permit Ledger TEX recipients. The existing
flow generates two PCZTs, collects signatures in order and checkpoints the batch
before handoff. A rejected second approval retries only the second signature.
Cancellation continues to await proposal creation/cleanup, and checkpoint retries
preserve both signatures. Unsupported legacy Orchard-to-Ironwood paths remain
gated.

## Provenance and verification boundaries

Adapted from Rowan's connection/core work (`1454b00e9`, `0e8e320d9`,
`1255a0cff`, `60ed148c2`, `66b9b7cb4`), Apple transport through `5d8af4e14`,
post-signing readiness (`ae9cfae0a`), consecutive shielding (`9c5ee6f0f`,
`2810f9540`) and mobile TEX entry (`8b63b73e1`). The partial core branches were
not merged wholesale; PCZT signing and the wallet's existing recovery behavior
remain present.

Run the shared Apple handler suite with `python3 scripts/test-ledger-apple.py`.
It uses the real pinned BLE library and Flutter framework in a temporary Swift
package, without launching the wallet app.

Automated tests use fake method channels, fake Ledger responses and local wallet
DBs. Physical macOS USB/BLE and mobile BLE verification still requires a device:
consecutive approvals, rejection/cancellation, reconnect, invalid pairing and
TEX two-transaction execution. Automated coverage is not evidence of firmware or
real-network compatibility. No 32-input limit expansion is included.

## Desktop USB platforms

The Rust HID transport is compiled for macOS, Windows and Linux. Windows and
Linux use USB only, even when saved account metadata prefers Bluetooth. Their
onboarding and signing recovery UI do not offer Bluetooth. macOS retains USB/BLE
selection; iOS and Android retain native BLE. Mainnet and device-app version gates
and the legacy Orchard recovery restriction remain unchanged.

Linux build hosts need `libudev` development files and `pkg-config`. The current
pinned HID crate selects `linux-static-hidraw`; do not enable a second Linux HID
backend through additive Cargo features. Linux bundles ship the rule and setup
instructions in `data/ledger-usb` (source: `linux/udev`). Windows uses HIDAPI's
Windows backend through the existing Rust DLL/Cargokit build, without a new
Flutter MethodChannel.

Validation on each target should include native Rust/Flutter release builds and
USB import, app switching, reconnect, cancellation, send/TEX, consecutive shielding
and voting. Speculos exercises APDUs, not host USB drivers or Linux permissions.
The desktop Speculos test uses the host target platform; the existing shell runner
accepts `FLUTTER_DEVICE=linux` as well as its default `macos` (Windows needs an
appropriate host runner). Physical USB checks must cover a normal user session,
not only an elevated/admin environment.
