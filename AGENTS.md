# Repository agent instructions

## Helper-share submission

Before changing helper-share planning, submission, transport, persistence,
polling, or recovery, read and follow
[`docs/helper_submission_invariants.md`](docs/helper_submission_invariants.md).

The document is the review specification for the invariants currently enforced
by this repository. In particular:

- do not weaken or bypass an invariant silently;
- preserve durable state transitions, timeout and retry boundaries, helper
  placement rules, and ambiguous-POST safety;
- update the specification and its cited regression tests in the same change
  whenever behavior intentionally changes; and
- explicitly report any conflict between a requested change and the
  specification before implementing it.

These instructions apply to all files that can affect helper-share behavior,
including `zcash_voting/src/share_policy.rs`,
`zcash_voting/src/share_tracking.rs`, `zcash_voting/src/share.rs`,
`zcash_voting/src/recovery.rs`, `zcash_voting/src/helper/`, and helper-share
storage or wire representations.
