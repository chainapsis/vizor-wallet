# Bundle-Indexed Voting API Spec

This spec records the required behavior for the bundle-indexed voting API.
Fast Rust unit tests cover the DB-backed portions; live-service happy paths are
left to the macOS/regtest E2E smoke because they require lightwalletd, a wallet
DB with spendable Orchard notes, PIR, proof generation, and transaction
broadcast.

## API Contract

Delegation must preserve the Swift SDK's explicit bundle model:

1. Initialize or load the voting round.
2. Select snapshot-eligible notes.
3. Run `setup_delegation_bundles` to persist bundles and return
   `bundle_count` plus total eligible weight.
4. For each selected `bundle_index`, call
   `build_and_prove_delegation_bundle`.
5. Store/read recovery state by `round_id + bundle_index`.
6. If only a prefix is processed, call `delete_skipped_bundles` and surface
   partial delegation honestly.

`build_and_prove_delegation_bundle` must use only the selected bundle's notes
for witness generation, governance PCZT construction, PIR/proof generation,
delegated weight calculation, and tx-hash recovery.

## Coverage Matrix

| Function | Fast test coverage | Live/spec coverage |
| --- | --- | --- |
| `prepare_voting_round` | Happy path and invalid round params in `rust/src/api/voting.rs` tests | N/A |
| `get_bundle_count` | Happy path after setup in `rust/src/api/voting.rs` tests | N/A |
| `store_delegation_tx_hash` | Happy path and missing-bundle error in `rust/src/api/voting.rs` tests | N/A |
| `get_delegation_tx_hash` | Happy path in `rust/src/api/voting.rs` tests | N/A |
| `delete_skipped_bundles` | Happy path in `rust/src/api/voting.rs` and storage wrapper tests | N/A |
| `setup_delegation_bundles` | Invalid-network preflight in `rust/src/api/voting.rs`; bundling happy path in `rust/src/wallet/voting/delegation.rs` via `ensure_bundles` | Requires live lightwalletd tree state and wallet note fixtures |
| `build_and_prove_delegation_bundle` | Invalid-network preflight, invalid round params, bundle-index validation, per-bundle note/weight tests | Requires live lightwalletd, PIR server, proof generation, signing, broadcast, and local wallet storage |

## Live Happy Path Requirements

The macOS/regtest happy path must verify:

- `setup_delegation_bundles` returns the expected `bundle_count` for a fixture
  wallet with more than five eligible notes.
- The session processes bundle indices explicitly and reports cumulative
  delegated weight separately from total eligible weight.
- Each successful bundle stores a distinct delegation tx hash under its own
  `bundle_index`.
- A resumed session does not rebroadcast a completed bundle.
- A partial/deferred flow deletes or marks skipped bundles before presenting the
  round as finished.
# Bundle-Indexed Voting API Spec

This spec records the required behavior for the bundle-indexed voting API.
Fast Rust unit tests cover the DB-backed portions; live-service happy paths are
left to the macOS/regtest E2E smoke because they require lightwalletd, a wallet
DB with spendable Orchard notes, PIR, proof generation, and transaction
broadcast.

## API Contract

Delegation must preserve the Swift SDK's explicit bundle model:

1. Initialize or load the voting round.
2. Select snapshot-eligible notes.
3. Run `setup_delegation_bundles` to persist bundles and return
   `bundle_count` plus total eligible weight.
4. For each selected `bundle_index`, call
   `build_and_prove_delegation_bundle`.
5. Store/read recovery state by `round_id + bundle_index`.
6. If only a prefix is processed, call `delete_skipped_bundles` and surface
   partial delegation honestly.

`build_and_prove_delegation_bundle` must use only the selected bundle's notes
for witness generation, governance PCZT construction, PIR/proof generation,
delegated weight calculation, and tx-hash recovery.

## Coverage Matrix

| Function | Fast test coverage | Live/spec coverage |
| --- | --- | --- |
| `prepare_voting_round` | Happy path and invalid round params in `rust/src/api/voting.rs` tests | N/A |
| `get_bundle_count` | Happy path after setup in `rust/src/api/voting.rs` tests | N/A |
| `store_delegation_tx_hash` | Happy path and missing-bundle error in `rust/src/api/voting.rs` tests | N/A |
| `get_delegation_tx_hash` | Happy path in `rust/src/api/voting.rs` tests | N/A |
| `delete_skipped_bundles` | Happy path in `rust/src/api/voting.rs` and storage wrapper tests | N/A |
| `setup_delegation_bundles` | Invalid-network preflight in `rust/src/api/voting.rs`; bundling happy path in `rust/src/wallet/voting/delegation.rs` via `ensure_bundles` | Requires live lightwalletd tree state and wallet note fixtures |
| `build_and_prove_delegation_bundle` | Invalid-network preflight, invalid round params, bundle-index validation, per-bundle note/weight tests | Requires live lightwalletd, PIR server, proof generation, signing, broadcast, and local wallet storage |

## Live Happy Path Requirements

The macOS/regtest happy path must verify:

- `setup_delegation_bundles` returns the expected `bundle_count` for a fixture
  wallet with more than five eligible notes.
- The session processes bundle indices explicitly and reports cumulative
  delegated weight separately from total eligible weight.
- Each successful bundle stores a distinct delegation tx hash under its own
  `bundle_index`.
- A resumed session does not rebroadcast a completed bundle.
- A partial/deferred flow deletes or marks skipped bundles before presenting the
  round as finished.
