# iOS migration confirmation

Read when changing the watch-only iOS task, read-only DB access, per-wave notifications, or multi-account continuation handoff.

## iOS task scope

- iOS's user-visible continued-processing task is in
  [`BackgroundMigrationPreparationManager.swift`](../../../../ios/Runner/BackgroundMigrationPreparationManager.swift).
  It reads preparation state/txids through C FFI and queries lightwalletd for
  the tip and exact transactions.

- iOS preparation is watch-only: no wallet sync, proofs, denomination advancement,
  or signing credentials.

## iOS read-only confirmation wave

- [`ffi.rs`](../../../../rust/src/ffi.rs) validates C inputs, catches panics, maps native
  results, and inspects through read-only Rust helpers without sync or advancement.

- Read-only SQLite access must remain `SQLITE_OPEN_READ_ONLY` below the helper
  boundary. Do not replace it with `migration_status` or any helper that calls
  `ensure_schema`.

- `NotFound`, mempool height `0`, and fork height `UInt64.max` contribute zero
  confirmations. A mined transaction contributes `tip - minedHeight + 1`,
  capped at the three-confirmation target.

- One system task tracks one materialized wave. Once all observed txs reach the
  target, submit any required confirmed-step notification before recording the
  foreground continuation and completing the task successfully.

- The task never waits for user action or the next stage. Foreground reentry
  acknowledges the continuation, syncs and advances durable state, then schedules
  a fresh read-only task if another wave appears.

- Expiration re-arms tracking; alone it is not migration failure. Inspection,
  fork, notification, and quiescence failures retain distinct recovery outcomes.

## iOS multi-account handoff

- Scopes use `network:account:run`. Foreground work for one account must not
  block another account's confirmation tracking.

- `migrationPreparationPendingTrackableScopes` returns confirmation-trackable
  scopes minus recorded continuations, preventing repeat tracking/notifications
  while foreground reconciliation is pending.

- `migrationPreparationHandoffContinuationScopes` preserves existing records
  and adds eligible scopes minus confirmation-trackable scopes. Mid-wave state
  `0` remains trackable; states `2`, `3`, `5`, or failed per-run inspections need
  foreground work. `applyTrackingBatch` already records confirmed waves after
  any required notification submission succeeds.

- `migrationPreparationHandoffHasBoundPreparation` tests whether any eligible
  run exists, independently of recorded continuations. A state-`0`-only launch
  stays bound with no new handoff records; otherwise cold launch cancels its
  healthy `.continuedProcessing` request.

## Verification anchors

- iOS task state and handoff:
  [`RunnerTests.swift`](../../../../ios/RunnerTests/RunnerTests.swift), especially
  `testForegroundOnlyAccountDoesNotVetoAnotherAccountsTracking`,
  `testHandoffDoesNotParkAnUnconfirmedTrackableRun`,
  `testTrackableOnlyLaunchIsBoundButRecordsNothing`, and
  `testFailedNotificationSubmissionDoesNotRecordContinuationScope`.

## Related changes

- When changing C/Rust inspection entry points, preserve [the restricted preparation surface](reference/preparation-core.md).
- When changing native lightwalletd access, read [background transport](../../platforms/ios/background-transport.md).
- When changing foreground advancement after a continuation, read [migration lifecycle](run-lifecycle.md).
