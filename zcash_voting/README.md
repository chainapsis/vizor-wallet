# zcash_voting

Client-side library for integrating [Zcash shielded voting](https://github.com/valargroup/vote-sdk) into a wallet. Wraps the Halo 2 ZKPs, voting hotkey construction from stored app-owned secret material, share construction, and governance-PCZT assembly that a wallet needs to participate in an on-chain voting round.

## Usage

Wallets should import `zcash_voting::prelude::*` and follow the stable setup →
precompute → delegate → vote → share lifecycle:

1. Open a `VotingDb`, set the wallet id, and call `create_round` (pass `None`
   when no round session metadata is available).
2. Convert eligible Orchard notes into `NoteInfo` with
   `NoteInfo::from_orchard_note`, then call `ensure_bundles`.
   The default `BundlePolicy` fills each bundle up to the circuit note-slot
   count. Wallets that need fewer real notes per bundle can call the
   `*_with_policy` variants with `BundlePolicy::new(...)`; proof construction
   still pads each bundle to the same fixed circuit slot count.
3. Build the governance PCZT with `setup_delegation`.
4. Precompute delegation inputs with `note_witnesses` and `delegation_pir`.
5. After `delegate::setup`, load `delegation_signing_request` and sign it in
   the wallet. Then prove with `delegate::prove`, assemble submission fields with
   `delegation_submission` plus `DelegationSigner::signature`, submit them
   through the wallet's chain client, and use `record_submission` while polling
   plus `confirm_delegation_submission` after confirmation.
6. Record each terminal ballot decision with `set_ballot_intent`, passing the
   proposal's declared option count so choices are validated before persistence,
   then use `vote::commit` to commit votes locally and submit cast-vote
   transactions. Submit helper shares after the cast-vote transaction is
   confirmed.
7. After restart, call `resume_plan` with the round's full proposal id list and
   execute one returned `NextStep`, persist its result, then call `resume_plan`
   again. `CastVote` includes the recorded choice, and `SubmitVote` resumes an
   already committed vote through `vote::submission`. For `SubmitVote`, submit
   those recovered cast-vote fields, persist the cast-vote tx hash with
   `vote::record_submission` while polling, then record confirmed cast-vote
   events with `confirm_vote_submission`. After confirmation, call
   `vote::recover_commit` again and use its helper-share payloads so they carry
   the confirmed VC position, then record each accepted helper share with
   `share::record`. `Decision::Skipped` is terminal, so `open_proposals`
   contains only proposals that have no recorded decision.

## Crate layout

| Crate | Purpose |
|---|---|
| **`zcash_voting`** (this crate) | Stable wallet API: round setup, note bundles, delegation precompute/proving, voting hotkey reconstruction from stored app-owned secret material, and round-state storage. |
| [`vote-commitment-tree`](../vote-commitment-tree) | Append-only Poseidon Merkle tree for VANs and vote commitments. |
| [`vote-commitment-tree-client`](../vote-commitment-tree-client) | HTTP client + CLI for syncing the vote commitment tree from a running chain node. |

## Public modules

| Module | Purpose |
|---|---|
| `prelude` | Recommended imports for wallet SDKs. |
| `round` | `VotingDb`, `RoundParams`, `RoundInfo`, idempotent `ensure_bundles`, and policy-aware bundle planning. |
| `precompute` | Orchard note witness generation and PIR precompute wrappers. |
| `delegate` | PCZT setup, proof generation, submission assembly, and chain recovery writes. |
| `confirmation` | Chain tx event parsing plus atomic delegation and cast-vote confirmation recording. |
| `vote` | ZKP2 construction, cast-vote signing, and vote recovery bundle persistence. |
| `share` | Helper-share payload recovery, nullifier computation, and share confirmation state. |
| `session` | Durable ballot intent plus the round-level resume planner. |
| `phases` | Per-bundle `DelegationPhase` derived from persisted artifacts. |
| `config` | Static and dynamic voting config validation, signature checks, and switch decisions. |
| `pir` | PIR endpoint selection helpers and client re-exports. |
| `hotkey` | Voting hotkey reconstruction from stored app-owned secret material plus random app-owned hotkeys. |
| `governance` | Low-level governance derivations, `BALLOT_DIVISOR`, and the circuit note-slot count. |

Wallet integrations should use the lifecycle modules above instead of writing
storage rows directly.

## Config resolution

The `config` module keeps voting service config policy in Rust while letting
wallets choose URLs and transport. This is a two-step flow because the dynamic
config URL is trusted only after the static config bytes pass hash-pin and
schema validation:

```rust
use zcash_voting::config::{
    decide_config_switch, resolve_dynamic_voting_config, resolve_static_voting_config,
    ResolveVotingConfigOptions,
};

# fn example(static_bytes: &[u8], dynamic_bytes: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
let source = "https://example.com/static.json?checksum=sha256:...";

// The wallet resolves the static trust anchor, learns the dynamic config URL
// from it, fetches that with its chosen transport, then resolves the dynamic
// config bytes against the authenticated static config.
let resolved_static = resolve_static_voting_config(source, static_bytes)?;
let _dynamic_config_url = &resolved_static.dynamic_config_url;

let resolved = resolve_dynamic_voting_config(
    resolved_static,
    dynamic_bytes,
    ResolveVotingConfigOptions::default(),
)?;

let switch_decision = decide_config_switch(
    None,
    (&resolved).into(),
);
# Ok(())
# }
```

Hash-pin mismatch and dynamic round signature verification failure are reported
as `VotingConfigError::RemoteAuthenticationFailed`, so callers can surface a
clear "remote authentication failed" message.

`decide_config_switch` classifies the semantic wallet transition as
`InitialLoad`, `Unchanged`, `SameChainServiceUpdate`, `NewChainOrRound`, or
`ProtocolChanged`. The wallet owns executing that branch. Endpoint and signing
key changes are same-chain service updates, so wallets should restart
network-derived work while keeping durable artifacts indexed by round id.
Authenticated round-set changes should reload and reselect the active round
context, but do not by themselves require wiping hotkeys or vote commitments
for old round ids.

A direct-HTTPS reference transport lives in the `wallet-example` crate as
`example_config`. It pairs the `resolve_static_voting_config` /
`resolve_dynamic_voting_config` calls with a `DirectHttpsFetcher` and shows how
to persist the resolved summary used for future switch decisions:

- `resolve_voting_config_over_https` fetches the static and dynamic config and
  returns the authenticated `ResolvedVotingConfig`.
- `resolve_config_switch` resolves the config and classifies it against the
  previously stored summary, returning the `ConfigSwitchDecision` plus the
  `StoredConfigState` to persist for the next run.
- `read_config_state` / `write_config_state` load and save that state, so the
  first run reports an initial load and later runs detect service, round-set,
  or protocol changes.

## Crates.io diagram

```text
zcash_voting
├── config
│   ├── static hash-pin verification
│   ├── dynamic config validation
│   ├── Ed25519 round signature verification
│   └── config-switch decisions
├── vote-commitment-tree-client ─── vote-commitment-tree
├── pir-client / vote-nullifier-pir types
├── voting-circuits
└── librustzcash crates
```

## Shared wallet policy helpers

The `share_policy` module contains pure helpers for wallet-side voting behavior
that should stay consistent across SDKs:

- last-moment helper-share window, deadline, and mode decisions from round
  timing
- delayed helper-share `submit_at` scheduling
- helper target counts and randomized helper ordering
- batch share planning with independent entropy per share
- resubmission ordering with untried helpers before already-sent helpers
- share tracking summaries, readiness checks, retry thresholds, and polling delay

Wallet SDKs should provide fresh CSPRNG bytes from their platform RNG and let the
crate own the sampling and ordering policy.

## Secret boundaries

Wallet seed material should stay in the wallet integration. For v2 integrations,
generate a random app-owned voting hotkey with `generate_random_voting_hotkey`,
store `VotingHotkey::stored_secret()` in platform secure storage, and
reconstruct a typed hotkey with `VotingHotkey::from_stored_secret` when needed.
Software and hardware wallets should follow the same random hotkey model. The
hotkey is not deterministic across fresh installs unless the stored hotkey
secret is restored.

Delegation signing follows the same boundary. After `setup_delegation`, call
`delegation_signing_request` to load the account index, network, seed
fingerprint, PCZT sighash, and spend auth randomizer. Software wallets should
derive the account SpendAuth key locally, randomize it with `alpha`, sign the
sighash, and call `delegation_submission` with `DelegationSigner::signature`.
The crate no longer accepts root wallet seed material for delegation signing.

## Dependency notes

`zcash_voting` tracks the upstream Zcash crates directly:

- **`orchard 0.14`** from crates.io, with the
  `unstable-voting-circuits` feature enabled for the governance proof paths.
- **`voting-circuits 0.8`** for the delegation and vote proof circuits.
- **`vote-commitment-tree 0.3`** and **`vote-commitment-tree-client 0.5`** for
  vote commitment tree state and optional HTTP sync.
- **`pczt`, `zcash_keys`, `zcash_primitives`, and `zcash_protocol`** from the
  published upstream Zcash crate line used by this release.

## Migrating from 0.10

- PIR and tree-sync APIs are now always compiled; no feature flags are required.
- Prefer `VotingDb::create_round`, `VotingDb::ensure_bundles`, and
  `VotingDb::delegation_phases` over direct `storage::queries` calls.
- Use `BundlePolicy` plus the `*_with_policy` APIs when an integration needs
  fewer real notes per bundle. Omit the policy for the default circuit-slot
  behavior.
- Use `precompute::note_witnesses` instead of hand-validating cached
  `TreeState` bytes and manually constructing `WitnessData`.
- Use `delegate::submission` with `DelegationSigner::signature(sig, sighash)`
  after signing `delegation_signing_request` in the wallet. Signer variants that
  accepted seeds and Keystone specific signature aliases were removed; software
  and hardware flows both pass an externally produced SpendAuth signature and the
  signed sighash.
- Use `generate_random_voting_hotkey` to create app-owned voting hotkeys for
  both software and hardware wallets, persist `VotingHotkey::stored_secret()`,
  and use `VotingHotkey::from_stored_secret` to reconstruct the same hotkey
  later. The crate no longer derives voting hotkeys from root wallet seeds.
- Use `confirmation::{confirm_delegation_submission, confirm_vote_submission}`
  after chain clients report confirmed delegation or cast-vote tx events. The
  confirmation API parses the chain `leaf_index` events and records tx hashes,
  VAN positions, and VC positions atomically.
- Use `session::resume_plan` instead of reconstructing what comes next from raw
  delegation, vote, and share phases in wallet code. Fetch step execution
  material through crate APIs such as `vote::submission`,
  `vote::recover_commit`, `share::*`, and the tx hash accessors.
- Use `vote::commit`, `vote::submission`, `vote::recover_commit`,
  `vote::record_submission`, and `vote::record_vc_position` for the cast-vote
  lifecycle. Wallets should not write recovery JSON, submission flags, or vote
  commitment positions directly.
- Pre-launch database migrations reset older schema versions; export local test
  state before opening an older wallet DB with this crate version.

## License

Dual-licensed under MIT or Apache-2.0. See [LICENSE-MIT](../LICENSE-MIT) and [LICENSE-APACHE](../LICENSE-APACHE).
