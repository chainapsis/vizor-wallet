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

# After changing Rust API files (rust/src/api/*.rs). Use the wrapper;
# bare flutter_rust_bridge_codegen fails on rustc's expanded `super let`.
scripts/generate-rust-bridge.sh

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

### Assets in widget tests

- The mobile token lane automatically filters app `assets/**/desktop/`
  artwork out of both asset loads and the asset manifest through
  `test/flutter_test_config.dart`. It forwards allowed loads to the original
  bundle; it does not copy assets or add a test wrapper command.
- A desktop-only asset request fails the mobile test even when an image
  `errorBuilder` consumes the error. Shared artwork belongs outside `desktop/`.
  Keep asset references and the relevant mobile/desktop screen tests together
  when adding, moving, or renaming files.
- `test/core/platform_asset_contract_test.dart` checks that desktop artwork is
  limited to Linux/macOS/Windows/web and that other runtime assets remain
  shared. A new subdirectory needs its own pubspec declaration. Run this test
  after changing assets or pubspec. The mobile-tagged
  `test/core/mobile_asset_bundle_test.dart` also runs these contracts and the
  filter regressions, so both normal test lanes validate them.
- Native video player mocks must check the selected asset against
  `AssetManifest.loadFromAssetBundle(rootBundle)`; a successful mock decoder
  alone does not prove availability. Native integration tests use the actual
  device bundle, not the host-test filter.

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

## Google Play opt-out (VIZOR_DEGOOGLED)

Android builds include Google Play integrations by default. Direct APK and
F-Droid builds explicitly pass `--dart-define=VIZOR_DEGOOGLED=true`; the
reproducible APK builder exposes this as `--degoogled`. Dart and Gradle read
the same define. When enabled, Android review scheduling is disabled and the
Google Play review SDK and implementation are excluded from the build. iOS
reviews and desktop behavior are unaffected. F-Droid's wrapper always passes
`--degoogled` to match deployment's direct APK build inputs.

Mobile review eligibility is classified once from the first successful startup
snapshot and persisted in `vizor_app_review_history_v1`. Existing wallet users
skip the three-launch wait; new users retain it even after creating a wallet.
Both require explicit usage and two idle seconds on home, with at most two API
attempts and a seven-day retry interval. Legacy history keeps its attempt budget
and dates when the classification field is added. Blocked startup must not be
classified as a new user; retry recovery supplies the successful snapshot.

## Deep-link Host (VIZOR_DEEPLINK_BASE_URL)

The HTTPS origin Vizor claims for incoming links has **one** knob on
Android and Dart: `--dart-define=VIZOR_DEEPLINK_BASE_URL` (default
`https://link.vizor.cash`).

- Dart is the source of truth: `VizorDeepLink` reads the define through
  `String.fromEnvironment`.
- Gradle derives its value from the same place. Flutter forwards every
  dart-define as `-Pdart-defines=<base64("KEY=VALUE")>,...`, and
  `android/app/build.gradle.kts` decodes that property to fill the
  `vizorDeeplinkHost` manifest placeholder and `BuildConfig
  .VIZOR_DEEPLINK_HOST`. There is deliberately no separate Gradle
  property or environment variable — a second knob could disagree with
  the compiled-in Dart origin and silently break verified app links.
  Invoking Gradle directly (no dart-defines) falls back to the default.
- iOS is the exception: it keeps `VIZOR_DEEPLINK_HOST` in the Flutter
  xcconfigs (`ios/Flutter/{Debug,Profile,Release}.xcconfig`), which feed
  `Info.plist` and `Runner.entitlements`. Change the host there too.
- The Android intent-filter claims the host with no path constraint, so
  the bare origin (empty path on Android), `/`, and
  `/payment-links/open` all open the app. Path filtering belongs to
  Dart's `classifyIncomingLink`, which drops unknown paths on the origin
  silently.

## Localization (VIZOR_I18N_PREVIEW)

Read [docs/i18n/developer-guide.md](docs/i18n/developer-guide.md) before adding
or changing user-facing text, ARB files, language selection, or copy that native
code draws. [docs/i18n/README.md](docs/i18n/README.md) indexes the translation
rules, adding a language, and Rust-originated text.

- **After editing translations or updating `intl`, run
  `fvm dart run tool/l10n/generate.dart`. `flutter gen-l10n` alone does not
  regenerate the bundled font subsets.** `--watch` is optional for translation
  work; do not auto-start it with normal app runs or builds.
- Korean bundles Pretendard's 11,172 modern Hangul syllables and supported
  jamo; Chinese bundles Noto Sans SC's 8,105 TGH 2013 characters. New UI and
  date/number-formatting characters are included automatically. Unsupported
  characters retain system fallback.
- Commit the generated `assets/fonts/Vizor*UI-VF.ttf`,
  `tool/l10n/ui_fonts.manifest.json`, and `tool/l10n/ui_font_characters.json`
  with translation changes; never edit these generated files by hand.
- Check freshness with `python3 tool/l10n/ui_fonts.py --check`. Screenshot
  tests must load the shipped subsets, not substitute external/system fonts.

## Mainnet Block-Time Table

On mainnet, wallet birthday conversions (import date to height, seed-phrase
screen height to date) never send lightwalletd a wallet-derived height. They
read `rust/src/wallet/block_times/mainnet_data.rs`, a generated table of
header times every 1,000 blocks. The only request left is the chain tip.

- The weekly `Update mainnet block times` workflow appends entries after two
  endpoints agree, and opens a PR for a person to merge.
- Bootstrap or refresh before a release cut with
  `scripts/update-mainnet-block-times.py` (needs `grpcurl`); validate offline
  with `--check`. Never edit the data file by hand.

## Image Assets

New raster image assets must be converted to lossless WebP before inclusion.
Preserve their dimensions and decoded pixels, and update app, Widgetbook, and
test references to `.webp`. For illustrations, use
`scripts/convert-illustrations-to-webp.py` (`--apply` writes verified conversions).

