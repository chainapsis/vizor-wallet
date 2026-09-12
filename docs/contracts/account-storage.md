# Account and storage contract

## Scope

Use this contract for account creation, import, selection, deletion, wallet
reset, account metadata, mnemonics, and wallet database identity. Password and
session rules are in [security-lifecycle.md](security-lifecycle.md); sync pause
and cache rules are in [lock-sync.md](lock-sync.md).

## Entry points and ownership

- Dart owns the persisted account list, active account UUID, account metadata,
  and per-account software secrets in
  [`AccountNotifier`](../../lib/src/providers/account_provider.dart).
- `AppSecureStore` owns encrypted secret storage and the randomized wallet DB
  name. Account code must resolve the DB path before destructive storage work.
- Rust owns wallet rows and Zcash account derivation in
  [`wallet/keys.rs`](../../rust/src/wallet/keys.rs). The FRB boundary in
  [`api/wallet.rs`](../../rust/src/api/wallet.rs) parses flat inputs and returns
  flat result structs; complex Zcash types stay below that boundary.
- [`with_wallet_db_write_lock`](../../rust/src/wallet/db.rs) serializes Rust
  wallet DB writers within this process and advances the summary-cache write
  epoch. Keep account and migration writes under this lock; Dart mutation
  draining does not replace it. It does not coordinate separate OS processes.
- Account identity across Dart and Rust is the UUID string exposed by
  `AccountUuid`, not list order or display name.

## Creation and import

- Creating the first software account deletes any stale DB at the resolved path,
  initializes with its seed, and creates a `Derived` account. This pins that
  seed as the database's seed-aware migration anchor.
- Additional software accounts may be imported from other seeds. They enter the
  shared DB through UFVK import with ZIP 32 derivation metadata and are
  `Imported`; their mnemonic and optional BIP 39 passphrase remain in secure
  storage.
- Same-seed account discovery can import higher ZIP 32 indices as derived
  accounts only when the existing database anchor matches that seed.
- A Keystone UFVK may be the first account. It requires no local mnemonic and
  can create an `Imported`-only database.
- Birthday selection is part of account recovery correctness. Fresh creation
  requires a current lightwalletd height; import may use a caller-supplied
  birthday or the discovery path.
- Persist the network when the first account succeeds. Existing-wallet imports
  use the wallet's stored network rather than a newly selected endpoint network.

## Startup snapshot

- [`loadAppBootstrap`](../../lib/src/app_bootstrap.dart) reconciles stored account
  metadata with Rust account rows and supplies the router, account, wallet, and
  sync providers with one startup snapshot. Normal startup awaits it before
  `runApp`, so the first frame already has its route and account state.
- Route from that snapshot: no wallet goes to `/welcome`, a locked wallet to
  `/unlock`, and an unlocked wallet to `/home`. Locked bootstrap does not publish
  the active address or hydrate balance/history; unlock restores those later.
- Initial balance/history hydration is best-effort and falls back to an empty
  snapshot for the same account. Secure-storage failure or
  DB migration failure blocks startup instead of masquerading as an empty
  wallet. Keep those failure boundaries separate.

## Multi-account invariants

- One wallet DB contains all accounts, including accounts from different seeds.
  The UI selects one active account, while the Rust scanner decrypts for every
  UFVK in the database.
- The first `Derived` account is not undeletable. Removing it can leave only
  `Imported` accounts and retains the seed-migration limitation below.
- Account order is UI metadata. After deletion Dart compacts order values and
  chooses a surviving active UUID; Rust validates that the requested UUID
  exists before deleting account-scoped rows.
- Switching accounts invalidates pending secret operations before resolving the
  new address. A completion from an older secure-storage session must not
  publish an address into the current session.

## Seed-migration limitation

- `zcash_client_sqlite` accepts one seed during initialization. A DB containing
  unrelated seeds is outside its fully supported seed-migration model.
- Schema-only and UFVK-based migrations can work for imported accounts. A future
  migration that strictly needs each imported account's seed may skip work,
  fail, or require a product recovery flow.
- Never pass an arbitrary seed to repair an `Imported`-only or multi-seed DB.
  Normal once-per-process migration uses `ensure_db_migrated_once` without a
  seed. The bootstrap software-account path is the seed-aware exception.

## Destructive operations

- Use the wallet mutation guard to stop and drain sync before changing the DB.
  Account deletion and reset also revoke and drain account migration work and
  other registered background writers before touching wallet rows.
- The Accounts UI uses per-account deletion only while another account remains.
  Removing the last account takes the full wallet-reset path, including reset
  drains, DB/storage cleanup, cached DB-path clearing, and onboarding navigation.
- Per-account deletion refuses unknown UUIDs and protected in-flight operations.
  It clears Rust rows first, then treats ancillary secure-storage and cache
  cleanup as separately reported best-effort work where the implementation says
  recovery remains possible.
- Full reset resolves the DB path first. If path lookup fails, delete nothing:
  removing the stored randomized name would orphan the existing DB.
- Full reset deletes the DB before secure storage. Once the DB is gone,
  `deleteAll` is retryable; the caller must then call
  `SyncNotifier.clearCachedWalletDbPath` so the next wallet resolves a new name.
- Reset also returns the network route to Direct without routing that transition
  through a sync restart against the DB being removed.

## Verification anchors

- Account/session behavior:
  [`account_metadata_session_test.dart`](../../test/providers/account_metadata_session_test.dart)
- Destructive ordering:
  [`wallet_mutation_guard_test.dart`](../../test/providers/wallet_mutation_guard_test.dart)
- Account removal/reset surfaces:
  [`account_provider_test.dart`](../../test/providers/account_provider_test.dart)
- Rust account deletion and scan-range repair:
  tests beside [`wallet/keys.rs`](../../rust/src/wallet/keys.rs)
