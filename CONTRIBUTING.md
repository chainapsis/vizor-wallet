# Contributing to Vizor

Thank you for helping improve Vizor. Vizor is a self-custody Zcash wallet, so
changes that affect keys, wallet state, synchronization, balances, transaction
construction, or privacy need especially careful review and testing.

By contributing, you agree that your contribution may be distributed under
the repository's [Apache License 2.0](LICENSE).

## Before you start

- Search the existing issues and pull requests before starting a change.
- For a large feature, a data migration, a new dependency, or a change to a
  wallet/security invariant, discuss the approach with the maintainers first.
- Keep a pull request focused on one coherent change. Separate unrelated
  refactors and formatting cleanups.
- Never use a real wallet or real secrets in tests, screenshots, logs, issues,
  or pull requests.

Use GitHub issues for questions and ordinary bug reports when issue creation is
available to you. A useful bug report includes the Vizor version or commit,
operating system and architecture, expected and actual behavior, reproducible
steps, and relevant sanitized logs. For device-specific bugs, also include the
device or simulator and OS version.

### Security and privacy reports

Do not disclose a suspected vulnerability or sensitive wallet information in a
public issue. Follow the [security policy](SECURITY.md) and report it privately
to [security@keplr.app](mailto:security@keplr.app).

Before attaching diagnostics, remove mnemonic phrases, BIP39 passphrases,
passwords/passcodes, spending keys, viewing keys, addresses, transaction IDs,
database contents, API credentials, and any other data that could identify a
wallet or its activity.

## Repository overview

Vizor combines a Flutter application with a Rust wallet core and native
platform integrations.

| Path | Responsibility |
| --- | --- |
| `lib/` | Flutter UI, routing, Riverpod state, secure-storage coordination, and platform service interfaces |
| `rust/src/wallet/` | Zcash keys, accounts, synchronization, balances, transaction construction, PCZT, and Keystone integration |
| `rust/src/api/` | Flutter Rust Bridge API exposed to Dart |
| `lib/src/rust/` | Generated Dart bindings; do not edit by hand |
| `ios/`, `android/`, `macos/`, `windows/`, `linux/` | Native runners and platform-specific integrations |
| `test/` | Dart unit and widget tests, including desktop and mobile-token lanes |
| `rust/tests/` | Rust regtest integration tests |
| `integration_test/` | Device and regtest end-to-end tests |
| `scripts/` | Build, packaging, Figma comparison, regtest, and E2E runners |
| `release_notes/` | Canonical user-facing desktop release notes |

The key architectural boundary is intentional: Rust owns Zcash cryptography,
wallet database access, synchronization, and transaction operations. Dart owns
presentation and application state. Avoid reimplementing wallet rules or
cryptographic behavior in Dart.

## Development setup

The repository pins Flutter with FVM. Install the following before building:

- Git
- FVM
- Flutter dependencies for your target platform
- A current stable Rust toolchain with Cargo and `rustfmt`
- Platform tooling as needed: Xcode and CocoaPods for Apple platforms, Android
  Studio/SDK for Android, Visual Studio with desktop C++ tools for Windows, or
  the Flutter Linux desktop prerequisites for Linux
- Docker Desktop or another Docker installation with Compose for regtest work

Then run from the repository root:

```bash
fvm install
fvm flutter pub get
```

The Flutter version is declared in `.fvmrc`. Always use `fvm flutter` and
`fvm dart`; do not use an unpinned `flutter` or `dart` executable.

Start the desktop app with:

```bash
fvm flutter run
```

Mobile builds select their design-token set at compile time:

```bash
fvm flutter run --dart-define=VIZOR_FORM_FACTOR=mobile
```

For iOS wallet creation/import testing, `./clear-app.sh` removes the app,
Keychain entries, and saved state from the booted simulator. This is destructive
to that simulator's Vizor data; use it only with disposable test wallets.

## Making changes

Create a branch from an up-to-date `main` unless a maintainer asks you to target
a release or stacked branch. The repository normally preserves reviewed commits
and merges pull requests with merge commits, so make each commit a meaningful,
reviewable unit.

Commit subjects should be concise and imperative, for example:

```text
Preserve balances after sync recovery
Add mobile account-switch regression test
```

Use the commit body when the motivation, safety property, tradeoff, or non-obvious
constraint would otherwise be lost. Conventional Commit prefixes are accepted
but are not required. Avoid `WIP`, review-fix, and formatting-only noise in the
final history. Preserve `Co-Authored-By` trailers when applicable.

### Rust and Flutter Rust Bridge

- Keep Zcash crate versions compatible with one another. In particular,
  `zcash_client_backend`, `zcash_client_sqlite`, `orchard`, `sapling-crypto`,
  and related public types must resolve to compatible versions.
- Treat database formats, secure-storage keys, serialized values, and native
  FFI contracts as persistent compatibility surfaces. Version or migrate them
  deliberately and test upgrades from existing data.
- Represent ZEC amounts with integer zatoshis. Do not use floating-point math
  for money.
- Keep secrets scoped narrowly, clear sensitive in-memory state on lock/reset,
  and avoid logging wallet-identifying data.
- Keep platform-neutral Rust logic outside `rust/src/api/` when it should not be
  exposed through Flutter Rust Bridge.

After changing any file under `rust/src/api/`, regenerate bindings from the
repository root:

```bash
flutter_rust_bridge_codegen generate
```