iOS native tab icons intentionally duplicate the Flutter SVGs in Xcode's asset
catalog. Before changing tab icons or their loading path, read
[docs/ios-native-tab-bar.md](docs/ios-native-tab-bar.md#icon-assets-and-synchronization)
and refresh/check both copies with `scripts/sync-ios-native-tab-icons.py`.

## Transaction Record Hero

A transaction record opens on its type's icon (the one its activity row
shows, from `activityKindIconName`) cast in liquid metal:
`TransactionTypeHero` draws `assets/icons/<name>.svg` through `LiquidMetal`
(`lib/src/core/widgets/liquid_metal.dart`, the NU7 announcement's shader) via
`SvgShapeImage`, which rasterizes the SVG for the shader's shape. A Gift Card
record shows the card instead, at 70% of the full card. There are no 3D
models. Tests hold every `LiquidMetal` still
(`LiquidMetal.debugDisableMotion`, set in `test/flutter_test_config.dart`) so
screens with it can settle.

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

The receive-address QR of a Keystone account is one of those codes: the device
scans it to verify rotating addresses. `ReceiveQrSurface(scanOptimized: true)`
draws it black-on-white with square modules in every theme and keeps the pool
badge. Its quiet zone is the white card's padding rather than modules inside
the bitmap; a Keystone device scans it at the current geometry. Software and
Ledger accounts keep the decorative dot style.

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
- English copy lives in `lib/l10n/app_en.arb`, where each key's description
  says where it appears. Check `lib/l10n/glossary.yaml` for the shared terms
  before introducing new copy.
- When editing existing copy, also update widgetbook fixtures
  (`lib/widgetbook/*.dart`) and tests (`test/`) that assert on the literal
  string — `find.text(...)` matchers, `expectedNextAction` fields, and
  `_tooltipWithMessage(...)` helpers will break otherwise.

## Privacy Mode

Before adding or changing UI that shows an amount, read `docs/privacy-mode.md` (the hide-balance toggle).

On mobile, turning the phone screen-down also hides amounts from any wallet
page (flip to hide, `FlipToHideBalanceHost`); `docs/privacy-mode.md` has its
rules. It only switches privacy mode, so a screen that masks correctly needs
nothing more.

## Release Notes

When asked to prepare user-facing release notes or a changelog for a release,
read `release_notes/README.md` and create `release_notes/vX.Y.Z.md`.
Unless the request explicitly says otherwise, draft desktop release notes for
Windows, Linux, and macOS from desktop user-facing changes only. Exclude
mobile-only changes.

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
Voting background work that can write account state or secure storage must
register with the destructive-operation drain before its first asynchronous
step, and account deletion/reset must await that work before clearing data.
Ledger outbox operations and their caller-side result persistence must register
with `ledgerOperationLifecycleProvider` before their first asynchronous step.
Account deletion/reset block new Ledger work and drain accepted operations before
invalidating the secret session or deleting wallet data. Keep the lease through
swap/pay metadata persistence and outbox acknowledgement; do not cancel a
broadcast after submission merely to unblock deletion. Device approval remains
outside this durable-operation lease. Ledger account import uses the same
`runMutation` boundary as software and Keystone imports. That boundary
(`runWithSyncPausedForAccountMutation` in
`lib/src/providers/wallet_mutation_guard.dart`) serializes account mutations,
a reset, and the Private queries toggle on every platform; only its keyring
interception is Linux-specific.
Each account's private transparent recovery companions live in the
`{dbPath}.tpir` directory beside the wallet DB. Rust `delete_account` removes
that account's companions after releasing the wallet write lock (a leftover is
removed at the next sync start); a full reset deletes the whole directory with
the DB and any `*.tpir` directory left by an earlier wallet. On iOS the
directory is excluded from iCloud and device backups, since it records which
transparent addresses had activity.

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
- The passcode keypad's `?` help action resets the wallet and must appear only
  on the app-start `/unlock` screen. Never show it in any other passcode keypad
  context.

### Account Creation and Home Setup

Ordinary software creation and Gift Card creation defer secret-passphrase backup
and Zcash education to Home. First ordinary accounts generate their mnemonic only
after password/passcode confirmation; additional accounts create from Welcome with
the unlocked credential. Imports retain account customisation. Ordinary creation
uses `createAccountForDeferredSetup`, journaling the unseen seed in encrypted
storage before first or additional account mutations. Recovery must preserve the
seed, persona and account-specific `setupPending` / `giftEducationPending` flags.
The existing Home cards share backup snooze/completion and education completion
with Gift creation; education completion never marks a seed backed up.

A separate mobile reminder that asks new users to back up later is still being
built (Tony Yoon’s version). Integrate it at `TODO(backup-reminder)` in
`mobile_home_screen.dart`, beside the NU7 announcement host, and record its
rules here when it lands.

### Mobile Screen Privacy

Mobile screen privacy applies only while secret material is visible. Keep
`SensitivePrivacyOverlay` on seed creation/import/review, settings seed, and
viewing-key screens. It covers exposed secrets when the app loses foreground
interaction and uses `NativeSensitiveContentBridge` for selective native capture
exclusion (Android `FLAG_SECURE`, iOS `SecureScreenshotShield`). Ordinary screens
and access gates with no exposed secret must remain uncovered in the app
switcher; do not add app-wide native lifecycle covers.

Keep `RouteCoverageAware` on import screens so capture exclusion survives route
transitions and releases only after full coverage. Keep biometric prompt
suppression around sensitive access gates, and exclude shielded content from
screen-reader semantics without unmounting it. Desktop continues to use
`SensitivePrivacyOverlay`.

The mobile keep-awake lock owns system Back before payment cards and routes.
Back may return from passcode entry to the lock status screen, but never acts
on the covered app or interrupts authentication. Its idle deadline counts
pointer, keyboard and deliberate platform semantics actions; automatic focus
notifications do not extend it. Remove global input listeners on disposal.

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
  ├── Checks at once when the mempool observer reports a new block
  ├── Re-syncs automatically when new blocks detected or previous sync incomplete
  ├── Duplicate sync guard: _isSyncing (Dart) + isSyncRunning() (Rust)
  ├── A start requested while its own stream still holds the Rust guard (its
  │   post-sync follow-ups included) is queued and runs when the stream ends;
  │   repeats coalesce, and a queued start is dropped if the app went background
  ├── `_sensitiveStateEpoch` discards late balance/progress updates after lock/sign-out
  ├── Passes activeAccountUuid to getBalance, getTransactionHistory
  ├── Sync itself is account-agnostic (covers all accounts)
  ├── Polling pauses on app background (onHide), resumes on foreground (onResume)
  ├── refreshAfterSend() called after account switch for immediate update
  ├── refreshAfterUnlock() restores the stored sync status, then the selected account's
  │   persisted display balance; it reads no wallet summary or history
  └── refreshHomeInBackground() refreshes live balance/history after sync starts; each publishes independently

SyncDisplayPercentageProvider (sync_display_progress_provider.dart)
  ├── Owns the 20 ms UI-only interpolation timer between Rust progress events
  ├── Watches only authoritative progress targets from SyncProvider
  ├── Exposes raw interpolated progress only to smooth progress indicators
  └── Exposes whole percentages to labels so unrelated UI does not rebuild per tick
