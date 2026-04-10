# CLAUDE.md

## Commands

```bash
# Always use fvm, never bare flutter
fvm flutter run
fvm flutter test
fvm flutter analyze

# Rust tests (run from project root or rust/)
cd rust && cargo test

# After changing Rust API files (rust/src/api/*.rs):
# MUST run from project root, not rust/
flutter_rust_bridge_codegen generate

# Clear app from iOS simulator (keychain + state + uninstall)
./clear-app.sh

# View Rust logs (log::info!, log::error!, etc.)
# FRB routes Rust logs to os_log (subsystem "frb_user"), not Flutter console.
# Run in a separate terminal:
log stream --predicate 'subsystem == "frb_user"' --level info
```

### clear-app.sh

Removes the app from the booted iOS simulator including Keychain data. This is necessary when testing wallet creation/import because the mnemonic is stored in iOS Keychain via `flutter_secure_storage`, which persists even after a normal app uninstall.

## Architecture

Flutter + Rust FFI via `flutter_rust_bridge` v2. All Zcash cryptography and sync run in Rust (`librustzcash` crates). Dart handles UI, state management (Riverpod), and secure storage only. Supports iOS, Android, and macOS.

### Multi-Account Model

Single DB (`zcash_wallet.db`) holds multiple accounts from different seeds. Single sync loop decrypts notes for all accounts simultaneously via `scan_cached_blocks` (uses all UFVKs). UI shows one "active account" at a time.

**Account creation strategy** (due to `zcash_client_sqlite` constraints):
- **First account**: `create_account()` → `AccountSource::Derived`. Uses `init_wallet_db(Some(seed))` so the seed fingerprint is pinned to the DB and future seed-requiring migrations can verify relevance.
- **Additional accounts (even if derived from a known software mnemonic)**: `import_account_ufvk(AccountPurpose::Spending { derivation })` → `AccountSource::Imported`. We have to go through this path because `create_account` enforces a single-seed fingerprint per DB, so the second software account with a different mnemonic would be rejected. Derivation metadata (`Zip32Derivation { seed_fp, account_index }`) is attached to the `Imported` record so the account's origin is at least known, but librustzcash never stores the seed itself for imported accounts.
- **DB init after the first account**: remains `init_wallet_db(None)`. Calling `init_wallet_db(Some(other_seed))` after the first account would fail the seed relevance check if `other_seed` doesn't match the pinned `Derived` account.

**Multi-account migration limitation.** librustzcash `init_wallet_db` docs explicitly state:

> *"Note that currently only one seed can be provided; as such, wallets containing accounts derived from several different seeds are unsupported, and will result in an error."*
>
> *"We do not check whether the seed is relevant to any imported account, because that would require brute-forcing the ZIP 32 account index space. Consequentially, seed-requiring migrations cannot be applied to imported accounts."*

What this means for our DB shape:
- **First account** (`Derived`, known seed): future seed-requiring migrations run correctly for this account.
- **Every account after the first** (`Imported`, different seed fingerprint): the DB holds derivation metadata but not the seed, and librustzcash's migration machinery cannot distinguish "software account with a second seed we happen to know" from "external account imported from another wallet entirely." Both look like `AccountSource::Imported` with a non-matching fingerprint. The hardware (Keystone) case is a special instance of this general pattern, not a separate problem.
- What happens to 2nd+ accounts during a seed-requiring migration depends entirely on how the individual migration is written. Schema-only migrations (the common case) apply unchanged. UFVK-based re-derivation migrations also work. Migrations that strictly need the per-account seed for an `Imported` record either skip the step, run a best-effort fallback, or — in the worst case — refuse to complete.
- The correct mental model: **our wallet behaves as a multi-seed wallet inside librustzcash's officially-unsupported envelope**. Everything works today because current migrations tolerate `Imported` accounts. A future migration that doesn't is a real risk, and there is no clean in-library escape hatch because `create_account` cannot be called on a DB that already holds unrelated `Imported` accounts.

**Hardware-first wallet constraint** (Keystone). Enforcing the general rule above, the first account in any wallet **must** be a software (`Derived`) account. `importKeystoneAccount` in `lib/src/providers/account_provider.dart` rejects the call when `accounts.isEmpty`, and `import_hardware_account` in `rust/src/wallet/keys.rs` backstops the same invariant by scanning `AccountSource::Derived` before proceeding. This does not make the multi-account migration limitation go away — it only guarantees that:
- `init_wallet_db(Some(seed))` has at least one `Derived` account to verify against, so future seed-requiring migrations can at least *start* (an `Imported`-only DB would fail the relevance check with `SeedRelevance::NoDerivedAccounts` and refuse to open).
- The first account in every wallet is always fully covered by any seed-requiring migration.
- `create_account()` cannot rescue a DB that has already fallen into `Imported`-only state — that call itself needs seed-aware init, which re-fails the relevance check. Once you are in the bad state, you are stuck there. Forcing the first account to be `Derived` is the only way to prevent it at DB-creation time.

