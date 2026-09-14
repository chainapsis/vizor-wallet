# Migration run lifecycle

Read when changing durable Ironwood runs, process operation ownership, user stop, or account deletion/reset preflight.

## Durable and process owners

- Rust wallet migration modules own the durable run, denomination stages,
  schedules, proposal locks, proof readiness, and outbox receipts.

- [`IronwoodMigrationService`](../../../../lib/src/features/migration/services/ironwood_migration_service.dart)
  owns Dart credentials and flat FRB calls, captures secure-storage generation,
  and zeros mnemonic byte buffers after handoff.

- `IronwoodMigrationOperationRegistry` serializes work per network/account and
  supplies revocation tokens. Commit keeps deleted accounts revoked against late
  callbacks; rollback allows retry when mutation did not happen.

- [`IronwoodMigrationCoordinator`](../../../../lib/src/features/migration/providers/ironwood_migration_coordinator_provider.dart)
  owns foreground permits, status refresh, reentry reconciliation, and automatic
  progression. Account deletion/reset revokes and drains this work before DB changes.

## Stop, delete, and password change

- User stop retires/reconciles network-visible work from durable run state;
  cancellation alone never proves a transaction was unsent.

- Account deletion revokes the account operation, quiesces native migration,
  removes migration rows in the wallet transaction, and resumes only surviving accounts.

- Full reset discards unsigned/partially proved hardware requests and revokes
  signed outbox work before DB deletion. Failed preflight preserves the wallet
  and rolls back process revocations.

## Verification anchors

- Dart service and coordinator behavior:
  [`test/features/migration/`](../../../../test/features/migration)

## Related changes

- When changing password rotation eligibility, preserve [password-change preflight](../security/change-password.md).
- When changing shared quiesce/pause/resume order, read [mutation barrier](../../references/wallet/mutation-barrier.md).
- When changing credential buffers or generations, read [secret sessions](../../references/storage/secret-sessions.md).
- When changing staging/submission recovery, read [signed outbox](signed-outbox.md).
