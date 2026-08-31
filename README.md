# zcash_voting

Client-side cryptographic library for Zcash shielded voting. Implements proof generation, vote construction, and tree synchronization for the [Zally governance protocol](https://github.com/valargroup/shielded-vote-book).

## Workspace Crates

| Crate | Description |
|-------|-------------|
| **zcash_voting** | Core library: ZKP delegation and vote proofs (Halo2), El Gamal encryption, governance PCZT construction, Merkle witness generation, chain confirmation parsing, SQLite round-state persistence |
| **vote-commitment-tree** | Append-only Poseidon Merkle tree for Vote Authority Notes and Vote Commitments |
| **vote-commitment-tree-client** | HTTP client and CLI for syncing the vote commitment tree from a chain node |

## Architecture

```
zcash_voting
├── config ───────────────────── config resolution + switch decisions
├── vote-commitment-tree-client ─ vote-commitment-tree
├── pir-client / vote-nullifier-pir types
├── voting-circuits ───────────── ZK delegation + vote proofs
└── librustzcash crates ───────── pczt, zcash_keys, zcash_client_sqlite, ...
```

The config resolver itself is transport-agnostic. Wallets choose the static
config source and network transport, fetch bytes, and pass those bytes into
`zcash_voting::config`. The `wallet-example::example_config` module shows a
direct HTTPS implementation for Rust consumers that do not need a custom
transport.

## Building

```bash
cargo check                   # check the default Zakura wallet path
cargo build -p zcash_voting  # build just the core library
```

Run the LRZ Ironwood / NU6.3 tests with:

```bash
cargo test -p zcash_voting --no-default-features --features lrz --locked
```

## Wallet API Lifecycle

New wallet integrations should import `zcash_voting::prelude::*` and use the
stage-oriented API:

- `round::*` creates rounds and binds eligible notes into bundles. Planning
  trims the low-value bundle tail so a concentrated holder emits fewer
  delegation submissions, bounded by the smaller of 1% of selected note value
  and 1,000 ZEC by default. `PrivacyTrim` reports the raw note value excluded,
  not bundle-quantized voting weight.
- `precompute::*` prepares shielded note witnesses, delegation PIR inputs, and VAN
  witnesses for vote proofs. `precompute_pir_proofs` warms PIR nullifier proofs in
  the background before any round or bundle exists (no hotkey needed), keyed by
  network and served IMT root; it plans the selected note set with the caller's
  `BundlePolicy` first so a dust tail is not fetched. The delegation prove path
  reads the same cache. `validate_cached_pir_proofs` checks warmed proofs against
  a round's `nullifier_imt_root` offline. Snapshots coexist in the cache;
  leftover roots are unused, and background warmup prunes cache rows created
  more than four weeks ago.
- `delegate::*` builds delegation PCZTs, proves delegation, prepares signing
  requests, and assembles signed delegation submissions. Wallets keep root seed
  material outside this crate, sign requests at the wallet boundary, and pass
  only signature bytes back through `PreparedSigner::signature`.
- `confirmation::*` parses delegation and cast-vote tx events, then records tx
  hashes and tree positions atomically.
- `vote::*` builds ZKP #2, signs cast-vote payloads, persists the canonical
  `VoteRecoveryBundle`, and reconstructs vote-chain submissions after a crash.
- `share::*` computes helper-share nullifiers and applies scheduling policy.
  `HelperClient::preflight_fleet`, `CommittedVote::prepare_share_delivery`, and
  `CommittedVote::submit_prepared_shares` own validated, journaled initial
  delivery, while `track_pending_shares` requires two distinct configured
  helpers to agree before persisting confirmation.
- `session::*` records durable ballot intent and returns a round-level
  `RoundPlan` with ordered `NextStep`s for restart recovery. Wallets should
  write `Decision::Choice` with the proposal's declared option count before
  starting a cast-vote flow, write `Decision::Skipped` with the same option
  count for proposals the user intentionally leaves blank, and use `resume_plan`
  after restart to decide whether to delegate, poll delegation/vote
  transactions, cast remaining votes, or confirm helper shares.
  `CastVote` steps include the recorded choice. `SubmitVote` resumes one
  singleton through `vote::submission`, `vote::record_submission`, and
  `confirmation::confirm_vote_submission`. `SubmitVoteBatch` and
  `PollVoteBatch` identify the first ordered action as a recovery anchor. Pass
  that key to `vote::recover_atomic_vote_batch`, submit its canonical
  `batch_json` once, persist the shared tx hash with
  `vote::record_batch_submission`, and record its ordered event with
  `confirmation::confirm_vote_batch_submission`. Recover each
  `vote::CommittedVote`, validate and rank the complete helper fleet with
  `HelperClient::preflight_fleet`, then call
  `CommittedVote::prepare_share_delivery` with the complete proposal id roster
  from the authenticated round configuration. The SDK requires matching
  terminal ballot intents and derives the round's single immediate share while
  atomically creating or reloading the complete plan. After vote confirmation,
  recover a fresh `CommittedVote`, then call
  `CommittedVote::submit_prepared_shares` with the complete current fleet. The
  crate validates every payload, rebuilds it with the confirmed VC position,
  and journals delivery before dispatch. After restart, prepare again to load
  the original plan; never replan only missing shares. Re-run `resume_plan`
  after each durable action because later work may depend on on-chain
  confirmations.
  `open_proposals` contains only proposals with no terminal decision yet.

The Zcash-format transaction signed during delegation is specified separately
in [Delegation signing transaction (TX1)](docs/delegation-signing-transaction.md).
It distinguishes the PCZT-only signing artifact from the vote-chain
delegation submission and includes software-wallet and Keystone examples.
The companion
[delegation capability handoff](docs/exporting-to-external-software.md)
documents the public-target, delivery-receipt, and zero-migration import flow
for cases where the funds controller and voter are separate parties, including
custody provider integrations.

## Migrating 0.11 to 0.12

- Replace `VotingDb::build_vote_commitment` + `vote_commitment::sign_cast_vote`
  + `VotingDb::build_share_payloads` orchestration with `vote::commit`.
- Replace custom cast-vote recovery JSON with `vote::serialize_recovery` and
  `vote::parse_recovery`.
- Replace direct `VoteTreeSync` ownership with
  `precompute::{sync_vote_tree, van_witness, reset_vote_tree}`.
- Replace direct `share_tracking` calls with `share::*`, and `share_policy`
  imports with `share::policy::*`.
- Replace raw vote/share workflow SQL with
  `VotingDb::{vote_phase, vote_phases, share_phase, share_phases}`.
- Replace wallet-local "what comes next" recovery planning with
  `session::resume_plan`; fetch execution material through crate APIs such as
  `vote::submission`, `vote::CommittedVote::recover`, `share::*`, and the tx hash
  accessors, then keep wallet-specific networking, proof execution, and UI
  routing at the wallet boundary.
- Replace wallet-local delegation proof and signing orchestration with
  `delegate::PreparedDelegationBundle`. Callers can use the prepared lifecycle
  for setup, witness completion, proving, signing request construction, signed
  payload assembly, and Keystone request construction.
- Use `confirmation::{confirm_delegation_submission, confirm_vote_submission,
  confirm_vote_batch_submission}`
  after chain clients report confirmed delegation or cast-vote tx events. The
  confirmation API parses the chain `leaf_index` events and records tx hashes,
  VAN positions, and VC positions atomically.
- Use `vote::commit` for one singleton. The existing `vote::commit_batch`
  remains as a one-draft compatibility wrapper for singleton submission, while
  `vote::commit_atomic_vote_batch` builds one atomic, ordered multi-question
  transaction. The distinct `SignedVoteCommitments` and `SignedVoteBatch`
  result types keep the singleton and atomic submission endpoints separate.
  Use `vote::submission`, `vote::CommittedVote::recover`,
  `vote::record_submission`, and `vote::record_vc_position` for the singleton
  lifecycle. Wallets should not write recovery JSON, submission flags, or vote
  commitment positions directly.

Pre-launch wallet databases with older schema versions are reset when opened by
this branch; callers that need to preserve test data should export it before
upgrading the crate.

The workspace uses the published `voting-circuits 0.11.2` release.

## Dependency Strategy

The LRZ backend uses one Ironwood dependency stack:

- **`orchard 0.15`** from [zcash/orchard](https://github.com/zcash/orchard),
  with `unstable-voting-circuits` enabled for the governance proof paths.
- **`pczt 0.9.2`, `zcash_client_backend 0.24.0-rc.7`,
  `zcash_client_sqlite 0.22.0-rc.7`, `zcash_keys 0.16.1`,
  `zcash_primitives 0.30.0`, and `zcash_protocol 0.10.4`** from published
  librustzcash releases.
- **`voting-circuits 0.11.2`** from
  [valargroup/voting-circuits](https://github.com/valargroup/voting-circuits)
  for the delegation and vote proof circuits.

`vote-commitment-tree` and `vote-commitment-tree-client` default to Zakura and
select their proving stack through mutually exclusive `zakura`/`lrz` features;
build with `--no-default-features --features lrz` for the LRZ VCT backend.

The published `zcash_voting` crate defaults to Zakura and exposes LRZ through
the mutually exclusive `lrz` feature. Wallet-family selection is consolidated
in published `zakura-wallet-lib 0.1.0-rc4`, whose complete `zakura` and `lrz`
modes never weak-reference both backend families. Gemini selects
`zcash_voting` with `default-features = false, features = ["lrz"]`; Vizor uses
the defaults. External-consumer regression tests verify that Gemini's Cargo
lockfile and resolved metadata contain no Zakura forks.

`Cargo.toml` is the source of truth for version and feature requirements, and
`Cargo.lock` records the exact package sources and versions used by this branch.
The current PIR and IMT releases require Rust 1.91 or newer.

## FFI

Mobile FFI bindings live in [zcash-swift-wallet-sdk](https://github.com/valargroup/zcash-swift-wallet-sdk) (hand-rolled C FFI + Swift wrappers). This repo is a pure Rust workspace.

## License

TODO