**Production tradeoff** (to revisit before release). Blocking hardware-first bootstrap gives the strongest migration guarantee but is hostile to Keystone-only users (they are forced to create or import a software mnemonic first). Alternatives considered: a hidden throwaway-mnemonic bootstrap (hacky, confuses the account list), or accepting the risk and documenting a re-import recovery flow when a future seed-requiring migration lands (simpler UX but requires users to re-scan from Keystone birthday when it happens). The current branch takes the conservative block. The actual production decision is deferred.

**Account identification**: `AccountUuid` (UUID string like `"550e8400-e29b-41d4-a716-446655440000"`). Passed as `String` between Dart and Rust via `Uuid::parse_str()` / `Uuid::to_string()`.

**Mnemonic storage**: Per-account in Flutter secure storage (`zcash_account_mnemonic_{uuid}`). Account list stored as JSON in `zcash_accounts` key. Active account in `zcash_active_account` key.

### Dart Provider Structure

```
AccountProvider (account_provider.dart)
  ├── Manages account list, active account, per-account mnemonics
  ├── createAccount() — first: create_wallet, additional: generateMnemonic + addAccount
  ├── importAccount() — first: import_wallet, additional: addAccount
  ├── switchAccount() — updates active, refreshes address
  └── getActiveMnemonic() — reads from secure storage

WalletProvider (wallet_provider.dart)
  ├── Watches AccountProvider
  ├── Exposes hasWallet, unifiedAddress, activeAccountUuid
  └── Propagates errors (does NOT mask as empty state)

SyncProvider (sync_provider.dart)
  ├── Listens to AccountProvider (ref.listen, not watch) — auto-starts sync on account creation
  ├── startSync() is fire-and-forget with _syncGen generation counter
  ├── Polls getLatestBlockHeight every 10s after sync completes
  ├── Re-syncs automatically when new blocks detected or previous sync incomplete
  ├── Duplicate sync guard: _isSyncing (Dart) + isSyncRunning() (Rust)
  ├── Passes activeAccountUuid to getBalance, getTransactionHistory
  ├── Sync itself is account-agnostic (covers all accounts)
  ├── Delegates background sync to BackgroundSyncDelegate (Android/iOS/NoOp)
  ├── Polling pauses on app background (onHide), resumes on foreground (onResume)
  ├── Background sync completion detected on resume via delegate.onResume()
  └── refreshAfterSend() called after account switch for immediate update
```

### Sync Engine (Rust-only)

The entire sync loop runs in Rust (`rust/src/wallet/sync_engine.rs`). A single call from Dart (`startFullSync()`) triggers the full pipeline:

1. tonic gRPC → lightwalletd (TLS via `tls-ring`)
2. Download subtree roots (sapling + orchard, incremental with start_index optimization)
3. Download compact blocks into memory (in-memory `MemoryBlockSource`, no file I/O)
4. `scan_cached_blocks` from memory (100 blocks per batch)
5. Enhancement: fetch full tx data (`GetStatus`, `Enhancement`, `TransactionsInvolvingAddress`)
6. Progress streamed to Dart via FRB `StreamSink` per batch

Single DB connection reused across entire sync (opened once, passed to all operations).

Progress percentage: `initial_total` (total blocks to scan) is captured once before the scan loop from `suggest_scan_ranges()`. After each batch, `remaining` unscanned blocks are recalculated, then `pct = 1.0 - remaining / initial_total`. Note: `suggest_scan_ranges()` does not return `Scanned` ranges, so per-batch `total` cannot be used as the denominator. Each progress event includes `has_new_tx` (from `ScanSummary` received/spent note counts) to trigger transaction history refresh only when needed.

Automatic retry: `run_sync_inner` wraps `run_sync_impl` with exponential backoff (3 retries, 2s/4s/8s). Cancel and mode-change are checked during retry wait. Both FRB and C FFI paths benefit.

