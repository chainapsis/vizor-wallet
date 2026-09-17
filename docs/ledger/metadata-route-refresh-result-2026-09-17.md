# Ledger metadata must not refresh active signing routes

## Scope and cause

Fixes the Ledger Send cancellation reported on Android and the same metadata-triggered route loss in mobile Ledger Swap/Pay. Both mobile platforms share this Dart path. Other wallet flows and generic route serialization are outside this task.

`recordLedgerConnection` publishes an updated account list. `WalletNotifier` previously watched that entire snapshot, emitted a new WalletState with unchanged values, and triggered the app router's wallet listener. GoRouter's refresh could then drop complex route extras and replace a Ledger signing screen with its fallback, disposing/cancelling the active signing UI.

## Change

WalletNotifier now selects the account fields it actually exposes: account existence, active account UUID and active address. Selection retains AsyncValue loading/error semantics. Ledger device ID/name/model and last-used transport updates remain available through accountProvider but do not reconstruct unchanged wallet state or trigger its router listener.

The router's security and feature-gate listeners, device verification, device cancellation, USB selection and broadcast ownership are unchanged. No new UI or route codec was introduced.

## Evidence

- Added six mobile regression cases: Send, Swap and Pay, each with saved-device transport recording and replacement-device metadata recording. They use the real AccountNotifier.recordLedgerConnection with mock storage, real WalletNotifier, the app's wallet-to-refresh binding, GoRouter, real payload classes and production mobile page builders. All six failed before the fix and passed after it.
- These tests inspect production page selection and payload identity without mounting Rust/native-dependent signing contents. They are routing integration tests, not physical-device or full native signing tests.
- Added six provider cases confirming Bluetooth/USB metadata does not notify wallet listeners while address, account switch, deletion, lock, error/recovery and loading transitions still propagate.
- Existing Ledger suites cover signing/cancellation, checkpoint/broadcast and caller behavior for Send, Swap/Pay, Shield, voting, payment links and immediate migration. No new native-device run was performed for those flows.
- Two review passes: reproduced and recorded the root cause, then verified the correction with no outstanding finding.

## Validation

- Focused provider and metadata-session tests: 16 passed.
- Desktop Ledger/caller/provider/onboarding selection: 453 passed, 6 skipped by lane tagging.
- Mobile Ledger/Send/onboarding/voting selection: 69 passed, including all six new route cases.
- `fvm flutter analyze --no-pub`: no issues.
- `git diff --check`: clean.

The product change is confined to wallet state derivation. No claims are made about preserving arbitrary extras through intentional security redirects or unrelated route refresh triggers.
