# Saved Ledger connection: skip repeated viewing-key approval

Implemented on top of `e215f9b87e0444334b41b289103932dd2bf18876`.

## Behavior

Every new Bluetooth operation still starts with device selection on iOS, Android and macOS.

- A selected nonempty ID matching the account’s saved Ledger ID connects and checks Zcash app readiness/version. It skips the local expected-UFVK read, device UFVK export, viewing-key approval and device metadata rebind.
- A different, missing or empty saved ID retains full UFVK and account-index verification. Only a match allows device metadata to be saved and the requested operation to continue. A mismatch preserves the saved connection.
- A same-ID operation failure propagates through the existing error flow; it does not trigger viewing-key export automatically. Retrying still asks for device selection.
- USB and macOS USB-first automatic behavior remain unchanged. Last-used transport can still be recorded when it changes.
- Matching an ID is a connection optimization, not proof that the device still holds the original seed. Reset/passphrase changes on the same ID intentionally rely on subsequent operation/signature checks, as requested.

The skipped request is the UFVK export used to check the account, not a general removal of shielded-address reads elsewhere.

## UI

The list now says “Choose the Ledger you want to use for this account.” Same-ID connection shows “Connecting to your Ledger” and instructs the user to unlock/open Zcash. It no longer claims to check the account or asks to share a viewing key. Other-device approval and mismatch copy remain unchanged.

Picker disposal checks whether selection already completed before cancelling the native operation. This prevents the successful same-ID transition from cancelling the signer that has just resumed.

## Validation

- Broad desktop Ledger and caller suite: 444 passed, 5 skipped (before the final two additional failure tests).
- Mobile UI lane: 63 passed.
- Core selection/connection/recovery suite compiled with mobile tokens: 126 passed (before the final two additional failure tests).
- Final recovery suite including same-ID readiness failure and cancellation: 30 passed.
- Static analysis: no issues.
- Deterministic captures: 42 desktop + 48 mobile passed. Inspected the changed desktop and mobile connection screens; captures include both themes and same-ID signing continuation.
- Two full self-review passes found no outstanding actionable issue. The successful-picker-disposal regression is explicitly tested.

Screenshots: `/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-known-device/index.html`.

No physical Ledger or native Bluetooth reset scenario was exercised in this environment. The tests use deterministic transport and account fixtures.
