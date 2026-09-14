# Wallet reset

Read when changing full wallet deletion, last-account reset, or recovery after partial reset failure.

## Reset sequence

Resolve the existing DB path before destructive storage work. Complete the registered-writer drains and sync pause through the mutation barrier before deleting the DB; then clear secure storage and the cached DB path before returning to onboarding.

## Destructive operations

- Full reset resolves the DB path first. If path lookup fails, delete nothing:
  removing the stored randomized name would orphan the existing DB.

- Full reset deletes the DB before secure storage. After DB deletion,
  `deleteAll` is retryable; the caller must then call
  `SyncNotifier.clearCachedWalletDbPath` so the next wallet resolves a new name.

- Reset returns the network route to Direct without restarting sync against the
  DB being removed.

## Security state

- `reset()` invalidates pending authentication, clears prepared setup and the
  session password, and publishes unconfigured locked state. The account reset
  flow owns durable wallet deletion.

## Cached path

- `clearCachedWalletDbPath` is mandatory after a successful full reset. Without
  it, sync can reopen the deleted wallet's cached randomized path instead of
  resolving the next wallet's new path.

## Failure and resume boundary

[`runWithSyncPausedForWalletReset`](../../../../lib/src/providers/wallet_mutation_guard.dart) clears the cached DB path even when reset throws. It does not resume sync after success or after a `WalletResetException` with `dbDeleted == true`; failures before DB deletion may resume the previous work.

## Verification anchors

- Destructive ordering:
  [`wallet_mutation_guard_test.dart`](../../../../test/providers/wallet_mutation_guard_test.dart)

- Account removal/reset surfaces:
  [`account_provider_test.dart`](../../../../test/providers/account_provider_test.dart)

## Related changes

- Before durable deletion, preserve [the mutation barrier](../../references/wallet/mutation-barrier.md).
- When revoking migration/outbox work during reset, preserve [migration reset preflight](../migration/run-lifecycle.md).
- When changing randomized DB identity or file deletion, read [wallet database](../../references/storage/wallet-database.md).
