# Account balances and authoritative refresh

Read when changing account-scoped display caches, restored spendable snapshots, or authoritative refresh after proposal release.

## Account-switch snapshots

- The account-switch cache is display-only and in memory. Restored spendable
  values are marked as a completed-sync snapshot; Rust proposal construction
  remains authoritative. An unavailable balance clears restored balance fields
  but preserves refreshed history. A thrown refresh error can leave the snapshot
  visible until a successful refresh.

## Authority

- Rust balance/proposal reads remain authoritative even when Dart preserves a
  completed-sync display snapshot during refresh or failure.

## Proposal release and authoritative refresh

- Releasing or discarding a send proposal unlocks Rust inputs, but the displayed
  balance may remain a locked completed-sync snapshot.

- The release owner must await
  `SyncNotifier.refreshAfterProposalRelease(accountUuid)` before the caller
  treats retry as ready.

- It removes the account's switch cache, refuses to publish over another active
  account, coalesces concurrent refreshes, and requires an authoritative balance.
  An unavailable read is not success.

- The authoritative requirement stays sticky across a coalesced refresh chain,
  so later ordinary requests cannot downgrade cancellation recovery.

## Verification anchors

- Sync generations, DB path, and proposal release:
  [`sync_provider_test.dart`](../../../../test/providers/sync_provider_test.dart)

- End-to-end proposal release ordering:
  [`send_proposal_release_test.dart`](../../../../test/features/send/send_proposal_release_test.dart)

## Related changes

- When changing active UUID and address handoff, read [account switching](../../domains/accounts/switch.md).
- When changing release ownership above balance refresh, read [proposal release](../transactions/proposal-release.md).
