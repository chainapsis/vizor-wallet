# Sender Gift Card usage tracking

Created cards keep their funding/share lifecycle (`draft`, `funded`, `shared`).
The optional `usage` field in the existing encrypted recovery record is a
separate sender observation; missing fields default to `unknown`. Malformed
present usage records fail validation. Receiver claim records are unchanged.

Unverified observations now carry an optional `reason`; older records without
it remain readable and do not imply pending funding. The sender UI shows:
- `Checking…` while an unverified card is being checked.
- `Confirming` only when every saved funding transaction is returned
  by lightwalletd with a matching parsed txid and at least one is unmined.
- `Unverified` for missing saved funding information, missing observed
  funding, incomplete scan history, or insufficient observed funding value.
  Hover/tap explains the specific reason on the list and completion screen.

The read-only transaction lookup runs only when local funding evidence is
missing. NotFound is inconclusive, never proof of pending funding. Network or
invalid-response failures retain the previous observation and show the error
indicator. Lookup uses the existing route-aware lightwalletd transport and
endpoint fallback; observer pause/reset cancels it and drains before cleanup.
Previously verified usage is preserved if a later observation lacks evidence.
Long inline labels may wrap to two lines while preserving the action positions.

## Ownership

`GiftCardTrackingService` serializes registration, scans, observations and
cleanup. A durable recovery draft is also the registration intent. Creation
attempts registration before funding; observation failure leaves that intent
retryable without causing another funding send. Related visible screens request
refreshes, coalesced with a 30-second cooldown. Usage is displayed on the card
list and creation completion screens; sharing and activity detail retain their
original presentation. List rows show a short status before the copy/QR actions,
with a reserved slot for a checking spinner or a per-card error icon. Error
details are available by hover or tap. Narrow mobile rows place the status
below the amount/date to preserve the details and 44-pixel action targets.
Activity detail does not request observation. No observer
timer runs globally.

A wallet-instance/network-scoped `gift_card_tracking_*` directory contains one
multi-account observer DB. Accounts use UFVKs with `AccountPurpose::ViewOnly`;
no mnemonic is stored there. Import verifies the derived address and is
idempotent. Older imported birthdays are handled by the library's pending scan
ranges. Existing registrations are reused. Inert/expired drafts removed by the
funding reconciler leave observer accounts that the next refresh retires.

Removing the final observer retains the DB. Before each isolated scan-range
selection, the engine demotes ranges before the earliest remaining account
birthday to Ignored. This also runs after tip refreshes and rewinds, which can
recreate old ranges from retained block metadata. A later card therefore does
not scan the idle gap; an older recovered card still keeps its required history.
Existing DBs receive this queue repair on their next scan without a schema
migration or deletion of saved usage evidence.

The Rust observer API owns an operation lock separate from the main wallet. It
reuses the isolated shielded scan engine with retransmission disabled, with its
own cancellation ID. Claim wallets retain their separate paths and owners.
The destructive-operation registry remembers its fence even if the tracker is
instantiated during reset. Lock/background events invalidate pending results;
reset drains the worker before directory cleanup and secure-storage deletion.

## Evidence and cleanup

Usage follows the original funding transaction's positive shielded outputs,
not an empty balance, arbitrary top-ups or who initiated the consuming send.
All expected funding IDs must be observed, covering at least the saved funded
amount. Byte order is normalized when matching funding IDs.

- `unknown`: insufficient funding evidence.
- `unused`: no mined consumption seen through the verified scan height.
- `spendDetected`: some consumption seen, awaiting complete/final evidence.
- `used`: all original funding outputs consumed with six scanned confirmations.

The verified height is capped by pending scan ranges. Reorgs before cleanup may
change the observed state; missing history alone never overwrites an earlier
observation or claims it was freshly verified. Card registration, lookup and account-deletion failures preserve the
snapshot, display an update error only on that card and allow other cards to
continue. They retry on the next refresh after the normal cooldown. Shared
store/list/scan failures still abort the refresh. Uncertain imports or stale
registration writes defer orphan cleanup, preventing deletion of an account
whose registration receipt has not been saved. Orphan cleanup failure retries
later without blocking live cards. Last checked is the observation time,
not a recipient identity or a promise of instantaneous status.

Before cleanup, the record saves the spending IDs, mined/verified heights and
`cleanupPending`. Only after that write succeeds may the account be deleted;
restart retries pending deletion idempotently. Positive remaining outputs
(including top-ups/change) postpone deletion even if the original card is used.
Zero-value change does not block it. The record then becomes `cleaned`, retaining
its historical usage and existing bearer-link retention policy. The sender's
link is not erased by this feature. Automatic observation stops after cleanup:
late deposits and deeper reorgs are outside this terminal policy.

## Validation

Focused Dart tests cover legacy records, stale writes, concurrency, reset,
cleanup recovery, write failure and top-ups; Rust unit tests cover funding
identity, finality, scan gaps, reorgs, view-only registration and independent
account deletion. UI tests cover reactive status and failure display.

The opt-in `regtest_gift_card_tracking` Rust integration test exercises real
multi-account viewing-key scans, a late older-birthday registration and an
external claim. It also covers 1 → 0 → later registration with real shielded
activity in the idle interval, zero scanned blocks in the skipped interval,
subsequent tip refresh and older-card recovery. The macOS
`flutter-macos-regtest-gift-card-tracking.sh` runner checks unmined funding → Unused, automatic UI/store
updates and retention across a process restart. See `scripts/e2e/README.md`.
It mines on the shared Docker chain; run it only when regtest
execution is explicitly requested.

Bridge bindings can be regenerated from the project root with
`scripts/generate-rust-bridge.sh`. It runs the standard FRB generator with a
local inspection-only workaround for FRB 2.11.1 parsing rustc-expanded
`super let` in dependencies. Actual compiled Rust source is unchanged.
