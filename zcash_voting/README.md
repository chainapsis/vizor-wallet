# zcash_voting

Client-side library for integrating [Zcash shielded voting](https://github.com/valargroup/vote-sdk) into a wallet. Wraps the Halo 2 ZKPs, voting hotkey construction from stored app-owned secret material, share construction, and governance-PCZT assembly that a wallet needs to participate in an on-chain voting round.

## Usage

Wallets should import `zcash_voting::prelude::*` and follow the stable setup →
precompute → delegate → vote → share lifecycle:

1. Open a `VotingDb`, set the wallet id, and call `create_round` with the
   wallet/voting `Network` (pass `None` when no round session metadata is
   available).
2. Convert eligible shielded notes into `NoteInfo` with
   `NoteInfo::from_orchard_note`, then call `ensure_bundles`. Snapshot
   selection is Ironwood / NU6.3-only and rejects non-NU6.3 snapshots.
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
   proposal's declared option count so choices are validated before persistence.
   For multiple answered proposals in one bundle, call `vote::commit_batch` once
   with their canonical order and submit the returned `batch_json` to the
   chain's `cast-vote-batch` endpoint. Every action signs the same batch digest,
   so the chain either accepts the complete authority chain or none of it. Use
   `confirm_vote_batch_submission` after confirmation, then submit each vote's
   helper shares. `vote::commit` and `confirm_vote_submission` remain the
   singleton path.
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
| `precompute` | Shielded note witness generation and PIR precompute wrappers. |
| `delegate` | PCZT setup, proof generation, submission assembly, and chain recovery writes. |
| `confirmation` | Chain tx event parsing plus atomic delegation, singleton-vote, and vote-batch confirmation recording. |
| `vote` | ZKP2 construction, bounded parallel batch proving, cast-vote signing, and atomic recovery-bundle persistence. |
| `share` | Helper-share payload recovery, nullifier computation, and share confirmation state. |
| `session` | Durable ballot intent plus the round-level resume planner. |
| `phases` | Per-bundle `DelegationPhase` derived from persisted artifacts. |
| `config` | Static and dynamic voting config validation, signature checks, and switch decisions. |
| `pir` | PIR endpoint selection helpers and client re-exports. |
| `hotkey` | Voting hotkey reconstruction from stored app-owned secret material plus random app-owned hotkeys. |
| `governance` | Low-level governance derivations, `BALLOT_DIVISOR`, and the circuit note-slot count. |

Wallet integrations should use the lifecycle modules above instead of writing
storage rows directly. An atomic batch preserves the original proof's
privacy for choices, notes, amounts, and voting keys. Its deliberate metadata
tradeoff is transaction-level linkage: observers can see that the ordered
proposal actions in the batch were submitted together.

## Config resolution

The `config` module keeps voting service config policy in Rust while letting
wallets choose URLs and transport. This is a two-step flow because the dynamic
config URL is trusted only after the static config bytes pass hash-pin and
schema validation. Dynamic config must include the top-level PIR geometry used
by the selected service:

```json
{
  "pir_layout": {
    "pir_depth": 19,
    "tier0_layers": 12,
    "tier1_layers": 7,
    "poly_len": 4096
  }
}
```

Resolution fails closed when the field is missing or malformed, the tier-layer
sum does not equal `pir_depth`, the depth is outside the voting circuit's
supported range of 1 through 29, or `poly_len` is not `2048` or `4096`.

Roll out the additive `pir_layout` object (including `poly_len`) in published
dynamic config before shipping wallet builds that require it. Older wallets
ignore unknown fields. New clients that resolve config without it, or that
connect to a PIR server that does not advertise matching `/root.pir_layout`
and `/params/tier1.poly_len`, fail closed at connect time before any private
query.

This validation describes layouts the compiled client can consume. Snapshot
tooling and fleet deployment determine which of those layouts is currently
available. Wallets intentionally do not require equality with a compiled
production default, so a consistently advertised service layout can change
without requiring a wallet release.

After resolution, wallets typically connect PIR through
`pir::connect_pir_blocking` (or `pir::connect_pir`) with the resolved config's
`pir_layout` and a caller-chosen endpoint URL. The helpers run the
config/server layout and YPIR-degree handshake and fail closed before any
private query (`VotingError::InvalidInput` on mismatch); they do not re-check
advertised-endpoint membership. Do not pass a compiled-client layout constant
in place of `resolved.pir_layout`.

```rust
use std::sync::Arc;
use zcash_voting::{connect_pir_blocking, HyperTransport};

# fn example(
#     resolved: &zcash_voting::wire::ResolvedVotingConfig,
#     pir_url: &str,
# ) -> Result<(), zcash_voting::VotingError> {
let pir_client = connect_pir_blocking(
    resolved.pir_layout,
    pir_url,
    Arc::new(HyperTransport::new()),
)?;
# let _ = pir_client;
# Ok(())
# }
```

When the caller already selected an endpoint (for example after exact-height
snapshot probing), pass that URL together with `resolved.pir_layout`.

```rust
use zcash_voting::config::{
    decide_config_switch, resolve_dynamic_voting_config, resolve_static_voting_config,
    ResolveVotingConfigOptions,
};

# fn example(static_bytes: &[u8], dynamic_bytes: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
let source = "https://example.com/static.json?checksum=sha256:...";

// The wallet resolves the static trust anchor, learns the dynamic config URLs
// from it, fetches one with its chosen transport, then resolves the dynamic
// config bytes against the authenticated static config.
let resolved_static = resolve_static_voting_config(source, static_bytes)?;
let _dynamic_config_urls = &resolved_static.dynamic_config_urls;

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

### Static config versions and dynamic config fallback

Two static config schema versions are supported, and both resolve through the
same `resolve_static_voting_config` call:

- **v1** (`static_config_version: 1`) names one `dynamic_config_url`.
- **v2** (`static_config_version: 2`) names an ordered `dynamic_config_urls`
  list of mirrors, most preferred first. Every mirror serves the same document;
  the list exists so a wallet is not stranded when the origin it is pinned to is
  unreachable.

Each version owns exactly one of those fields, and a document carrying the
other version's field is rejected rather than reinterpreted. Existing v1 pins
are unaffected: they resolve exactly as before.

`ResolvedStaticVotingConfig::dynamic_config_urls` is always non-empty, so a
wallet can walk it uniformly regardless of schema version.
`dynamic_config_url` remains as its first entry for callers written against v1.

`resolve_dynamic_voting_config_from_attempts` takes the ordered fetch outcomes
and returns the first that resolves, plus the mirrors it passed over:

```rust
use zcash_voting::config::{
    resolve_dynamic_voting_config_from_attempts, DynamicConfigAttempt,
    ResolveVotingConfigOptions, ResolvedStaticVotingConfig,
};

# fn example(
#     resolved_static: ResolvedStaticVotingConfig,
#     fetch: impl Fn(&str) -> Result<Vec<u8>, String>,
# ) -> Result<(), Box<dyn std::error::Error>> {
let attempts = resolved_static
    .dynamic_config_urls
    .iter()
    .map(|url| match fetch(url) {
        Ok(bytes) => DynamicConfigAttempt::fetched(url, bytes),
        Err(e) => DynamicConfigAttempt::failed(url, e),
    })
    .collect();

let (resolved, skipped) = resolve_dynamic_voting_config_from_attempts(
    resolved_static,
    attempts,
    ResolveVotingConfigOptions::default(),
)?;
# let _ = (resolved, skipped);
# Ok(())
# }
```

Async wallets can instead call `resolve_dynamic_voting_config_over_mirrors`,
which walks the same list lazily and wraps each fetch in
`DYNAMIC_MIRROR_FETCH_TIMEOUT` (30s) so a stalled primary cannot block a
healthy later mirror. The wallet-example and `config_fetcher` reference
transports use that helper; wallets with a custom stack should apply an
equivalent per-attempt deadline before recording a fetch failure.
A mirror is skipped when its fetch failed, its bytes did not decode, or it
advertised unsupported versions. A mirror that resolves but authenticates no
rounds is deprioritized rather than skipped: later mirrors are tried first, but
if none carries a verifiable round set, the round-less resolution is returned —
an empty authenticated round set is a valid outcome, with unverifiable rounds
reported through `skipped_round_ids`. When no mirror resolves at all, the error
is `VotingConfigError::AllMirrorsFailed`, whose message enumerates each URL and
its reason — no single mirror's error can stand in for the set, since mirrors
commonly fail for different reasons. A one-mirror list, which is every v1
static config, has nothing to enumerate and reports its own error verbatim —
including the transport cause when the fetch itself failed.

Fallback widens **availability, not trust**. Whichever mirror answers, the
static hash pin still covers the trust anchor and every round is still
authenticated against the static `trusted_keys`, so a mirror can serve a stale
round set but cannot forge one. Resolving from a mirror other than the first
emits a `ConfigConditionKind::DynamicMirrorFallbackUsed` condition so wallets
can surface the degradation.

`ConfigConditionKind::StaticHashPinVerified` reports whether a pin was actually
checked: a source without a `?checksum=sha256:` query resolves, but that
condition is reported as `false`.

`decide_config_switch` classifies the semantic wallet transition as
`InitialLoad`, `Unchanged`, `SameChainServiceUpdate`, `NewChainOrRound`, or
`ProtocolChanged`. The wallet owns executing that branch. Endpoint and signing
key changes and PIR layout changes are same-chain service updates, so wallets
should restart network-derived work, including PIR precompute, while keeping
durable artifacts indexed by round id. Summaries persisted before `pir_layout`
was recorded remain readable and cause the first newly known layout to register
as a service update.
Authenticated round-set changes should reload and reselect the active round
context, but do not by themselves require wiping hotkeys or vote commitments
for old round ids.

A direct-HTTPS reference transport lives in the `wallet-example` crate as
`example_config`. It pairs the `resolve_static_voting_config` /
`resolve_dynamic_voting_config` calls with a `DirectHttpsFetcher` and shows how
to persist the resolved summary used for future switch decisions:

- `resolve_voting_config_over_https` fetches the static config, then walks its
  `dynamic_config_urls` lazily via `resolve_dynamic_voting_config_over_mirrors`
  — each attempt bounded by `DYNAMIC_MIRROR_FETCH_TIMEOUT`, stopping at the
  first mirror that both fetches and authenticates — and returns the
  `ResolvedVotingConfig` together with the mirrors it skipped.
- `resolve_config_switch` resolves the config and classifies it against the
  previously stored summary, returning the `ConfigSwitchDecision` plus the
  `StoredConfigState` to persist for the next run.
- `read_config_state` / `write_config_state` load and save that state, so the
  first run reports an initial load and later runs detect service, round-set,
  or protocol changes.
- `connect_pir_from_resolved` connects a PIR client with that config's
  `pir_layout` and a caller-chosen PIR URL (layout handshake; no hardcoded
  depth/split). Delegation example helpers
  (`precompute_delegation_bundle`, `prove_and_submit_*`) take `PirLayout` plus
  the selected PIR URL instead of the full resolved config.

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
- delayed helper-share `submit_at` scheduling, capped at 100 hours while still
  ending before the round's last-moment window
- progressive helper timing: inspect ready responses after two seconds, keep
  waiting for half of the configured helpers rounded up, and stop at 30 seconds
- 30-second helper POST attempts with bounded initial-delivery concurrency
- half-fleet batch planning with independent entropy per share and balanced
  initial assignments across the ready helper pool; with ten ready helpers,
  each receives eight shares, while retries remain liveness-first
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

The default `upstream` feature uses the Ironwood librustzcash stack selected by
the workspace root. `--no-default-features --features zakura` selects the Zakura
wallet-libraries forks and the matching proving backend. The two features are
mutually exclusive.

`Cargo.toml` is the source of truth for version and feature requirements, and
`Cargo.lock` records the exact package sources and versions used by this branch.
This release line requires Rust 1.88 or newer.

- **`orchard 0.15`** from [zcash/orchard](https://github.com/zcash/orchard),
  with `unstable-voting-circuits` enabled for the governance proof paths
  (or `zakura-orchard 1.0.0-rc.1` when the `zakura` feature is selected).
- **`voting-circuits 0.10.2`** from [valargroup/voting-circuits](https://github.com/valargroup/voting-circuits)
  for the delegation and vote proof circuits.
- **`vote-commitment-tree 0.5.0`** and
  **`vote-commitment-tree-client 0.7.0`** for vote commitment tree state
  and optional HTTP sync.
- **`pczt 0.9.2`, `zcash_client_backend 0.24.0-rc.7`,
  `zcash_client_sqlite 0.22.0-rc.7`, `zcash_keys 0.16.1`,
  `zcash_primitives 0.30.0`, and `zcash_protocol 0.10.4`** from published
  librustzcash releases (or the `zakura-*` wallet-libraries forks when the
  `zakura` feature is selected).

## Downstream test fixtures

Downstream integration and FFI tests can enable the non-default
`test-fixtures` feature as a development dependency when they need committed
vote recovery state without building ZKP2. Use the same source and version as
the runtime dependency and add `features = ["test-fixtures"]` to the crate's
development dependency entry.

Create the round and its bundles through the normal public setup APIs, then use
`zcash_voting::vote::insert_recovery_fixture`. The helper atomically stores the
resulting post-commit state but deliberately skips every commit-time
verification gate. It leaves transaction and confirmation fields unset so
tests can exercise the public submission and confirmation APIs. Only pass
trusted fixture data. Cargo features are additive and are not a security
boundary, so production builds should not enable this feature.

## Migrating from 0.10

- PIR and tree-sync APIs are now always compiled; no feature flags are required.
- Prefer `VotingDb::create_round`, `VotingDb::ensure_bundles`, and
  `VotingDb::delegation_phases` over direct `storage::queries` calls. Pass the
  round's wallet/voting `Network` when creating or ensuring a round.
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
- Use `confirmation::{confirm_delegation_submission, confirm_vote_submission,
  confirm_vote_batch_submission}`
  after chain clients report confirmed delegation or cast-vote tx events. The
  confirmation API parses the chain `leaf_index` events and records tx hashes,
  VAN positions, and VC positions atomically.
- Use `session::resume_plan` instead of reconstructing what comes next from raw
  delegation, vote, and share phases in wallet code. Fetch step execution
  material through crate APIs such as `vote::submission`,
  `vote::recover_commit`, `share::*`, and the tx hash accessors.
- Use `vote::commit` for singleton transactions or `vote::commit_batch` for one
  atomic, canonical multi-question transaction. Use `vote::submission`,
  `vote::recover_commit`,
  `vote::record_submission`, and `vote::record_vc_position` for the cast-vote
  lifecycle. Wallets should not write recovery JSON, submission flags, or vote
  commitment positions directly.
- Pre-launch database migrations reset older schema versions; export local test
  state before opening an older wallet DB with this crate version.

## License

Dual-licensed under MIT or Apache-2.0. See [LICENSE-MIT](../LICENSE-MIT) and [LICENSE-APACHE](../LICENSE-APACHE).
