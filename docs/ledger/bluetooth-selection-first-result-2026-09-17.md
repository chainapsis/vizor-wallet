# Bluetooth device selection before Ledger interaction

Implemented on top of `8824d644ac98534eb391256f5ba1e1a52bc22e49`.

## User flow

- iOS/Android Bluetooth device work now waits for an explicit device selection. The picker starts discovery on entry. A saved device, a single result, or an already-connected device is never automatically selected.
- macOS with an explicit Bluetooth preference opens the same picker. Automatic mode tries USB preparation first, even if the last successful transport was Bluetooth. Only a preparation failure can fall through to the Bluetooth picker; a started operation is never replayed on another transport.
- Explicit USB and Windows/Linux retain their existing USB preparation/signing path. No USB enumeration, device-selection API, native handler, or Rust transport changes were introduced.
- macOS offers the existing Bluetooth/USB selector in the picker. Choosing USB is local to the current operation; it does not rewrite the saved preference. The Connect action runs the existing USB path.
- Every selected Bluetooth device exports the viewing key for the existing account index. Full UFVK and index verification precede metadata persistence and signing, including when the discovery ID matches the saved ID.
- On verification success, the original operation proceeds using that same connection. There is no extra connection-success confirmation screen. Account mismatch, pairing problems and permission recovery stay within the selection flow until resolved or cancelled.
- An old saved device model does not prevent selecting a replacement Bluetooth-capable device for the same account. Discovery IDs remain connection hints, not proof of identity.

## Operation scope and integration

Send (desktop/mobile), shield, swap/pay deposits, payment links, immediate migration and voting use an in-memory connection scope. A single user operation shares its verified selection across signing rounds/bundles; a new operation asks again. An intervening connection owner, cancellation, account/session change or a device-operation failure invalidates reuse.

Transaction preparation may still run before the signer needs the device. The selection boundary prevents automatic Bluetooth connection and device interaction, not local proof preparation. Already-signed checkpoint/storage/broadcast recovery continues without requesting a device.

The existing recovery component supplies discovery, quiet device rows, pairing help, permission recovery and account-mismatch presentation. Retry from a failed signing operation enters the new selection boundary instead of verifying once in recovery and then asking again.

## Review and fixes

Review identified and fixed three boundary problems:

1. Cancelling a pending picker now cancels native verification and stops discovery, and retains exclusion until accepted work retires. Account/lock changes and dismissal settle the pending request.
2. A captured connection generation prevents one operation from reusing a connection selected by another operation, even if both use the same discovery ID.
3. An explicitly selected USB connection checks cancellation after subsequent signing-round results, consistently with the normal USB path.

Regression tests reproduce each boundary. Follow-up review found no remaining actionable findings.

## Validation

- Desktop Ledger/onboarding/send/payment-link/voting regression selection: **442 passed, 5 skipped**.
- Mobile-tagged Ledger/send/onboarding/voting selection: **63 passed**.
- Connection, selection UI and pairing recovery tests compiled with mobile tokens: **124 passed**.
- Flutter analyze: **no issues**. Git whitespace validation passed.
- Flutter widget captures: **82 passed** (38 desktop, 44 mobile), including **14 new-flow screenshots** in both themes. Inspected device lists, USB transition and subsequent signing presentation.

Gallery: `/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-select-first/index.html`.

Tests and captures use deterministic transport fixtures. Real Ledger pairing prompts, viewing-key approval, USB availability and signing still require physical-device verification on iOS, Android and macOS. No real transaction was submitted during this task.
