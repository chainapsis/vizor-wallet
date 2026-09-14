# Wallet mutation barrier

Read when changing the shared quiesce/drain/pause boundary or success/failure recovery around wallet mutations.

## Registered writers

- Use the wallet mutation guard to stop and drain sync before DB changes.
  Account deletion and reset also revoke and drain account migration work and
  other registered background writers before touching wallet rows.

## Quiesce, pause, mutation, and recovery

[`runWithSyncPausedForAccountMutation`](../../../../lib/src/providers/wallet_mutation_guard.dart) runs inside the [Linux keyring mutation boundary](../../platforms/linux/keyring.md). When applicable, it quiesces migration first, drains voting work second, then pauses foreground sync before running the action. Draining voting before the sync pause prevents a waiting precompute from queuing a newer sync after the pause.

Successful mutations resume only when `resumeAfterMutation` allows it. Failure recovery follows `shouldResumeAfterFailure` or `resumeAfterFailure`; full reset does not restart sync after the DB was deleted. Attempted migration quiescence is released even after an ambiguous response. A failure to resume migration is best-effort and must not turn an already committed mutation into a reported mutation failure.

## Sync pause and resume

- `pauseForWalletMutation` snapshots which work was active, requests mode `0`,
  cancels and drains Rust work with the longer destructive-operation timeout,
  and fails the mutation if quiescence is not reached.

- `resumeAfterWalletMutation` restores only the snapshotted lanes, unless the
  wallet is now locked.

## Verification anchors

- Destructive ordering:
  [`wallet_mutation_guard_test.dart`](../../../../test/providers/wallet_mutation_guard_test.dart)

## Related changes

- For account-specific migration revocation and rollback, read [migration lifecycle](../../domains/migration/run-lifecycle.md).
- For DB/storage deletion and the no-resume-after-deletion boundary, follow [wallet reset](../../domains/wallet/reset.md).
- When changing participant voting leases, read [voting participant](../../domains/voting/mutation-participant.md).
- When changing Gift Card claim writers, read [claim submission](../../domains/gift-cards/claim-submission.md).