All sync log messages include `[Xs]` elapsed time from sync start (set once in `run_sync_inner`, consistent across retries). Errors are logged via `log` crate (forwarded to os_log subsystem `frb_user` by FRB `setup_default_user_utils()`). Log level set to `Info` to filter verbose rustls TLS logs. Rust logs are NOT visible in `flutter run` terminal — use `log stream --predicate 'subsystem == "frb_user"' --level info` in a separate terminal.

### Rust Module Structure

```
rust/src/
├── lib.rs              # pub mod api, ffi, wallet, frb_generated
├── api/
│   ├── mod.rs          # pub mod simple, sync, wallet
│   ├── simple.rs       # init_app() with setup_default_user_utils() + log level filter
│   ├── wallet.rs       # FRB: create_wallet, import_wallet, add_account, list_accounts,
│   │                    # generate_mnemonic, get_unified_address(account_uuid),
│   │                    # get_transparent_address(account_uuid), get_latest_block_height
│   └── sync.rs         # FRB: start_full_sync(StreamSink, mode), cancel_full_sync(),
│                        # set_sync_mode(), get_sync_mode(), is_sync_running(),
│                        # get_balance(account_uuid), get_transaction_history(account_uuid),
│                        # propose_send(account_uuid), estimate_fee(account_uuid),
│                        # execute_proposal, get_next_available_address(account_uuid)
│                        # DESIRED_SYNC_MODE, SYNC_RUNNING, SYNC_CANCEL globals
├── ffi.rs              # C FFI for Swift: zcash_run_full_sync(), zcash_cancel_sync(),
│                        # zcash_get/set_sync_mode(), zcash_is_sync_running()
│                        # TX tracking: zcash_get_pending_txs(), zcash_check_tx_status()
│                        # Validates C strings, logs all errors, checks mode before starting
│                        # Uses current_thread tokio runtime (inherits iOS .utility QoS)
│                        # Located outside api/ to avoid FRB codegen picking it up
├── wallet/
│   ├── mod.rs          # pub mod keys, sync, sync_engine
│   ├── keys.rs         # Key derivation, mnemonic, account creation (Derived + Imported),
│   │                    # list_accounts, ensure_db_initialized, parse_account_uuid
│   ├── sync.rs         # Per-account wallet operations (balance, send, history, etc.)
│   │                    # All per-account functions take account_uuid parameter
│   │                    # NoOp Sapling provers for Orchard-only transactions
│   │                    # TX broadcast via gRPC SendTransaction
│   └── sync_engine.rs  # run_sync_inner() — retry wrapper (3 retries, 2/4/8s backoff)
│                        # run_sync_impl() — single sync attempt
│                        # MemoryBlockSource (BlockSource trait impl)
│                        # Single DB connection reused across entire sync
│                        # Checks cancel + mode mismatch after each download/scan/batch
│                        # Progress: initial_total based (remaining / initial_total)
│                        # has_new_tx from ScanSummary note counts
└── frb_generated.rs    # Auto-generated by flutter_rust_bridge
```

### Two FFI Paths

```
Dart (foreground)                    Swift (iOS background)
    │                                    │
    ▼                                    ▼
api/sync.rs                          ffi.rs
start_full_sync(mode=1, sink)        zcash_run_full_sync() [C FFI, mode=2]
    │                                    │
    ▼                                    ▼
    └──── both call ────► sync_engine::run_sync_inner(running_mode, &DESIRED_MODE)
                              │
                              ▼
                    gRPC + scan + enhancement
                    (exits if DESIRED_MODE != running_mode)
```

- **Dart → Rust**: via `flutter_rust_bridge` (FRB). `start_full_sync()` returns `Stream<ApiSyncProgressEvent>`.
- **Swift → Rust**: via C FFI (`#[no_mangle] pub extern "C"`). `ffi.rs` exposes sync functions. Swift calls through `zcash_sync.h` imported in `Runner-Bridging-Header.h`.

`ffi.rs` is at `rust/src/ffi.rs` (NOT in `api/`) to prevent FRB codegen from generating Dart bindings for it.

### Sync Mode Management

Rust has a shared `DESIRED_SYNC_MODE` AtomicU8 (0=none, 1=foreground, 2=background).

- `run_sync_inner` checks `DESIRED_MODE != running_mode` after each batch → graceful exit
- Also checks after download and after scan (mid-batch) for faster response
- `SYNC_RUNNING` AtomicBool prevents concurrent sync (shared between FRB and C FFI)
- `SYNC_CANCEL` Arc<AtomicBool> unified — both `cancelFullSync()` (Dart) and `zcash_cancel_sync()` (Swift) set the same flag
- C FFI checks `DESIRED_MODE == 2` before starting (does not force-set mode)

