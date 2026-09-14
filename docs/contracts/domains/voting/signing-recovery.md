# Voting signing and recovery

Use when changing saved signatures, signing cancellation, or durable recovery planning.

Implementation: [voting_recovery_service.dart](../../../../lib/src/features/voting/voting_recovery_service.dart), [voting.rs](../../../../rust/src/api/voting.rs).

Implementation: [voting_session_provider.dart](../../../../lib/src/providers/voting/voting_session_provider.dart). Protocol internals: [Rust voting guide](../../../../rust/src/wallet/voting/README.md).

- Reload durable recovery state to select pending bundles/proposals/shares.
  Serialize mutating UI actions through `_enqueue`.
- Validate Keystone request identity, expected bundle/signature counts, and
  signature contents before persistence. Validation/persistence errors remain
  recoverable scan errors, allowing the same response to be rescanned.
- Signing cancellation preserves saved partial signatures; reentry reloads them
  and requests only unsigned bundles. Closing the QR scanner differs from
  abandoning the signing screen. For changes to common request/message/count validation, read
  [batch correlation](../../references/signing/keystone-batch-correlation.md).
- Submission/share acceptance is not chain confirmation. Preserve exact durable
  artifacts and pending work for recovery. Completed local voting can hide Home
  without another participation RPC.
- Process-local vote-tree reset neither deletes durable recovery rows nor stops
  running proofs. `reset_voting_session_state` also clears unsigned abandoned
  delegation setup; do not use it as a harmless warmup reset.
- Helper-share tracking can outlive foreground submission. Register its owner
  before releasing the submission guard; the registry remains the drain barrier
  after the foreground status job finishes.

## Verification

- [Voting providers](../../../../test/providers/voting/voting_providers_test.dart):
  account changes, pinned submissions, partial signing, participation and drain.
  For casting, start with `each bundle confirms a proposal before proving the
  next one`, `proposal wave serializes broadcasts and overlaps confirmations`,
  `vote tree sync runs before each proposal`, and `a failed bundle chain stops
  at that bundle only`. These use fake chain/Rust responses.

- [Recovery service](../../../../test/features/voting/voting_recovery_service_test.dart):
  bundle/proposal keys, exact retry artifacts, and remaining planner work.
