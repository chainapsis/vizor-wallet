# Wallet database identity and writes

Read when changing randomized wallet DB identity, Rust writer serialization, or the boundary between DB and secure-store deletion.

## Entry points and ownership

- `AppSecureStore` owns encrypted secret storage and the randomized wallet DB
  name. Account code must resolve the DB path before destructive storage work.

- [`with_wallet_db_write_lock`](../../../../rust/src/wallet/db.rs) serializes Rust
  wallet DB writers within this OS process only and advances the summary-cache
  write epoch. Account and migration writes need this lock even when Dart
  mutation draining is used.

## Verification anchors

- Destructive ordering:
  [`wallet_mutation_guard_test.dart`](../../../../test/providers/wallet_mutation_guard_test.dart)

- Rust account deletion and scan-range repair:
  tests beside [`wallet/keys.rs`](../../../../rust/src/wallet/keys.rs)

## Related changes

- For the complete destructive sequence and partial-failure behavior, follow [wallet reset](../../domains/wallet/reset.md).
- For account UUID and seed/schema assumptions, read [account model](../accounts/account-model.md).
