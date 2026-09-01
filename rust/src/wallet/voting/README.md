# Vizor Voting Integration (Rust)

This module integrates the [`zcash_voting`](https://github.com/valargroup/zcash_voting)
crate into Vizor. It owns the wallet-side concerns the crate intentionally leaves
to the host app: wallet seed handling, voting hotkey storage, the voting sidecar
database, delegation signing, and the Flutter Rust Bridge (FRB) surface that
exposes the crate lifecycle to Dart.

`zcash_voting` owns the protocol and the durable recovery state machine. Vizor
adds no parallel workflow tables. All phases and recovery are derived from the
crate's own `bundles`, `votes`, and `share_delegations` rows. For the canonical
setup -> precompute -> delegate -> vote -> share lifecycle, the per-bundle phase
definitions, and the restart planner, see the crate docs:

- Crate README: [`zcash_voting/zcash_voting/README.md`](https://github.com/valargroup/zcash_voting/blob/main/zcash_voting/README.md)
- Reference usage: [`wallet-example/src`](https://github.com/valargroup/zcash_voting/tree/main/wallet-example/src)
  (`example_delegation.rs`, `example_vote.rs`, `example_recovery.rs`)

This document focuses on what Vizor's integration is responsible for.

## Module Map

| File | Responsibility |
| --- | --- |
| `db.rs` | Opens the voting sidecar DB via `VotingDb::open_wallet_sidecar` at the deterministic path next to the wallet DB. The voting schema is isolated from the wallet `user_version`. |
| `network.rs` | Converts between wallet-layer network enums and `zcash_voting::Network` so wallet modules do not depend on API-layer helpers. |
| `hotkey.rs` | Reconstructs app-owned voting hotkeys from stored opaque secret bytes before handing them to crate operations. The secret is never persisted by Rust. |
| `delegation.rs` | Prepares, proves, and signs delegation bundles (software and Keystone paths), forwarding `DelegationProgress` to callers. Wallet seed signing stays here. |
| `transport.rs` | Fetches the voting snapshot anchor over the process route policy (`open_lwd_channel` + `anchor_tree_state_with_retry_on`) and refuses to proceed when Tor is selected but unusable, so PIR cache warm-up does not dial lightwalletd directly. This module owns the route decision and *dial* retry; the crate owns the *RPC* retry. PIR HTTP still uses the crate's `HyperTransport`. |
| `../../api/voting.rs` | FRB boundary. Thin wrappers that open the sidecar DB and call crate lifecycle APIs (`delegate::*`, `vote::*`, `share::*`, `confirmation::*`, `session::*`, `precompute::*`). |
| `../../api/voting_helpers.rs` | API-only helper glue for delegation input resolution and bundle-parameter construction used by the FRB boundary. |

## Account Invariants And Secret Boundaries

Coinholder voting uses a crate-owned voting hotkey for delegation outputs and
vote signing.

- Software and hardware accounts both generate a random per-account, per-round
  hotkey through `zcash_voting::hotkey::generate_random_voting_hotkey`. Dart
  stores the opaque hotkey secret bytes and passes them back for later
  delegation and vote work.
- If the stored hotkey is missing after any hotkey-bound artifact exists, the
  session must fail instead of generating replacement material. v2 does not try
  to recover deterministic hotkeys from the wallet seed.
- Locked software wallets still need the mnemonic only for delegation SpendAuth
  signing. Hotkey generation and vote signing do not require mnemonic access.

The wallet seed never leaves the wallet boundary. Delegation signing in
`delegation.rs::sign_delegation_request` consumes a crate-provided
`DelegationSigningRequest`, verifies the seed fingerprint, derives the account
SpendAuth key, randomizes it with `alpha`, and returns only the detached
signature plus sighash. The crate never receives root seed material.

### Session Pinning

A `votingSessionProvider(roundId)` instance is pinned to the active account UUID
captured when the session is built. All later context reloads, recovery reads,
delegation setup, vote-tree sync, vote submission, and share recovery must
continue to use that session account, even if the user switches accounts while
the round screen is open. Do not re-read the active account inside individual
session actions except through the session-pinned account helper.

## Durable vs Process-Local State

Two kinds of state exist, and they are both account scoped:

- **Durable** state lives in the `zcash_voting` sidecar tables (delegation
  bundles, signed artifacts, transaction hashes, VAN/VC positions, share
  submission history). This is the recovery source of truth.
- **Process-local** state is Rust memory and cached clients owned by the current
  app process, including the crate-owned vote-tree client.

Any durable key or process-local cache that touches prepared PCZTs, vote-tree
sync state, hotkeys, recovery rows, or share-delegation history must include the
wallet DB path plus the session account UUID where applicable.

### Reset Semantics

`reset_vote_tree(db_path, account_uuid, round_id)` clears only process-local
vote-tree sync state. It does not delete durable recovery rows, signed
artifacts, transaction hashes, or share history, and it does not abort in-flight
proof or vote jobs already running on worker threads.

- A non-empty `round_id` performs round-scoped cleanup via
  `zcash_voting::precompute::reset_vote_tree(db, round_id)`.
- `None` or an empty `round_id` is an account-wide reset via
  `zcash_voting::precompute::reset_vote_tree(db, "")`.

`reset_voting_session_state(db_path, account_uuid, round_id)` is broader. It
clears the same vote-tree sync state and also clears unsigned delegation setup
fields for abandoned round work. Do not use it for best-effort vote-tree warmup
failover while the user may still be signing or submitting.

Vote-tree sync and reset are owned by the crate
(`zcash_voting::precompute::{sync_vote_tree, reset_vote_tree}`); Vizor does not
maintain its own tree-sync registry.

Account-wide reset runs when switching away from the active account, removing an
account, resetting the wallet, or locking/signing out. These lifecycle
boundaries invalidate the owner of the process-local tree client but never
delete durable `zcash_voting` recovery rows.

## Lifecycle And Recovery

Vizor calls the crate's stage-oriented APIs rather than writing storage rows
directly. The mapping from FRB functions to crate APIs:

| Stage | FRB entry (`api/voting.rs`) | Crate API |
| --- | --- | --- |
| Background PIR cache warm-up | `warm_pir_proof_cache` | `selection::select_notes_with_lwd`, `precompute::{cache_pir_proofs, prune_pir_proof_cache}` — bundle-, round-, and hotkey-independent; keyed by `(wallet_id, network, root, nullifier)`, read by the delegation prove path |
| Bundle setup | `setup_delegation_bundles` | `delegate::ensure_round_context`, `VotingDb::ensure_bundles_with_skipped_suffix_with_policy` |
| Background delegation proof | `precompute_delegation_proof` | `delegate::prepare_delegation_bundle`, `VotingDb::has_persisted_delegation_proof`, and `PreparedDelegationBundle::{ensure_setup, ensure_proof}` — persists ZKP1 and the exact SDK-owned PCZT after snapshot PIR warm-up without receiving the mnemonic or signing, for both software and Keystone accounts |
| Delegation sign / fallback prove | `build_prove_and_sign_delegation_payload_with_progress`, Keystone variant | Software lets `ensure_setup` and `ensure_proof` reuse durable setup or ZKP1, then calls `signing_request` and `signed_bundle`; Keystone reloads the exact request with `keystone_request`, then uses `ensure_proof` and `signed_bundle` |
| Delegation submit/confirm | `mark_delegation_submitted`, `confirm_delegation_submission` | `VotingDb::mark_delegation_submitted`, `confirmation::confirm_delegation_submission` |
| Vote commit | `build_vote_commitments_with_progress`, `recover_vote_commitment` | `vote::prepare_commit_batch`, `vote::persist_prepared_commit_batch`, `vote::recover_signed_commitments` |
| Vote submit/confirm | `mark_vote_submitted`, `confirm_vote_submission` | `VotingDb::mark_vote_submitted`, `confirmation::confirm_vote_submission` |
| Share plan/submit/confirm | `preflight_voting_helpers`, `prepare_committed_share_delivery`, `submit_prepared_shares_to_helpers`, `confirm_share_with_helpers`, `track_pending_shares` | `HelperFleetPreflight`, `CommittedVote::{prepare_share_delivery, submit_prepared_shares}`, `share_tracking::{confirm_pending_share, track_pending_shares}` |
| Ballot intent / restart | `set_ballot_intent`, `get_round_plan`, `get_round_recovery_state` | `VotingDb::set_ballot_intent`, `session::resume_plan`, `recovery::round_snapshot` |

The `confirmation::*` APIs parse chain `tx` events and atomically record tx
hashes, VAN positions, and VC positions. Restart recovery is driven by
`session::resume_plan`, which returns the ordered remaining `NextStep`s and the
proposals still open. Vizor's Dart recovery code consumes the crate's phase
strings; it does not derive its own phases.

```mermaid
stateDiagram-v2
    state "Delegation Bundle" as Delegation {
        [*] --> Prepared
        Prepared --> Signed: prove + sign
        Signed --> Submitted: mark_delegation_submitted
        Submitted --> Confirmed: confirm_delegation_submission
        Confirmed --> [*]
    }
    state "Vote Commitment" as Vote {
        [*] --> Committed
        Committed --> Submitted2: mark_vote_submitted
        Submitted2 --> Confirmed2: confirm_vote_submission
        Confirmed2 --> [*]
    }
    state "Helper Share" as Share {
        [*] --> SubmittedShare
        SubmittedShare --> ConfirmedShare: two configured helpers confirm
        ConfirmedShare --> [*]
    }
```

### Helper Share Scheduling

Helper-share `submit_at` (the Unix-second reveal time sent to the helper server)
is planned and durably persisted by `zcash_voting`'s complete-batch delivery
API. Vizor supplies authenticated round timing, the configured fleet, and the
round's immediate-share key; the SDK owns entropy, readiness-derived targets,
placement, generation binding, and restart reuse:

- The last-moment buffer is 40% of the round duration from `ceremony_phase_start`
  to `vote_end_time`, capped at six hours.
- Before that buffer, each share samples a randomized `submit_at` uniformly in
  `[now, vote_end_time - buffer)`.
- Inside the buffer, the vote commitment uses single-share mode and shares use
  `submit_at = 0` (immediate submission).
- If round timing is missing or invalid, Vizor uses `submit_at = 0`.

Overdue recovery submits immediately (`submit_at = 0`), while early
under-placement replenishment preserves the original schedule in both the
helper payload and durable record. The canonical scheduling, delivery,
retry, and polling policy lives in the SDK. Dart calls the batch-oriented
adapter in `api/voting.rs`; it neither materializes plans nor submits
individual helper payloads. The SDK also enforces the process-wide ceiling of
16 concurrent helper POSTs.

Definite acceptances, outcome-unknown deliveries, and in-flight markers left by
an interrupted process remain tracked after the vote screen closes. An
outcome-unknown helper is polled for global on-chain confirmation but never
counts toward the intended placement target because a `pending` response does
not prove possession. Early replenishment uses other eligible helpers without
waiting for the overdue threshold. Overdue recovery first tries untried
helpers, then may duplicate-safely re-POST an outcome-unknown helper once in
that pass.
Configured helpers are trusted global chain-status oracles, but one helper
cannot finalize a share by itself. The crate requires matching `confirmed`
responses from two distinct helpers in the current configuration and binds the
confirmation write to the exact stored nullifier generation. Vizor uses the
crate's focused `confirm_pending_share` API for the designated immediate share
and the full `track_pending_shares` pass for background recovery. It does not
expose helper observations or implement a second polling path.

Fresh commitments use a strict, SDK-persisted complete plan. The SDK reuses
that exact plan after restart and submits only definite-delivery deficits, so
fleet compatibility, aggregate quota, and target guarantees remain bound to
the original commitment generation. The Rust boundary separates preparation
after durable vote commitment creation from submission after confirmation
persistence, so the host cannot conflate those lifecycle steps. Normal vote
confirmation advances a matching plan from the exact pre-confirmation recovery
snapshot to the exact confirmed snapshot; replacement, clearing, and unrelated
recovery-material changes invalidate it. `LegacyBestEffort` is metadata only
for old durable state that predates complete-plan persistence. Vizor surfaces
that state but does not implement a second replanning policy.

Initial submission and recovery share one account/round/database-bound Rust
helper delivery context. Before a fresh helper POST, the crate commits an
in-flight (`attempting`) marker; it then promotes that marker to definite
acceptance or outcome-unknown, or removes it after a definite pre-dispatch
failure. A crash or failed outcome write therefore leaves the helper poll-only
during early replenishment. Once overdue, duplicate-safe recovery can retry it
after untried helpers without mistaking it for a fresh target.
Tor connection, TLS, connect-timeout, URL, and request-construction failures
are definite and remain retryable; request/response-phase failures are
ambiguous.

On launch, unlock, and resume, Vizor asks
`zcash_voting::share::pending_rounds` for durable
unconfirmed rounds and rejects expired or unauthenticated entries before
restoring a session. A restored session checks only helpers still present in
the current config and retains itself while work remains. Overdue shares use
the crate's randomized, health-aware recovery order and continue until the
complete definite-placement deficit is filled, candidates are exhausted, or
the round cutoff is reached. An outcome-unknown POST remains eligible for
status polling, and recovery may continue to another helper when a transport
outcome is ambiguous. This deliberately trades possible duplicate encrypted-
share delivery and additional helper metadata exposure for liveness when a
share might otherwise never reach the chain. Lock, account
deletion, and wallet reset stop and drain discovery plus active checks before
protected state changes. If a mutation aborts while wallet state remains,
Vizor requests fresh discovery after leaving the mutation boundary.

## Wire Types And FRB Scanning

`zcash_voting::wire` is the canonical owner of protocol wire JSON and wallet view
DTOs (field names, `serde` renames, base64/hex shaping, JSON-safe integer
bounds), for example `DelegationSubmissionWire`, `VoteCommitmentWire`,
`VanWitness`, `DraftVote`, `SignedVoteCommitmentsView`, and `RoundPlanView`. See
`zcash_voting::wire` for the full set.

Vizor keeps no FRB-local `Api*Wire` mirrors for these types. FRB codegen scans
the shared crate module directly via `flutter_rust_bridge.yaml`:

```yaml
rust_input: crate::api,zcash_voting::wire
```

That scan emits Dart value classes under
`lib/src/rust/third_party/zcash_voting/wire.dart` and generates the
`SseEncode` / `SseDecode` glue in Vizor's bridge code. The `zcash_voting` crate
stays framework-agnostic and does not depend on FRB.

FRB third-party scanning expects a struct-only module surface, so the DTO structs
stay in `zcash_voting::wire` while serialization helpers and conversions that
pull richer crate internals (`VotingError`, payload transforms) live in
`zcash_voting::wire_codec`. Call sites import canonical structs from
`zcash_voting::wire::*`.
