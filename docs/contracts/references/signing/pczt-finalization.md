# PCZT finalization and persistence

Read when changing PCZT proof construction, final validation, broadcast, or post-broadcast storage.

- Rust PCZT roles and completion: [`pczt.rs`](../../../../rust/src/wallet/sync/pczt.rs).

- Rust consumes a stored proposal and creates an IO-finalized base PCZT.
- Vizor independently adds Orchard/Ironwood proofs and required
   Sapling output proofs to its wallet-owned copy.
- Rust applies and verifies every compact signature against the wallet-owned
   PCZT, finalizes every transaction, broadcasts in dependency order, and
   persists the accepted or ambiguous prefix.

For any PCZT with a Sapling bundle, pass Sapling parameters to both
`addProofsToPczt` and the final store/broadcast call. Proof creation needs the
local prover; final validation and storage need its verifying keys.

PCZT creation consumes the replayable in-memory proposal, retaining its wallet
input lock. Before broadcast takes ownership, the feature adapter must discard
cancelled or failed drafts and confirm release before allowing another attempt.
After transfer, UI disposal must not race broadcast with a second release.

Rust validates all correlated proof/signature payloads before network or DB
effects. Broadcast precedes persistence: definite rejections stay out of the
wallet DB; accepted or ambiguous transactions are persisted for recovery. If
rich PCZT-aware storage fails after broadcast, Rust uses its transaction fallback
where possible and returns explicit post-broadcast storage status, not permission
for a blind resend.

## Verification

- Rust tests in [`pczt.rs`](../../../../rust/src/wallet/sync/pczt.rs): correlation,
  expiry, and broadcast/store outcomes.

## Related changes

- When changing accepted signing protocols or inputs, read [protocol selection](pczt-protocol-selection.md).
- When changing signature-response identity checks, read [batch correlation](keystone-batch-correlation.md).
