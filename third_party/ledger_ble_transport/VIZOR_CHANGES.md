# Vizor BLE transport patch

Source: https://github.com/LedgerHQ/hw-transport-ios-ble
Version: 1.0.1
Revision: 4df8fff21c1738a1dff4d2ee19175dd3263d6c5f
License: MIT (see LICENSE)

Both Apple runners and scripts/test-ledger-apple.py use this local package.
Changes settle disconnected requests exactly once, clear response assembly,
isolate connection generations and fail incomplete connection handshakes.

The CoreBluetooth connect operation keeps its queue slot after timeout until
radio teardown, cancels late successes, and consumes callbacks once. Failed
peripheral lookup also completes the queue instead of starting a nil peripheral.
Discovery continuations and notification delegates are detached on disconnect.

Validation: `swift test --package-path third_party/ledger_ble_transport` and
`python3 scripts/test-ledger-apple.py`. The former injects only the radio boundary
and executes this package's production framing, handshake and connection queue
logic. The latter runs the shared iOS/macOS handler against controlled callbacks.

Imported Swift sources have trailing whitespace normalized.
Radio-unavailable state changes also invalidate module operations and listeners
before SDK callbacks. Work enqueued before a connection generation change cannot
start after the queue has been reset.

Discarding a Scan now cancels its timeout/expiry timers, releases callbacks, and
makes queued expiry, late timeout and stale stop/start events inert. Normal stops
still notify once. ScanLifetimeTests exercises the production Scan and Queue with
only CoreBluetooth radio calls substituted, including fast radio off/on recovery.
