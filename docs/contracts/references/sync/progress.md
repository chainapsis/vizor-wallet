# Sync progress and UI interpolation

Read when changing authoritative progress targets, denominator updates, UI smoothing, or the meaning of completed progress.

## Authoritative progress

- Rust events define progress targets; Dart interpolation is display-only.

- Normal progress starts from initial pending work. Recompute remaining work;
  new ranges may expand the total, and repair phases may reset their baseline.
  Never use a later total omitting completed work as the normal denominator.

- Preparation phases may report completed/total work units and named phases
  before block download and scan.

## UI interpolation

- For sync animation, [sync_display_progress_provider.dart](../../../../lib/src/providers/sync_display_progress_provider.dart)
  owns the 20ms interpolation timer. Smooth indicators read raw progress; labels read
  whole percentages. Rust/provider progress is authoritative; only real completion
  produces 100%.

## Verification anchors

- UI interpolation: [sync_display_progress_provider_test.dart](../../../../test/providers/sync_display_progress_provider_test.dart).



- Rust sync and channel behavior: tests beside
  [`wallet/sync_engine/`](../../../../rust/src/wallet/sync_engine)

## Related changes

- When changing stream closure or cancellation rather than progress values, read [foreground sync lifecycle](foreground-lifecycle.md).
- When changing completed balance snapshots, read [account balances](account-balances.md).
