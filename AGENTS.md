# Vizor agent notes

## Project boundaries

- Flutter/Riverpod owns UI, orchestration, and secure storage; Rust owns Zcash
  cryptography, wallet DB, and scanning via `flutter_rust_bridge` v2. Keep complex
  Zcash types below `rust/src/api/`.
- Accounts cross Dart/Rust as UUID strings. One main wallet DB and one scan cover
  all accounts; active-account selection scopes displayed data, not the scan.
- Never infer retry safety from cancellation or a missing response. Check the
  relevant contract before changing signing, broadcast, lock, or wallet deletion.
- Read or modify developer `onboarding/` documentation only when requested.

## Read the relevant contract

Before editing, choose the relevant contract using the task's symbols or callers.
Read known contracts directly; in an index, select only the matching entry.
Check the code/tests needed for the change. Follow related links only when their
condition applies; do not load sibling areas or all contracts at startup.

| Work area | Start here |
| --- | --- |
| Account creation, import, switch, or deletion | [Accounts](docs/contracts/domains/accounts/index.md) |
| Startup, lock/unlock, or whole-wallet reset | [Wallet lifecycle](docs/contracts/domains/wallet/index.md) |
| Password/passcode setup or change | [Security](docs/contracts/domains/security/index.md) |
| ZEC transfer, donation, or shielding | [Send](docs/contracts/domains/send/index.md), [Donation](docs/contracts/domains/donation/index.md), [Shielding](docs/contracts/domains/shielding/flow.md) |
| Receive request or incoming payment URI | [Receive](docs/contracts/domains/receive/request-draft.md), [Payment requests](docs/contracts/domains/payment-requests/index.md) |
| Swap, exact-output Pay, or Gift Card | [Swap](docs/contracts/domains/swap/index.md), [Pay](docs/contracts/domains/pay/index.md), [Gift Cards](docs/contracts/domains/gift-cards/index.md) |
| Encrypted wallet transfer | [Wallet Link](docs/contracts/domains/wallet-link/index.md) |
| Voting discovery, participation, or execution | [Voting](docs/contracts/domains/voting/index.md) |
| Ironwood migration or background preparation | [Migration](docs/contracts/domains/migration/index.md) |
| Proposal ownership, release, or broadcast outcome | [Transactions](docs/contracts/references/transactions/index.md) |
| Keystone/PCZT or shared desktop signing | [Signing](docs/contracts/references/signing/index.md) |
| Wallet DB or secure-storage sessions | [Storage](docs/contracts/references/storage/index.md) |
| Sync, balances, or progress | [Sync](docs/contracts/references/sync/index.md) |
| Tor/Direct routing or failover | [Network routing](docs/contracts/references/network/route-policy.md) |
| Form factor, insets, window, or copy | [UI](docs/contracts/references/ui/index.md) |
| Keychain/keyring, native background work, or OS behavior | [OS and environment](docs/contracts/platforms/index.md) |

Unknown owner: use the [domain](docs/contracts/domains/index.md) or
[shared](docs/contracts/references/index.md) index. Undocumented areas start from
code and tests. Keep applicable constraints in the task context and verify them
against current code.

## Commands and task guides

- Use `fvm flutter` / `fvm dart` from the project root. Before selecting tests,
  read [Test execution](docs/contracts/guides/testing.md); the owning contract
  identifies relevant coverage. Required PR checks remain in [Testing](CONTRIBUTING.md#testing).
  Documentation-only edits need fact, link, and diff checks, not app builds.
- Every mobile run/build/test/drive needs `--dart-define=VIZOR_FORM_FACTOR=mobile`.
- After changing `rust/src/api/*.rs`, run `flutter_rust_bridge_codegen generate`
  from the project root, never `rust/`.
- Setup, `clear-app.sh` simulator/Keychain reset, logs, and dependency changes:
  [Development setup](CONTRIBUTING.md#development-setup).
- Run regtest/integration suites only when explicitly requested; read the [E2E guide](scripts/e2e/README.md)
  first. macOS E2E windows stay hidden unless visual verification requires them.
- Figma implementation or comparison: [Visual contract](docs/contracts/references/ui/figma-comparison.md).
  A comparison does not authorize Figma edits. For requested edits, read
  [FIGMA-AI-FIX.md](FIGMA-AI-FIX.md) completely.
- Release notes: follow [the release guide](release_notes/README.md); default to
  desktop Windows/Linux/macOS changes, excluding mobile-only changes.

## Keep contracts useful

Update the owning contract when behavior changes. Keep rules, exceptions, and
source/test pointers concise; reuse existing owners and guides. See
[contract maintenance](CONTRIBUTING.md#contract-maintenance) when writing one.
Preserve comments about security, ordering, races, ownership, constraints, or
recovery, plus API docs, directives, licenses, and executable examples.

`AGENTS.md` is the project entry point; `CLAUDE.md` forwards here.