```

### App Bootstrap

`main()` does a one-shot bootstrap before `runApp()` and injects it via
`appBootstrapProvider`. This snapshot is the startup source of truth for the
first frame and avoids the old `/welcome -> /home` jump plus the "empty home
until sync callback arrives" flash.

- `loadAppBootstrap()` reads:
  - secure storage (`zcash_accounts`, `zcash_active_account`, `zcash_wallet_network`)
  - Rust wallet DB metadata via `list_accounts` (one projection; no viewing-key
    decoding or address reads)
  - the selected account's receive address and persisted display balance, only
    when unlocked; no live balance summary or transaction history before `runApp`
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
  initial address/cache hydration fails, in which case sync state falls back
  to empty and the live sync repopulates it.

### Sync

The sync engine (`rust/src/wallet/sync_engine/`) and the Dart sync provider
(`lib/src/providers/sync_provider.dart`) are described in `docs/sync.md`.
Read it before changing either, and update it when their behaviour changes.

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
│   │                    # prepare_pczt_for_keystone_batch,
│   │                    # store_and_broadcast_pczts_with_keystone_signatures_for_proposal,
│   │                    # discard_proposal (hardware-wallet PCZT pipeline),
│   │                    # DESIRED_SYNC_MODE, SYNC_RUNNING, SYNC_CANCEL globals
│   └── keystone.rs     # FRB: encode_pczt_to_ur, decode_ur_to_pczt, encode_pczt_ur_parts,
│                        # encode_zcash_sign_batch_ur_parts,
│                        # decode_zcash_batch_sign_response,
│                        # decode_ur_part, reset_ur_session (#[frb(sync)]),
│                        # decode_accounts_from_cbor, decode_pczt_from_cbor,
│                        # decode_accounts_ur. Keystone UX is QR-only.
│                        # Re-exports KeystoneAccountInfo, UrDecodeResult from
│                        # crate::wallet::keystone via `pub use`.
├── ffi.rs              # Thin, read-only C adapter for iOS Ironwood migration
│                        # inspection and observable preparation-txid listing.
├── migration_preparation.rs
│                       # Platform-neutral mobile preparation core. Android JNI
│                       # uses its operation lifecycle, preparation-only sync,
│                       # inspect/advance, cancellation, and foreground-sync
│                       # exclusion. iOS C FFI exposes only read-only inspect,
│                       # proof-readiness, and observable txid reads.
│                       # Located outside api/ to avoid FRB codegen picking it up.
├── wallet/
│   ├── mod.rs          # pub mod keys, sync, sync_engine, keystone
│   ├── keys.rs         # Key derivation, mnemonic, account creation (Derived + Imported),
│   │                    # list_accounts, ensure_db_initialized, parse_account_uuid,
│   │                    # delete_account with account existence check and row cleanup,
│   │                    # init_db_and_create_account (software first-account bootstrap),
│   │                    # import_hardware_account (Keystone UFVK import;
│   │                    # Keystone-first is allowed)
│   ├── sync/           # Per-account wallet operations (balance, send, history, etc.)
│   │                    # All per-account functions take account_uuid parameter
│   │                    # NoOp Sapling provers for Orchard-only software TXs
│   │                    # TX broadcast via gRPC SendTransaction
│   │                    # PROPOSAL_STORE: in-memory HashMap<u64, StoredProposal>
│   │                    #   populated by propose_send, consume-on-entry from
│   │                    #   execute_proposal / create_pczt_from_proposal,
│   │                    #   explicit discard_proposal for cancel paths.
│   │                    # Hardware PCZT pipeline:
│   │                    #   create_pczt_from_proposal → add_proofs_to_pczt +
│   │                    #   prepare_pczt_for_keystone_batch → compact signatures →
│   │                    #   store_and_broadcast_pczts_with_compact_signatures_for_proposal
│   │                    #   (see "Hardware Wallet (Keystone) Send Flow" above for
│   │                    #   the broadcast-before-store and Sapling-params invariants)
│   ├── sync_engine.rs  # run_sync_inner() — retry wrapper (3 retries, 2/4/8s backoff)
│   │                    # run_sync_impl() — single sync attempt
│   │                    # MemoryBlockSource (BlockSource trait impl)
│   │                    # Single DB connection reused across entire sync
│   │                    # Checks cancel + mode mismatch after each download/scan/batch
│   │                    # Progress: work-unit fraction of a persisted sync job
│   │                    # has_new_tx from ScanSummary note counts
│   └── keystone.rs     # Keystone hardware wallet integration:
│                        # - UR (Uniform Resources) encode/decode for animated QR:
│                        #   batch-sign encode/decode, decode_ur_part, reset_ur_session
│                        #   (ur::Decoder directly, not KeystoneURDecoder, to avoid
│                        #   URType registry issues with `zcash-accounts`)
│                        # - Single-part UR helpers retained for compatibility
│                        # - QR-only product flow; USB transport is intentionally absent
│                        # - Global UR_SESSION: Mutex<Option<UrSession>>, auto-reset
│                        #   on type change / completion, caller resets via
│                        #   reset_ur_session() on scan-screen entry
└── frb_generated.rs    # Auto-generated by flutter_rust_bridge
```

### Foreground Sync and Platform-Specific Migration Preparation

Normal wallet sync has one path: Dart calls `start_full_sync()` through
`flutter_rust_bridge` and consumes `Stream<ApiSyncProgressEvent>`.
`DESIRED_SYNC_MODE`, `SYNC_CANCEL`, and `SYNC_RUNNING` belong to that foreground
path.

iOS and Android intentionally have different preparation contracts:

```
Android IronwoodMigrationPreparationWorker
    → JNI adapter
    → begin preparation operation
    → preparation-only Rust full sync / inspect / advance
    → end preparation operation

Swift BackgroundMigrationPreparationManager
    → submit user-visible BGContinuedProcessingTask
    → read-only C FFI inspect / observable preparation txids
    → native lightwalletd GetLatestBlock + GetTransaction queries
    → update system task progress until every executed preparation tx has
      3 confirmations
    → record the foreground continuation and post a "step confirmed" alert
    → complete the continued-processing task successfully for that wave
    → leave sync / migration advance to foreground
```

- iOS submits `BGContinuedProcessingTaskRequest` only while denomination
  preparation is active. Its normal polling loop only queries the lightwalletd
  tip and each materialized preparation tx. It never runs a wallet sync or
  advances migration state.
- The iOS C-FFI inspection path opens SQLite with `SQLITE_OPEN_READ_ONLY` and
  queries only the run phase and stage counts it needs. It must not call
  `migration_status`, stage helpers that run `ensure_schema`, or any schema
  upgrade path. Missing or incompatible preparation tables are a foreground
  recovery signal, never a reason to repair the DB from the system task.
- The iOS task treats `NotFound` and mempool as zero confirmations, derives
  mined confirmation depth from the queried chain tip, and waits until every
  observable tx in the current wave reaches 3 confirmations. It then records
  the foreground continuation, posts a distinct "step confirmed" notification,
  and completes the continued-processing task successfully. One task tracks one
  wave; it never idles waiting for the user. Expiration of a mid-wave tracking
  pass is reported as pause-and-re-arm, never as failure. Foreground reentry
  owns the wallet sync, denomination advance, and submission of a fresh
  read-only task for the next wave.
- Android keeps its WorkManager foreground worker and native preparation path.
  The worker may run the existing mode-2 full sync, inspect proof readiness,
  advance denomination preparation, and enqueue a continuation.
- `rust/src/migration_preparation.rs` owns the mobile preparation operation's
  cancel token and desired mode. Foreground `cancelFullSync()` does not cancel
  that operation; the paths share `SYNC_RUNNING` while the sync engine is active
  so two wallet scans cannot run concurrently.
- Already-signed migration outbox transport remains background-capable. It may
  query the chain tip and broadcast exact signed bytes, but it never scans the
  wallet.
- Account DB mutations quiesce and drain native migration work before changing
  the wallet DB.
- The removed general iOS background-sync identifier
  `com.keplr.vizor.sync` is cancelled once at launch as a tombstone for requests
  submitted by older builds; no handler is registered for it.

### Network Upgrades

Read [docs/network-upgrades.md](docs/network-upgrades.md) before changing send
expiry or block-time and wait-time estimates. It covers what the wallet refuses
around an upgrade, where those rules live
(`rust/src/wallet/network_upgrade.rs`), and NU7's block spacing.

### Tor and the network route

Tor covers the app's foreground traffic only. The desired route lives in Rust
process memory, applied by the Dart layer at startup and by the settings
toggle; every foreground lightwalletd and HTTP path goes through the
policy-aware openers and fails closed while Tor is starting or broken, except
a sync's large block download (below).

- **Large block downloads may leave Tor; nothing identifying does.** With Tor
  and Private queries on, a sync session whose estimated direct download
  reaches `DIRECT_BLOCK_DOWNLOAD_MIN_BYTES` downloads its main-scan batches
  over `open_block_download_lwd_transport`. Keep these rules:
  - Only the batches `batch_uses_direct_connection` allows use it. Every
    request that carries an address, txid or transaction stays on Tor.
  - Never dial an onion server directly (`block_download_can_go_direct`).
  - The session opens its Tor route first and fails closed with it; a direct
    failure sends the batch over Tor.
  - HTTP/2 pings only on a multi-threaded runtime (`keep_alive_fits_runtime`).
  - Settings copy says Vizor uses Tor to protect the IP address; it does not
    promise that every request goes through Tor.

  How it opens, falls back and reconnects, and what the server learns from it:
  "Direct block connection" in `docs/sync.md`.
- **Voting SDK network clients are constructed only in**
  `rust/src/wallet/voting/network_clients.rs`. Chain, helper, PIR, and
  vote-tree are separate transport roles; injecting a chain transport does
  not configure the tree. Both tree pre-sync and the round executor must use
  the same shared routed transport. When upgrading the SDK, audit new
  network-capable entry points and extend the routing table and service tests
  in `rust/src/wallet/voting/README.md`. The Rust suite includes a supplemental
  constructor guard; it does not replace checking actual network behavior.
