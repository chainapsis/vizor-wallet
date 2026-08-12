# Delegation capability handoff

## Purpose

This handoff supports voting when Zcash funds and the voting hotkey are
controlled by different parties. For example, a custody provider can delegate
voting weight to a voter without receiving the voter's key or exposing the
provider's Zcash account keys.

The voter creates and retains a fresh `VotingHotkey`. The funds controller
receives only a public target bound to one vote chain, network, and round. After
the funds controller prepares and signs every delegation transaction, it
durably stores a compact capability package before broadcasting and delivers
the package over an authenticated, confidential channel. Delivery and broadcast
may proceed concurrently; the voter imports the package and acknowledges its
digest as a delivery receipt.

No wallet seed, account spending key, account IVK or FVK, or voting-hotkey
secret crosses this boundary.

The wallet example includes a compile-checked, role-separated walkthrough in
[`example_capability_handoff.rs`](../wallet-example/src/example_capability_handoff.rs).

## Roles

- The **voter** owns the voting hotkey and later produces ZKP2 votes.
- The **funds controller** owns the Zcash funds and account signing keys,
  selects the eligible notes, proves the delegations, and broadcasts them. A
  custody provider is one example of this role.
- The **vote chain** publishes the confirmed transaction event and VAN leaf
  position. The existing public vote-tree sync supplies the commitment and
  witness used by ZKP2.

Version 1 supports one funds controller and one fresh hotkey per voter and
round. Using a fresh hotkey for each relationship also avoids bundle-index
collisions and unnecessary cross-controller linkability.

## Public target handoff

The voter encodes `VotingHotkey::delegation_target()` as
`VotingHotkeyTargetV1`, validates it against independently authenticated round
parameters, calls `to_json`, and sends those JSON bytes. The target contains:

- format version;
- vote-chain identifier;
- Zcash network;
- vote-round identifier;
- fixed address index zero; and
- the 43-byte raw Orchard address, encoded as padded standard Base64.

The funds controller parses the received bytes with
`VotingHotkeyTargetV1::from_json`, then independently calls `validate_for` with
its authenticated chain, network, and full round parameters. That validation
creates a controller-local opaque `RoundBoundVotingHotkeyTarget`; the opaque
type itself never crosses the boundary. The controller passes that value to
`prepare_delegation_bundle_for_target` and MUST use the same target for every
bundle in that delegation job.

The funds controller application, not `VotingDb`, owns the durable job/outbox
record. That record MUST retain the validated target across restarts because
the target cannot be recovered from the VAN. It MUST also retain the exact
signed transactions, their hashes, the canonical package bytes and digest,
voter acknowledgement state, and broadcast state.

## Capability package

`DelegationCapabilityV1` is a canonical compact JSON document. Its top-level
context repeats the target binding, followed by a complete bundle array. Each
bundle contains:

| Field | Meaning |
| --- | --- |
| `bundle_index` | Contiguous zero-based index in the complete delegation batch. |
| `num_ballots` | Voting weight after division by `BALLOT_DIVISOR`. |
| `van_comm_rand` | Canonical padded Base64 of the 32-byte VAN blinding field. |
| `delegation_tx_hash` | Lowercase SHA-256 of the exact signed vote-chain transaction bytes. |

The package contains privacy-sensitive linkage material but no voting or
spending authority. It belongs on the same authenticated, confidential channel
as the parties' other private account data and should be excluded from logs
and analytics.

The strict codec rejects unknown or duplicate fields, noncanonical JSON,
noncanonical Base64 or field elements, non-lowercase hashes, empty or oversized
batches, gaps, duplicate transaction hashes, duplicate VANs, zero voting
weight, and aggregate values above `MAX_MONEY`.

## Delivery and broadcast protocol

The funds controller MUST use this protocol:

1. Prepare, prove, and sign every delegation transaction for the retained
   public target.
2. Persist the exact signed transaction bytes and their SHA-256 hashes.
3. Call `export_delegation_capability` and persist the returned package's exact
   `canonical_json()` bytes and typed `digest()`. Both come from the same
   serialization.
4. After that durable write, broadcast the same signed transactions whose bytes
   produced the package hashes. Package delivery may proceed concurrently.
5. Deliver the exact package bytes to the voter. The voter atomically
   imports them with `import_delegation_capability`, durably commits, and returns
   the digest produced by the importer.
6. Compare the acknowledgement to the stored digest. A missing or mismatched
   acknowledgement triggers redelivery; it does not gate broadcast.

Retries MUST redeliver byte-identical package bytes. The funds controller MUST
retain the outbox through round close. If both parties lose the package before
the voter stores it, that round's voting weight can become unusable; the
underlying funds are never at risk.

## Voter import

The voter supplies independent trusted context through
`ImportDelegationCapabilityParams`: its locally retained hotkey, chain ID,
network, full authenticated round parameters, and optional session metadata.

Import validation derives the public target from the voter's own hotkey and
requires an exact package match. It recomputes every VAN from the hotkey
address, round ID, `num_ballots`, and `van_comm_rand`. It then stores only the
existing runtime fields needed by voting:

- canonical quantized `total_note_value`;
- `van_comm_rand`;
- recomputed `gov_comm`;
- address index zero; and
- the exact delegation transaction hash.

The round row and all bundle rows commit in one immediate SQLite transaction.
The current schema is sufficient. No delegation construction fields, proofs,
raw vote transactions, account keys, or provenance records are imported.

The package is complete and contiguous. A byte-identical reimport is a no-op,
including after later confirmation updates the current VAN position. Partial,
locally constructed, or conflicting state is rejected without mutation.

## Confirmation and voting

After broadcast, the voter queries the existing transaction-status API by
the package's transaction hash and passes its `delegate_vote` event to
`confirm_delegation_submission`. The existing confirmation path rejects a hash
that differs from the package and records the public `leaf_index`.
Use the package's canonical lowercase hash for both the status lookup and the
confirmation call; do not substitute a differently rendered broadcast result.

The voter MUST record confirmation for every bundle in an imported package
before creating its first vote commitment. The library enforces this barrier
for imported capability rounds while preserving per-bundle voting for locally
prepared rounds.

At the next `sync_vote_tree`, the library obtains the public tree root and
witness for that position and verifies that the leaf is the imported,
voter-recomputed VAN. A wrong target, weight, blinding factor, transaction,
or event position therefore fails before ZKP2 work starts. Correct state then
uses the unchanged `van_witness` and `vote::commit` path.

The vote proof and cast-vote signature still require the voter's hotkey
secret. Possession of a capability package alone cannot create voting
authority.

## Recovery boundary

Version 1 deliberately does not add a continuation memo, raw-transaction
receipt decoder, or public-chain-only recovery protocol. The funds controller
must support idempotent package redelivery through round close, and the voter
must retain both its hotkey and imported voting database.

An unknown, timed-out, or missing transaction remains retryable and MUST NOT be
treated as terminal. If the controller establishes that an exact signed
transaction cannot confirm and must be replaced, it prepares and retains a
corrected complete package. Before any vote commitment exists, the voter may
retain its session metadata and draft choices, call `clear_round`, import the
corrected package, and restore that local state. The all-bundle confirmation
barrier keeps this reset ahead of irreversible vote state.

If public-chain recovery becomes a product requirement, it can be designed for
a future round boundary without changing the authority model in this version.
