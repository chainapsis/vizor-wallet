# Voting

Choose the contract for the behavior being changed. Known contracts can be read
directly; follow additional links only when their stated condition applies.

| Change or question | Read |
| --- | --- |
| Captured account/round context, background job ownership, or secret hotkeys | [Voting session ownership](session-ownership.md) |
| Saved signatures, signing cancellation, or durable recovery planning | [Voting signing and recovery](signing-recovery.md) |
| Per-bundle sequencing, shared concurrency pools, tree synchronization, or failure isolation | [Vote execution order](vote-execution.md) |
| Background-work registration, drain, or account-scoped cleanup | [Voting deletion and reset participation](mutation-participant.md) |
| Candidate discovery, card visibility, lazy loading, or refresh/failure behavior | [Voting Home discovery](home-discovery.md) |
| Discovery build defines and bundled source configuration | [Voting discovery configuration](home-configuration.md) |
| Viewing-key inspection, vote-RPC queries, proof verification, trust pins, or unknown eligibility | [Voting participation proof and trust](participation-proof.md) |
| Persistence, refresh cancellation, cache invalidation, or partial participation recovery | [Voting participation cache and recovery](participation-cache.md) |
| Common deletion/reset writer barrier | [Mutation barrier](../../references/wallet/mutation-barrier.md) |
| Requested chain integration or reinstall verification | [Voting regtest guide](../../guides/voting-regtest.md) |