- **A Tor connection that could not open is a `SocketException` in Dart.**
  The Rust Tor HTTP bridge retries an exit's DNS failure or Arti's
  `RemoteNetworkTimeout` once on a fresh circuit (`tor_stream_open_recovery`),
  then marks any stream-opening failure so `RustTorHttpBridge` rethrows it as
  the direct route would. Voting retry, vote-server failover, and config-mirror
  classification depend on that type; a raw Tor error string skips them all.
- **iOS background migration transport is pinned direct**
  (`open_background_direct_lwd_channel`), bypassing the route policy as a
  product decision. A background pass never brings Tor up or borrows the
  foreground's client, so routing that lane through the policy would only
  convert it into failures on a Tor wallet. The mobile settings card
  discloses this. Nothing in the foreground may use the pinned opener.
- **The saved route may be stricter than the enforced route, never laxer.**
  The saved preference is all a fresh launch has to go on, so a toggle
  persists in whichever order keeps this true at every intermediate point:
  enabling writes before the runtime switch (a failed write aborts a toggle
  that has not happened yet), disabling writes after it (a failed write
  leaves the stricter Tor value behind). `networkPrivacyPersistedRouteIsSafe`
  is the executable statement of this rule.

Key files:
- `rust/src/migration_preparation.rs` — shared mobile preparation core
- `rust/src/android_jni.rs` — Android preparation execution adapter
- `rust/src/ffi.rs` — iOS read-only inspection and query adapter
- `ios/Runner/zcash_sync.h` — matching C header
- `ios/Runner/BackgroundMigrationPreparationManager.swift` — continued-task
  confirmation tracker and foreground-handoff owner
- `lib/src/providers/wallet_mutation_guard.dart` — mutation ordering fence
- `lib/src/features/migration/services/ironwood_migration_service.dart` —
  foreground preparation recovery

### iOS Preparation Confirmation Tracking

`BGContinuedProcessingTask`
(`com.keplr.vizor.ironwood-preparation`) polls lightwalletd every 60 seconds
while an executed denomination preparation waits for confirmations.

- `BackgroundMigrationPreparationManager.swift` owns the task, reads observable
  txids through C FFI, updates the system task `Progress`, and advances its
  progress heartbeat every 15 seconds.
- `NativeLightwalletdClient.swift` uses only `GetLatestBlock` and
  `GetTransaction`; it checks both txid byte orientations.
- `NotFound`, mempool height `0`, and fork height `UInt64.max` contribute zero
  confirmations. A normal mined height contributes
  `tip - minedHeight + 1`, capped at 3.
- A preparation transaction the tracker saw broadcast while the next block
  was still before a network upgrade, and that the server reports `NotFound`
  on two consecutive passes once it is past, was dropped at activation (nodes
  clear old-branch transactions, ZIP 200). The wave goes to the foreground
  without failing the task, since only the foreground can stop the run.
  Transactions first seen later may target the new branch and are not judged.
  The check reads `zcash_next_upgrade_activation_height` and process memory,
  not the wallet DB.
- Reaching 3 confirmations finishes only the current observation wave. The
  manager stores a foreground-continuation token, posts an “Open Vizor”
  notification under its own `confirmedWaveReady` kind so healthy copy never
  reuses failure copy, and immediately completes that system task successfully
  without opening the wallet DB for sync or advance. It does not wait for the
  user; a completed wave leaves nothing for a read-only task to observe.
- Foreground reentry acknowledges the token before syncing and advancing the
  durable run. If another transaction wave is materialized, it submits a fresh
  read-only continued-processing task.
- A foreground handoff records continuations only for runs that genuinely need
  the foreground — never for a run the read-only task could still finish. A
  multi-account task otherwise parks an account that is merely mid-wave, and
  that account stops being re-armed until the user makes it active. The
  "is a preparation bound to this request" boolean stays broader than the
  recorded set on purpose: it gates cancellation of the pending request, so
  deriving it from the recorded set would cancel healthy mid-wave runs.
- OS expiration is completed without a failure presentation and re-arms
  background tracking, because it interrupts one execution opportunity rather
  than proving the migration failed. Expiry posts no notification of its own:
  scopes whose waves already confirmed keep their earlier step-confirmed
  alert, and the interrupted wave resumes when the re-armed task runs.
- While private queries are on, the task does not track
  confirmations. A background pass cannot advance the wallet's scanned
  state, so it can never accept a Status PIR anchor, and it must not fall back
  to a public `GetTransaction`. `migrationPreparationContinuedTaskDisposition`
  maps a continued-processing target to `.foregroundOnly`, so the task is not
  submitted (`blocked_private_recovery`) and a launched task hands off to the
  foreground. Dart sends the effective setting through the
  `setPrivateRecovery` channel method at startup and on every toggle. Native
  treats a value it never received as private. Dart likewise resolves an
  unreadable saved preference to private for that launch without writing it
  back, and a blocked bootstrap applies no setting at all.

### Send Flow

2-step: `propose_send(account_uuid)` → confirmation dialog (shows fee) → `execute_proposal()` → broadcast via `SendTransaction` gRPC.

- Integer-only ZEC-to-zatoshi parsing (no floating-point)
- Real fee estimation via `estimate_fee(account_uuid)` on each keystroke
- No-op Sapling provers for Orchard-only TXs (avoids 50MB param download)
- Post-send: `refreshAfterSend()` for immediate pending TX display
- Friendly error messages via `_friendlyError()` pattern matching

### Ledger Device-App Limits

Before changing a Ledger send, Gift Card, shielding, swap, or voting flow, read
`docs/ledger/limitations.md`. **32 actions per pool does not mean 32 recipients:**
the device can review only **4 external shielded outputs across both pools**;
internal change is excluded. Numeric limits live in `rust/src/wallet/ledger/limits.rs`.
Keep account-key verification before PCZT transmission. Apps before 3.10.0
reject the NU7 branch and an Orchard spend into Ironwood; `LedgerAppSupport`
carries what the connected app can sign, and the serializer refuses the rest.

### Signing Cancellation

Keep desktop and mobile consistent when cancelling signing, not merely closing the QR scanner:

- Send / Gift Card: preserve inputs, return to Review, and refresh balance and fees before retry.
- Swap / Pay: return to the composer without preserving inputs; obtain a new quote on the next Review.
- Vote: preserve saved partial signatures and resume unsigned bundles.
- For transaction proposals, finish input-lock release and balance refresh before allowing retry.

Send proposal reservations are process-scoped until a signed outbox checkpoint
or the first broadcast attempt. Wallet-owned PCZTs carry the reservation owner;
strip that metadata from device signer views. Ledger checkpoint insertion and
reservation transfer must commit in the same SQLite transaction. Keystone marks
retention before the first network submission, including TEX's first round.
A hardware TEX request's ZIP 320 ephemeral address follows the same boundary:
releasing the request before that boundary returns the address, so cancelled
approvals cannot exhaust the ephemeral gap limit; after it the address stays
reserved.
Normal app exit closes the proposal gate and requests sync cancellation.
Desktop exits hide the window before awaiting reservation cleanup, except on
Linux. Linux keeps the window visible during the same bounded cleanup, then
calls `exit(0)` instead of GTK hide/destroy teardown to avoid the compositor
shutdown crash. Rust allows 250ms to
acquire the wallet write lock and drain accepted DB creators, then releases only
unsubmitted reservations without waiting on SQLite contention. Once the budget
expires, it starts no further cleanup; unfinished work is left for startup
recovery. It does not interrupt an active DB operation. Dart bounds its cleanup
wait at 300ms. On macOS, the exit-only `desktop_exit` channel orders the window
out synchronously and suppresses last-window auto-quit while Dart is preparing
its exit reply; ordinary window visibility still uses `window_manager`.
Backgrounding or hiding a window by itself does not end the session, except
that mobile returning after 15 minutes in the background locks it through the
sign-out sequence (`BackgroundAutoLockHost`).
Before the first balance read after restart, the DB migration gate recovers
abandoned process-scoped reservations without network access. Legacy retained,
signed, and ambiguous-broadcast reservations keep their expiry-based recovery.
Never clear all account locks: migration owners and durable outbox work are
outside cancellation cleanup.

