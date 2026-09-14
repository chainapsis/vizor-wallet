# Account deletion

Read when changing deletion of one account, selection of a surviving account, or the last-account reset handoff.

## Surviving account selection

- Account order is UI metadata. After deletion Dart compacts order values and
  selects a surviving active UUID. Rust checks the requested UUID exists before
  deleting account-scoped rows.

## Destructive operations

- The Accounts UI deletes individual accounts only while another remains. The
  last account requires full wallet reset: drains, DB/storage cleanup, cached
  DB-path clearing, and onboarding navigation.

- Per-account deletion refuses unknown UUIDs and protected in-flight operations.
  It clears Rust rows first. Ancillary secure-storage and cache cleanup is
  separately reported best-effort work where the implementation allows recovery.

## Verification anchors

- Account removal/reset surfaces:
  [`account_provider_test.dart`](../../../../test/providers/account_provider_test.dart)

- Rust account deletion and scan-range repair:
  tests beside [`wallet/keys.rs`](../../../../rust/src/wallet/keys.rs)

## Related changes

- Before deleting wallet rows, complete [mutation barrier](../../references/wallet/mutation-barrier.md).
- When the last account is removed, follow [full wallet reset](../wallet/reset.md).
- When changing migration revocation or protected work, read [migration lifecycle](../migration/run-lifecycle.md).
- When deleting the seed-anchor account, preserve [seed-migration limitations](../../references/accounts/account-model.md).
