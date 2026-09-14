# Foreground sync lifecycle

Read when changing foreground scanning, running/mode/cancel guards, polling, mempool observation, or surfaced termination and retry.

## Sync boundary

- Dart starts normal wallet sync through `startFullSync` in
  [`SyncNotifier`](../../../../lib/src/providers/sync_provider.dart) and consumes the
  FRB progress stream.

- [`api/sync.rs`](../../../../rust/src/api/sync.rs) owns the process-wide desired mode,
  cancel token, running guard, active-account refresh priority, and flat FRB
  progress translation.

- [`wallet/sync_engine/`](../../../../rust/src/wallet/sync_engine) owns channel policy,
  subtree/compact-block download, scanning, enhancement, recovery, retry, and progress.

- FRB streams carry Dart-visible termination. The generated API detaches the
  Rust task future, so `start_full_sync` sends terminal errors through the stream
  and returns `Ok` after arranging delivery.

## Single wallet scan

- The main wallet runs one full sync at a time. Acquire `SYNC_RUNNING` before network
  parsing/migration and release it even across caught panics.

- One DB and one scan cover every account UFVK. The active account only
  prioritizes pending transparent refreshes and selects Dart balance/history
  reads, not compact-block scanning.

- Mode `1` is the Dart foreground run. Mode changes and the cancel token are
  checked throughout long-running phases and retry waits.

- Payment-link claim scans use separate claim IDs/DBs, never the main wallet's
  desired mode or running guard.

## Retry and observation

- The sync engine owns bounded retry, checking cancel/mode changes during
  backoff. Dart decides endpoint fallback separately after a surfaced foreground failure.

- Dart polls the chain tip every ten seconds while process-work policy allows
  it, and restarts when the tip advanced or the previous sync was incomplete.

- Backgrounding stops mobile polling. Desktop policy may keep sync and scheduled
  migration active behind hidden windows.

- The mempool observer has its own Rust lifecycle and cancel token. Dart starts
  and stops it with foreground sync, refreshing only for wallet-relevant events.

- Cancelling a Dart subscription does not stop Rust mempool work; send its
  explicit stop signal too.

## Stop and independent cancel tokens

- `stopSync` invalidates pending starts, cancels foreground sync and mempool
  observation, stops polling, and leaves the session intentionally quiet.

- `cancelFullSync` affects the foreground full-sync cancel token. Mobile
  migration preparation owns a separate cancel token; both compete for the
  shared Rust `SYNC_RUNNING` guard while scanning.

## Stream termination

- Stream closure without a complete event may mean cancellation or mode
  replacement. Clear Dart attachment/running markers so later starts are not blocked.

## Verification anchors

- Dart sync lifecycle and balance refresh:
  [`sync_provider_test.dart`](../../../../test/providers/sync_provider_test.dart)

- Rust sync and channel behavior: tests beside
  [`wallet/sync_engine/`](../../../../rust/src/wallet/sync_engine)

- FRB mode/running guards: tests beside
  [`api/sync.rs`](../../../../rust/src/api/sync.rs)

## Related changes

- When changing destructive pause/resume, preserve [mutation barrier](../wallet/mutation-barrier.md).
- When changing privacy transport replacement, read [network route policy](../network/route-policy.md).
- When changing preparation mode 2, retain the shared running guard and read [preparation core](../../domains/migration/reference/preparation-core.md).