Android Ledger device work must use `LedgerMobileHandler.launchOperation`,
including app queries and app-opening approval, not only signing APDUs. Register
ownership before dispatch, settle each MethodChannel result once, and retain the
SDK-wide exclusion until the job actually completes after cancellation. Discovery
and disconnect cleanup also participate in exclusion across Activity recreation.
Dart preparation uses `ledgerDeviceRequestsProvider`: capture before the first
await and check before starting the next stage or publishing a result. Do not
apply this cancellable device policy to already-submitted durable broadcasts.

### Hardware Wallet (Keystone) Send Flow

Normal hardware sends use Keystone's signatures-only batch protocol, even for
one transaction. The device cannot generate ZK proofs (proving keys are too
big for the device), and the phone cannot sign (the spending key lives on the
device), so Vizor retains the proof PCZT and applies only the compact
Orchard/Ironwood signatures returned by Keystone.

```
1. createPcztFromProposal                         → base PCZT (phone)
   (IO-finalized, no proofs, no signatures)
      │
      ├── 2a. addProofsToPczt(base, params?)      → pcztWithProofs
      │       (Orchard or Ironwood proof; Sapling output proofs if the
      │        proposal has needsSaplingParams=true)
      │
      └── 2b. preparePcztForKeystoneBatch(base)   → compact redacted PCZT
              → zcash-sign-batch QR
              → device signs Orchard/Ironwood spend_auth_sig
              → zcash-batch-sig-result QR         → signatures only
                                                         ↓
3. storeAndBroadcastPcztsWithKeystoneSignaturesForProposal(
     pcztWithProofs, signatureBlobs,
     spend_params?, output_params?,
   )                                                → txid
```

Roles in the split:

| Step | PCZT role | Runs on | Needs what |
|------|-----------|---------|------------|
| 1 | Creator + IoFinalizer | phone | wallet DB |
| 2a | Prover | phone | proving params (Orchard or Ironwood; Sapling ~50MB if the target recipient is Sapling) |
| 2b | Batch redactor | phone | wallet-owned base PCZT |
| sign | Signer | device | spend authorization derivation (device holds USK) |
| 3 | Signer application + TransactionExtractor | phone | wallet-owned proof PCZT, compact signatures, verifying keys, and wallet DB |

The v1 `BatchSignResponse` can represent only Orchard and Ironwood spend
authorization signatures. It cannot represent transparent-input or Sapling
spend signatures. Therefore hardware TEX sends and hardware transparent
shielding still use the full-PCZT signer response until the Keystone batch
protocol gains transparent signatures. Normal sends and ZEC swap deposits must
not fall back to the full-PCZT response.

One batch round can return at most 96 spend signatures, and one PCZT cannot be
split across rounds. `prepare_pczt_for_keystone_batch` therefore rejects a
transaction requiring more than 96 signatures before the request QR is shown.
Callers surface an actionable smaller-amount message and must not fall back to
the full-PCZT response.

**Critical invariants** (each of these was a real bug at some point in
development; breaking them is a correctness or data-loss regression):

