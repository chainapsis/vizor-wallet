# PIR and DAG-sync: Vizor plan

Status: 2026-09-02. Phase 1 complete; Phase 2 not started.

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
| 1. Widen the ACTION record to 792 bytes | merged (#31, #32), POC redeployed | `feature/pir` | pinned, rebuilt, verified live | done |
| 2. Parameterize the coordinator by table | — | — | — | next |
| 3. WITNESS as a sharded table | — | — | — | after 2 |
| 4. NULLIFIER cold/warm | — | — | — | after 2 |
| 5. Production deployment shape | — | n/a | n/a | after 3 and 4 |
| 6. Query envelope and protocol version | — | — | — | after 3 and 4 |

## What each phase changes in Vizor

**Phase 1, done.** Pin bump only. The client crate parses the new record; the sync engine's memo
completion path is unchanged. Also landed with it: the snapshot gate in the wallet library now
authenticates against the scanned anchor block rather than the contiguous scan frontier, so a
restored wallet completes Ironwood memos as soon as the post-activation range is scanned.

**Phase 2.** `rust/src/wallet/sync_engine/memo_pir.rs` moves from `/memo/*` to `/v1/generation`
and `/v1/action/*`, and reads the generation manifest for the anchor check. No behaviour change.
Two-generation retention on the server removes the one-off failure when a query straddles a
publish, which today surfaces as a hard sync error.

**Phase 3.** New `sync_engine/pir_witness.rs` mirroring `memo_pir.rs` (same anchor gate, same
routed transport). `send.rs::orchard_witnesses` falls back to an externally supplied witness for
Ironwood inputs, and the balance summary treats externally witnessed notes as spendable. Gate: a
note received into a sealed shard becomes spendable before the local shard completes.

**Phase 4.** New `sync_engine/dag_sync.rs` runs at sync start: spend check for every known note,
change discovery from ACTION rows, witness fetch, all against one pinned generation. The existing
compact scan loop covers the tail from the anchor to the tip. Gate: a wallet restored at the
Ironwood activation birthday shows correct spendable balance and change chain before compact
scanning reaches the tip.

**Phase 6.** `dag_sync.rs` and `memo_pir.rs` issue exactly the fixed per-pass query envelope; the
per-row scheduling in `memo_pir.rs` moves into the library's `DagSyncSession`. Gate: transcript
tests showing that zero, one, and many pending notes produce identical request sequences.

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

- `tx_retrieval_queue` in the wallet library keeps stale rows after an account is deleted.
  Harmless under the gate; fix in queue reconciliation.
- A query that straddles a generation publish fails once until Phase 2 lands.
- No in-app observability yet. A developer "privacy" panel (endpoint, route, accepted
  generation, pending and completed memo counts, suppressed enhancement count) is planned as part
  of the Phase 2 Vizor work.
