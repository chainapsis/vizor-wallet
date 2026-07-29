# AGENTS.md

## Commands

```bash
# Always use fvm, never bare flutter
fvm flutter run
fvm flutter test      # mobile-tagged tests auto-skip (dart_test.yaml)
fvm flutter analyze

# Unless the task explicitly requires a visible window, run macOS E2E with the
# app window hidden. The scripts do this by default; opt out only when the
# window is needed for debugging or visual verification.
VIZOR_E2E_HIDDEN_WINDOW=false scripts/e2e/flutter-macos-regtest-import-sync.sh

# Mobile form factor: mobile-targeted runs and tests pass the token
# define. Details in the "Design Token Form Factor" section below.
fvm flutter run --dart-define=VIZOR_FORM_FACTOR=mobile
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile

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

## Design Token Form Factor (VIZOR_FORM_FACTOR)

UI design tokens (typography, component sizing) are selected at **build
time**, not runtime. The Figma `Sizing` and `Fonts` variable collections
have Desktop and Mobile modes; both are compiled in as const sets, and
`--dart-define=VIZOR_FORM_FACTOR=desktop|mobile` (default: `desktop`)
decides which one the unsuffixed token classes (`AppTypography.*`,
`AppInputSizing.*`, ...) resolve to. The unused set is tree-shaken from
release builds. Source of truth:
`lib/src/core/layout/app_form_factor.dart` (`kAppFormFactor`).

### When the define is required

- **Every mobile-targeted invocation** — `run`, `build`, `test`, and
  `drive` alike. The test binary is compiled per-lane like any other
  build, so widget tests that assert mobile-mode UI need the define too
  (full lane command in "Test lanes" below).
- Desktop (macOS) runs, widgetbook, and plain `fvm flutter test` need no
  flag — the default is `desktop`.

### What happens when you forget it

- **Debug app run on a phone**: fails fast at startup (assert in
  `lib/main.dart`) with the exact flag to pass.
- **Tests**: the default lane never runs mobile-tagged tests (they
  auto-skip — see "Test lanes" below), so the only risk is the mobile
  lane itself: `--run-skipped` without the define resolves desktop
  values. `test/mobile_lane_sanity_test.dart` fails first, by name, in
  that case.
- **Release builds**: no guard either — release/CI lanes for iOS/Android
  must hardcode the define or they ship desktop tokens.

### Test lanes

A single `flutter test` invocation compiles exactly one form factor —
the define cannot vary per test. Mobile-UI tests are opt-in via the
`mobile` tag:

- A test file that asserts mobile-mode UI MUST start with
  `@Tags(['mobile'])`.
- `dart_test.yaml` marks the `mobile` tag as skipped by default, so the
  plain desktop lane (`fvm flutter test`, no flags) never runs them —
  they report as skipped with the mobile-lane command as the reason.
- The mobile lane re-enables them:
  `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`
  (`--tags mobile` scopes the run to mobile tests, `--run-skipped`
  lifts the tag's default skip, the define compiles the mobile token
  set). Note `--run-skipped` lifts every skip inside the selected
  tests, so don't use `skip:` to park a broken mobile test — comment it
  out or fix it.
- `test/mobile_lane_sanity_test.dart` (tagged `mobile`) asserts the
  define, so a mobile-lane run missing `--dart-define` fails loudly by
  name instead of as confusing metric mismatches.

Untagged tests may run in either lane and must be lane-agnostic:

- Compare against token constants, not literal numbers:
  `expect(style, AppTypography.bodyMedium)` passes in both lanes;
  `expect(style.fontSize, 14)` passes only in the desktop lane.
- To pin one mode regardless of lane, reference the explicit sets:
  `AppTypographyDesktop` / `AppTypographyMobile`,
  `AppAssetSizeDesktop` / `AppAssetSizeMobile`,
  `AppButtonSizingDesktop` / `AppButtonSizingMobile`,
  `AppInputSizingDesktop` / `AppInputSizingMobile`.
- `test/core/theme/design_tokens_test.dart` follows these rules and
  passes in both lanes — use it as the reference.

### Rules for new code

- App code uses only the unsuffixed selectors. Reference the
  `*Desktop` / `*Mobile` sets directly only in tooling that must show
  both modes inside one binary (widgetbook galleries, token tests).
- New tokens with per-mode values follow the same pattern: a `*Desktop`
  + `*Mobile` const namespace pair plus a const selector in the
  unsuffixed class. The `Spacing`, `Radii`, `Units`, and `Window` groups
  are identical across Figma modes and stay single-mode (`AppSpacing`,
  `AppRadii`, `AppWindowSizing`).
- Form-factor branching in app code uses `kAppFormFactor` (const, so the
  dead branch is tree-shaken) — never `Platform.isIOS`-style checks.
  Runtime `Platform` checks remain only for OS-specific *behavior*
  (keychain, background sync), not for choosing UI metrics or layout
  shells.
- Widgetbook is exempt from the platform/define match check: previewing
  mobile tokens on a desktop host is legitimate —
  `fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile`.
  Only `lib/main.dart` asserts the match.

## Editing Figma

When the user explicitly asks you to modify a Figma file or design, read
`FIGMA-AI-FIX.md` completely before starting and use it as the instructions and
reference for that work.

## Figma Visual Verification

Use the widget-test capture as the default visual-comparison path in both
directions: when applying an existing Flutter implementation to Figma and when
implementing a Figma design in Flutter, then capturing the result to find and
correct differences from the design.

- Represent the required screen and state as a deterministic scenario in
  `lib/figma_compare/figma_compare_scenarios.dart`. Prefer reusing an existing
  Widgetbook fixture. The scenario must not depend on production wallet data,
  storage, network, or Rust state.
- Match the Figma reference's form factor, logical viewport, theme, locale,
  content, and component state. Use the widget-test renderer for normal
  desktop and mobile iterations:

  ```bash
  scripts/figma-compare.sh widget \
    --scenario <scenario> \
    --theme <dark|light>

  scripts/figma-compare.sh widget \
    --form-factor mobile \
    --scenario <mobile-scenario> \
    --theme <dark|light>
  ```

- Compare `content.widget.png` with the corresponding Figma capture side by
  side and, when practical, with an overlay or image diff. After implementing
  from Figma, correct the Flutter code and repeat the widget capture until no
  actionable visual difference remains. Do not use Widgetbook chrome as
  comparison evidence.
- For desktop typography, font weight can render differently across Figma,
  macOS, Windows, and Linux because platform font rasterization differs. Treat
  the weight as matching when Flutter's configured `fontWeight` value matches
  Figma's weight setting; do not choose a different weight solely to force
  pixel-level visual parity. Continue to verify font family, size, line height,
  letter spacing, wrapping, and positioning normally.
- If the required state is not registered, add a reusable deterministic
  capture scenario before falling back to a running platform app. Temporary
  production routes, bootstrap overrides, or provider changes are a last
  resort and must be removed before completion.
- Use native macOS or iOS Simulator captures only for a final check of behavior
  the widget-test renderer cannot represent, such as operating-system chrome,
  the real window shell, native insets, or a material platform-rendering
  difference. Keep the widget capture as the primary app-content comparison.
- A request to compare an implementation with Figma does not authorize any
  Figma mutation. Do not copy, move, or edit Figma nodes unless the user
  explicitly requests a Figma change. When they do, read `FIGMA-AI-FIX.md` in
  full and follow its target-approval, copy-only, and visual-parity workflow.

## Figma Layer Interpretation

When reading or implementing Figma designs, distinguish app UI from
operating-system chrome and presentation-only background layers.

- Ignore layers named `_MacOS Light Mode` and `_MacOS Dark Mode`. These are
  operating-system screenshots/images placed behind the design for presentation
  context only, and are not part of the app UI.
- In a `Screen` frame, ignore any `Controls` layer that is a sibling of
  `Window Contents`. This represents the native OS window title/status bar
  controls, not app content.
- If a Figma screen uses this structure, treat the meaningful app UI as starting
  inside `Window Contents`, specifically from the `Trailing Pane` layer onward.
- Do not recreate, style, test, or otherwise implement the ignored OS/background
  layers unless the user explicitly asks to work on native window chrome.

### Hardware Wallet QR Codes

Hardware-wallet PCZT QR codes prioritize scan reliability over Figma parity.
Use black-on-white square modules with an explicit quiet zone. Do not apply
decorative QR treatments to codes that Keystone devices need to scan.

## UI Copy Conventions

- **Sentence case is the project default for all user-facing strings**: button
  labels, nav items, tab titles, toasts, dialog titles/bodies, sidebar items,
  tooltips, error messages, status labels, form labels, picker headers, empty
  states, page titles. Only capitalize the first word and proper nouns. Keep
  proper-noun acronyms in their canonical form (`ZEC`, `USDC`, `USDT`, `NEAR`,
  `Vizor`, `Keystone`, `Zcash`, `Ethereum`).
- Figma-authored display headings may keep title case.
- This applies to interpolated labels too: `'$symbol deposit tx'`, not
  `'$symbol Deposit tx'`. The asset symbol carries its own casing; the rest of
  the label is sentence case.
- **Exception**: sidebar entries and screen titles may use Title Case (e.g.
  onboarding step labels `Secret Passphrase`, `Wallet Birthday Height`) — do
  not sentence-case them in copy sweeps.
- Existing rationale and full audit are in `qa-copy-review.csv` and
  `copy-review-20260528-1554.csv` at the repo root. Reference these before
  introducing new copy in this project.
- When editing existing copy, also update widgetbook fixtures
  (`lib/widgetbook/*.dart`) and tests (`test/`) that assert on the literal
  string — `find.text(...)` matchers, `expectedNextAction` fields, and
  `_tooltipWithMessage(...)` helpers will break otherwise.

## Release Notes

When asked to prepare user-facing release notes or a changelog for a release,
read `release_notes/README.md` and create `release_notes/vX.Y.Z.md`.
Unless the request explicitly says otherwise, draft desktop release notes for
Windows, Linux, and macOS from desktop user-facing changes only. Exclude
mobile-only changes.

### clear-app.sh

Removes the app from the booted iOS simulator including Keychain data. This is necessary when testing wallet creation/import because the mnemonic is stored in iOS Keychain via `flutter_secure_storage`, which persists even after a normal app uninstall.

### scripts/figma-export.js

Exports a single Figma node as a rendered, composited image (PNG / JPG / SVG / PDF) via the Figma REST API. Reach for this instead of the Figma MCP `use_figma` + `exportAsync` path whenever you need the bytes on disk as an asset. The MCP export route returns base64 through a 20 KB-truncated tool output, forcing a multi-call chunk reassembly; the REST endpoint renders server-side and returns a single signed URL, so one HTTP call produces the file.

```bash
node scripts/figma-export.js \
  --file <fileKey> --node <nodeId> \
  --output assets/illustrations/foo.png \
  [--scale 1|2|3]  # default 1
  [--format png|jpg|svg|pdf]  # default png
  [--force]  # required to overwrite a git-tracked output
```

`fileKey` and `nodeId` come from the Figma URL — `figma.com/design/<fileKey>/<name>?node-id=<nodeId>`. The node-id in the URL uses a dash (`258-5229`); the script expects the canonical colon form (`258:5229`).

`FIGMA_TOKEN` (read scope is enough, Settings → Security → "Generate new token") must be set. Keep it in `~/.zshenv` rather than `~/.zshrc` — Claude Code's Bash tool spawns a non-interactive zsh which only sources `.zshenv` by default.

Output is minimal: start line, "downloading rendered image", and either `ok: <path> (<KB>, <WxH> for PNG)` or `fail: <msg>` with a non-zero exit. Check the printed dimensions before trusting the file — a wrong node ID still renders "successfully", usually as a tiny junk image. Overwriting a git-tracked output is refused without `--force`; verify the render at an untracked path first.

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
- **Software bootstrap account** (`Derived`, known seed): future seed-requiring migrations run correctly for this account when the wallet was created through the software create/import path.
- **Imported accounts** (`Imported`, different seed fingerprint): the DB holds derivation metadata but not the seed, and librustzcash's migration machinery cannot distinguish "software account with a second seed we happen to know" from "external account imported from another wallet entirely." Both look like `AccountSource::Imported` with a non-matching fingerprint. The hardware (Keystone) case is a special instance of this general pattern, not a separate problem.
- What happens to 2nd+ accounts during a seed-requiring migration depends entirely on how the individual migration is written. Schema-only migrations (the common case) apply unchanged. UFVK-based re-derivation migrations also work. Migrations that strictly need the per-account seed for an `Imported` record either skip the step, run a best-effort fallback, or — in the worst case — refuse to complete.
- The correct mental model: **our wallet behaves as a multi-seed wallet inside librustzcash's officially-unsupported envelope**. Everything works today because current migrations tolerate `Imported` accounts. A future migration that doesn't is a real risk, and there is no clean in-library escape hatch because `create_account` cannot be called on a DB that already holds unrelated `Imported` accounts.

**Hardware-first wallet policy** (Keystone). Keystone accounts are allowed to be the first account. `importKeystoneAccount` in `lib/src/providers/account_provider.dart` routes a fresh install through password setup and then imports the hardware UFVK, and `import_hardware_account` in `rust/src/wallet/keys.rs` does not require an existing `Derived` account. This improves Keystone-only onboarding but accepts the known librustzcash tradeoff:
- A Keystone-first wallet can be `Imported`-only from DB creation time. Additional software accounts are also imported through UFVK metadata, so they do not automatically turn the wallet into a `Derived`-account DB.
- Current schema and UFVK-tolerant migrations should continue to work. A future seed-requiring migration that refuses `Imported`-only wallets may require a product recovery path, such as warning the user and re-importing/rescanning from the Keystone account birthday.
- Calling `create_account()` later is not a clean rescue mechanism for an `Imported`-only DB because that path itself depends on seed-aware initialization and seed relevance.

**Account deletion and reset invariants.** Per-account deletion is allowed for
any listed account while another account remains, including the initial
`Derived` seed-anchor account. Deleting that account can leave the wallet DB
containing only `Imported` accounts, which is the same migration tradeoff
accepted for Keystone-first onboarding: current schema and UFVK-tolerant
migrations should work, but a future seed-requiring migration may need a product
recovery path. Deleting the last remaining account is not a per-account delete;
the Accounts UI treats it as a full wallet reset, clearing the wallet DB, secure
storage, active account state, and routing back to onboarding. Dart
`AccountNotifier.removeAccount` and Rust `delete_account` still validate the
target account exists before removing account-scoped wallet rows.

**Account identification**: `AccountUuid` (UUID string like `"550e8400-e29b-41d4-a716-446655440000"`). Passed as `String` between Dart and Rust via `Uuid::parse_str()` / `Uuid::to_string()`.

**Mnemonic storage**: Per-account in Flutter secure storage (`zcash_account_mnemonic_{uuid}`). Account list stored as JSON in `zcash_accounts` key. Active account in `zcash_active_account` key.

### Wallet Password Policy

- The local wallet setup/unlock password is **ASCII-only**. Accept only printable
  English letters, numbers, and symbols (`0x21`-`0x7E`).
- Do **not** implement keyboard-layout or IME normalization for passwords
  (for example, treating Korean 2-beolsik input as QWERTY). Passwords are
  compared as exact strings under this ASCII-only policy.
- Reuse the shared Dart helper in
  `lib/src/core/security/password_policy.dart` for all password validation.
- The charset validation message must stay exactly:
  `Use only English letters, numbers, and symbols.`
- **Mobile passcode**: the mobile form factor sets and unlocks the wallet
  with a 6-digit passcode instead of a typed password. The digit string
  is stored verbatim as the wallet password through the same
  `appSecurityProvider` prepare/commit path — there is no separate
  credential model. `kWalletPasswordMinLength` is form-factor dependent
  (6 on mobile, 8 on desktop) because the security provider enforces it
  on commit; the mobile passcode screens additionally require exactly
  6 digits (`kMobilePasscodeLength`).

### Dart Provider Structure

```
AccountProvider (account_provider.dart)
  ├── Manages account list, active account, per-account mnemonics
  ├── createAccount() — first: create_wallet, additional: generateMnemonic + addAccount
  ├── importAccount() — first: import_wallet, additional: addAccount
  ├── importKeystoneAccount() — hardware UFVK import; may be first account
  │                              (Keystone-first accepts Imported-only DB risk)
  ├── switchAccount() — updates active, refreshes address
  ├── renameAccount() — AccountInfo.copyWith (preserves isHardware)
  ├── clearSensitiveStateForLock() — preserves account list/active UUID, clears in-memory address
  ├── restoreAfterUnlock() — rehydrates active account UA from Rust after unlock
  ├── getActiveMnemonic() — reads from secure storage only while unlocked (null for hardware/locked)
  └── isActiveAccountHardware — routes send flow to PCZT pipeline when true

WalletProvider (wallet_provider.dart)
  ├── Watches AccountProvider
  ├── Exposes hasWallet, unifiedAddress, activeAccountUuid
  └── Propagates errors (does NOT mask as empty state)

SyncProvider (sync_provider.dart)
  ├── Listens to AccountProvider (ref.listen, not watch) — auto-starts sync on account creation
  ├── startSync() is fire-and-forget with _syncGen generation counter
  ├── startSync() no-ops while wallet is locked (`appSecurityProvider.requiresUnlock`)
  ├── clearSensitiveStateForLock() — clears in-memory sync state, cancels Rust work, stops polling
  ├── clearCachedWalletDbPath() — must be called after wallet reset/deleteAll()
  │   so the next sync resolves the newly generated DB name instead of using the
  │   deleted wallet's cached path
  ├── startSyncAnyway() — unlock recovery path for cancelled-but-still-unwinding Rust sync
  ├── Polls getLatestBlockHeight every 10s after sync completes
  ├── Re-syncs automatically when new blocks detected or previous sync incomplete
  ├── Duplicate sync guard: _isSyncing (Dart) + isSyncRunning() (Rust)
  ├── `_sensitiveStateEpoch` discards late balance/progress updates after lock/sign-out
  ├── Passes activeAccountUuid to getBalance, getTransactionHistory
  ├── Sync itself is account-agnostic (covers all accounts)
  ├── Polling pauses on app background (onHide), resumes on foreground (onResume)
  ├── refreshAfterSend() called after account switch for immediate update
  └── refreshAfterUnlock() refreshes balances/history before foreground sync recovery
```

### App Bootstrap

`main()` does a one-shot bootstrap before `runApp()` and injects it via
`appBootstrapProvider`. This snapshot is the startup source of truth for the
first frame and avoids the old `/welcome -> /home` jump plus the "empty home
until sync callback arrives" flash.

- `loadAppBootstrap()` reads:
  - secure storage (`zcash_accounts`, `zcash_active_account`, `zcash_wallet_network`)
  - Rust wallet DB via `list_accounts`
  - active-account DB data via `get_sync_status`, `get_balance`,
    `get_transaction_history(limit: 10)`
- If the wallet is locked, bootstrap does **not** hydrate active address or
  initial balance/history; it routes straight to `/unlock` and lets the unlock
  flow repopulate that state.
- Router uses `bootstrap.initialLocation` instead of always starting at `/`.
- `AccountProvider` starts from `bootstrap.initialAccountState`.
- `WalletProvider` falls back to bootstrap values while `accountProvider` is
  still loading.
- `SyncProvider` starts from `bootstrap.initialSyncSnapshot` (balances, recent
  txs, scanned/tip heights) and then kicks off the normal live sync flow.
- Bootstrap is best-effort: route/account bootstrap can still succeed even if
  initial balance/history hydration fails, in which case sync state falls back
  to empty and the live sync repopulates it.

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
│   ├── mod.rs          # pub mod simple, sync, wallet, keystone
│   ├── simple.rs       # init_app() with setup_default_user_utils() + log level filter
│   ├── wallet.rs       # FRB: create_wallet, import_wallet, add_account, list_accounts,
│   │                    # delete_account,
│   │                    # generate_mnemonic, get_unified_address(account_uuid),
│   │                    # get_transparent_address(account_uuid), get_latest_block_height,
│   │                    # import_hardware_account (Keystone UFVK-only)
│   ├── sync.rs         # FRB: start_full_sync(StreamSink, mode), cancel_full_sync(),
│   │                    # set_sync_mode(), get_sync_mode(), is_sync_running(),
│   │                    # is_sync_cancel_requested(),
│   │                    # get_balance(account_uuid), get_transaction_history(account_uuid),
│   │                    # propose_send(account_uuid), estimate_fee(account_uuid),
│   │                    # execute_proposal, get_next_available_address(account_uuid),
│   │                    # create_pczt_from_proposal, add_proofs_to_pczt,
│   │                    # redact_pczt_for_signer, extract_and_broadcast_pczt,
│   │                    # discard_proposal (hardware-wallet PCZT pipeline),
│   │                    # DESIRED_SYNC_MODE, SYNC_RUNNING, SYNC_CANCEL globals
│   └── keystone.rs     # FRB: encode_pczt_to_ur, decode_ur_to_pczt, encode_pczt_ur_parts,
│                        # decode_ur_part, reset_ur_session (#[frb(sync)]),
│                        # decode_accounts_from_cbor, decode_pczt_from_cbor,
│                        # decode_accounts_ur. Keystone UX is QR-only.
│                        # Re-exports KeystoneAccountInfo, UrDecodeResult from
│                        # crate::wallet::keystone via `pub use`.
├── ffi.rs              # Thin C adapter for Swift Ironwood migration preparation.
│                        # Validates native pointers, converts C values, preserves
│                        # the iOS ABI, and delegates to migration_preparation.rs.
├── migration_preparation.rs
│                       # Platform-neutral mobile preparation execution core:
│                       # operation begin/end/cancel, preparation-only sync,
│                       # inspect/advance, progress state interpretation, and
│                       # shared foreground-sync exclusion. Future Android JNI
│                       # adapters must delegate here instead of duplicating it.
│                       # Located outside api/ to avoid FRB codegen picking it up.
├── wallet/
│   ├── mod.rs          # pub mod keys, sync, sync_engine, keystone
│   ├── keys.rs         # Key derivation, mnemonic, account creation (Derived + Imported),
│   │                    # list_accounts, ensure_db_initialized, parse_account_uuid,
│   │                    # delete_account with account existence check and row cleanup,
│   │                    # init_db_and_create_account (software first-account bootstrap),
│   │                    # import_hardware_account (Keystone UFVK import;
│   │                    # Keystone-first is allowed)
│   ├── sync.rs         # Per-account wallet operations (balance, send, history, etc.)
│   │                    # All per-account functions take account_uuid parameter
│   │                    # NoOp Sapling provers for Orchard-only software TXs
│   │                    # TX broadcast via gRPC SendTransaction
│   │                    # PROPOSAL_STORE: in-memory HashMap<u64, StoredProposal>
│   │                    #   populated by propose_send, consume-on-entry from
│   │                    #   execute_proposal / create_pczt_from_proposal,
│   │                    #   explicit discard_proposal for cancel paths.
│   │                    # Hardware PCZT pipeline:
│   │                    #   create_pczt_from_proposal → add_proofs_to_pczt +
│   │                    #   redact_pczt_for_signer → extract_and_broadcast_pczt
│   │                    #   (see "Hardware Wallet (Keystone) Send Flow" above for
│   │                    #   the broadcast-before-store and Sapling-params invariants)
│   ├── sync_engine.rs  # run_sync_inner() — retry wrapper (3 retries, 2/4/8s backoff)
│   │                    # run_sync_impl() — single sync attempt
│   │                    # MemoryBlockSource (BlockSource trait impl)
│   │                    # Single DB connection reused across entire sync
│   │                    # Checks cancel + mode mismatch after each download/scan/batch
│   │                    # Progress: initial_total based (remaining / initial_total)
│   │                    # has_new_tx from ScanSummary note counts
│   └── keystone.rs     # Keystone hardware wallet integration:
│                        # - UR (Uniform Resources) encode/decode for animated QR:
│                        #   encode_pczt_ur_parts, decode_ur_part, reset_ur_session
│                        #   (ur::Decoder directly, not KeystoneURDecoder, to avoid
│                        #   URType registry issues with `zcash-accounts`)
│                        # - Single-part UR helpers retained for compatibility
│                        # - QR-only product flow; USB transport is intentionally absent
│                        # - Global UR_SESSION: Mutex<Option<UrSession>>, auto-reset
│                        #   on type change / completion, caller resets via
│                        #   reset_ur_session() on scan-screen entry
└── frb_generated.rs    # Auto-generated by flutter_rust_bridge
```

### Foreground Sync and iOS Migration Preparation

Normal wallet sync has one path: Dart calls `start_full_sync()` through
`flutter_rust_bridge` and consumes `Stream<ApiSyncProgressEvent>`.
`DESIRED_SYNC_MODE`, `SYNC_CANCEL`, and `SYNC_RUNNING` belong to that foreground
path.

iOS Ironwood denomination preparation has a separate native path because its
`BGContinuedProcessingTask` must keep working without a Dart isolate:

```
Swift BackgroundMigrationPreparationManager
    → begin preparation operation
    → wait until foreground sync releases SYNC_RUNNING
    → thin C FFI adapter
    → platform-neutral Rust preparation sync / inspect / advance
    → end preparation operation
```

- `rust/src/migration_preparation.rs` owns the operation's private cancel token
  and desired mode for the whole native operation, including both sync and
  advance calls. The same core is the required entry point for Android JNI.
- Foreground `cancelFullSync()` cannot cancel migration preparation.
- The two paths share only `SYNC_RUNNING` while the sync engine is actually
  active, preventing concurrent access to the wallet sync pipeline.
- Account DB mutations first quiesce and drain native migration work, then pause
  foreground sync, mutate the DB, resume foreground sync, and finally resume
  only still-active native preparation.
- Ordinary migration status reads are side-effect free. Native scheduling is
  performed only at explicit recovery points such as startup, unlock,
  foreground return, or post-mutation resume.
- The removed general iOS background-sync identifier
  `com.keplr.vizor.sync` is cancelled once at launch as a tombstone for requests
  submitted by older builds; no handler is registered for it.

Key files:
- `rust/src/migration_preparation.rs` — platform-neutral preparation core
- `rust/src/ffi.rs` — migration-preparation-only iOS C adapter
- `ios/Runner/zcash_sync.h` — matching C header
- `ios/Runner/BackgroundMigrationPreparationManager.swift` — native task owner
- `lib/src/providers/wallet_mutation_guard.dart` — mutation ordering fence
- `lib/src/features/migration/services/ironwood_migration_service.dart` —
  explicit preparation recovery and scheduling

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

### Hardware Wallet (Keystone) Send Flow

Hardware send uses a **three-PCZT pipeline** that matches the
`zcash-android-wallet-sdk` / Zashi pattern. The hardware device cannot generate
ZK proofs (proving keys are too big for the device), and the phone cannot
sign (spending key lives on the device), so the two sides work on separate
clones of the same base PCZT and the phone combines them at the end.

```
1. createPcztFromProposal                      → base PCZT (phone)
   (IO-finalized, no proofs, no signatures)
      │
      ├── 2a. addProofsToPczt(base, params?)   → pcztWithProofs   (phone, CPU)
      │       (Orchard proof always; Sapling output proofs if the
      │        proposal has needsSaplingParams=true)
      │
      └── 2b. redactPcztForSigner(base)        → redactedPczt     (phone)
              → Keystone device (animated QR)
              → device signs Orchard spend_auth_sig
              → signed PCZT back to phone       → pcztWithSignatures
                                                       ↓
3. extractAndBroadcastPczt(
     pcztWithProofs, pcztWithSignatures,
     spend_params?, output_params?,
   )                                             → txid
```

Roles in the split:

| Step | PCZT role              | Runs on | Needs what                          |
|------|------------------------|---------|--------------------------------------|
| 1    | Creator + IoFinalizer  | phone   | wallet DB                            |
| 2a   | Prover                 | phone   | proving params (Orchard always; Sapling ~50MB if target recipient is Sapling) |
| 2b   | Redactor               | phone   | —                                    |
| sign | Signer                 | device  | spend_auth_sig derivation (device holds USK) |
| 3    | Combiner + TransactionExtractor | phone | verifying keys (Orchard always; Sapling if bundle non-empty) + wallet DB |

**Critical invariants** (each of these was a real bug at some point in
development; breaking them is a correctness or data-loss regression):

1. **`extract_and_broadcast_pczt` must broadcast before it persists.**
   The function order is: `TransactionExtractor::extract()` (in-memory, no
   DB) → `send_transaction` gRPC → *only then* `extract_and_store_transaction_from_pczt`.
   Store-then-broadcast leaves the wallet in an unrecoverable state if
   lightwalletd rejects the tx: DB thinks the notes are spent, network
   has no record of the tx, user has to manually rescue the wallet.

2. **Local storage failure after a successful broadcast must not surface
   as a send failure.** The primary store path is
   `extract_and_store_transaction_from_pczt` (preserves rich PCZT
   recipient/memo metadata). On failure, fall back to
   `decrypt_and_store_transaction` — the same path sync uses when it
   discovers one of our sent txs on-chain. Correctness is preserved
   (spent notes get marked spent via nullifier matching) at the cost of
   some PCZT-only display metadata. Only if both paths fail do we
   return an error, and the error message must tell the user the tx is
   on the network and not to retry.

3. **Sapling params must be passed to BOTH `add_proofs_to_pczt` AND
   `extract_and_broadcast_pczt` whenever the PCZT contains a Sapling
   bundle.** `add_proofs_to_pczt` needs `LocalTxProver` to build Sapling
   output proofs; `extract_and_broadcast_pczt` needs `LocalTxProver
   ::verifying_keys()` (a) to validate the extracted transaction and
   (b) to let `extract_and_store_transaction_from_pczt` store it. Both
   functions share the `Option<&str>` / `Option<&str>` signature. If
   the caller supplied paths to `add_proofs_to_pczt` but passed `None`
   here, extraction bails with `SaplingRequired` and the user sees a
   cryptic error after already downloading 50MB of params and
   approving on the device. `send_screen.dart` threads the same
   `proposal.needsSaplingParams ? spendPath : null` into both FFI
   calls — keep it that way.

4. **`PROPOSAL_STORE` is consume-on-entry for both execute paths, plus
   explicit discard on cancel.**
   - `create_pczt_from_proposal` and `execute_proposal` both call
     `.remove()` at the top (dropping the store lock before any DB
     work). A second call with the same `proposal_id` returns
     `"Proposal not found (expired or already consumed)"`.
   - Dart `_send()` runs the whole flow inside a `try/finally`
     with a `proposalConsumed` flag that flips to true immediately
     after the consume call. The `finally` block calls
     `discardProposal(proposalId)` when the flag is still false —
     this covers confirmation-dialog cancel, Sapling-params-dialog
     cancel, exceptions during Sapling download, and any error
     before the consume call. `discardProposal` is idempotent.
   - If you add a new entry point that reads a stored proposal,
     follow the same "consume on entry, idempotent discard on any
     non-consuming exit" pattern. Silently reading without
     consuming (`.get()`) reintroduces the memory-leak /
     replayable-ID bugs that a prior revision of this branch had.

The Dart flow in `lib/src/features/send/screens/send_screen.dart`
implements this pipeline end-to-end; the Rust side lives in
`rust/src/wallet/sync.rs::{create_pczt_from_proposal,
add_proofs_to_pczt, redact_pczt_for_signer, extract_and_broadcast_pczt,
discard_proposal}` with FRB wrappers in `rust/src/api/sync.rs`.

### Wallet Creation

`create_wallet()` fetches chain tip from lightwalletd as birthday height before creating the account. This prevents new wallets from doing a full chain scan. Birthday fetch failure blocks wallet creation (network required).

### Rust API Design Constraint

FRB codegen works best with simple types. Keep the `rust/src/api/` surface limited to primitives, `String`, and flat structs. Do all complex Zcash type manipulation inside `rust/src/wallet/` and return simple results through `rust/src/api/`.

All per-account API functions take `account_uuid: String`. Sync-level operations (`start_full_sync`, etc.) operate on all accounts and do NOT take account_uuid.

### Key Security Model

`zcash_client_sqlite` intentionally does NOT store spending keys in the DB — only viewing keys (UFVK).

**Software accounts**: the mnemonic/seed lives in Flutter's `flutter_secure_storage` (iOS Keychain / Android Keystore) per-account (`zcash_account_mnemonic_{uuid}`) and is passed to Rust only when needed for transaction signing. Seed is scoped in a block and dropped before network I/O (broadcast).

**Hardware (Keystone) accounts**: no seed ever reaches the phone. On import the phone receives only the UFVK via QR/UR; the USK stays on the device. There is no corresponding `zcash_account_mnemonic_{uuid}` entry, and `getActiveMnemonic()` returns null for hardware accounts. Transaction signing happens inside the device via the PCZT handoff (see "Hardware Wallet (Keystone) Send Flow"), so the phone never holds spending key material for these accounts at any point.

### WalletDb Initialization

`WalletDb::for_path()` requires 4 params: `(path, Network, SystemClock, OsRng)`. `init_wallet_db()` must be called before `create_account()` — it runs schema migrations.

Seed-relevance rule:
- **Software bootstrap account**: `init_db_and_create_account` calls `init_wallet_db(Some(seed))` then `create_account` → `AccountSource::Derived`. This pins the seed fingerprint so future seed-requiring migrations can verify relevance.
- **Subsequent opens**: `ensure_db_initialized` calls `init_wallet_db(None)`. Calling `init_wallet_db(Some(other_seed))` after the first account would fail the relevance check when any `Imported` account exists.
- **Hardware-first bootstrap is allowed**: `import_hardware_account` initializes without a local seed and imports the Keystone UFVK. This can produce an `Imported`-only DB, so seed-requiring migration recovery must be handled at the product layer if such a migration appears.

### Dart Sync Provider

`lib/src/providers/sync_provider.dart` — Riverpod `AsyncNotifier`.

**Auto-sync lifecycle:**
- `build()` watches `accountProvider` via `ref.listen` (not `ref.watch` — avoids rebuild on switch/rename)
- Account count increase triggers `startSync()` + `_startPolling()` (both first account and additional accounts)
- `_checkAndSync()`: polls `getLatestBlockHeight` every 10s, re-syncs if tip > last synced height or previous sync incomplete (`percentage < 1.0`)
- `_checkAndSync()`, `_refreshBalance()`, and `_onSyncProgress()` all bail out while
  locked and discard late async completions via `_sensitiveStateEpoch`
- Polling stops during `_checkAndSync` execution to prevent concurrent overlap, restarts after
- Duplicate sync guard: `_isSyncing` (Dart-side bool) + `isSyncRunning()` (Rust AtomicBool)

**startSync() is fire-and-forget:**
- Sets up FRB stream listener and returns immediately (no Completer, no await)
- `_syncGen` generation counter: incremented by `stopSync()`, checked in `.then()` callbacks to invalidate pending operations after user-initiated stop
- Stream `onDone` → `_onSyncDone()` (balance refresh + start polling)
- Stream `onError` → sets error state + starts polling for auto-retry

**Sync control:**
- `stopSync()`: increments `_syncGen` + `cancelFullSync()` + `_stopPolling()`. Polling does not restart until next `onResume`
- `clearSensitiveStateForLock()`: increments `_syncGen`/`_sensitiveStateEpoch`,
  clears in-memory sync state, sends `setSyncMode(0)` + `cancelFullSync()`,
  and waits briefly for stale Rust sync / mempool work to stop
- `startSyncAnyway()`: unlock recovery path. If Rust is still running but already
  cancelling, waits for teardown before starting foreground sync; if teardown
  times out, it at least restores polling so a later retry can recover

**Lifecycle:**
- `onResume`: refreshes balance → `_checkAndSync()` (which starts polling)
- `onHide`: stops polling (no wasted network in background)
- `SyncState.recentTransactions`: latest 10 transactions, updated on `hasNewTx`, sync completion, and app resume
- All balance/history queries pass `activeAccountUuid` from `AccountProvider`

### Desktop Window Bootstrap

Desktop window appearance is managed by the external [`desktop_window_bootstrap`](https://github.com/chainapsis/desktop_window_bootstrap) package plus `window_manager`, with a strict responsibility split:

- `desktop_window_bootstrap` owns window appearance and titlebar overlap handling.
  - On macOS this means the transparent titlebar / full-size content-view shell is applied natively before the window is shown, via `macos/Runner/MainFlutterWindow.swift`.
  - The app calls `DesktopWindowBootstrap.initialize()` in `lib/main.dart` after `initializeDesktopWindow()` has created the OS window but before `showDesktopWindow()` reveals it.
  - `DesktopWindowTitlebarSafeArea` in `lib/app.dart` pads Flutter content below the macOS traffic-light/titlebar area. Keep it wrapped around the app root.
- `window_manager` owns sizing/lifecycle only.
  - `lib/src/core/layout/app_layout.dart` should remain responsible for initial size, minimum size, aspect ratio, `show()`, `focus()`, and layout-mode reconciliation from window events.
  - Do not reintroduce `TitleBarStyle` ownership or other appearance writes through `window_manager`; that overlaps with `desktop_window_bootstrap`.

Current startup order for desktop platforms:

```text
WidgetsFlutterBinding.ensureInitialized()
→ RustLib.init()
→ initializeDesktopWindow()      // window_manager creates the OS window
→ DesktopWindowBootstrap.initialize()
→ showDesktopWindow()
→ runApp()
```

### Figma comparison tooling

For deterministic code-to-Figma screenshots, use the widget-test capture as
the normal iteration path. It renders the same `FigmaCompareApp` and registered
scenario without building Rust, CocoaPods, Xcode, or a macOS app:

```bash
scripts/figma-compare.sh widget --scenario pay-recipient --theme dark
```

Use the native entry point only for final macOS window-shell and restoration
verification:

```bash
scripts/figma-compare.sh native --scenario pay-recipient --theme dark
```

Registered states live in
`lib/figma_compare/figma_compare_scenarios.dart` and must use deterministic
dev-only mocks. Outputs go below the app sandbox's `vizor-figma-compare`
temporary directory: `content.widget.png` is the fast app-content reference;
`content.png` and `content.window.png` are the real-engine and native-window
final evidence. The native entry point reuses production macOS window
initialization without starting Rust, storage, sync, wallet, or network state,
automatically restores a minimized window before capture, and returns it and
the previously foreground app to their original states afterward. Full
workflow, mobile capture, and cleanup rules are in `FIGMA-AI-FIX.md`.

Important desktop design rule:

- `Scaffold.backgroundColor: Colors.transparent` is required anywhere the native acrylic/translucent shell should remain visible.
- Any opaque `Container`, `ColoredBox`, decoration color, or other filled background will cover the native effect in that region.
- Treat transparency as opt-in per region: only paint solid backgrounds where the UI should actually be solid.

### Mobile Bottom Safe Area (iOS proportional padding)

Mobile bottom-sheet bodies and the floating tab bar wrap their bottom
edge in `MobileBottomSafeArea`
(`lib/src/core/layout/mobile/mobile_bottom_safe_area.dart`), not raw
`SafeArea(top: false)`.

- The rule: on iOS, when the wrapped content's own bottom padding is
  `kIosHomeIndicatorClearance` (16) or more, the bottom safe-area inset
  is skipped so the bottom gap equals the side padding. Android always
  honors the inset — navigation-bar modes vary per device.
- Why: the iOS home indicator is an overlay occupying only the bottom
  ~13pt of the screen (8pt offset + 5pt bar), so it floats inside 16px
  of empty padding; stacking the 34pt inset on top of that padding
  makes the bottom gap visually heavier than the sides.
- `bottomPadding` must equal the bottom padding the wrapped content
  actually provides below its last control — when changing a sheet's
  padding token, update the argument with it.
- Tab bar (`AppMobileShell`): the gap below the bar is 16 on iOS
  (matching its 16px side margins) and the Figma 12 + inset on Android.
- Keyboard avoidance is unaffected — `viewInsets` is a separate channel
  from the `viewPadding` this consumes.
- Platform branching uses `defaultTargetPlatform` (overridable in
  widget tests), not `dart:io` `Platform` checks.
- New sheets follow `MobileBottomSafeArea(bottomPadding: token)` >
  `Padding(...)`; both platform geometries are pinned in
  `test/core/layout/mobile/mobile_bottom_safe_area_test.dart`.

## Testing

- Rust unit tests: `cd rust && cargo test` — 11 tests covering key derivation, address encoding / Orchard-only UA derivation, determinism, and PROPOSAL_STORE lifecycle (idempotent discard, consume-on-entry, replay rejection). Tests that need a DB use `tempfile::tempdir()`.
- Dart unit tests: `fvm flutter test` (mobile-tagged tests auto-skip).
  Mobile-UI tests:
  `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
  Lane rules in "Design Token Form Factor" above.
- Integration tests: `fvm flutter test integration_test/` (requires device/simulator)
- Flutter regtest E2E notes:
  - Run app tests with `--dart-define=ZCASH_DEFAULT_NETWORK=regtest`; do not use the old `ZCASH_USE_E2E_STORAGE` path. Secure storage and wallet DB names are network-scoped.
  - Cleanup code should guard on `kZcashDefaultNetworkName == ZcashNetwork.regtest.name`, then delete `getWalletDbName()` plus its `-shm` / `-wal` files.
  - Use `ZCASH_E2E_LIGHTWALLETD_URL` only as the endpoint override, and keep Rust API calls on the same network as `kZcashDefaultNetworkName`.
  - Mempool receive E2E should use external zcashd/lightwalletd funding when testing true inbound tx discovery, not another in-app account.
  - To prove mempool behavior while sync is active, pre-mine enough regtest blocks and pass the debug-only Rust throttle env vars inline: `ZCASH_E2E_SYNC_BATCH_SIZE` and `ZCASH_E2E_SYNC_BATCH_DELAY_MS`.
- Mobile (iOS simulator) regtest E2E:
  - One-shot runner: `./scripts/e2e/flutter-ios-regtest-mobile-full.sh`; per-scenario runners are `scripts/e2e/flutter-ios-regtest-mobile-*.sh`. Same heaviness rule as desktop: do not run unless explicitly asked.
  - Tests live in `integration_test/regtest_mobile_*_test.dart` and share `integration_test/support/mobile_regtest_flow.dart` (pump/tap helpers, regtest-guarded cleanup, mobile flow primitives). Desktop regtest tests keep their per-file helpers; do not merge them.
  - Mobile runs need THREE defines: `VIZOR_FORM_FACTOR=mobile`, `ZCASH_DEFAULT_NETWORK=regtest`, `ZCASH_E2E_LIGHTWALLETD_URL` — `run_mobile_e2e` in `scripts/e2e/lib-mobile.sh` injects them.
  - Device selection: `SIMULATOR_UDID` env wins; otherwise the single booted simulator. The runner refuses to pick among multiple booted sims.
  - Each `flutter test integration_test` invocation reinstalls the app: the wallet DB dies with the container while the iOS Keychain persists, so in-test `cleanupE2eWalletState()` (deleteAll + db files, regtest-guarded) runs at test start AND teardown. Cross-invocation wallet reuse is impossible by design.
  - The simulator shares the host loopback: `127.0.0.1` URLs, the in-test lightwalletd proxy, and the python E2E driver all work unchanged. Android emulators would need `10.0.2.2` and are out of scope.
  - Desktop scenarios without mobile counterparts (feature gaps, add when the features land): custom-endpoint privacy (no mobile endpoint settings UI), shield-transparent ×2 (no mobile transparent balance / shield UI), mempool during-sync / expiry variants.
- Zcash regtest Rust integration tests:
  - One-shot runner from repo root: `./run-regtest-rust-tests.sh`
  - The runner always starts by tearing down any existing regtest containers and resetting `.regtest/`, so each run starts from the same clean chain/wallet state.
  - The runner writes its terminal log to `.regtest-logs/regtest-rust-tests.log`, which is intentionally separate from `.regtest/` so the log survives the default final cleanup.
  - Sapling proving params are cached separately at `~/.zcash-params` by default, so they survive `scripts/regtest/reset.sh`. Override with `SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh` if needed.
  - By default the runner also does a final `down/reset` cleanup after the tests finish. Use `./run-regtest-rust-tests.sh --keep` if you want to keep the regtest state around for debugging.
  - These regtest scenarios are slow and heavy. Do not run them unless the user explicitly asks for regtest/integration execution.
  - Manual flow:
    - Start services: `./scripts/regtest/up.sh`
    - Run individual scenario tests: `cd rust && cargo test --test regtest_receive_sync -- --ignored --nocapture --test-threads=1`
    - Other available targets: `regtest_send`, `regtest_import`, `regtest_multi_account`
    - Stop services: `./scripts/regtest/down.sh`
  - The one-shot runner streams the full test output to the terminal and also saves a copy to `.regtest-logs/regtest-rust-tests.log`.
- `scripts/regtest/` utilities:
  - `up.sh` — starts the Dockerized `zcashd + lightwalletd` regtest stack, waits for both services to become ready, and ensures the faucet state exists.
  - `down.sh` — stops the regtest Docker compose stack.
  - `reset.sh` — destroys the regtest containers/volumes and clears `.regtest/` state, then recreates a clean local chain on the next `up.sh`.
  - `mine.sh <count>` — mines `<count>` new regtest blocks through `zcash-cli`.
  - `fund-wallet.sh <unified_address> <amount_zec> [confirmations]` — sends shielded funds from the local faucet to the given UA, then mines enough blocks for confirmation. Example: `./scripts/regtest/fund-wallet.sh <ua> 1.25 10`
  - `lib.sh` — shared helper functions used by the other regtest scripts; source it from scripts, do not run it directly.
- Regtest prerequisites:
  - Docker Desktop / `docker compose` must be available.
  - `grpcurl` is optional but recommended. If installed, the scripts use it to wait for `lightwalletd` gRPC readiness and chain-tip propagation; otherwise they fall back to a simpler TCP port check.
- Debug vs Release: Rust crypto is ~5-10x slower in debug (`opt-level=0`). Use `--release` for realistic sync performance.

## Crate Versions

Constrained in `rust/Cargo.toml` and resolved in `rust/Cargo.lock`. Key crates: `zcash_client_backend` 0.22.0, `zcash_client_sqlite` 0.20.2, `orchard` 0.13.1, `sapling-crypto` 0.7.0. These must stay compatible — check librustzcash releases before bumping.

`tonic` 0.14 with `tls-ring` + `tls-webpki-roots` features for gRPC TLS. `rustls` 0.23+ requires explicit crypto provider — `tls-ring` provides this.

`log` 0.4 for Rust logging — forwarded to Flutter console via FRB. Level set to `Info` in `init_app()`.

Additional crates for multi-account: `uuid` 1.1, `zip32` 0.2, `jubjub` 0.10, `bls12_381` 0.8, `rand_core` 0.6.

## Ignored Paths

`onboarding/` — Developer onboarding documentation. Do not read or modify during normal development. Only update when explicitly asked.

`CLAUDE.md` intentionally contains only `@AGENTS.md`; update this file as the source of truth and keep this line as the final line.
