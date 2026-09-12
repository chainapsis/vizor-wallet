# Lock and sync contract

## Scope

Use this contract when changing app lock/unlock, account switching, wallet
reset, sync cancellation, transport restart, or post-proposal balance recovery.
Network-route policy is in [sync-network.md](sync-network.md). Send cancellation
also depends on [send.md](send.md).

## Owners and entry points

- `AppSecurityNotifier.lock` owns authentication/session invalidation.
- `AccountNotifier.clearSensitiveStateForLock` removes the active address and
  other in-memory account secrets while preserving account metadata and the
  active UUID needed to restore after unlock.
- [`SyncNotifier`](../../lib/src/providers/sync_provider.dart) owns displayed
  balances/history, sync subscriptions, polling, mempool observation, cached DB
  path, and epochs that reject late async results.
- UI lock actions must invoke these owners in their established orchestration;
  no one provider call represents the whole lock transition.

## Lock transition

- Security lock clears the secure-store session first, preventing new secret
  reads from joining the old session.
- Account clearing publishes no active address. Any pending address or mnemonic
  completion checks the secure-store generation before publishing.
- `SyncNotifier.clearSensitiveStateForLock` increments sync, progress, balance,
  and sensitive-state generations; clears all displayed account data and the
  account-switch snapshot cache; stops polling and mempool observation; requests
  Rust sync mode `0` and cancellation; then waits up to its bounded teardown
  interval.
- Subscription cancellation is not Rust cancellation. Keep both: cancelling a
  Dart stream does not stop the Rust task that owns the DB/network work.
- Late progress and balance completions must compare their captured generation
  or epoch and drop themselves after lock, account change, or notifier disposal.

## Unlock transition

- A successful `unlock` opens the secure-storage session and publishes unlocked
  security state; it does not restore account or sync data itself.
- The unlock surface then calls `AccountNotifier.restoreAfterUnlock`,
  `SyncNotifier.refreshAfterUnlock`, and `SyncNotifier.startSyncAnyway` before
  routing to the wallet and releasing parked payment intents.
- `restoreAfterUnlock` re-reads the active account address and publishes it only
  if the same unlocked session and active UUID still own the result.
- `refreshAfterUnlock` restores account-scoped balance/history from Rust.
- `startSyncAnyway` is recovery for a cancelled old run that may still be
  unwinding. It waits for cancel-requested sync and stale mempool tasks, then
  starts only after their running guards clear. An unrelated live Rust sync is
  joined by omission rather than cancelled.

## Stop, pause, and restart are distinct

- `stopSync` invalidates pending starts, cancels foreground sync and mempool
  observation, stops polling, and leaves the session intentionally quiet.
- `pauseForWalletMutation` snapshots which work was active, requests mode `0`,
  cancels and drains Rust work with the longer destructive-operation timeout,
  and fails the mutation if quiescence is not reached.
- `resumeAfterWalletMutation` restores only the lanes represented in that
  snapshot, unless the wallet is now locked.
- `restartSyncAfterTransportChange` cancels and drains both network lanes before
  applying the route callback. A real transport change fails closed if tasks do
  not quiesce; a same-transport refresh may preserve the older start-anyway
  behavior.
- `cancelFullSync` affects the foreground full-sync cancel token. Mobile
  migration preparation owns a separate cancel token; both compete for the
  shared Rust `SYNC_RUNNING` guard while scanning.

## Account and DB identity

- Account switching does not restart the wallet-wide scan. It changes the
  active account target and refreshes account-scoped state while the one Rust
  scan continues across all accounts.
- The account-switch cache is display-only and in memory. Restored spendable
  values are marked as a completed-sync snapshot; Rust proposal construction
  remains authoritative. An unavailable balance clears restored balance fields
  while preserving refreshed history; a thrown refresh error can leave the
  snapshot visible until a later successful refresh.
- `clearCachedWalletDbPath` is mandatory after a successful full reset. Without
  it, sync can reopen the deleted wallet's cached randomized path instead of the
  next wallet's newly generated path.

## Proposal release and authoritative refresh

- Releasing or discarding a send proposal unlocks inputs in Rust, but the
  displayed balance can still be a locked completed-sync snapshot.
- The release owner must await
  `SyncNotifier.refreshAfterProposalRelease(accountUuid)` before the caller
  treats retry as ready.
- That method removes any switch cache for the account, refuses to publish over
  another active account, coalesces concurrent refreshes, and requires a real
  authoritative balance. An unavailable read is not success.
- The authoritative requirement stays sticky across a coalesced refresh chain,
  so a later ordinary request cannot downgrade a cancellation recovery.

## Verification anchors

- Sync generations, DB path, and proposal release:
  [`sync_provider_test.dart`](../../test/providers/sync_provider_test.dart)
- End-to-end proposal release ordering:
  [`send_proposal_release_test.dart`](../../test/features/send/send_proposal_release_test.dart)
- Secret-session races:
  [`app_secure_store_session_test.dart`](../../test/core/storage/app_secure_store_session_test.dart)
- Wallet mutation pause/reset ordering:
  [`wallet_mutation_guard_test.dart`](../../test/providers/wallet_mutation_guard_test.dart)