### Foreground ↔ Background Sync Transitions

**Android**: Foreground service (`flutter_foreground_task`) adds notification only. Sync continues via same Dart FRB stream. No mode switching needed.

**iOS (26+)**: Mode switch triggers sync handoff.

Foreground → Background:
1. Dart: `setSyncMode(2)` → Rust fg sync exits at next batch
2. Dart: `bg_sync.startBackgroundSync()` → Swift BGTask submit
3. Swift handler (`using: nil`): dispatches to `.utility` syncQueue
4. Waits for `mode==2 && !is_running` (timeout 120s) → `zcash_run_full_sync()`
5. On completion with mode still 2: resubmits BGTask to continue

Background → Foreground:
1. Dart: `setSyncMode(1)` → Rust bg sync exits at next batch
2. Dart: waits for `isSyncRunning()==false` (timeout 120s) → `startSync()`

Expiration: `expirationHandler` cancels heartbeat + sets mode=0 + cancel → no resubmit → on app resume, detects mode=0 with backgroundMode=true → restarts foreground sync.

### iOS Background Sync

Uses `BGContinuedProcessingTask` (iOS 26+). Swift calls Rust directly via C FFI.

```
BGTaskScheduler.register(using: nil)  ← expirationHandler can run on different queue
    │
    ▼
handleBackgroundTask()
    ├── expirationHandler set (cancels heartbeat + sync)
    ├── syncQueue.async { runSync() }  ← .utility QoS, Rust inherits this
    └── semaphore.wait()               ← handler thread waits, doesn't block syncQueue

runSync():
    → wait for mode==2 && !is_running (timeout 120s)
    → heartbeat timer on .global(qos: .utility) — nudges completedUnitCount +1 every 5s
    → zcash_run_full_sync() [C FFI, blocking, current_thread tokio]
    → C callback: sets completedUnitCount = percentage * 10000 (scan-queue based)
    → C callback → SyncProgressStreamHandler → EventChannel → Dart (if foreground)
    → EventChannel forwards: scannedHeight, chainTipHeight, percentage, isSyncing, isComplete, hasNewTx
    → on completion: if mode still 2, resubmit BGTask
```

Key files:
- `ios/Runner/BackgroundSyncManager.swift` — `@available(iOS 26.0, *)`, BGTask handling with semaphore pattern
- `ios/Runner/AppDelegate.swift` — task registration, MethodChannel + EventChannel, simulator check
- `ios/Runner/SyncProgressStreamHandler.swift` — bridges C callback → Dart EventChannel
- `ios/Runner/zcash_sync.h` — C header for all FFI functions

### iOS TX Tracking

Separate `BGContinuedProcessingTask` (`com.zcash.zcashWallet.txtrack`) polls lightwalletd `GetTransaction` every 5s to detect when pending transactions are mined or expired.

- `TxTrackManager.swift` — manages BGTask lifecycle, poll loop with `cancelled` flag
- `DynamicIslandManager.swift` — Live Activity lifecycle, priority switching (TX tracking > sync)
- Widget extension (`SyncWidget/`) — dual UI for sync progress and TX tracking states

### Send Flow

2-step: `propose_send(account_uuid)` → confirmation dialog (shows fee) → `execute_proposal()` → broadcast via `SendTransaction` gRPC.

- Integer-only ZEC-to-zatoshi parsing (no floating-point)
- Real fee estimation via `estimate_fee(account_uuid)` on each keystroke
- No-op Sapling provers for Orchard-only TXs (avoids 50MB param download)
- Post-send: `refreshAfterSend()` for immediate pending TX display
- Friendly error messages via `_friendlyError()` pattern matching

### Wallet Creation

`create_wallet()` fetches chain tip from lightwalletd as birthday height before creating the account. This prevents new wallets from doing a full chain scan. Birthday fetch failure blocks wallet creation (network required).

### Rust API Design Constraint

FRB codegen works best with simple types. Keep the `rust/src/api/` surface limited to primitives, `String`, and flat structs. Do all complex Zcash type manipulation inside `rust/src/wallet/` and return simple results through `rust/src/api/`.

All per-account API functions take `account_uuid: String`. Sync-level operations (`start_full_sync`, etc.) operate on all accounts and do NOT take account_uuid.

### Key Security Model