Commit all resulting changes in `lib/src/rust/` and
`rust/src/frb_generated.rs` with the API change. Do not manually patch generated
files. The project uses Flutter Rust Bridge `2.11.1`; use a compatible codegen
binary.

### Flutter UI and application state

- Use the unsuffixed design-token selectors such as `AppTypography` and
  `AppInputSizing` in application code. Desktop/mobile selection is controlled
  by `VIZOR_FORM_FACTOR`, not by runtime OS checks.
- Use `kAppFormFactor` for form-factor layout branching. Runtime platform checks
  are only for actual OS-specific behavior.
- A test that asserts mobile-only UI must begin with `@Tags(['mobile'])` and run
  in the mobile test lane. Untagged tests must be form-factor agnostic.
- User-facing copy uses sentence case by default. Preserve canonical names and
  acronyms such as Vizor, Zcash, ZEC, USDC, USDT, NEAR, and Keystone. Sidebar
  entries and screen titles may use title case.
- Reuse the shared password policy. Desktop passwords accept only printable
  ASCII characters, and mobile uses an exact six-digit passcode through the
  same credential path.
- Update Widgetbook fixtures and literal-string assertions when changing copy
  or component behavior.
- Keep deterministic UI states independent of production wallet data, Rust
  state, storage, and the network.

For visual changes, add or reuse a scenario in
`lib/figma_compare/figma_compare_scenarios.dart`, then capture it with:

```bash
scripts/figma-compare.sh widget --scenario <scenario> --theme <dark|light>
```

For a mobile reference, add `--form-factor mobile`. Compare the generated
`content.widget.png` with the intended design at the same viewport, theme,
locale, content, and state. Native captures are reserved for behavior that the
widget renderer cannot represent, such as window chrome or native insets.

If a contribution explicitly modifies a Figma file, read `FIGMA-AI-FIX.md`
before doing so. Comparing code with Figma does not by itself authorize changes
to the design file.

## Testing

Run the smallest relevant tests while developing and the complete applicable
set before opening a pull request. In the PR description, list the exact
commands run and any tests not run, with the reason.

### Baseline checks

For Dart or Flutter changes:

```bash
fvm dart format --output=none --set-exit-if-changed <changed Dart files>
fvm flutter analyze
fvm flutter test
```

The default Flutter test command is the desktop-token lane. Mobile-tagged tests
are skipped there and must be run separately:

```bash
fvm flutter test --tags mobile --run-skipped \
  --dart-define=VIZOR_FORM_FACTOR=mobile
```

For Rust changes:

```bash
cd rust
cargo fmt --check
cargo test
```

An API/FFI change normally requires both the Rust and Flutter checks after code
generation. A native-platform change also requires a build or targeted test on
that platform.

Add a regression test for bug fixes whenever practical. Keep unit/widget tests
deterministic and prefer fakes over production storage, live wallet data, and
network calls.

### Integration and regtest checks

Integration and regtest suites are slower and require additional services. Run
the scenarios relevant to changes in synchronization, transaction lifecycle,
endpoint failover, account import, shielding, migration, or native background
execution.

Rust regtest suite:

```bash
./run-regtest-rust-tests.sh
```

macOS Flutter regtest suite (hidden window by default):

```bash
scripts/e2e/flutter-macos-regtest-full.sh
```

iOS mobile regtest suite:

```bash
scripts/e2e/flutter-ios-regtest-mobile-full.sh
```

The runners manage the required `regtest` and mobile compile-time definitions.
Docker Compose is required; `grpcurl` is optional but improves readiness checks.
Use a targeted script under `scripts/e2e/` instead of a full suite when it
covers the changed behavior. State which scenario you ran in the PR.

Regtest runners reset local chain and wallet state. Never point them at mainnet
or reuse production wallet material. Debug Rust crypto is substantially slower
than release builds, so use release mode for performance conclusions.

## Pull requests

A pull request should:

- Explain the problem and why the chosen approach is appropriate.
- Describe user-visible behavior before and after the change.
- Call out security, privacy, wallet-state, migration, network, and
  cross-platform implications.
- Link the relevant issue or design when one exists.
- Include tests for new behavior and exact local validation commands.
- Include review screenshots for any design or user-visible UI change.
  Attach widget-test captures (`scripts/figma-compare.sh widget`) for every
  form factor the change ships on, covering the entry point and the important
  new or changed states. Embed the images in the PR description; do not leave
  the UI described only in prose.
- Include generated Flutter Rust Bridge files when an exposed Rust API changes.
- Avoid unrelated dependency, lockfile, formatting, asset, and generated-file
  churn.
- Remain a draft while known failures or required work remain.

Reviewers may ask for a change to be split when independent behavior, broad
refactoring, and generated or mechanical changes obscure one another.

## Release notes

Do not add or update a release-note file as part of an ordinary pull request.
Before a release, maintainers use AI to review the relevant commits and pull
requests and generate the release notes according to `release_notes/README.md`.

Write a clear, accurate pull request description so that this review can
reliably identify user-visible behavior, affected platforms, important fixes,
and any upgrade or compatibility notes. Clearly distinguish desktop changes
from mobile-only and internal changes.

When explicitly preparing a release, follow `release_notes/README.md` and
create `release_notes/vX.Y.Z.md`. Unless the release scope says otherwise,
those notes cover desktop behavior on Windows, Linux, and macOS and exclude
mobile-only or internal changes.

## License

Vizor is licensed under the [Apache License 2.0](LICENSE). Submit only work that
you have the right to contribute, and preserve third-party notices and license
terms for copied or derived material.
