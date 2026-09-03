# PIR and DAG-sync: Vizor plan

Status: 2026-09-03. Phases 1 and 2 deployed; Phases 3 and 4 built end to end, awaiting the server deploy and the wallet-library merge.

The design and the full phased plan live in the server repository:

- `spendability-pir/docs/pir_deployment_architecture.md` — the unified nullifier, witness,
  and action PIR deployment for DAG-sync.
- `spendability-pir/docs/pir_implementation_phases.md` — the six phases across the server,
  `wallet-libraries`, and this app.

This document is the Vizor-side view: what each phase changes here, what has landed, and how
to see it working. It does not repeat the design.

## Where the work lands

| Repository | Branch | Role |
| --- | --- | --- |
| `valargroup/spendability-pir` | `main` | coordinator, workers, ingest, deploy tooling |
| `zakura-core/wallet-libraries` | `feature/pir` (PR #14, feature branch) | PIR client crate, wallet backend and storage |
| this repo | `roman/ironwood-memo-pir` | sync-engine integration, transport, UI |

Vizor pins `wallet-libraries` by commit in `rust/Cargo.toml` (both the direct dependency and the
`[patch.crates-io]` block). Every wallet-library phase therefore ends with a pin bump here.

## Phase status

| Phase | Server | wallet-libraries | Vizor | Status |
| --- | --- | --- | --- | --- |
| 1. Widen the ACTION record | merged, deployed | `feature/pir` | pinned, verified live | done |
| 2. Parameterize the coordinator by table | merged, deployed (`/v1/*`, two generations) | `feature/pir` | `/v1` client, verified live | done |
| 3. WITNESS as a sharded table | PR #39 (`feat/pir-witness`), CI green | PR #16 (`feat/pir-dag-sync`) | `dag_sync.rs`, pin `49f1f136` | built; merge and deploy pending |
| 4. NULLIFIER cold/warm | same PR #39 | same PR #16 | same | built; merge and deploy pending |
| 5. Production deployment shape | — | n/a | n/a | after 3 and 4 |
| 6. Query envelope and protocol version | folded into #39 (`envelope` in the manifest, v1: 8 / 4 / 4) | `DagSyncPlanner` issues it | `dag_sync.rs` | built with 3 and 4; packing-key batch spike deferred |

## What each phase changes in Vizor

**Phase 1, done.** Pin bump only. The client crate parses the new record; the sync engine's memo
completion path is unchanged. Also landed with it: the snapshot gate in the wallet library now
authenticates against the scanned anchor block rather than the contiguous scan frontier, so a
restored wallet completes Ironwood memos as soon as the post-activation range is scanned.

**Phase 2.** `rust/src/wallet/sync_engine/memo_pir.rs` moves from `/memo/*` to `/v1/generation`
and `/v1/action/*`, and reads the generation manifest for the anchor check. No behaviour change.
Two-generation retention on the server removes the one-off failure when a query straddles a
publish, which today surfaces as a hard sync error.

**Phases 3 and 4, built together.** `rust/src/wallet/sync_engine/dag_sync.rs` runs before memo
completion at the pre-loop slot and after every compact batch. It builds five table sessions
from one generation manifest (transport shared with `memo_pir.rs`), applies the same anchor
gate, checks the witness cap's tree root against the local Ironwood tree when that checkpoint is
retained, then drains passes of exactly the manifest's envelope: nullifier pairs (cold and warm),
action rows, witness pairs. A spend found in one pass is attributed to its transaction in the next
(the action row at the spending transaction's first output carries the txid), change is
trial-decrypted from action rows and stored with its memo, and reconstructed Merkle paths are
stored in `ironwood_pir_witnesses`. Spend checks run only while a scan range below the anchor is
still pending, so a synced wallet sends nothing. If the service does not serve all five tables
the pass logs and stands down for that sync; compact scanning is unaffected.

Send path: the wallet library's transaction builder prefers stored PIR witnesses when every
Ironwood input has one at the same anchor (`WalletCommitmentTrees::external_ironwood_witness`),
so no PCZT post-processing is needed in Vizor. Spendability treats a stored witness as
`witness_stabilized`.

Gate (still to run once the server deploys): a wallet restored at the Ironwood activation
birthday shows correct spendable balance and its change chain, and can send, before compact
scanning reaches the tip; `scripts/memo-pir-status.sh` shows the new counters.

**Phase 6.** The envelope is fixed now (folded into 3 and 4). What remains is the `ipir-sp`
packing-key batch API spike, which changes bytes on the wire but not the request schedule.

## Constraints that shape the Vizor side

- DAG-sync cannot discover payments from third parties. Compact scanning stays for discovery;
  DAG-sync is the fast path for spendability, change, and history on top of it.
- No `GetTransaction(txid)` fallback for the covered class, ever. The mainnet privacy gate in
  `enhance.rs` currently makes txid enhancement inert for all transactions, so pre-Ironwood
  Orchard and Sapling transactions have amounts but no memos, fees, or sent-recipient details.
  Narrowing that gate to the Ironwood-only class is a product decision, not a bug.
- Transport is policy-aware: Tor when desired, fail closed, never a direct fallback.
- All request counts must be independent of what the wallet found (Phase 6 makes this explicit).

## Seeing it work

`scripts/memo-pir-status.sh [--db <wallet.db>] [--server <url>]` prints the server's snapshot next
to a local wallet's state. The number that matters is "completed privately": memos stored while
the wallet never fetched the transaction, which only the PIR client can produce. The Rust
`frb_user` logs from the isolated build do not reach the unified log, so the database is the
evidence.

Demo procedure for memo retrieval is in `docs/memo_pir_demo.md`.

## Known follow-ups

- Merge order for the current stage: wallet-libraries #16 into `feature/pir`, then
  spendability-pir #39 (its deploy re-ingests the journal, about 9 minutes, and serves manifest
  schema 4 with five tables). Vizor is already pinned to the #16 head and degrades gracefully
  until the server serves five tables; memo completion, which is stricter, fails closed on the
  schema bump until the app is rebuilt, which it already is.
- Frontier updates (`/v1/witness/frontier`) are served and the client can apply them, but Vizor
  does not yet refresh held witnesses; a stored witness stays bound to the anchor it was fetched
  at, which consensus accepts for Ironwood spends.
- The witness cap's tree root is verified against the local tree only when the anchor's
  checkpoint is retained; otherwise the manifest's block-hash and tree-size gate is the check.
- No in-app observability yet; the status script is the demo surface.
