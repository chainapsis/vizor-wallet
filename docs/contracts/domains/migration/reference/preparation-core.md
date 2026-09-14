# Migration preparation core

Read when changing the platform-neutral preparation operation API, its mode/cancel boundary, or restricted read-only entry points.

## Preparation core

- [`migration_preparation.rs`](../../../../../rust/src/migration_preparation.rs) is a
  platform-neutral core. Each operation shares one cancel token and desired
  mode across its optional sync and advance phases.

- `begin_operation` is exclusive; `cancel_operation` signals the operation;
  `end_operation` removes and cancels its control object.

- Preparation sync uses mode `2`, a cancel token separate from foreground
  `cancelFullSync`, and the shared `SYNC_RUNNING` guard to prevent overlapping scans.

- `inspect` and `advance` can mutate state through schema-aware migration
  status/advancement helpers; they are foreground-capable paths.

- `inspect_read_only`, `observable_transaction_ids`, and
  `inspect_proof_readiness` are iOS's restricted observation surface. Missing or
  incompatible tables require recovery, never a native background DB upgrade.

## Android runtime availability

- There is currently no Android preparation worker or `background_migration`
  channel. Dart reports tracking support as `false`, and `_usesNativePreparation`
  excludes Android. Platform-neutral Rust functions do not imply an Android runtime.

## Verification anchors

- Platform-neutral lifecycle and read-only schema behavior: tests beside
  [`migration_preparation.rs`](../../../../../rust/src/migration_preparation.rs)

## Related changes

- When changing mode 2 scanning, preserve the common SYNC_RUNNING authority in [foreground sync lifecycle](../../../references/sync/foreground-lifecycle.md).
- When changing iOS consumers of read-only helpers, read [iOS confirmation](../ios-confirmation.md).
