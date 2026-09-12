# AGENTS.md

## Project boundaries

- Vizor is a Flutter/Riverpod wallet with Rust behind `flutter_rust_bridge` v2.
  Rust owns Zcash cryptography, wallet DB operations, and scanning; Dart owns UI,
  orchestration, and secure storage. Keep complex Zcash types below the flat
  `rust/src/api/` boundary.
- Accounts cross Dart/Rust as UUID strings. One main wallet DB and one scan cover
  all accounts; active-account selection scopes displayed data, not the scan.
- Never infer retry safety from cancellation or a missing response. Read the
  relevant contract before changing signing, broadcast, lock, or wallet deletion.
- Do not read or modify `onboarding/` during normal development; it is developer
  onboarding documentation maintained only when explicitly requested.

## Commands and verification

Always use `fvm` for Flutter/Dart. Run commands from the project root unless a
command below changes directory.

```bash
fvm flutter run
fvm flutter analyze
fvm flutter test
fvm dart format <changed-dart-files>
(cd rust && cargo test)
```

- Every mobile-targeted run, build, test, and drive needs
  `--dart-define=VIZOR_FORM_FACTOR=mobile`. Desktop is the default. Mobile UI tests
  require their own lane; plain `fvm flutter test` skips them:

  ```bash
  fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile
  ```

- After changing Rust API files (`rust/src/api/*.rs`), run
  `flutter_rust_bridge_codegen generate` from the project root, never `rust/`.
- Follow [CONTRIBUTING.md](CONTRIBUTING.md#testing) for applicable checks. Start
  near the change; a passing build alone does not verify visible UI behavior.
- Regtest E2E is slow and resets shared chain/wallet state. Run it only when the
  user explicitly requests regtest/integration execution; read the
  [E2E guide](scripts/e2e/README.md) first. macOS E2E windows stay hidden by
  default; use `VIZOR_E2E_HIDDEN_WINDOW=false` only for needed visible debugging.
- `./clear-app.sh` removes the booted iOS simulator app, state, and Keychain
  data. Use only when that wallet reset is intended; normal uninstall leaves
  Keychain data behind.
- On macOS, Rust logs go to `os_log` subsystem `frb_user`, not the Flutter
  terminal: `log stream --predicate 'subsystem == "frb_user"' --level info`.

## Find the relevant contract

Start with the task's symbols, callers, or changed region. When a change touches
one of these boundaries, read its contract and follow the source/test links
needed to decide the behavior. Follow cross-links when the task crosses an
owner; do not load every contract as startup context. Verify current code when
editing behavior and correct a stale contract in the same change.

| Task or boundary | Contract |
| --- | --- |
| Account creation/import, bootstrap, UUIDs, DB identity, deletion | [Account and storage](docs/contracts/account-storage.md) |
| Password/passcode, unlock, secret sessions, rotation | [Security lifecycle](docs/contracts/security-lifecycle.md) |
| Lock clearing, cancellation/drain, account switch, balance recovery | [Lock and sync](docs/contracts/lock-sync.md) |
| Scanner, progress, mempool, endpoint changes, Tor routing | [Sync and network](docs/contracts/sync-network.md) |
| Send inputs, review/status navigation, proposal ownership, retry | [Send](docs/contracts/send.md) |
| Keystone QR, PCZT roles, compact signatures, TEX exceptions | [Hardware signing](docs/contracts/hardware-signing.md) |
| NEAR Intents quotes, deposit routes, Swap/Pay cancellation | [Swap and Pay](docs/contracts/swap-pay.md) |
| Gift Card payloads, funding, claims, recovery, deep-link host | [Payment links](docs/contracts/payment-links.md) |
| Voting sessions, recovery, background submission, deletion drain | [Voting](docs/contracts/voting.md) |
| Ironwood preparation, credentials, native tracking, outbox | [Migration](docs/contracts/migration.md) |
| Design tokens, form factor, windows, safe areas, copy, Figma | [UI and platform](docs/contracts/ui-platform.md) |

## Task-specific guides

- Setup, test conventions, and contribution workflow: [CONTRIBUTING.md](CONTRIBUTING.md).
- For Figma implementation or comparison, read the
  [visual contract](docs/contracts/ui-platform.md#figma-comparison). Widget-test
  capture is the default. A comparison request does not authorize Figma edits.
- Before an explicitly requested Figma mutation, read
  [FIGMA-AI-FIX.md](FIGMA-AI-FIX.md) completely and follow its workflow.
- For user-facing release notes, read [release_notes/README.md](release_notes/README.md)
  and create `release_notes/vX.Y.Z.md`. Default to desktop Windows/Linux/macOS
  changes; exclude mobile-only changes unless requested.
- Dependency versions come from `pubspec.yaml`, `pubspec.lock`, `rust/Cargo.toml`,
  and `rust/Cargo.lock`. Verify compatible librustzcash versions before bumps.

## Keep context useful

Keep cross-file behavior contracts in `docs/contracts/`, with stable source
symbols and focused verification links. Reuse existing detailed guides instead
of duplicating their rules. Update the owning contract when a behavior changes.

Keep local comments that explain security, ordering, races, ownership, unusual
constraints, or recovery. Preserve API docs, directives, licenses, and executable
doc examples. Remove code restatements or duplicated flow narratives only when
the remaining code and contract retain the important reasoning.

`AGENTS.md` is the project instruction entry point; `CLAUDE.md` forwards here.
