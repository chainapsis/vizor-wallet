# Vote execution order

Use when changing per-bundle sequencing, shared concurrency pools, tree synchronization, or failure isolation.

Implementation: [voting_session_provider.dart](../../../../lib/src/providers/voting/voting_session_provider.dart). Protocol internals: [Rust voting guide](../../../../rust/src/wallet/voting/README.md).

- `_runVoteRoundChains` preserves draft order per delegation bundle. Before its
  next proof: submit, confirm on-chain, persist the updated vote authority note
  (VAN) position, then obtain a fresh tree witness. Reusing VAN state produces a
  duplicate `van_nullifier`.
- Bundles progress concurrently, but share bounded proof/share pools and one
  broadcast permit. Cast-vote broadcasts are serialized across bundles;
  confirmation waits overlap and hold no proof permit.
- `_VoteTreeSyncCoalescer.freshAndUse` only supplies a sync that started after
  the request and materializes served witnesses before another sync can reset
  shared tree state on failover. An already-running sync may predate the bundle's
  last confirmed VAN.
- Helper-share delivery starts after confirmation persistence and runs separately
  from the next proposal. Its failures remain reportable/recoverable; durable
  VAN advancement does not prove share delivery.
- Chain failure stops that bundle's remaining proposals while others drain.
  `_VotingAlreadyStarted` also sets a shared abort before releasing the broadcast
  permit, preventing queued submissions after that spent-nullifier signal.
  Recheck context freshness after acquiring the permit.

## Verification

- [Voting providers](../../../../test/providers/voting/voting_providers_test.dart):
  account changes, pinned submissions, partial signing, participation and drain.
  For casting, start with `each bundle confirms a proposal before proving the
  next one`, `proposal wave serializes broadcasts and overlaps confirmations`,
  `vote tree sync runs before each proposal`, and `a failed bundle chain stops
  at that bundle only`. These use fake chain/Rust responses.

- Source-only or mocked checks do not prove real voting-chain/device behavior;
  relevant regtest runners are documented in the existing participation guide.
