# Ironwood migration contract

## Scope

Use this contract for Ironwood run coordination, background credentials,
preparation confirmation, foreground continuation, cancellation, account
mutation barriers, and native platform boundaries. Sync transport rules are in
[sync-network.md](sync-network.md); software-secret rules are in
[security-lifecycle.md](security-lifecycle.md). Hardware signing details belong
in [hardware-signing.md](hardware-signing.md).

## Durable and process owners

- Rust wallet migration modules own the durable run, denomination stages,
  schedules, proposal locks, proof readiness, and outbox receipts.
- [`IronwoodMigrationService`](../../lib/src/features/migration/services/ironwood_migration_service.dart)
  owns the Dart credential context and calls flat FRB APIs. It captures secure
  storage generation and zeros mnemonic byte buffers after handing them off.
- `IronwoodMigrationOperationRegistry` serializes work per network/account and
  provides revocation tokens. Commit keeps a deleted account revoked for late
  callbacks; rollback permits retry when mutation did not happen.
- `IronwoodMigrationCoordinator` owns foreground permits, status refresh,
  reentry reconciliation, and automatic progression. Account deletion/reset
  must revoke and drain this work before changing the DB.

## Preparation core

- [`migration_preparation.rs`](../../rust/src/migration_preparation.rs) is a
  platform-neutral execution core. An operation owns one cancel token and a
  desired mode used by both its optional sync and advance phases.
- `begin_operation` is exclusive; `cancel_operation` signals the operation;
  `end_operation` removes and cancels its control object.
- Preparation sync uses mode `2` and a separate cancel token from foreground
  `cancelFullSync`. It still acquires the shared `SYNC_RUNNING` guard, so two
  scans cannot overlap.
- `inspect` and `advance` are mutating/foreground-capable paths because they may
  call schema-aware migration status and advancement helpers.
- `inspect_read_only`, `observable_transaction_ids`, and
  `inspect_proof_readiness` are the restricted observation surface used by iOS.
  Missing or incompatible tables are recovery signals, not permission to
  upgrade the DB from native background work.

## Current mobile support
- iOS owns a user-visible continued-processing task in
  [`BackgroundMigrationPreparationManager.swift`](../../ios/Runner/BackgroundMigrationPreparationManager.swift).
  It reads local preparation state/txids through C FFI and queries lightwalletd
  for the tip and exact transactions.
- iOS background preparation is watch-only. It never runs wallet sync, creates
  proofs, advances denomination stages, or loads a signing credential.
- The current repository has no Android preparation worker or Android
  `background_migration` channel. Dart returns `false` for background
  preparation tracking support on Android, and `_usesNativePreparation` excludes
  it. The platform-neutral Rust execution functions are not evidence of an
  installed Android runtime path.

## iOS read-only confirmation wave
- [`ffi.rs`](../../rust/src/ffi.rs) validates C inputs, catches panics, and maps
  native result structs. Its migration inspection calls the read-only Rust
  helpers; it does not invoke sync or advancement.
- Read-only SQLite access must remain `SQLITE_OPEN_READ_ONLY` below the helper
  boundary. Do not replace it with `migration_status` or any helper that calls
  `ensure_schema`.
- `NotFound`, mempool height `0`, and fork height `UInt64.max` contribute zero
  confirmations. A mined transaction contributes `tip - minedHeight + 1`,
  capped at the three-confirmation target.
- One system task tracks one materialized transaction wave. When every observed
  tx reaches the target, native code records a foreground continuation, posts
  the confirmed-step notification, and completes the task successfully.
- The task does not wait for user action or the next stage. Foreground reentry
  acknowledges the continuation, performs wallet sync and durable advancement,
  and schedules a fresh read-only task if another wave appears.
- Expiration interrupts one opportunity and re-arms tracking; by itself it is
  not a migration failure. Inspection, fork, notification, or quiescence
  failures retain their distinct recovery outcomes.

## Signed outbox exception
- Already-signed outbox transport may remain background-capable. It can inspect
  the chain and submit the exact staged transaction bytes, but it never scans
  the wallet or derives new signatures.
- iOS background lightwalletd calls use the pinned Direct opener described in
  [sync-network.md](sync-network.md). Foreground migration calls use the normal
  route policy.
- Outbox receipt reconciliation must distinguish “submitted but DB update still
  pending” from “credential or staged batch missing”; do not direct the former
  into credential repair.

## Stop, delete, and password change

- User stop retires or reconciles network-visible work according to durable run
  state; cancellation alone is not proof that a transaction was never sent.
- Password change is blocked while the migration preflight says encrypted
  migration state cannot be safely rotated.
- Account deletion revokes the account operation, quiesces native migration,
  removes account migration rows with the wallet transaction, and resumes work
  only for surviving accounts.
- Full reset discards unsigned/partially proved hardware requests and revokes
  signed outbox work before DB deletion. A failed preflight leaves the wallet
  intact and rolls back process revocations.

## Verification anchors

- Platform-neutral lifecycle and read-only schema behavior: tests beside
  [`migration_preparation.rs`](../../rust/src/migration_preparation.rs)
- iOS task state and handoff: tests in
  [`ios/RunnerTests/`](../../ios/RunnerTests)
- Dart service and coordinator behavior:
  [`test/features/migration/`](../../test/features/migration)
