# Migration signed outbox

Read when changing background submission of staged signed transaction bytes or reconciliation after transport/storage outcomes.

Implementation: [Dart orchestration](../../../../lib/src/features/migration/services/ironwood_migration_service.dart),
[native runner](../../../../ios/Runner/BackgroundMigrationOutboxRunner.swift), and
[Rust receipt reconciliation](../../../../rust/src/wallet/sync/send.rs).
Verify Dart recovery with the [service tests](../../../../test/features/migration/ironwood_migration_service_test.dart)
and receipt outcomes with the [Rust send tests](../../../../rust/src/wallet/sync/send/tests.rs).

## Signed outbox exception

- Background-capable signed outbox transport may inspect the chain and submit
  exact staged transaction bytes; it never scans the wallet or derives signatures.

- iOS background lightwalletd calls use the pinned Direct opener described in
  [iOS background transport](../../platforms/ios/background-transport.md). Foreground migration calls use the normal
  route policy.

- Reconcile “submitted, DB update pending” separately from “credential/staged
  batch missing”; the former must not enter credential repair.

## Verification anchors

- Dart service and coordinator behavior:
  [`test/features/migration/`](../../../../test/features/migration)

## Related changes

- When changing iOS background networking, preserve [the pinned Direct opener](../../platforms/ios/background-transport.md).
- When changing stop/reset revocation of staged work, read [migration lifecycle](run-lifecycle.md).