1. **The hardware completion path must broadcast before it persists.**
   The function order is: `TransactionExtractor::extract()` (in-memory, no
   DB) → `send_transaction` gRPC → *only then* `extract_and_store_transaction_from_pczt`.
   Storing first would mark notes spent by a transaction no server holds.
   Once the server has the whole transaction, a nonzero `SendResponse` is no
   proof it was dropped: Zebra and Zakura re-queue rejected transactions for
   later blocks. A rejected transaction is stored like an unknown result, so
   its inputs stay spent until its expiry height; for a TEX payment round,
   sync keeps resubmitting it after the funding round. A transaction without
   an expiry height still fails outright, and
   so does a rejected TEX first round: it pays only the wallet's ephemeral
   address, and keeping it would drop the signed payment round.

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
   the hardware completion path whenever the PCZT contains a Sapling
   bundle.** `add_proofs_to_pczt` needs `LocalTxProver` to build Sapling
   output proofs; the completion path needs `LocalTxProver
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
`rust/src/wallet/sync/pczt.rs::{create_pczt_from_proposal,
add_proofs_to_pczt, prepare_pczt_for_keystone_batch,
store_and_broadcast_pczts_with_compact_signatures_for_proposal,
discard_proposal}` with FRB wrappers in `rust/src/api/sync.rs`.

**Transparent inputs under Private queries.** Every hardware broadcast path
(Ledger outbox, Keystone compact and full batches, legacy PCZT) re-checks its
transparent inputs just before `SendTransaction`
(`rust/src/wallet/sync/hardware_authority.rs`). Under a private policy the
check targets the wallet's own tip + 1, so a block that lands while the device
signs does not refuse the signature. Until private recovery covers the
wallet's latest scanned block the refusal is `CatchingUp`; the broadcast waits
up to 30 s (`CATCH_UP_WAIT`) for it, and a busy wallet DB is waited out the
same way. If it still cannot dispatch, the refusal is retryable and the caller
keeps the signed transaction rather than releasing it. Under Private queries,
Ledger accounts recover privately from their stored birthday like other
accounts (`docs/ledger/transparent-recovery.md`). A birthday later than the
account's first activity can omit earlier transparent history; existing public
records that private recovery cannot explain block activation, and turning
the setting off restores public discovery from height 0.

### Wallet Creation

`create_wallet()` fetches chain tip from lightwalletd as birthday height before creating the account. This prevents new wallets from doing a full chain scan. Birthday fetch failure blocks wallet creation (network required).

On mainnet, the wallet API (`rust/src/api/wallet.rs`, `restored_birthday`)
stores every restored birthday rounded down to one past a grid point
(`tree_states::restore_birthday`), so lightwalletd learns only the bucket. The
grid is every 10,000 blocks before NU7 and every 30,000 from it, about 8.7 days
in both eras, and the bucket containing the activation starts at the last grid
point before it. It is a height grid, not a calendar, so every app version
draws the same buckets.
When the grid point is a compiled checkpoint (`rust/src/wallet/tree_states.rs`)
the first scan batch reads its state locally instead of sending
`GetTreeState`; a restore newer than the table fetches the grid point's state.
Restores are the discovery import
(`import_software_wallet_with_account_discovery`), wallet-link import
(`import_software_account_at_index`), and hardware import
(`import_hardware_account`). Newly created accounts (`create_wallet`,
`add_account`, and `import_wallet` from onboarding's reveal-then-confirm
flow), payment-link claims (`import_wallet`), and Gift Card observers keep the
exact height; testnet and regtest are unchanged. Code that queries lightwalletd from a restored birthday must use the
rounded value, never the exact requested height. The weekly
`update-mainnet-chain-tables.yml` workflow appends checkpoints.

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

## Mobile UI Standards

Follow these whenever you build or change mobile UI, and especially when there
is no Figma design for it. They record decisions already made for the app, so
a screen that follows them looks and behaves like the rest. When you add a
reusable mobile component or settle a new visual rule, add it here in the same
change. The subsections below this list carry the detailed rules.

**Start from the shared pieces.** Don't rebuild a private copy of any of these:

- Page route: `_mobilePage` in `mobile_routes.dart` (`MobilePage` plus
  `MobilePageViewport`).
- Page header: `MobileTopNav.back`.
- Sheet: `showAppMobileSheet` with a `MobileModalScaffold` body. A flow
  with steps of its own (type an amount, then hand over a result) is a page
  instead, like Pay and Request ZEC: `MobileTopNav.back` over the step, its
  buttons docked at `kMobileFooterGap`, Back returning a step at a time.
- Card surface: `MobileSurfaceCard`. Titled list group: `MobileSection` with
  `MobileSectionRows` and `MobileListRow`.
- Single choice: `MobileRadioCard`. An option that starts an action:
  `MobileActionCard`.
- Floating bottom button: `MobileStickyBottomAction`. A list page's add
  action (Accounts' Add account, Contacts' Add contact) is this button, not
  a top-right "+".
- A two-way choice on a page (Receive's pools, the viewing key's QR code and
  Text): `AppSegmentedControl` set up as on Receive, 320 by 44, 20px icons,
  `labelLarge` w500, the selected pill `background.inverse`.
- Whose page it is (the viewing key choice, the secret passphrase):
  `MobileAccountHeader` with `mobileAccountHeaderBalance`. It shows the
  account's `AppProfilePicture` (`xLarge`) above its name in `bodyLarge` w600
  `text.accent`, then its balance in `bodyLarge` `text.secondary` (masked in
  privacy mode; left out when unknown), centered, 32 above the content. On
  the secret passphrase it is optional, a proposal rather than a
  requirement: it signals that the words are this wallet's master key, so
  the user treats the screen with care. Removing it there is acceptable.
- Success, pending and failure screen: `MobileTransactionProgressScreen`.
- Typing an amount: `MobileAmountCard`, Pay's card (its header row holds
  Pay's asset picker; Request ZEC leaves it out and the amount centres in
  the same minimum 240 height). Its amount/conversion rows and header grow with
  scaled text; narrow Pay headers and actions reflow before labels are clipped.
  Adding a message (memo):
  `showMobileMemoSheet`, Send's sheet, opened from a line under the card;
  pass a title, hint and `sanitize` for a flow with its own rules.
  Memo labels, errors and buttons grow with text; the input keeps an internal
  scroll view. Its scrollbar has a 24px hit area and a 6px visible thumb.
- A shortened address or transaction id takes one of the three forms in
  `lib/src/core/formatting/address_display.dart`, never a local `substring`:
  `truncatedAddress` (6 + 5 on phones, `u19509 ... 90591`; 9 + 7 on
  desktop, which has the room) where the address shares a
  line with a name, label or action (reviews, statuses, composers, deposit
  rows, sentences); `truncatedLongAddress` (13 + 11) where checking it is the
  point and it has a line to itself (the receive address, the Send recipient
  lists, an address being saved as a contact, accounts found on import); a
  long-form row that runs short of room gives `AddressLine(shortAddress:)` so
  it drops to the short form instead of being cut. Pay's recipient rows carry
  amounts and keep the short form throughout; `truncatedTxid` (8 + 8) for
  transaction ids and hashes. Log lines and viewing keys keep their own
  shortening.
- A one-line sentence naming a compacted address ("To: Mike (0x5290 ...
  69ee7) on Ethereum"): an `AddressLine` (`AddressLine.inTemplate` around the
  ARB message) shown through `ReviewInfoRow.bottomLeftAddress` or
  `AddressLineText`, on desktop too, never a pre-built string in a `Text` that
  ellipsizes. The address is never cut, and a saved contact's name stays
  visible on phones too. When the line is too wide, the text after the
  address gives way first; then the name moves to its own line above the
  address (shortened if it must be), so the row grows by a line; without a
  name, the text before the address gives way last. Pass `keepBefore: true`
  when that text says what the address is for ("Refund to:" under the amount
  paid); it then stays, with the address wrapping below it.
- In a `ReviewInfoRow`, the text beside the "Full address" action
  (`trailingActionLabel`) keeps its whole line: when the two don't fit side
  by side, the action moves to a line of its own below, still at the end,
  rather than the address being cut. A line naming a saved contact keeps the
  order above instead: the name moves up and the address stays beside the
  action.
- Buttons `AppButton`, icons `AppIcon(AppIcons.x)`, toasts `showAppToast`,
  haptics `AppHaptics`.

**Layout and spacing**

- Spacing comes from `AppSpacing` (4, 8, 12, 16, 24, 32, 48, 64) and radii
  from `AppRadii` (8, 12, 16, 24, 32). Don't write a literal where a token
  exists.
- Pages use `kMobilePageMargin` (20) at the sides. Sheets, card insides,
  toasts and the tab bar keep 16.
- 12 between stacked buttons and between stacked cards, 24 between sections,
  24 from a sheet's body to its buttons.
- Bottom buttons sit `kMobileFooterGap` above the safe-area inset (see
  "Mobile Page Footers").
- Rows and labels that hold text take a minimum height, never a fixed one, so
  large text grows instead of clipping.
- A page with a fixed layout (Receive) fits a 393×852 screen without
  scrolling. Receive keeps its QR at 228 for that, still easy for a camera;
  check the fit there before growing anything on such a page.

**Pages**

- Register every pushed screen through `_mobilePage`. It gives the window
  background, the side constraints, the scroll edge fades, the fade-and-zoom
  entrance (320ms, `Cubic(0.23, 1, 0.32, 1)`), the edge-swipe back and the page
  haptic. Button Back slides out over 400ms, restoring the previous page from
  1.03 scale to 1 with the same progress; a back swipe follows the finger and
  settles over 350ms. Both exits keep the page opaque and at full size, so the
  page below shows beside it. Under Reduce Motion button Back only fades.
  A pop during entry reverses that entry without jumping to a slide. A route
  outside it (onboarding, the Gift Card claim) installs
  `MobileScrollEdgeFades(color: window, bottomHeight: AppSpacing.xl)` itself.
- Onboarding steps enter instantly: `_mobileOnboardingPage` uses
  `MobilePageTransition.onboarding`. Back slides out over 400ms (fades under
  Reduce Motion); a back swipe stays opaque and follows the finger, then
  completes or cancels over 350ms. The previous page stays still. Keep entry
  duration zero and use the shared policy rather than per-screen transitions.
  Unlock, tab roots and the wallet root shell retain `NoTransitionPage`.
- Every step with a progress bar uses `MobileTopNav.steps` with its default
  geometry (`kMobileTopNavHeight`, no `progressOffset`, the default track
  color), directly under the safe area. Don't give one step its own height,
  offset or track, or the bar jumps between pages.
- An onboarding step that shows the citadel art passes
  `MobileOnboardingCitadelBackground` as the scaffold's `background`, the
  unlock screen's asset; the step then scrolls without edge fades.
- Inner pages keep `MobileTopNav.back`'s default `headlineSmall` title. Only
  the four tab roots (Home, Swap, Activity, Settings) pass
  `AppTypography.headlineLarge`, the serif. Don't pass `titleStyle` on an
  inner page.
- The four tab roots share one top: the nav (`kMobileTopNavHeight`) right at
  the safe-area top, nothing above it, and the first card `AppSpacing.s`
  under it. Switching tabs then moves neither the header nor the first card.

**Scrolling and fades**

- Every vertical scroll view under a page or sheet fades its cut edges by
  itself (`MobileScrollEdgeFades`); one that fits shows none. Don't add a
  private fade and don't clip rows flat.
- The fades paint the surface color. Where an image or gradient sits behind
  the scroll view (the castle engraving on records and success screens), wrap
  that body in `MobileScrollEdgeFades.off`.
- A scroll area that needs a taller, tuned fade (tab roots, a list under a
  floating button) uses `MobileTabRootScrollFades`, `MobileTopScrollFade` or
  `MobileBottomScrollFade`; each turns the standard edge off below it.
- Content that scrolls under a floating button gets its bottom padding from
  `MobileStickyBottomAction.contentInset`.

**Sheets**

- `MobileModalScaffold` is the one template: a `bodyLarge` w600 `text.accent`
  title, the shared close button, 32 top, 16 sides, 16 from title to body, 24
  bottom. Don't override its paddings without a stated reason.
- The scaffold scrolls a body taller than the room left (keyboard, large
  text). Pass `constrainBody: true` only for a body that brings its own
  scroll view.
- A field focused on open calls `focusWhenMobileSheetOpens` from a post-frame
  callback instead of `autofocus`, so the keyboard waits for the sheet.
- One decision per sheet. A setting with options shows as a Settings-style
  row (label left, the current value and a chevron right) that opens its own
  sheet one level down; there a tap marks an option and one primary Update
  applies it. Adding or editing an item (a custom source or server) opens a
  further sheet, so no sheet mixes a list with a form. Vote config is the
  example (`mobile_voting_config_settings_sheet.dart`).

**Surfaces, cards and lists**

- Cards are `MobileSurfaceCard`: ground fill with the `mobileSurfaceShadows`
  lift and no stroke. Borders mark structure (hairlines, a selected choice,
  inputs), never elevation.
- A titled group is a `MobileSection`: a 16px `text.secondary` label, 12
  above the card, sections 24 apart, rows split by `MobileSectionDivider`
  (0.5px `border.subtle`).
- Row icons are `icon.accent`; trailing chevrons are `icon.muted`.
- A list that runs longer than a screenful of choices (networks, tokens) gets
  a search field at its top, the Contacts search field or the Swap asset
  picker's, filtering on name and ticker, with the list holding its height
  while it filters and a "No … found" line when nothing matches.

**Typography**

- Mobile text is at least 16px: use `labelLarge`, `bodyMedium` and
  `codeMedium` at mobile call sites. The 13 and 14px tokens are for desktop or
  for spots with no room (seed-word grids, badges).
- Readable secondary text is `text.secondary`. `text.muted` fails 4.5:1, so
  keep it for disabled or decorative text.
- Amounts, balances and list dates use tabular figures (`withTabularFigures`).
- A page's hero amount is Young Serif at the Send amount's size (48, its
  ticker 38) inside `FittedBox(fit: BoxFit.scaleDown)`, so a long amount
  shrinks to fit between the page margins instead of clipping or wrapping.
- An amount shown with its QR (Request ZEC's result) uses the Home balance
  card's serif (`kMobileSerifAmountStyle`, its ticker
  `kMobileSerifTickerStyle`) with the `PoolBadge` under it, and the QR,
  amount and badge sit centred together between the header and the buttons.
- A large serif amount that privacy mode masks (Home's balance, a record's
  hero amount) builds its span with `serifPrivacyMaskSpan`: Young Serif sets
  the bullet a digit wide, and the helper pulls the dots to about half a dot
  apart.
- Copy follows "UI Copy Conventions" (sentence case, the glossary).

**Transaction records**

- The top shows only the type icon in liquid metal (a Gift Card shows its
  card art, without the amount), then the hero amount and its dollar value.
- Everything else is a row of the detail card, the status first, in the
  card's two columns: a `text.secondary` label and its value on the right.
- The castle engraving sits behind the record and the status screens in both
  themes; the art is a translucent grey that reads on light and dark.

**Color, icons and amounts**

- Colors come from `context.colors` tokens; no hex values in feature code.
- A shielded pool is the filled shield (`AppIcons.shieldKeyhole`); there is
  no outline version.
- An icon cast in liquid metal (a record's hero, the onboarding intro's
  shield) is `LiquidMetal` over `SvgShapeImage('assets/icons/<name>.svg')`
  with a transparent `colorBack`, `softness: 1` and `scale: 1`, as
  `TransactionTypeHero` sets it, wrapped in `ExcludeSemantics`.
- A line that names an address's or a payment's pool is `PoolBadge`: the
  crimson shield (or the muted transparent glyph) and "Shielded" or
  "Transparent" in `text.secondary`, on mobile drawn exactly as the activity
  rows draw it: the 16px regular label and the `icon.brandCrimson` /
  `icon.muted` glyph colors (the text crimson is a lighter pink in dark mode).
  Don't tint the word itself or pair it with another icon color.
- A value that opens or expands (a message) shows `AppIcons.expand`, the
  vertical chevrons. The up-down arrows (`AppIcons.doubleArrowVertical`)
  only switch units, such as ZEC and dollars.
- A viewing key is the eye (`AppIcons.eye`): the full key, the Settings row
  and "Show viewing key". The incoming-only key is the receive arrow
  (`AppIcons.arrowDownCircle`). Request ZEC is the speech bubble with the Z
  (`AppIcons.request`), not the link icon.
- Received amounts show "+", sent amounts no sign, both in the row's accent
  tone. Amounts follow privacy mode (`docs/privacy-mode.md`).

**Controls**

- `AppButton`: one primary (black accent) action per view, secondary for
  alternatives, ghost for Cancel; full width (`expand: true`) at the bottom of
  a page. Disabled buttons are solid (`button.disabled`), so a floating button
  never shows content through it.
- Toggles have no outline: the off track is `background.overlay` and the thumb
  carries `appSurfaceShadow`.
- Every custom tap target is wrapped in `Semantics(button: true, label: ...)`
  and is at least 24pt.
- A copy confirms with a toast (`showAppToast`, "... copied"; a failure uses
  the destructive tone), not by changing the button's label.
- Menu items that reveal a secret say "Show ...": "Show secret phrase",
  "Show viewing key".
- A Settings on/off setting is a card like Keep screen awake and Flip to hide:
  a `MobileSection` title, a row with its icon, label and the shared
  `_SettingsToggle`, and a `bodyMedium` `text.secondary` explanation under it.
  The switch ticks `selection()` as it flips, and a failed save shows a toast.
- The Flutter fallback tab bar (`AppMobileTabBar`) has 52 by 72 items in a
  60-high bar (`kMobileTabBarHeight`), hugging its tabs, with 24px icons. Code that
  clears it reads `kMobileTabBarHeight` or
  `MobileNavigationScope.bottomClearanceOf`, never a literal.
  Its horizontal bar previews the touched tab over 100ms, adding finger travel
  during that arrival; navigation commits only on tap/drag release. Cancel
  restores the actual selection. Keep the first pointer in control, one haptic
  per selection boundary, and instant arrivals under Reduce Motion. The vertical
  bar retains its selected-tab drag origin.
  Raw drag recognizers inherit `MediaQuery` gesture settings and require the
  horizontal threshold before accepting a drag. A tab's tap rejection only
  releases its icon press; it must not discard a pending drag preview. Cover
  device touch slop and diagonal movement in gesture regressions.
- iOS 26+ uses the native Liquid Glass tab bar when available. Preserve the
  native root host, registration and `nativeBar` precedence in `AppMobileShell`.
  UIKit owns its sizing, safe area, selection lens, motion and press haptics;
  Flutter fallback metrics, icon flourishes and surrounding touch blocker do
  not wrap the native lane. See `docs/ios-native-tab-bar.md`.
- A host that toasts from any wallet page (flip to hide) sits in the wallet's
  root shell route (`buildMobileRoutes`), so its toast shows in the root
  overlay. Mounted above the router it would draw into the tab shell's toast
  host, under any pushed page.

**Motion**

- Gate every animation on `MediaQuery.disableAnimationsOf(context)`; iOS
  Reduce Motion reaches it through `PlatformReduceMotionScope`. Under reduced
  motion keep fades and drop movement, scale and rotation.
- Curves: `Cubic(0.23, 1, 0.32, 1)` for entrances, `Cubic(0.77, 0, 0.175, 1)`
  for movement on screen, `Cubic(0.32, 0.72, 0, 1)` for iOS-style sheets and
  pagers.
- Keep interaction motion short (pages 320ms in and 400ms out, toasts 350ms in
  and 200ms out, sheets about 200ms). Longer motion is for one-off moments
  only, such as the tab icon flourishes and the 1,950ms success ripple. Frequent actions
  (typing, row taps) don't animate.
- Passcode keys fire on touch and dim to 50% while held: at once on the
  touch, fading back over 150ms on release (`_PasscodeKey` in
  `passcode_widgets.dart`). The fade never delays the next digit.

**Haptics**

- Use `AppHaptics`, not `HapticFeedback`:
  - `action()` on a button that starts a flow, before the push. Routes play
    `pageTransition()` themselves.
  - `selection()` the moment a toggle, radio or segmented control flips, not
    after its save finishes. `AppSegmentedControl` ticks it on a tap itself;
    a pager that switches the same choice by swipe (Receive's pools) ticks
    it on its page change, so each switch ticks once.
  - `tabSwitch()` (medium) for the Flutter fallback tab bar, `copy()`, and
    `error()` for a rejected passcode.
  - `sendSuccess()` or `sendFailure()` once, when a transaction's outcome
    arrives while its screen is open.

**Check a new mobile screen**

- Add a deterministic capture scenario (`figma_compare_scenarios.dart`,
  ideally from a Widgetbook use case) and look at it in light and dark:
  `scripts/figma-compare.sh widget --form-factor mobile --scenario <id>
  --theme <light|dark>`.
- Tag its tests `mobile` and compare against tokens, not literal numbers.

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

### Mobile Page Footers

Every mobile page's bottom buttons sit `kMobileFooterGap` (12) above the
bottom safe-area inset: 46pt from the bottom edge on a current iPhone, the
Send flow's distance. The token lives in
`lib/src/core/layout/mobile/mobile_sticky_bottom_action.dart`.

- A footer docked under a page's scroll view, in a bottom `SafeArea`, pads
  its buttons' bottom by `kMobileFooterGap`.
- A button floating over the scroll view uses `MobileStickyBottomAction`
  (its `bottomOffset` adds the inset, which drops to the gap above a raised
  keyboard).
- A page body wrapped in `MobileBottomSafeArea` passes
  `bottomPadding: kMobileFooterGap`; that is under the iOS clearance, so the
  inset always applies and the page matches the others. The iOS
  proportional rule above stays for sheets and the tab bar only.

### Mobile Sheets and the Keyboard

Mobile sheets are root-navigator routes, and a text field in one raises the
keyboard over the whole window. Keep a keyboard animation from rebuilding or
laying out more than the sheet itself:

- Routes beneath a sheet hold still. `CoveredRouteKeyboardHold`
  (`lib/src/core/layout/mobile/covered_route_keyboard_hold.dart`) wraps every
  `MobilePage` and the wallet shell route: a covered route whose keyboard was
  down sees none until the keyboard rises for it again. Wrap any new
  root-level page type the same way.
- Sheet bodies sized to the room above the keyboard use
  `MobileKeyboardAwareHeight` instead of reading `MediaQuery` in their own
  build. Only its builder runs per keyboard frame; pass the body as `child`.
- Elsewhere, read the narrow lookups (`MediaQuery.viewInsetsOf`,
  `sizeOf`, `paddingOf`) rather than `MediaQuery.of`, and keep any
  `MediaQuery.of` read out of the app-root `builder`.

### Mobile Cards

Mobile option and action cards share one surface, `MobileSurfaceCard`
(ground fill with `mobileSurfaceShadows`, no stroke). Build new ones from
the shared components in `lib/src/core/widgets/mobile/` instead of a
private copy:

- `MobileRadioCard` — one choice in a single-choice list (Figma `Radio
  Card`): optional icon, title, detail lines or a description paragraph, a
  badge beside the title, action buttons before the trailing round check,
  and a dimmed disabled state. Only the selected card carries the 2px strong
  stroke. Stack them 12px apart.
- `MobileActionCard` — a card that starts an action: round badge in the
  primary button's colours, title, description (the Home Receive sheet).

## Testing

- Keep small Rust internal tests in the source file's `#[cfg(test)] mod tests`.
- When fixtures or scenarios obscure the implementation, split into `<module>/tests.rs`; do not split by line count alone.
- Put public-API integration tests in `rust/tests/`; do not widen production visibility for test placement.
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
  - Mobile runs need THREE defines: `VIZOR_FORM_FACTOR=mobile`, `ZCASH_DEFAULT_NETWORK=regtest`, `ZCASH_E2E_LIGHTWALLETD_URL` — `run_mobile_e2e` in `scripts/e2e/lib-mobile.sh` injects them. Gift Card scenarios need a fourth, `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` (payment links stay gated off without it), plus `VIZOR_DEEPLINK_BASE_URL`; the runner passes both to `run_mobile_e2e` as extra defines rather than `run_mobile_e2e` injecting them.
  - Device selection: `SIMULATOR_UDID` env wins; otherwise the single booted simulator. The runner refuses to pick among multiple booted sims.
  - Each `flutter test integration_test` invocation reinstalls the app: the wallet DB dies with the container while the iOS Keychain persists until the reinstalled app's first launch clears it, so in-test `cleanupE2eWalletState()` (deleteAll + db files, regtest-guarded) runs at test start AND teardown. Cross-invocation wallet reuse needs `--no-uninstall`: the Ironwood restart runners pass it to their prepare phase so the resume phase reopens the same install. Gift Card scenarios pair it with `cleanupMobileE2ePaymentLinkClaimWallets()`, the regtest-guarded claim-wallet sweep — claim wallets from every network share one support directory, so the sweep is scoped to regtest names. Scenarios that leave the pasteboard populated clear it in teardown too; the simulator pasteboard outlives the app container.
  - The simulator shares the host loopback: `127.0.0.1` URLs, the in-test lightwalletd proxy, and the python E2E driver all work unchanged. Android emulators would need `10.0.2.2` and are out of scope.
  - Desktop scenarios without mobile counterparts (feature gaps, add when the features land): custom-endpoint privacy (no mobile endpoint settings UI), mempool during-sync / expiry variants.
  - Payment-request round trip and payment-URI locked-send: desktop runners only. The mobile receive pane has its own request sheet, so this is a harness gap rather than a feature gap.
  - Gift Card restart recovery and reorg retry: desktop runners only. The Gift Card round trip has a mobile counterpart driving the **Redeem a card → Paste card link** path; mobile claiming over a universal link still needs a publicly reachable HTTPS origin — see `scripts/e2e/README.md`. The payment-URI send also has a mobile counterpart, which instead pushes an `onUris` call over the `com.zcash.wallet/payment_uri` MethodChannel to raise the payment-request card.
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

The zakura wallet crates come from their crates.io releases, with no `[patch]`. A release that adds a wallet migration makes the database unreadable to builds with an older release.

`tonic` 0.14 with `tls-ring` + `tls-webpki-roots` features for gRPC TLS. `rustls` 0.23+ requires explicit crypto provider — `tls-ring` provides this.

`log` 0.4 for Rust logging — forwarded to Flutter console via FRB. Level set to `Info` in `init_app()`.

Additional crates for multi-account: `uuid` 1.1, `zip32` 0.2, `jubjub` 0.10, `bls12_381` 0.8, `rand_core` 0.6.

## Ignored Paths

`onboarding/` — Developer onboarding documentation. Do not read or modify during normal development. Only update when explicitly asked.

`CLAUDE.md` intentionally contains only `@AGENTS.md`; update this file as the source of truth and keep this line as the final line.
