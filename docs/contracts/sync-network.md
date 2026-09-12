# Sync and network contract

## Scope

Use this contract for foreground wallet sync, polling, mempool observation,
endpoint failover, Tor route changes, progress semantics, cancellation, and
retry. Lock sequencing is in [lock-sync.md](lock-sync.md); platform migration
work is in [migration.md](migration.md).

## Sync boundary

- Dart starts normal wallet sync through `startFullSync` in
  [`SyncNotifier`](../../lib/src/providers/sync_provider.dart) and consumes the
  FRB progress stream.
- [`api/sync.rs`](../../rust/src/api/sync.rs) owns the process-wide desired mode,
  cancel token, running guard, active-account refresh priority, and translation
  from Rust progress into flat FRB structs.
- The sync engine lives under
  [`wallet/sync_engine/`](../../rust/src/wallet/sync_engine). It owns channel
  policy, subtree and compact-block download, scanning, enhancement, recovery,
  retry, and progress calculation.
- FRB stream delivery is the Dart-visible terminal channel. The generated Dart
  API detaches the Rust task future, so `start_full_sync` forwards terminal
  errors to the stream and returns `Ok` after arranging that delivery.

## Single wallet scan

- The main wallet has one full-sync run at a time. `SYNC_RUNNING` is acquired
  before network parsing/migration and released even across caught panics.
- One DB and one scan cover every account UFVK. The active account only
  prioritizes pending transparent refreshes and selects Dart balance/history
  reads; it does not scope compact-block scanning.
- Mode `1` is the Dart foreground run. Mode changes and the cancel token are
  checked throughout long-running phases and retry waits.
- Payment-link claim scans are deliberately isolated by claim ID and DB. They
  do not use the main wallet's desired mode or running guard.

## Progress and completion

- Progress targets come from Rust events. Dart may interpolate the display but
  must not turn UI interpolation into authoritative scan state.
- Normal scan progress starts from initial pending work. Remaining work is
  recomputed, the total can expand when new ranges appear, and repair phases may
  reset their own baseline; never use a later range total that omits completed
  work as the ordinary denominator.
- Preparation phases may report completed/total work units and named phases
  before block download and scan.
- A closed stream without a complete event can mean cancellation or mode
  replacement. Dart must clear its attached state and running markers so a
  later start is not permanently blocked.
- Rust balance/proposal reads remain authoritative even when Dart preserves a
  completed-sync display snapshot during refresh or failure.

## Retry and observation

- The full sync engine owns bounded retry and checks cancellation and mode
  changes during backoff. Endpoint fallback is a separate Dart decision after
  a surfaced foreground failure.
- Dart polls the chain tip every ten seconds while process-work policy allows
  it, and restarts when the tip advanced or the previous sync was incomplete.
- App backgrounding stops mobile polling. Desktop process-work policy may keep
  wallet sync and scheduled migration work active while windows are hidden.
- The mempool observer has its own Rust lifecycle and cancel token. Dart starts
  and stops it with the foreground-sync lifetime, and refreshes only for
  wallet-relevant events.
- Do not infer mempool shutdown from cancelling its Dart subscription; the Rust
  observer must also receive its explicit stop signal.

## Route policy

- [`initializeNetworkPrivacyRuntime`](../../lib/src/providers/network_privacy_provider.dart)
  applies the persisted route before bootstrap or provider network work begins.
- Foreground lightwalletd and HTTP clients use policy-aware openers. Tor enable
  installs fail-closed intent synchronously before bootstrap; requests wait or
  fail while Tor is starting or failed rather than falling back to direct.
- Route toggles quiesce sync, mempool, and direct HTTP work before changing the
  runtime transport. A busy old route blocks a privacy-changing toggle.
- Persisted route state may temporarily be stricter than the live runtime, never
  laxer. Enable persists Tor before changing the runtime; disable persists
  Direct only after the runtime is Direct. Keep
  `networkPrivacyPersistedRouteIsSafe` as the executable ordering rule.
- A superseded toggle must recheck its generation after every suspension point;
  an old disable must never reopen direct traffic under a newer Tor enable.
- Native desktop update transports are coordinated separately because they do
  not automatically use the embedded Tor client.

## Direct background exception

- iOS background migration confirmation and signed-outbox transport use the
  explicitly named `open_background_direct_lwd_channel` path. This is a product
  exception disclosed by the mobile settings UI.
- That opener is pinned Direct and must stay out of foreground wallet flows.
  Background confirmation observes exact txids and chain state; it does not
  borrow the foreground Tor client or silently bootstrap Tor.
- Android currently has no repository-owned background preparation worker; do
  not describe the platform-neutral preparation core as an active Android
  network lane. See [migration.md](migration.md).

## Verification anchors

- Dart sync lifecycle and balance refresh:
  [`sync_provider_test.dart`](../../test/providers/sync_provider_test.dart)
- Route ordering and failure behavior:
  [`network_privacy_provider_test.dart`](../../test/providers/network_privacy_provider_test.dart)
- Rust sync and channel behavior: tests beside
  [`wallet/sync_engine/`](../../rust/src/wallet/sync_engine)
- FRB mode/running guards: tests beside
  [`api/sync.rs`](../../rust/src/api/sync.rs)