`zcash_client_sqlite` intentionally does NOT store spending keys in the DB — only viewing keys (UFVK). The mnemonic/seed lives in Flutter's `flutter_secure_storage` (iOS Keychain / Android Keystore) per-account (`zcash_account_mnemonic_{uuid}`) and is passed to Rust only when needed for transaction signing. Seed is scoped in a block and dropped before network I/O (broadcast).

### WalletDb Initialization

`WalletDb::for_path()` requires 4 params: `(path, Network, SystemClock, OsRng)`. `init_wallet_db()` must be called before `create_account()` — it runs schema migrations. First account uses `init_wallet_db(Some(seed))` for migration support; subsequent DB opens use `init_wallet_db(None)`.

### Dart Sync Provider

`lib/src/providers/sync_provider.dart` — Riverpod `AsyncNotifier`.

**Auto-sync lifecycle:**
- `build()` watches `accountProvider` via `ref.listen` (not `ref.watch` — avoids rebuild on switch/rename)
- Account count increase triggers `startSync()` + `_startPolling()` (both first account and additional accounts)
- `_checkAndSync()`: polls `getLatestBlockHeight` every 10s, re-syncs if tip > last synced height or previous sync incomplete (`percentage < 1.0`)
- Polling stops during `_checkAndSync` execution to prevent concurrent overlap, restarts after
- Duplicate sync guard: `_isSyncing` (Dart-side bool) + `isSyncRunning()` (Rust AtomicBool)

**startSync() is fire-and-forget:**
- Sets up FRB stream listener and returns immediately (no Completer, no await)
- `_syncGen` generation counter: incremented by `stopSync()`, checked in `.then()` callbacks to invalidate pending operations after user-initiated stop
- Stream `onDone` → `_onSyncDone()` (balance refresh + start polling)
- Stream `onError` → sets error state + starts polling for auto-retry

**Sync control:**
- `stopSync()`: increments `_syncGen` + `cancelFullSync()` + `_stopPolling()`. Polling does not restart until next `onResume`
- `enableBackgroundSync()`: delegates to `BackgroundSyncDelegate`
- `disableBackgroundSync()`: delegates to `BackgroundSyncDelegate`. `disable()` returns `bool` — iOS returns `true` (needs fg restart), Android returns `false`

**BackgroundSyncDelegate** (`background_sync_delegate.dart`):
- Abstract interface with Android/iOS/NoOp implementations
- All `Platform.isAndroid`/`Platform.isIOS` checks isolated here (zero in sync_provider.dart)
- `shouldSuppressPolling`: Android=`false` (notification only), iOS=`_active` (BGTask manages sync)
- Android: `onSyncDone()` keeps `_active` true (notification persists across sync cycles)
- iOS: `onResume()` detects bg sync completion/expiration, `onProgress()` detects EventChannel completion

**Lifecycle:**
- `onResume`: refreshes balance → `_bgDelegate.onResume()` → `_checkAndSync()` (which starts polling)
- `onHide`: stops polling (no wasted network in background)
- `SyncState.recentTransactions`: latest 10 transactions, updated on `hasNewTx`, sync completion, and app resume
- All balance/history queries pass `activeAccountUuid` from `AccountProvider`
- `background_sync_service.dart`: platform abstraction (Android foreground service + iOS MethodChannel)

## Testing

- Rust unit tests: `cd rust && cargo test` (8 tests: key derivation, address encoding, determinism)
- Dart unit tests: `fvm flutter test`
- Integration tests: `fvm flutter test integration_test/` (requires device/simulator)
- Debug vs Release: Rust crypto is ~5-10x slower in debug (`opt-level=0`). Use `--release` for realistic sync performance.

## Crate Versions

Pinned in `rust/Cargo.toml`. Key crates: `zcash_client_backend` 0.21.2, `zcash_client_sqlite` 0.19.5, `orchard` 0.11, `sapling-crypto` 0.5. These must stay compatible — check librustzcash releases before bumping.

`tonic` 0.14 with `tls-ring` + `tls-webpki-roots` features for gRPC TLS. `rustls` 0.23+ requires explicit crypto provider — `tls-ring` provides this.

`log` 0.4 for Rust logging — forwarded to Flutter console via FRB. Level set to `Info` in `init_app()`.

Additional crates for multi-account: `uuid` 1.1, `zip32` 0.2, `jubjub` 0.10, `bls12_381` 0.8, `rand_core` 0.6.

## Ignored Paths

`onboarding/` — Developer onboarding documentation. Do not read or modify during normal development. Only update when explicitly asked.
