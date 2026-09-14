# Wallet lock and unlock

Read when changing the complete user lock/unlock transition across security, accounts, sync, navigation, and parked intents.

## Owners and entry points

- `AppSecurityNotifier.lock` owns authentication/session invalidation.

- `AccountNotifier.clearSensitiveStateForLock` clears the active address and
  other in-memory account secrets, preserving metadata and active UUID for unlock.

- [`SyncNotifier`](../../../../lib/src/providers/sync_provider.dart) owns displayed
  balances/history, sync subscriptions, polling, mempool observation, cached DB
  path, and epochs that reject late async results.

- UI lock actions must invoke these owners in the established orchestration;
  no single provider call completes the lock transition.

## Security lock boundary

- `lock()` invalidates unlock and confirmation requests, clears the session
  password, and publishes locked state. Callers must then clear sensitive
  account and sync state; `lock()` alone does not.

## Lock transition

- Security lock clears the secure-store session first, preventing new secret
  reads from joining the old session.

- Account clearing publishes no active address. Pending address or mnemonic
  completion checks the secure-store generation before publishing.

- `SyncNotifier.clearSensitiveStateForLock` increments sync, progress, balance,
  and sensitive-state generations; clears all displayed account data and the
  account-switch snapshot cache; stops polling and mempool observation; requests
  Rust sync mode `0` and cancellation; then waits up to its bounded teardown
  interval.

- Cancel both subscriptions and Rust work: cancelling a Dart stream does not
  stop the Rust task owning DB/network work.

- Late progress and balance completions must compare their captured generation
  or epoch and be dropped after lock, account change, or notifier disposal.

## Unlock transition

- Successful `unlock` opens the secure-storage session and publishes unlocked
  security state; account and sync restoration follow separately.

- The unlock surface then calls `AccountNotifier.restoreAfterUnlock`,
  `SyncNotifier.refreshAfterUnlock`, and `SyncNotifier.startSyncAnyway` before
  routing to the wallet and releasing parked payment intents.

- `restoreAfterUnlock` re-reads the active address and publishes it only while
  the same unlocked session and active UUID own the result.

- `refreshAfterUnlock` restores account-scoped balance/history from Rust.

- `startSyncAnyway` recovers from a cancelled run that may still be unwinding.
  It waits for cancel-requested sync and stale mempool tasks, starting only after
  their running guards clear. An unrelated live Rust sync is joined by omission
  rather than cancelled.

## Verification anchors

- Sync generations, DB path, and proposal release:
  [`sync_provider_test.dart`](../../../../test/providers/sync_provider_test.dart)

- Secret-session races:
  [`app_secure_store_session_test.dart`](../../../../test/core/storage/app_secure_store_session_test.dart)

- Unlock orchestration source:
  [`unlock_screen.dart`](../../../../lib/src/features/onboarding/unlock_screen.dart).
  Parked-request routing is covered by
  [`unlock_screen_payment_uri_test.dart`](../../../../test/features/onboarding/unlock_screen_payment_uri_test.dart)
  and [its mobile counterpart](../../../../test/features/onboarding/mobile_unlock_screen_payment_uri_test.dart).
  These tests stub account/sync recovery; they do not verify real Rust recovery.

## Related changes

- When changing secret freshness checks, preserve [secret sessions](../../references/storage/secret-sessions.md).
- When changing underlying Rust running/cancel guards, read [foreground sync lifecycle](../../references/sync/foreground-lifecycle.md).
- When changing balance restoration semantics, read [account balances](../../references/sync/account-balances.md).
