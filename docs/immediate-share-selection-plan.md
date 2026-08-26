# Immediate share selection plan

## Goal

Submit exactly one helper share immediately for each voting round. All other
shares retain their normal randomized submission time.

The selection rule is:

> Share 0 of the lowest voted proposal ID in the highest-index bundle is the
> round's immediate share.

Bundles are ordered by total value descending, so the highest bundle index is
the lowest-value bundle. Proposals marked as skipped are not voted proposals
and are excluded from selection.

## Required properties

- At most one share is designated immediate per round.
- No share is designated until the round has an eligible bundle and at least
  one proposal with a recorded ballot choice.
- The designation is deterministic and stable across restarts.
- Completing a proposal does not move the designation to another proposal.
- The designated share has `submit_at = 0`.
- Other shares keep their existing randomized schedules and helper targets.
- Last-moment and single-share modes may give other shares `submit_at = 0`, but
  they do not change which share owns the round-level designation.

## Round-level selection

Expose an `ImmediateShareKey` containing:

- `bundle_index`: the maximum eligible bundle index;
- `proposal_id`: the minimum proposal ID with `Decision::Choice`;
- `share_index`: always `0`.

Derive this key from durable round state in `session::resume_plan`. Do not use
open or incomplete proposals, because those sets shrink as work completes and
could select a different share after restart.

### Host lifecycle contract

The host collects every proposal decision on one selection screen and does not
submit votes or helper shares until the user confirms the final submission.
During selection, recording another lower-ID choice can change the derived
`immediate_share_key`; that key is provisional and MUST NOT trigger network
work.

The host may consume `immediate_share_key` only after every proposal has a
terminal `Choice` or `Skipped` decision and the user has confirmed submission.
At that point the set of voted proposals is complete, so the lowest voted
proposal cannot change. Restarts after final submission therefore derive the
same key. Integrations that submit proposals incrementally do not satisfy this
contract and must persist the first designation or otherwise prevent a second
immediate submission.

The selector should accept the highest eligible bundle index directly instead
of converting it to a bundle count and subtracting one again.

## Batch planning

The round-level rule uses a domain share index, while
`plan_share_submissions` operates on positions in a caller-supplied batch.
Those indexes differ for reordered or recovery subsets.

Keep that distinction explicit:

1. The caller compares the batch's bundle and proposal with
   `ImmediateShareKey`.
2. If they match, the caller finds the batch position whose payload has domain
   `share_index == 0`.
3. The caller passes that position to the planner; otherwise it passes `None`.
4. The planner marks only that plan as designated and assigns it
   `submit_at = 0`.

An arbitrary batch-position parameter is therefore a transport mapping, not a
second share-selection policy. A boolean such as `make_first_share_immediate`
is insufficient unless every caller guarantees canonical ordering and that
share 0 is present.

Plans should remain aligned with their input payloads unless submission-order
output is a firm SDK requirement. If plans are reordered, each plan must carry
its original batch position so callers cannot attach a plan to the wrong
payload.

## Public and wire API

- Add the selected key to `RoundPlan` and `RoundPlanView`.
- Preserve an explicit `immediate` marker on submission plans. Testing only
  `submit_at == 0` is ambiguous in last-moment and single-share modes.
- Keep secret `plaintext_value` out of wire types. Selection is by identity,
  not by inspecting or publishing a share's value.
- Document that share index 0 is a deterministic identity after the ZKP #2
  shuffle; it is not guaranteed to contain a particular denomination.

## Verification

Add tests covering:

- highest bundle index, lowest voted proposal ID, and share index 0;
- skipped proposals and rounds without choices;
- stability after completion and restart;
- exactly one designated plan;
- immediate timing without perturbing other schedules or helper targets;
- last-moment and single-share timing ambiguity;
- reordered and subset batches where domain share 0 is not batch position 0;
- invalid or missing batch positions;
- serialization through the round-plan wire view.

