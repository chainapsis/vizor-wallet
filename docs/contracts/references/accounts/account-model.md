# Account identity and seed model

Read when changing account identity, first/additional account derivation, or seed-aware DB migration assumptions.

## Entry points and ownership

- Dart owns the stored account list, active UUID, metadata, and per-account
  software secrets in
  [`AccountNotifier`](../../../../lib/src/providers/account_provider.dart).

- Rust owns wallet rows and Zcash account derivation in
  [`wallet/keys.rs`](../../../../rust/src/wallet/keys.rs). The FRB boundary in
  [`api/wallet.rs`](../../../../rust/src/api/wallet.rs) uses flat inputs and result
  structs; complex Zcash types stay below it.

- Dart and Rust identify accounts by the UUID string exposed by
  `AccountUuid`, not list order or display name.

## Derived and imported accounts

- Creating the first software account deletes any stale DB at the resolved path,
  initializes with its seed, and creates a `Derived` account, pinning that seed
  as the seed-aware migration anchor.

- Additional software accounts, possibly from other seeds, enter the shared DB
  through UFVK import with ZIP 32 derivation metadata as `Imported`. Their
  mnemonic and optional BIP 39 passphrase remain in secure storage.

- Same-seed discovery can import higher ZIP 32 indices as derived accounts only
  when the existing DB anchor matches that seed.

- A Keystone UFVK may be the first account, requires no local mnemonic, and can
  create an `Imported`-only DB.

## Multi-account invariants

- One wallet DB holds all accounts, including different seeds. The UI selects
  one active account; the Rust scanner decrypts for every UFVK in the DB.

- Deleting the first `Derived` account may leave only `Imported` accounts, with
  the seed-migration limitation below.

## Seed-migration limitation

- `zcash_client_sqlite` accepts one initialization seed. Unrelated seeds in one
  DB fall outside its fully supported seed-migration model.

- Schema-only and UFVK-based migrations can work for imported accounts. A future
  migration that strictly needs each imported account's seed may skip work,
  fail, or require a product recovery flow.

- Never pass an arbitrary seed to repair an `Imported`-only or multi-seed DB.
  Normal once-per-process migration uses `ensure_db_migrated_once` without a
  seed; software-account bootstrap is the seed-aware exception.

## Verification anchors

- Rust account deletion and scan-range repair:
  tests beside [`wallet/keys.rs`](../../../../rust/src/wallet/keys.rs)

## Related changes

- When changing DB path identity or writer serialization, read [wallet database](../storage/wallet-database.md).
