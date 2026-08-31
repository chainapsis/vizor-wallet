# Helper submission invariants

## Status and scope

This document records the helper-share submission invariants implemented by
`zcash_voting`. It is an audit map for wallet integrators and reviewers. It
covers planning, initial delivery, transport outcomes, persistence,
confirmation polling, and recovery.

The implementation is authoritative. A change to an invariant below SHOULD
update this document and the named regression tests in the same pull request.
Values exposed as policy metadata but not enforced by a particular API are
called out explicitly.

The main implementation surfaces are:

- [`share_policy`](../zcash_voting/src/share_policy/), whose
  [`mod.rs`](../zcash_voting/src/share_policy/mod.rs) facade exposes helper
  placement, server ordering, submission scheduling, and timing implemented in
  [`initial_placement.rs`](../zcash_voting/src/share_policy/initial_placement.rs),
  [`server_order.rs`](../zcash_voting/src/share_policy/server_order.rs),
  [`submission_schedule.rs`](../zcash_voting/src/share_policy/submission_schedule.rs),
  and [`timing.rs`](../zcash_voting/src/share_policy/timing.rs);
- [`helper`](../zcash_voting/src/helper/), which defines helper identity,
  transport, retry, and health behavior;
- [`share_tracking`](../zcash_voting/src/share_tracking/), whose
  [`mod.rs`](../zcash_voting/src/share_tracking/mod.rs) facade coordinates the
  validated fleet, durable complete-plan lifecycle, initial fan-out, polling,
  and recovery implemented in
  [`configured_fleet.rs`](../zcash_voting/src/share_tracking/configured_fleet.rs),
  [`delivery_plan.rs`](../zcash_voting/src/share_tracking/delivery_plan.rs),
  [`initial_delivery.rs`](../zcash_voting/src/share_tracking/initial_delivery.rs),
  [`confirmation.rs`](../zcash_voting/src/share_tracking/confirmation.rs), and
  [`recovery.rs`](../zcash_voting/src/share_tracking/recovery.rs);
- [`share`](../zcash_voting/src/share.rs), which derives and records share
  identity and reconstructs recovery payloads; and
- [`storage`](../zcash_voting/src/storage/), whose
  [`queries/mod.rs`](../zcash_voting/src/storage/queries/mod.rs) facade and
  [`queries/share_delegations.rs`](../zcash_voting/src/storage/queries/share_delegations.rs)
  preserve delivery state across restarts.

## Confidentiality statement

The primary confidentiality adversary considered by the helper-distribution
policy is collusion by the MPC validator committee. Decrypting an encrypted
share requires control of at least the protocol's two-thirds validator
threshold. For a complete normal commitment planned once as one batch with at
least two configured helpers, an adversary controlling that threshold together
with one helper can obtain at most 12 of the 16 plaintext shares from that
helper's returned initial target assignments.

This is a 75-percent share-count bound, not necessarily a bound on the
percentage of voting balance revealed. It is an initial-planning statement,
not a lifetime possession bound: ambiguous delivery, initial-delivery
fallback, replenishment, overdue recovery, fleet changes, legacy delivery
state that predates complete-plan persistence, and single-share mode fall
outside it. New SDK planning atomically persists the complete commitment-wide
plan before any POST and reuses it across restart; it never replans only the
missing subset. New plans without preexisting delivery rows report
`SharePlacementGuarantee::Strict`.
`SharePlacementGuarantee::LegacyBestEffort` (abbreviated `LegacyBestEffort`
below) records that delivery rows already existed without a complete original
plan. It is metadata about old state, not permission to discard or recompute a
plan. The statement also makes no claim about the combined view of colluding
helpers.

## Terminology and state model

A **configured helper** is a canonical HTTP or HTTPS helper endpoint in the
wallet's current configuration. This is a routing and persistence identity,
not an authenticated operator identity: distinct canonical URLs are counted as
distinct helpers even when they are controlled by one operator, terminate at
one backend, or change operators over time.

A **definite acceptance** is a `POST /shares` response with status `queued` or
`duplicate`. Its helper is stored in `sent_to_urls`.

An **ambiguous attempt** is a POST that may have reached the helper but did not
produce a usable acceptance response. Its helper is stored in
`ambiguous_urls`. Ambiguous attempts are poll-only and do not count as definite
placements.

An **attempting helper** is an initial-submission or recovery target durably
reserved in `attempting_urls` before its POST is dispatched. A process
interruption can leave that reservation without a classified response; on
restart it is treated as outcome-unknown and receives one duplicate-safe
reconciliation attempt per pass after untried helpers. Cancellation that is
observed before a fresh reservation dispatches is different: because the POST
is definitely unsent, the reservation is cleared as a definite failure rather
than retained as outcome-unknown.

An **interrupted helper** is an attempting helper whose durable reservation is
loaded by a later tracking operation with no corresponding live request in
that operation. The earlier process may have stopped before dispatch, during
transport, or before persisting the response, so interruption proves neither
acceptance nor non-acceptance. It remains in `attempting_urls` until a
duplicate-safe reconciliation classifies it as accepted or explicitly
ambiguous.

Initial network fan-out and tracking acquire one process-wide asynchronous lock
keyed by wallet, round, bundle, proposal, and share. Durable initial preparation
occurs before that lock and is protected by its own generation-bound atomic
write. After acquiring the lock, each network operation re-reads the exact
nullifier generation. Two live operations in one process therefore cannot
mistake each other's reservation for an interrupted attempt, act on a replaced
generation, or independently advance through fallback helpers. The durable
initial-reservation compare-and-swap also counts configured accepted and
attempting helpers against the placement target, so separate database
connections cannot reserve disjoint excess initial placements. This lock is
per share; unrelated shares remain independent.

The durable **placement target** is the desired number of definite helper
acceptances for one share. Tracking caps its effective value to both the
protocol's helper target cap and the size of the current valid configured
fleet. A share is **under-placed** while the number of currently configured
helpers in `sent_to_urls` is below that effective target.

A share is **confirmed** when its reveal nullifier is considered confirmed on
the vote chain. Confirmation is global; it is not proof that the particular
helper answering the status request possesses the share.

**Early replenishment** repairs under-placement before the share is overdue and
preserves its original `submit_at`. **Overdue recovery** occurs after the
timing threshold and rebuilds the payload with `submit_at = 0`.

The durable state transition is:

```text
initial target --> attempting_urls --> initial POST
                                      |-- definite --> sent_to_urls
                                      \-- unknown --> ambiguous_urls

under-placed or overdue --> attempting_urls --> recovery POST
                                               |-- definite --> sent_to_urls
                                               \-- unknown --> ambiguous_urls

early or overdue: attempting_urls --> duplicate-safe re-POST
                                      |-- accepted --> sent_to_urls
                                      \-- otherwise --> ambiguous_urls

overdue only: ambiguous_urls --> duplicate-safe re-POST
                                |-- accepted --> sent_to_urls
                                \-- otherwise --> unchanged

sent_to_urls, ambiguous_urls, or attempting_urls
    -- confirmed status from the configured quorum --> confirmed
```

The authoritative in-memory contract is `ShareDeliveryState` in
[`share.rs`](../zcash_voting/src/share.rs). Its precedence is **Accepted >
OutcomeUnknown > InFlight**: stronger evidence replaces weaker evidence, while
weaker evidence cannot replace stronger evidence. The persisted public/schema
field names remain `sent_to_urls`, `ambiguous_urls`, and `attempting_urls`,
respectively, and MUST remain disjoint. The same state transitions are enforced
for storage updates in
[`storage/queries/share_delegations.rs`](../zcash_voting/src/storage/queries/share_delegations.rs).
`delivery_state_preserves_order_and_strongest_evidence` exercises this
precedence directly.

An explicitly ambiguous helper is poll-only for early replenishment. An
interrupted helper is retried after every untried helper, even without vote-end
timing, and at most once per tracking pass. Helper-side duplicate detection
(`duplicate` is a definite acceptance) makes the re-POST converge instead of
double-counting. Acceptance moves it to `sent_to_urls`; any completed
non-acceptance moves the crash marker to explicit `ambiguous_urls`, preventing
unbounded early replay while preserving the original unknown outcome.

## Planning invariants

### Initial-distribution policy

Planning combines an explicit protocol fan-out cap with a per-helper limit
derived from the canonical normal-commitment share count. Let:

```text
S = VOTE_COMMITMENT_SHARE_COUNT
C = SHARE_HELPER_TARGET_COUNT_CAP = 10
N = number of distinct configured helpers
R = number of ready helpers in the readiness-ranked prefix
```

The normal protocol MUST have `S >= 2`. Single-share mode is a separate mode,
is valid only when the planned payload count is exactly one, does not change
`S`, and is exempt from the commitment-wide distribution bound below. A caller
cannot mark an `S`-share commitment as single-share to bypass that bound.
`C = 10` is an independent protocol choice: it bounds initial
fan-out and prevents fleet growth from increasing per-share distribution
without limit. It is not derived from `S`.

The strict initial per-helper share fraction is three quarters. Its integer
limit rounds down so it never exceeds 75 percent:

```text
max_initial_shares_per_helper = M = floor(3S / 4)
```

The per-share definite-placement target remains half the configured fleet,
rounded up, until it reaches the protocol cap:

```text
target_count = T = min(ceil(N / 2), C)
```

For the current `S = 16` and `C = 10`, these formulas produce `M = 12`.
Consequently, fleets through 20 helpers retain the half-rounded-up target,
while larger fleets target at most 10 definite acceptances per share.

For a complete normal commitment, planning creates `S * T` assignments. The
planning pool MUST contain enough helpers for every assignment without any
helper exceeding `M`:

```text
minimum_planning_pool = P_min = ceil(S * T / M)
planning_pool = P = min(N, max(R, P_min))
```

The one-helper fleet is the only forced-full-coverage exception: it uses
`T = P = 1`, and that helper necessarily receives every initially planned
share. For every `N >= 2`, the derived capacity MUST fit within the configured
fleet before planning succeeds. A future change to `S` or the three-quarters
ratio that makes the capacity infeasible MUST fail planning explicitly rather
than silently weakening the target or the per-helper bound.

The current values include:

| Configured helpers `N` | Target `T` | Minimum pool `P_min` | Effective initial maximum |
| ---: | ---: | ---: | ---: |
| 1 | 1 | 1 (forced exception) | 16 |
| 2 | 1 | 2 | 12 |
| 3 | 2 | 3 | 12 |
| 5 | 3 | 4 | 12 |
| 10 | 5 | 7 | 12 |
| 20 | 10 | 14 | 12 |
| 30 | 10 | 14 | 12 |
| 100 | 10 | 14 | 12 |

The selector MUST enforce `M` as a hard quota while constructing a complete
batch, not merely rely on an average produced by balancing. Among helpers
below the quota, it continues to prefer the lowest current assignment count
and uses independent CSPRNG-derived order to break ties. If it cannot select
`T` distinct helpers for a share without exceeding the quota, planning fails.

Readiness selects the planning-pool prefix but does not weaken its required
capacity. If `R < P_min`, the pool includes the first `P_min - R` configured
fallback helpers after the ready prefix. This is an explicit tradeoff: the
strict initial distribution bound may require planning across helpers that did
not answer readiness probing.

The derived bound applies only to the returned target lists for one complete
normal batch of exactly `S` shares. It does not claim that a helper can never
physically hold more than `M` shares:

- single-share mode necessarily gives a selected helper the only share;
- incomplete low-level batches, independently planned shares, and legacy rows
  that predate complete-plan persistence have no commitment-wide usage history and
  therefore provide no percentage bound;
- an ambiguous POST may have reached a helper without producing a definite
  acceptance; and
- initial fallback, early replenishment, overdue recovery, and fleet changes
  remain liveness-first and may give a helper an initially omitted share.

An absolute lifetime possession cap is intentionally not claimed. Enforcing
one would make ambiguous delivery unknowable and could prevent recovery from
using the only functioning helper.

The assignment limit `M` is a wallet-policy consequence of `S`, and `P_min` is
calculated from `S`, `T`, and `M`; neither makes `S` independently
configurable. `C` is separately chosen protocol policy. Changing `S` remains a
coordinated protocol change across the circuits, wallet wire validation,
helper payload validation, chain types, and their fixed-size arrays and tests.
Changing `C` changes helper distribution and recovery redundancy but does not
change the share format.

Existing durable rows whose stored `target_count` exceeds `C` keep their
historical value but MUST use `C` as their effective target. This read-time
clamp avoids a schema migration while preventing a legacy value from restoring
the old uncapped behavior.

Regression coverage:

- target count remains half-rounded-up through `N = 20` and is capped by the
  independent protocol constant `C = 10` above that boundary;
- the maximum initial assignment count is derived as `floor(3S / 4)`;
- the minimum pool is derived as `ceil(S * T / M)` at small, boundary, and
  large fleet sizes;
- every helper in a complete normal batch is assigned at most `M` shares;
- planning fails rather than exceeding `M` when presented with an infeasible
  capacity;
- the one-helper and single-share forced-coverage exceptions are explicit;
- single-share mode rejects zero, incomplete, and complete multi-share batches;
- incomplete or independently planned low-level batches and legacy pre-v17
  state do not advertise the complete batch guarantee;
- fallback and recovery remain able to exceed the initial-only quota; and
- `legacy_target_above_protocol_cap_is_effectively_clamped` ensures a durable
  target above the protocol cap cannot drive new placements above the
  canonical target.

### Share count and identity

1. A normal vote commitment contains 16 encrypted shares. Single-share mode
   emits only domain share index 0, and the planner rejects `single_share =
   true` unless the committed vote contains exactly one payload. The SDK
   derives this mode from the committed payload count; the host cannot pass a
   contradictory mode flag.
2. Share indexes identify the post-ZKP-2 shuffled shares. Share index 0 does
   not imply a particular denomination or value.
3. At most one share is designated as the round's immediate share. It is share
   index 0 of the lowest voted proposal ID in the highest eligible bundle
   index. Bundles are value-descending, so this is the lowest-value eligible
   bundle.
4. The immediate designation is derived from durable ballot choices and is
   stable across restart and vote completion. Skipped proposals do not
   participate.
5. `immediate = true` and `submit_at = 0` are not equivalent. Last-moment and
   single-share planning can assign `submit_at = 0` to undesignated shares,
   but the designated immediate share MUST always have `submit_at = 0`.

Enforcement:
[`round_immediate_share_key`](../zcash_voting/src/share_policy/initial_placement.rs)
and
[`plan_share_submissions`](../zcash_voting/src/share_policy/initial_placement.rs).

Regression tests:
`round_immediate_share_key_uses_highest_bundle_lowest_voted_proposal_and_share_zero`,
`immediate_batch_position_stays_aligned_and_does_not_perturb_other_plan`,
`immediate_marker_is_distinct_when_all_shares_submit_immediately`,
`single_share_mode_is_exempt_from_complete_batch_usage_cap`,
`single_share_mode_rejects_non_singleton_batches`, and the
round-plan tests in [`session.rs`](../zcash_voting/src/session.rs). The policy
tests are in
[`share_policy/tests/initial_placement.rs`](../zcash_voting/src/share_policy/tests/initial_placement.rs).

### Placement target

For `N` distinct configured helpers and protocol target cap `C = 10`, every
initial share target is:

```text
target_count = min(ceil(N / 2), C)
```

The concrete values include:

| Configured helpers | Target |
| ---: | ---: |
| 0 | 0 |
| 1 | 1 |
| 2 | 1 |
| 3 | 2 |
| 5 | 3 |
| 10 | 5 |
| 20 | 10 |
| 21 | 10 |
| 30 | 10 |
| 100 | 10 |

An empty helper list is invalid even though the pure target-count function
returns zero. The high-level entry point does not accept an unvalidated raw
list: `HelperClient::preflight_fleet` canonicalizes the complete fleet, rejects
empty or duplicate canonical identities, derives the readiness target
internally, and returns `HelperFleetPreflight`.
FFI boundaries may reconstruct the same public snapshot with
`HelperFleetPreflight::from_readiness`; it applies the same nonempty,
canonical, and distinct configured-fleet checks and additionally requires the
ready list to be a distinct subset of that fleet.
`CommittedVote::prepare_share_delivery` consumes that validated snapshot.
It also consumes the complete proposal-id roster from the authenticated round
configuration. The roster must be nonempty, distinct, and exactly match the
round's durable terminal ballot intents. The SDK combines those intents with
the durable bundle set to derive the single immediate share; the host does not
select an immediate share index.
Low-level pure planners remain implementation tools, not the wallet lifecycle
boundary.

The delivery and tracking entry points enforce the stronger trust-boundary
contract through validated fleet types: complete-plan preparation, prepared
batch submission, and `track_pending_shares` reject empty fleets, URLs that fail canonicalization,
and distinct spellings that canonicalize to the same helper identity with
`InvalidInput` before any storage or network effect. Misconfiguration must
surface as an error; configured entries are never silently dropped or
collapsed.

The SDK derives the target from the canonical fleet size. Crate-private raw
fan-out helpers retain explicit targets only for internal and regression use;
the public lifecycle admits only validated, SDK-derived planning state.

`target_count` is a target for definite acceptances, not an upper bound on the
number of helpers that may physically hold a share. An ambiguous helper may
have accepted the POST, while recovery must still obtain enough definite
acceptances. Recovery can therefore cause more than `target_count` helpers to
hold the same share.

Enforcement:
[`share_submission_target_count`](../zcash_voting/src/share_policy/server_order.rs),
`require_share_servers` in
[`share_policy/initial_placement.rs`](../zcash_voting/src/share_policy/initial_placement.rs),
`HelperClient::preflight_fleet` and `HelperFleetPreflight` in
[`helper/client.rs`](../zcash_voting/src/helper/client.rs), complete-plan
validation in
[`share_tracking/delivery_plan.rs`](../zcash_voting/src/share_tracking/delivery_plan.rs),
and committed delivery in
[`share_tracking/initial_delivery.rs`](../zcash_voting/src/share_tracking/initial_delivery.rs).

Regression tests:
`helper_target_count_is_half_rounded_up_and_capped_by_protocol_policy`,
`share_submission_plan_rejects_empty_server_list`,
`share_submission_plan_rejects_duplicate_server_urls`,
`committed_vote_submission_rejects_uncapped_large_fleet_target`,
`fan_out_canonicalizes_candidates_without_shrinking_the_target`,
`submit_rejects_invalid_candidate_url_before_any_network_io`, and
`tracking_rejects_invalid_configured_url`. Boundary coverage additionally
includes
`committed_submission_rejects_duplicate_spelling_fleet_before_effects`,
`tracking_rejects_duplicate_spelling_fleet_before_effects`, and
`tracking_rejects_empty_fleet_before_effects` in
[`share_tracking/tests/initial_delivery.rs`](../zcash_voting/src/share_tracking/tests/initial_delivery.rs).
The public boundary is also covered by
`current_boundary_rejects_schema_invalid_bodies_and_canonical_duplicates` in
[`helper_share_adversarial.rs`](../zcash_voting/tests/helper_share_adversarial.rs).

### Helper selection and balancing

1. Production planning uses SDK-owned operating-system CSPRNG entropy. The
   host cannot inject, reuse, persist, or accidentally correlate timing and
   helper-order bytes. Helper order uses a Fisher-Yates shuffle with eight
   bytes per shuffle step.
2. Batch planning consumes independent timing entropy and helper-order entropy
   for every share. Reusing one sample or helper order for all shares is not
   allowed by the batch API.
3. Initial assignments prefer helpers with the lowest current assignment
   count. Random order breaks ties, balancing a complete `S`-share commitment
   across the planning pool without allowing an assignment count above
   `M = floor(3S / 4)`.
4. The minimum planning-pool size is `ceil(S * T / M)`. A readiness-ranked
   prefix can enlarge that pool, but too few ready helpers cannot shrink it.
   When necessary, planning includes configured fallback helpers after the
   ready prefix to provide the required assignment capacity.
5. For every complete normal commitment and every fleet with at least two
   helpers, each helper is initially assigned at most `M` shares. With the
   current `S = 16`, that is at most 12 of 16 shares, a strict maximum of 75
   percent under the three-quarters bound.
6. The derived `max_shares_per_server` is an initial-planning property, not a
   permanent privacy bound. Initial fallback and recovery can place additional
   shares on a helper when needed for liveness. The bound makes no claim about
   the combined view of colluding helpers.
7. Persisted plans remain positionally aligned with committed payloads. The
   high-level API accepts a domain share index and maps it to the committed
   payload position internally.
8. The commitment-wide bound applies only when all `S` shares are planned once
   in one batch. The SDK persists that complete batch atomically and reuses it
   after restart. Single-share mode, incomplete low-level batches, and legacy
   state marked `LegacyBestEffort` do not claim it.

Enforcement:
`shuffled_share_server_order`,
`plan_share_submissions_with_preferred_servers`, and
`select_batch_share_submission_targets` in
[`share_policy/server_order.rs`](../zcash_voting/src/share_policy/server_order.rs)
and
[`share_policy/initial_placement.rs`](../zcash_voting/src/share_policy/initial_placement.rs).

Regression tests: `randomized_helper_order_uses_entropy`,
`share_submission_batch_plan_uses_independent_entropy_per_share`,
`complete_batch_with_three_helpers_balances_two_targets`,
`complete_batch_caps_helper_usage_at_derived_three_quarters`,
`preferred_pool_limits_initial_targets`,
`minimum_planning_pool_enforces_derived_three_quarters_cap`,
`infeasible_initial_assignment_capacity_is_rejected`,
`incomplete_batch_is_exempt_from_complete_batch_usage_cap`,
`single_share_mode_is_exempt_from_complete_batch_usage_cap`, and
`complete_batch_with_one_helper_is_forced_full_coverage` in
[`share_policy/tests/server_order.rs`](../zcash_voting/src/share_policy/tests/server_order.rs)
and
[`share_policy/tests/initial_placement.rs`](../zcash_voting/src/share_policy/tests/initial_placement.rs).

## Scheduling invariants

### Initial `submit_at`

The last-moment window is two fifths of the interval from ceremony start to
vote end, rounded up to whole seconds and capped at six hours. Invalid or
zero-length timing has no last-moment window.

Outside that window, a delayed `submit_at` is sampled uniformly from:

```text
[now, min(last_moment_boundary, now + 100 hours))
```

The upper bound is exclusive. A delayed sample requires eight CSPRNG bytes.
The following conditions instead produce `submit_at = 0`:

- single-share mode;
- a missing or zero last-moment buffer;
- `now` at or after the last-moment boundary; or
- the round timing leaves no positive delay window.

The round-designated immediate share is independently forced to
`submit_at = 0`.

Enforcement: `last_moment_buffer_seconds`,
`delayed_share_window_seconds`, and
`scheduled_share_submit_at_from_entropy` in
[`share_policy/timing.rs`](../zcash_voting/src/share_policy/timing.rs) and
[`share_policy/submission_schedule.rs`](../zcash_voting/src/share_policy/submission_schedule.rs).

Regression tests: `last_moment_buffer_uses_two_fifths_of_round_duration`,
`last_moment_buffer_caps_at_six_hours`,
`scheduled_submit_at_from_random_unit_samples_before_deadline`,
`delayed_share_window_caps_long_round_at_100_hours`,
`delayed_share_window_is_immediate_inside_last_moment_buffer`, and
`scheduled_submit_at_entropy_requirement_matches_delay_window` in
[`share_policy/tests/timing.rs`](../zcash_voting/src/share_policy/tests/timing.rs)
and
[`share_policy/tests/submission_schedule.rs`](../zcash_voting/src/share_policy/tests/submission_schedule.rs).

### Polling and overdue timing

For delayed shares, the recovery base time is `submit_at`. For immediate
shares, it is the durable `created_at`.

1. Status polling begins 10 seconds after the base time.
2. The overdue threshold is one quarter of the base-time-to-vote-end window,
   clamped to the range 30 seconds through one hour.
3. A confirmed share is never ready or overdue.
4. Overdue recovery is permitted only while more than 10 seconds remain before
   vote end. Equality closes the recovery window.
5. Without a vote-end time, status polling remains available, but a share
   cannot be classified as overdue.
6. Under-placement is independent of overdue status and can trigger early
   replenishment when no vote-end time is available.

After a tracking pass, the next delay is the earliest future grace boundary,
capped at 30 seconds. If every remaining share is already ready, the delay is
15 seconds. Every nonempty delay is at least three seconds. No unconfirmed
shares yields no next delay.

Enforcement: `share_recovery_base_time`, `should_resubmit_share`,
`is_share_resubmission_window_open`, and `next_tracking_delay_seconds` in
[`share_policy/timing.rs`](../zcash_voting/src/share_policy/timing.rs).

Regression tests: `immediate_shares_use_created_at_for_status_and_retry`,
`delayed_shares_use_submit_at_for_status_and_retry`,
`overdue_threshold_is_quarter_window_with_bounds`,
`resubmission_window_closes_exactly_at_the_cutoff`,
`next_tracking_delay_applies_minimum_and_future_cap`, and
`next_tracking_delay_uses_ready_poll_interval_for_ready_pending_shares` in
[`share_policy/tests/timing.rs`](../zcash_voting/src/share_policy/tests/timing.rs).
Facade-level timing behavior is covered by
`confirmed_shares_are_never_ready_or_overdue`,
`missing_vote_end_suppresses_overdue_but_not_status_checks`, and
`young_share_is_idle_until_the_status_grace_passes` in
[`share_tracking/tests/timing_policy.rs`](../zcash_voting/src/share_tracking/tests/timing_policy.rs).

## Transport and timeout invariants

### Readiness

A helper is ready only when its base URL canonicalizes and `GET /status`
returns a 2xx `application/json` response whose `status` string equals `ok`
case-insensitively. Invalid URLs, transport failures, non-2xx responses,
oversized or invalid bodies, and any other status all produce `ready = false`.
Readiness is advisory and never fails the voting flow by itself.

`HelperClient::preflight_fleet` canonicalizes the caller's list, derives the
readiness target from the canonical fleet size, and starts every valid probe
concurrently. Its crate-internal raw preflight primitive receives that derived
target. It
collects responses through the two-second soft window. If the target is still
unmet, pending probes remain alive until enough helpers are ready, every probe
finishes, or the shared 30-second hard deadline expires. If the target is met
before the soft boundary, pending probes are stopped at that boundary; a zero
target still produces the ordered canonicalized result list but returns before
creating the probe task set, so it opens no connections even on a multi-threaded
runtime. Probes are not retried because readiness is only a bounded,
best-effort ranking hint; an unsuccessful helper remains available as a
planning fallback, and delivery applies its own retry and recovery policy.
Results preserve caller order, use canonical spellings for valid URLs, and
report invalid or unfinished entries as not ready.

### Default limits

| Operation or limit | Default | Enforced by |
| --- | ---: | --- |
| Initial readiness window | 2 seconds (from `SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS`) | `HelperClient::preflight_fleet` |
| Absolute readiness deadline | 30 seconds (from `SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS`) | `HelperClient::preflight_fleet` |
| One status GET | 5 seconds | `HelperClient::share_status` |
| Concurrent status GETs per share | 4 (from `SHARE_STATUS_MAX_CONCURRENT_POLLS`) | `poll_share_helpers` |
| Total status quorum search for one share | 10 seconds (from `SHARE_STATUS_POLL_BUDGET_MILLISECONDS`) | `poll_share_helpers` |
| One helper POST | 30 seconds | `HelperClient` |
| Concurrent initial POSTs across the process | 16 (from `SHARE_HELPER_MAX_CONCURRENT_POSTS`) | `CommittedVote::submit_prepared_shares` |
| Total initial fan-out per share | 60 seconds | committed share delivery |
| Minimum budget to start an initial POST | 1 second | committed share delivery |
| Retry backoffs | 200 ms, then 600 ms | `HelperClient::with_retry` |
| Accepted response body | 256 KiB | `HelperClient` and `HyperTransport` |
| Ready-share poll interval | 15 seconds | `next_tracking_delay_seconds` |
| Recovery cutoff | 10 seconds before vote end | `track_pending_shares` |

The timeout passed to a `HelperTransport` covers connection setup, response
headers, and the complete response body. `HelperClient` wraps every transport
future in that deadline and rejects responses larger than 256 KiB, so these
limits also hold when a custom transport ignores the supplied timeout or
buffers an oversized response. `HyperTransport` additionally enforces both
while streaming. Its `with_http_connector` constructor lets a host supply
socket, proxy, DNS, or route-lifecycle behavior without reimplementing these
HTTP semantics; because Hyper pools connections, the supplied connector and
its returned I/O MUST also prevent an old pooled connection from surviving a
route change that forbids it. Successful responses MUST carry
`application/json` (optional
parameters such as `charset` are accepted); the client validates the content
type metadata returned by every transport. Non-2xx bodies are size-checked
before diagnostic string conversion while retaining their HTTP status for
retry and ambiguity classification.

Every caller-configurable helper timeout and retry delay must be nonzero and
representable by Tokio's monotonic clock. Configuration rejects values that
cannot form a deadline, and request, preflight, and retry paths use checked
instant arithmetic defensively rather than allowing caller-shaped durations to
panic the process.

A status GET remains eligible for its configured same-helper retries, but
`poll_share_helpers` wraps the complete quorum search for one share in a
ten-second outer budget and keeps at most four requests in flight. Budget
expiry can therefore stop an individual request or retry sequence before its
per-helper limits are exhausted. This budget applies separately to each share,
not to the complete tracking pass. An unconfirmed or stalled share returns when
its budget is exhausted so tracking can advance to later durable shares.

Initial fan-out has a shared 60-second budget. Before every attempt, including
same-helper retries, the client recomputes the remaining overall budget and
caps the complete transport timeout to the smaller of that budget and the
configured per-request timeout. No attempt starts with less than one second of
fan-out budget — such an attempt could only end outcome-unknown. A retry
backoff that would cross the fan-out deadline is skipped and the held error is
returned, so a definite failure is never converted into an unknown outcome by
cancellation during a sleep. If the deadline expires during an in-flight POST,
that attempt is ambiguous and is retained for polling.

Enforcement:
[`helper/client.rs`](../zcash_voting/src/helper/client.rs),
[`helper/transport.rs`](../zcash_voting/src/helper/transport.rs),
[`http_transport.rs`](../zcash_voting/src/http_transport.rs), and
[`share_tracking/initial_delivery.rs`](../zcash_voting/src/share_tracking/initial_delivery.rs).

Regression tests: `preflight_keeps_slow_probes_alive_until_the_target_is_ready`,
`preflight_stops_at_the_soft_window_when_enough_helpers_are_ready`,
`preflight_stops_slow_helpers_at_the_hard_deadline`,
`preflight_with_zero_target_does_not_open_connections`,
`defaults_use_distinct_status_and_post_deadlines`,
`helper_config_rejects_invalid_durations_and_excessive_retries`,
`client_enforces_deadline_when_custom_transport_ignores_it`,
`every_retry_is_capped_to_the_remaining_delivery_deadline`,
`retry_backoff_does_not_turn_a_definite_failure_ambiguous`,
`retries_without_an_overall_deadline_keep_the_configured_timeout`,
`fan_out_stops_at_the_overall_deadline_and_clamps_the_last_request`,
`definite_failure_in_backoff_is_not_marked_ambiguous`,
`definite_failure_at_backoff_deadline_clears_durable_attempt_and_retries_later`,
`no_attempt_starts_under_minimum_budget`, and the
helper transport timeout/body tests in `http_transport.rs`.

### Endpoint retry policy

| Call | Attempts | Same-helper retry rule |
| --- | ---: | --- |
| `GET /status` | 1 | Never retried |
| Initial `POST /shares` | Up to 3 | Retry only definite transient failures |
| `GET /share-status/{round_id}/{share_id}` | Up to 3 | Retry transient failures, including ambiguous transport failures |
| Recovery `POST /shares` | 1 | Never retried by the client |

The two configured backoffs produce at most three attempts. GET retries are
safe because the operation is idempotent. A POST MUST NOT be repeated against
the same helper after any ambiguous result. Once a dispatched POST completes,
its result takes precedence over cancellation: in particular, late cancellation
cannot turn an outcome-unknown result into `Cancelled`. Cancellation still
suppresses an otherwise-eligible retry or a request that has not started.

For current POST classification:

| Outcome | Classification | Same-helper retry |
| --- | --- | --- |
| `queued` or `duplicate` | Definite acceptance | Stop |
| DNS, connect, TLS, or route failure before dispatch | Definite failure | Retry |
| HTTP 429 | Definite transient failure | Retry |
| HTTP 500, 502, 503, or 504 | Ambiguous transient failure | Never |
| Timeout | Ambiguous | Never |
| Failure after dispatch but before headers | Ambiguous | Never |
| Failure while reading the response body | Ambiguous | Never |
| 2xx with missing or unknown submission status | Ambiguous | Never |
| Other 5xx statuses | Ambiguous non-transient failure | Never |
| Other non-2xx statuses | Definite non-transient failure | Never |
| Body outside the closed `VoteShareWire` schema | Local definite failure | No request |

Caller-supplied bodies are parsed as the closed `VoteShareWire` schema,
validated, and canonically reserialized before submission. Invalid JSON,
unknown or duplicate fields, oversized bodies, noncanonical encodings, and
protocol-invalid values are rejected before the submission enters the scored
network path. Rejection therefore performs no request and does not increment
or clear the selected helper's health state.

Every 5xx response is ambiguous because the helper may have processed the
share before returning a server error. The narrower set `500`, `502`, `503`,
and `504` is also transient, which permits same-helper retries for idempotent
GETs. Initial POST submission never retries any ambiguous response, including
an otherwise transient 5xx.

Enforcement: `HelperError::is_transient`, `HelperError::is_ambiguous`,
`HelperClient::with_retry`, and `parse_submission_response` in
[`helper/client.rs`](../zcash_voting/src/helper/client.rs).

Regression tests: `submit_retries_definite_throttling_but_not_ambiguous_failures`,
`unusable_successful_submission_is_ambiguous_and_not_retried`,
`late_cancellation_preserves_ambiguous_submission_errors`,
`cancellation_suppresses_a_pending_retry`,
`resubmit_makes_one_attempt_and_preserves_its_result`, and
`invalid_share_bodies_are_not_sent_or_scored`. The adversarial integration
test `mixed_initial_failures_follow_current_retry_and_durability_rules` covers
the ambiguous, non-transient 501 boundary.

## Initial fan-out invariants

`CommittedVote::prepare_share_delivery` is the planning boundary. It consumes a
`HelperFleetPreflight` and the authenticated complete proposal roster. In one
immediate SQLite transaction it requires an exact set of durable terminal
ballot intents, derives the round-wide immediate key from those intents and the
durable bundle set, uses SDK-owned entropy, plans every committed payload,
validates the fleet, target sets, immediate designation, and aggregate quota,
then writes one generation-bound `helper_share_plans` row. A repeat call,
including after restart, loads and returns the exact stored plan instead of
drawing a replacement, even when the newly preflighted helper fleet has
changed. The current preflight is used only when creating a plan; an existing
plan validates against its own persisted planning fleet. Existing round plans
are checked so roster drift cannot create a second or conflicting immediate
designation.

`CommittedVote::submit_prepared_shares` is the delivery boundary. It loads that
plan, requires the plan's exact current committed-vote generation, binds the
submitting handle to that generation, validates the immutable plan against its
persisted planning fleet, and separately validates the complete current fleet.
A handle must contain the exact current recovery snapshot, and
callers must recover a fresh handle after confirmation changes that snapshot.
It reconstructs and validates every payload before the first POST, then
executes all incomplete shares. The original target remains durable across
fleet churn. Planned targets still present in the current fleet are attempted
first, followed by every other current helper; removed helpers are never
contacted or counted. Target-count drift within the persisted plan, malformed
payloads, aggregate-quota violations, a nonzero schedule on the designated
immediate share, or a missing confirmed VC position fail before network I/O.
The raw per-share executor is
crate-private, and there is no public post-hoc delivery mutator.

Up to 16 share tasks across all wallets and committed votes in the process may
hold a delivery permit at once. Each task retains per-share serialization, the
30-second request deadline, the 60-second total fan-out deadline, and durable
reservation-before-POST. `ShareBatchDeliveryReport` is sorted by domain share
index. It contains durable reports for completed tasks, the indexes still
queued when cancellation stopped new work, a final cancellation flag, and the
persisted placement guarantee. A completed task may still report a placement
deficit for tracking to repair. Cancellation never rolls back durable effects.

`LegacyBestEffort` is assigned only when v17 first creates a complete plan for
a vote that already has delivery rows from an older lifecycle. The SDK still
persists and reuses the new plan. The marker records that earlier placements
cannot be proven to satisfy the commitment-wide quota; it is never permission
to replan missing shares or to bypass aggregate-quota validation for the new
complete plan.

The `test-fixtures` feature exposes hidden `share::record`,
`share::record_delivery_fixture`, and `share::confirm_fixture` seed helpers for
external integration tests. They do not exist in production builds and MUST
NOT be used to model wallet submission behavior.

Complete-plan persistence and per-share preparation are both bound atomically
to the exact commitment-bundle generation validated for the `CommittedVote`
handle. Plan loading requires the handle's exact stored generation. The schema
trigger advances the persisted plan through the confirmation-only VC-position
transition, so a caller must recover a fresh `CommittedVote` before submitting.
A version-17 migration first normalizes released singleton recovery JSON that
predates nullable atomic-batch metadata. This happens before the plan table
exists, allowing confirmation to remain a byte-exact VC-position-only
transition without weakening generation comparison for any other recovery
change.
A replacement that lands after an earlier recovery read, including one that
preserves the vote commitment, invalidates the handle or plan and fails before
any helper POST instead of combining old payload or placement data with the
replacement generation.

After validation it creates or merges the durable share record. Persistence
returns the effective write-once `submit_at`; resumed fan-out rebuilds the wire
payload with that durable schedule before contacting any newly selected
helper. A recomputed plan therefore cannot split one share across different
schedules, and an existing immediate schedule (`submit_at = 0`) cannot be
resurrected as delayed.

Before network fan-out, live initial delivery and tracking passes for the same
share are serialized by the per-share operation lock described above. A
waiting operation re-reads the exact row generation after acquiring the lock.
Initial reservation itself is also target-aware: its atomic storage update
refuses a fresh configured helper when the number of configured definite
acceptances plus configured `attempting_urls` already reaches `target_count`.
An `AlreadyRecorded` result for one helper therefore cannot let an overlapping
pass walk disjoint fallbacks beyond the shared target.

Planned targets are attempted first, followed by the remaining configured
fleet. Health ranking is applied independently within those groups, so a
healthy fallback never moves ahead of a degraded planned target. For every
selected helper it writes
`attempting_urls` before dispatch, then:

1. re-evaluates helper health before each attempt;
2. selects each helper at most once in the outer fan-out (the client can still
   repeat a definite transient transport attempt under its retry policy);
3. resolves definite and ambiguous outcomes into their separate durable sets;
4. stops when `target_count` definite helpers have accepted, candidates are
   exhausted, cancellation fires, or the 60-second deadline expires; and
5. returns partial or empty acceptance as a report rather than treating it as
   a network-level function error.

Ambiguous attempts do not satisfy the target. The returned report summarizes
the exact current durable generation after fan-out, including placements made
by a serialized overlapping caller; a deleted or replaced generation fails
instead of returning its stale snapshot. The tracker is responsible for
repairing any remaining deficit. `ShareSubmissionReport` has no separate
in-flight field, so its `ambiguous_urls` projection includes both durable
`ambiguous_urls` and process-interrupted `attempting_urls`. Storage and tracker
logic continue to keep those states distinct.

Regression tests in
[`share_tracking/tests/initial_delivery.rs`](../zcash_voting/src/share_tracking/tests/initial_delivery.rs):
`fan_out_stops_at_the_target_count`,
`fan_out_moves_past_a_refusing_helper`,
`fan_out_never_retries_the_same_helper`,
`fan_out_returns_partial_acceptance_rather_than_failing`, and
`fan_out_retains_ambiguous_attempts_separately`. Durable dispatch ordering is
covered by `initial_post_is_journaled_before_transport_dispatch`,
`definite_initial_failure_clears_attempt_and_remains_retryable`,
`ambiguous_initial_failure_is_not_replayed_by_initial_delivery`,
`failed_outcome_write_is_reported_as_ambiguous_on_resume`, and
`failed_attempt_write_prevents_network_dispatch`. Overlap coverage is provided
by `overlapping_initial_fan_outs_share_one_target`,
`tracking_waits_for_live_initial_fan_out_before_replenishing`, and
`concurrent_attempt_reservations_share_one_placement_capacity`.
Cancellation while waiting for that serialization boundary is covered by
`cancellation_aborts_initial_wait_for_live_share_operation`.
Typed-boundary coverage is
provided by
`committed_vote_submission_keeps_degraded_planned_target_before_healthy_fallback`,
`stale_committed_vote_submission_is_rejected_before_side_effects`,
`generation_bound_preparation_rejects_replacement_after_validation`,
`repeated_committed_submission_preserves_the_original_schedule`,
`repeated_partial_committed_submission_sends_original_schedule_to_new_helper`,
`repeated_committed_submission_does_not_resurrect_zero_schedule`,
`committed_vote_submission_rejects_mismatched_plan_before_side_effects`, and
`invalid_candidate_url_does_not_create_a_share_record`. Cleanup concurrency is
covered by `initial_delivery_does_not_recreate_share_after_recovery_cleanup`.
Released recovery-format migration and strict plan invalidation are covered by
`migrate_v15_recovery_json_preserves_plan_only_through_confirmation`.
The high-level boundary regressions in
[`share_tracking/tests/delivery_plan.rs`](../zcash_voting/src/share_tracking/tests/delivery_plan.rs)
are `stale_handle_cannot_prepare_same_commitment_replacement`,
`same_commitment_replacement_after_plan_load_stops_every_post`,
`prepared_batch_stays_bound_to_its_starting_wallet`,
`complete_plan_is_persisted_and_reused`,
`preconfirmation_plan_survives_confirmation_restart_and_submission`,
`preconfirmation_handle_is_stale_after_confirmation_transition`,
`restart_reuses_the_plan_and_resumes_definite_delivery_deficits`,
`restart_resumes_with_a_replaced_helper_without_contacting_the_removed_target`,
`restart_after_fleet_expansion_preserves_the_original_target`,
`restart_after_fleet_contraction_clamps_delivery_to_current_helpers`,
`fleet_reordering_preserves_persisted_fleet_identity`,
`one_helper_fleet_is_planned_and_submitted_by_the_sdk`,
`every_payload_is_validated_before_the_first_post`,
`quota_rejects_strict_and_legacy_tampering_but_legacy_metadata_propagates`,
`complete_roster_derives_exactly_one_round_immediate_share`,
`skipped_lower_proposal_does_not_take_the_immediate_designation`,
`planning_rejects_incomplete_duplicate_and_omitting_rosters_before_persistence`,
`later_lower_choice_blocks_stale_submission_and_a_second_immediate_plan`,
`delayed_immediate_plan_is_rejected_before_network`, and
`global_ceiling_is_sixteen_and_queued_cancellation_returns_pending_shares`.
These replace the former wallet-example planner and per-share delivery tests.

## Confirmation and health invariants

### Status interpretation

The status endpoint recognizes exactly `pending` and `confirmed`.

- Confirmation considers the wallet's complete current configured fleet,
  because the status is global rather than evidence of local share possession.
  Helpers are ordered by current health, at most four status requests are in
  flight, and completed slots are refilled while quorum remains possible.
- Fleets with at least two helpers require matching `confirmed` responses from
  two distinct helpers. Observing the second response stops scheduling, aborts
  outstanding status tasks, and persists confirmation before returning. Since
  polling is concurrent, the bounded in-flight group may already have been
  dispatched when quorum is observed.
- A one-helper fleet uses its only available confirmation. With two or more
  configured helpers, one confirmation remains insufficient: polling
  continues, the share remains durable-unconfirmed, and recovery is not
  suppressed.
- `track_pending_shares` and the focused `confirm_pending_share` are the only
  public confirmation mutation paths. Both use the same quorum poller and
  generation-bound write. The raw storage transition is crate-private so
  supported integrations cannot bypass the configured-fleet quorum.
- `pending` means only that the nullifier is not globally confirmed. It does
  not prove that the answering helper stores the share.
- A pending response from an ambiguous helper does not promote it into
  `sent_to_urls`.
- Invalid, missing, or unknown status values are failures. Polling continues
  through the remaining health-ordered candidates while time remains.
- The complete quorum search for one share ends after ten seconds. Budget
  expiry leaves that share durable-unconfirmed and advances the tracking pass
  to later shares; it is not a ten-second deadline for the complete pass.
- Only helpers in the wallet's current configuration are polled or counted
  toward placement.

Regression tests: `two_distinct_confirmations_stop_status_checks`,
`focused_confirmation_confirms_only_the_requested_share`,
`focused_confirmation_ignores_malformed_unrelated_share`,
`focused_confirmation_rejects_a_missing_share_without_network_io`,
`focused_confirmation_returns_an_existing_confirmation_without_network_io`,
`focused_confirmation_bypasses_the_tracker_status_grace`,
`focused_confirmation_does_not_confirm_a_replacement_generation`,
`focused_confirmation_reports_cancellation_without_mutation`,
`stalled_status_poll_does_not_starve_a_later_share`,
`expired_status_budget_does_not_start_or_penalize_helpers`,
`cancellation_aborts_bounded_in_flight_status_polls`,
`late_cancellation_does_not_replace_final_confirmation`,
`one_confirmation_is_not_enough`,
`one_helper_fleet_uses_its_only_available_confirmation`,
`two_helper_fleet_polls_beyond_its_single_placement`,
`one_confirmation_does_not_suppress_under_placement_recovery`,
`confirmed_share_is_never_resubmitted_even_when_overdue`,
`every_helper_pending_reports_not_confirmed`,
`pending_status_keeps_an_ambiguous_attempt_out_of_placement`,
`invalid_status_scores_a_failure_without_blocking_confirmation`, and
`unconfigured_helpers_are_not_polled` in
[`share_tracking/tests/confirmation.rs`](../zcash_voting/src/share_tracking/tests/confirmation.rs)
and
[`share_tracking/tests/recovery.rs`](../zcash_voting/src/share_tracking/tests/recovery.rs).

### Helper health

Health is a process-local ordering hint, not a block list.

1. A usable scored status or submission response clears a helper's accumulated
   failures.
2. A non-cancellation error passed through `HelperClient::score` increments
   the consecutive-failure count. Readiness probes and failures rejected
   before scoring, such as an invalid helper base URL or malformed caller JSON,
   are not scored.
3. When the ten-second status budget expires, the tracker aborts and drains the
   task set, preserves every result that completed at the boundary, and records
   one failure only for each helper whose task actually aborted and therefore
   remains in flight. A completed poll keeps its own single success or failure
   score. Quorum and caller cancellation abort outstanding tasks without
   charging the abort itself as a helper failure.
4. Three consecutive failures demote a helper for 30 seconds.
5. Demotion moves the helper behind healthy peers but never removes it.
6. If every candidate is degraded, caller order is returned unchanged.
7. Cooldown expiry readmits a helper with two failures, so one subsequent
   failure immediately demotes it again.
8. Every accepted helper URL is canonicalized before health state is read or
   written. Equivalent scheme, host, default-port, mount-path escape, and
   trailing-slash spellings therefore share one score. Candidate ordering
   retains the caller's original spellings in its output; invalid URLs fall
   back to exact-string identity and remain unusable at the delivery boundary.
9. Health state is not persisted; restart gives all helpers a clean score.

Enforcement:
[`helper/health.rs`](../zcash_voting/src/helper/health.rs) and
`HelperClient::score`, plus `poll_share_helpers` in
[`share_tracking/confirmation.rs`](../zcash_voting/src/share_tracking/confirmation.rs).

Regression tests: `degraded_helper_is_demoted_not_removed`,
`all_helpers_degraded_still_returns_every_candidate`,
`equivalent_url_spellings_share_one_health_identity`,
`invalid_urls_keep_their_exact_health_identity`,
`success_clears_accumulated_failures`,
`cooldown_expiry_readmits_one_failure_below_threshold`,
`cancellation_before_request_is_not_scored`,
`cancellation_aborts_bounded_in_flight_status_polls`, and
`stalled_status_poll_does_not_starve_a_later_share`. The budget-boundary race is
covered by `budget_expiry_scores_only_polls_that_are_still_running` and
`budget_expiry_preserves_boundary_quorum_without_penalizing_abort`. Local
submission validation is covered by `invalid_share_bodies_are_not_sent_or_scored`.

## Recovery invariants

For each unconfirmed share, `track_pending_shares` computes timing and current
definite placement from the intersection of durable state and the currently
configured helper set.

### Replenishment and ordering

1. Under-placement starts replenishment immediately; it does not wait for the
   share to become status-checkable or overdue.
2. Early replenishment preserves the durable `submit_at`. It tries untried
   helpers first, then process-interrupted helpers. Explicitly ambiguous and
   accepted helpers remain excluded.
3. Overdue recovery rebuilds the payload with `submit_at = 0`. It tries
   untried helpers first, then interrupted helpers, explicitly ambiguous
   helpers, and finally previously accepted helpers. Already-journaled retries
   rely on their durable history instead of adding a fresh attempt marker.
4. The untried and previously accepted groups are independently randomized
   from SDK-owned operating-system CSPRNG bytes. Interrupted and ambiguous retry groups are
   deterministic last resorts whose membership is already persisted; health
   ordering is applied within every group.
5. An ambiguous helper stays poll-only for early replenishment. Overdue
   recovery re-POSTs it at most once per pass; a definite acceptance
   (including `duplicate`) moves it to `sent_to_urls`, while a definite
   failure of the re-POST leaves the outcome-unknown state untouched because
   it says nothing about the original POST.
6. An interrupted helper is retried at most once per pass. Acceptance makes it
   definite; an ambiguous or definite failure moves it to explicit ambiguity,
   consuming the early-retry crash marker without discarding uncertainty.
7. A definite failure is attempted at most once in one tracking pass. It can
   become eligible again in a later pass.
8. One pass continues until it fills the complete definite-placement deficit
   or has no eligible helper that accepts.
9. A configured interrupted marker is an independent reconciliation trigger,
   even when definite placement already meets the target and vote-end timing is
   unavailable. In that placement-satisfied case, tracking preserves the
   durable schedule and contacts only interrupted helpers; it does not expand
   to untried, explicitly ambiguous, or accepted helpers. It continues until
   every configured interrupted marker is classified or another normal stop
   condition fires.
10. Recovery may use any configured helper for liveness; initial balancing is
    not a recovery cap. Fresh reservations normally enforce the placement
    target. Overdue recovery and early recovery that must preserve
    untried-before-interrupted ordering select an explicit recovery policy that
    permits reservations beyond the target instead of changing the target
    value itself.

Regression tests: `under_placed_share_preserves_delayed_submit_at`,
`overdue_share_reaches_an_untried_helper_and_records_it`,
`one_tracking_pass_fills_the_complete_placement_deficit`,
`early_replenishment_never_reposts_to_an_accepted_helper`,
`one_tracking_pass_does_not_repeat_a_definite_failure`,
`a_definite_failure_is_eligible_again_on_a_later_pass`,
`early_replenishment_excludes_ambiguous_helpers`,
`interrupted_one_helper_share_recovers_without_vote_end_time`,
`failed_early_interrupted_retry_is_not_repeated_without_vote_end_time`,
`placement_satisfied_share_reconciles_interrupted_attempt_without_expanding`,
`overdue_recovery_retries_ambiguous_helper_after_untried`,
`overdue_recovery_reposts_to_accepted_helper_after_untried_helpers_fail`,
`ambiguous_accepted_helper_retry_preserves_the_stronger_delivery_state`,
`small_fleet_all_ambiguous_still_recovers`, and
`ambiguous_repost_failure_keeps_ambiguous_state` in
[`share_tracking/tests/recovery.rs`](../zcash_voting/src/share_tracking/tests/recovery.rs).

### Durability and cutoff

Before dispatching any initial or recovery POST, the helper MUST be durably
journaled: a fresh target is added to `attempting_urls`, while an overdue
re-POST to an ambiguous or accepted helper and any interrupted re-POST rely on
already-persisted delivery history. A definite acceptance moves the helper to
`sent_to_urls`; an ambiguous result moves a fresh helper to `ambiguous_urls`;
and a definite failure of a fresh attempt removes the reservation so the
helper can be retried in a later pass. A definite failure of an overdue
outcome-unknown re-POST leaves that earlier unknown state in place, while a
failure of an accepted fallback leaves the earlier acceptance intact. Each
transition is persisted before the workflow contacts another helper.

A process interruption during an in-flight initial or recovery request leaves
the helper in `attempting_urls`. On restart, that state is exposed as
outcome-unknown and receives a deliberate, duplicate-safe reconciliation after
untried helpers, even when vote-end timing is unavailable. A completed
non-acceptance promotes it to explicit ambiguity; a second early pass therefore
does not replay it again. A failed outcome write has the same conservative
behavior as process interruption.

Immediately before every recovery POST, the durable confirmation bit is
re-read. A fresh helper gets this check while its `attempting_urls` reservation
is written; an already-journaled outcome-unknown or accepted helper gets the
same check without changing its state. Confirmation by another task after the
tracking pass loaded its initial snapshot therefore suppresses every kind of
POST.

The vote-end cutoff is checked before recovery starts and again before every
POST using elapsed wall time. No new recovery POST starts at or after the
cutoff. Effects already completed and persisted are not rolled back.

Early replenishment also obeys the cutoff when vote-end time is known. Missing
vote-end time allows early replenishment with the original schedule but
suppresses overdue recovery.

Regression tests: `ambiguous_attempt_is_durable_before_recovery_advances`,
`ambiguous_resubmission_is_recorded_while_recovery_continues`,
`cancellation_before_interrupted_retry_keeps_the_crash_marker`,
`concurrent_confirmation_stops_outcome_unknown_retry`,
`under_placement_stops_at_the_resubmission_cutoff`,
`resubmission_rechecks_the_cutoff_before_every_post`, and
`missing_vote_end_still_allows_early_replenishment` in
[`share_tracking/tests/recovery.rs`](../zcash_voting/src/share_tracking/tests/recovery.rs).

### Recovery material

A recovery POST MUST use:

- the persisted commitment bundle;
- the requested proposal and share identity;
- the real confirmed vote-commitment tree position; and
- the preserved or immediate `submit_at` selected by the recovery mode.

Position zero is a valid tree position and MUST NOT be used as a placeholder
for a submitted but unconfirmed vote. Recovery with a commitment bundle but no
real position waits without posting. Missing or corrupt recovery material is
reported as unrecoverable rather than retried across helpers. If parseable
recovery material derives a different nullifier from the loaded share, tracking
re-reads the exact row generation: the same generation makes the mismatch
persistently unrecoverable, while a deleted or different generation is a
concurrent stale replacement and is silently left to its owning operation.

Enforcement:
[`helper_recovery_material`](../zcash_voting/src/recovery.rs) and
`resubmit_to_next_helper` in
[`share_tracking/recovery.rs`](../zcash_voting/src/share_tracking/recovery.rs).

Regression tests: `missing_recovery_material_is_reported_not_retried`,
`persistent_recovery_nullifier_mismatch_is_reported_unrecoverable`,
`recovery_nullifier_mismatch_from_replacement_remains_stale`, and
`resubmission_waits_for_the_confirmed_vc_position`.

### Cancellation

The cancellation callback is checked between shares, POST targets, attempts,
and retry backoffs. While concurrent status tasks are pending or an initial or
tracking pass is waiting for another operation on the same share, it is also
checked on a 50-millisecond interval. A prepared batch waiting for one of the
process-wide initial-delivery permits observes cancellation on the same
interval without waiting for a permit to be released. Cancellation prevents
additional requests from starting, returns the effects already recorded, sets
`ShareTrackingReport::cancelled` for tracking, and is not charged to helper
health when it suppresses pending work. Once the final observed request has
completed, its result takes precedence: cancellation observed afterward does
not replace that result or suppress its health score.

If cancellation becomes visible after a fresh helper has been reserved but
before its POST dispatches, recovery resolves that reservation as a definite
failure so the helper remains eligible on the next pass. Cancellation before a
retry backed by an interrupted, explicitly ambiguous, or accepted durable
state does not weaken or erase that existing evidence.

The concurrent status poller responds to caller cancellation or confirmation
quorum by signalling its status clients and aborting the task set. At budget
expiry it aborts first and drains the set, preserving results that completed at
the boundary before scoring only the tasks that actually aborted. This drops
in-flight status transport futures instead of waiting for their individual
request timeouts. Outside that poller, cancellation does not generally
interrupt an already-running custom transport request because `HelperTransport`
does not receive the callback. Initial fan-out's outer
60-second deadline can additionally drop the in-flight POST future; that
result is treated as ambiguous.

Regression tests: `cancellation_aborts_bounded_in_flight_status_polls`,
`fresh_recovery_cancelled_before_dispatch_clears_marker_and_remains_retryable`,
`cancellation_before_interrupted_retry_keeps_the_crash_marker`,
`cancelled_outcome_unknown_retry_preserves_ambiguous_state`,
`cancelled_accepted_fallback_preserves_acceptance`,
`cancelled_pass_reports_cancellation_and_keeps_durable_effects`,
`cancellation_aborts_initial_wait_for_live_share_operation`,
`cancellation_aborts_wait_for_live_share_operation`,
`global_ceiling_is_sixteen_and_queued_cancellation_returns_pending_shares`,
`cancellation_before_request_is_not_scored`,
`late_cancellation_does_not_replace_final_failed_poll`, and
`late_cancellation_does_not_replace_final_failed_resubmission`.

## Persistence and compatibility invariants

### Durable record semantics

1. The persisted key is wallet, round, bundle, proposal, and share index.
2. The share nullifier is derived from persisted recovery material rather than
   accepted from a wallet caller. The recovery material's embedded proposal
   MUST match the proposal in that persisted key. Re-recording the key with a
   different nullifier fails.
3. Re-recording merges accepted, ambiguous, and attempting history instead of
   replacing it.
4. A definite acceptance removes the same helper from the ambiguous set.
5. Accepted, ambiguous, and attempting sets are pairwise disjoint. Resolving an
   attempt removes it from `attempting_urls`.
6. Helper lists are canonicalized, deduplicated, and preserve first-occurrence
   order.
7. Re-recording cannot reduce `target_count`.
8. Re-recording preserves an existing confirmed bit, original `created_at`,
   and original `submit_at`. A repeated typed submission cannot replace the
   schedule already delivered to an accepted helper.
9. Immediate overdue recovery sets durable `submit_at` to zero. Early
   replenishment leaves it unchanged.
10. Share writes and confirmation MUST match the current durable ballot intent.
   Changing or skipping that intent clears stale share rows.
11. Pending rounds are wallet-scoped and remain discoverable until every share
    is confirmed.
12. An asynchronous submission or tracking pass captures its wallet scope
    before storage or network work. Every post-await transition is conditional
    on that wallet and the exact persisted share nullifier. A deleted or
    replacement generation is left untouched, and its stale helper result is
    omitted from reports.
13. Storage operations that validate durable state before updating it begin an
    immediate SQLite transaction. The writer reservation is acquired before
    the validation read, so a concurrent WAL writer waits or is waited on
    within the configured busy timeout instead of invalidating the operation's
    snapshot with `SQLITE_BUSY_SNAPSHOT`.
14. Confirmation and sent-server updates carry the nullifier of the share
    generation whose helper result they apply. The transactional read and
    update require that exact nullifier, so a delayed result for a cleared
    generation cannot confirm or add placement evidence to its replacement.

Enforcement:
[`share.rs`](../zcash_voting/src/share.rs),
[`storage/operations.rs`](../zcash_voting/src/storage/operations.rs), and
[`storage/queries/share_delegations.rs`](../zcash_voting/src/storage/queries/share_delegations.rs).

Regression coverage: `test_share_delegation_lifecycle` in
`storage/operations.rs`,
`pending_rounds_return_session_context_until_all_shares_confirm` in
`share.rs`, `confirmation_stays_bound_to_the_wallet_that_started_tracking`,
`confirmation_does_not_apply_to_a_replaced_share_generation`,
`initial_delivery_stays_bound_to_its_starting_wallet`,
`initial_delivery_rejects_a_replaced_share_generation`, and
`initial_delivery_does_not_recreate_share_after_recovery_cleanup`,
`interrupted_retry_does_not_resolve_a_replaced_share_generation` in
`share_tracking/tests`,
`public_vote_writers_reserve_before_validation_and_wait_on_contention`
in `storage/operations.rs` for public submission and VC-position writes, and
`helper_share_writers_reserve_before_validation_and_reject_stale_intent` in
`storage/operations.rs` for share recording, confirmation, and server updates,
`record_derives_share_identity_after_reserving_wal_writer` in `share.rs` for
recovery-identity derivation under the same reservation,
`record_rejects_recovery_for_a_different_proposal` in `share.rs` for binding
the embedded recovery proposal to the durable key,
`wrong_nullifier_generation_cannot_apply_any_delivery_transition` in
`share_tracking/tests/initial_delivery.rs` for identity-bound confirmation and
placement updates, and
`changed_choice_ignores_stale_share_confirmations` and
`skipped_intent_clears_and_blocks_stale_share_rows` in `session.rs`.

### Configuration and migration

The effective target is capped to both the protocol target cap `C = 10` and the
current valid configured fleet size. Persisted accepted or ambiguous helpers
removed from configuration are neither polled nor counted. A durable target
above `C` remains historical data but cannot drive additional placement above
the protocol cap. If a legacy row has `target_count = 0`, tracking derives
`min(ceil(N / 2), C)` from the current helper set.

During a pending vote, fleet contraction clamps the effective target and
replenishes among the remaining helpers where possible. Fleet expansion can
repair an unmet durable target but does not by itself increase a nonzero
target. Removed helpers may retain shares, so churn can increase the lifetime
set of helpers that possessed a share; liveness remains best-effort within the
reachable fleet and recovery cutoff.

Schema version 16 adds `ambiguous_urls` and `attempting_urls` with default `[]`
and `target_count` with default `0`. Databases from launch schema version 13
onward migrate in place; the migration MUST preserve existing round and
delivery rows. A schema newer than the crate supports is rejected.

Schema version 17 adds `helper_share_plans`. Its composite key and foreign key
match the owning vote, and deleting the vote cascades to its plan. The row
stores the exact `commitment_bundle_json` generation, canonical configured
fleet, complete plan vector, format version, placement guarantee, and creation
time. Any true recovery-generation replacement, clearing, or unrelated
recovery-material edit deletes the plan.

Confirmation is the sole snapshot transition that preserves a plan. On the
first `vc_tree_position: NULL -> non-NULL` vote update, the v17 trigger updates
a plan only when it is bound to the exact OLD JSON and replacing only the
JSON's `vc_tree_position` yields the exact NEW JSON. It then deletes any plan
whose snapshot still differs. Singleton and atomic-batch confirmation perform
this transition inside their existing transaction. Runtime loading requires
the plan and submitting handle to match that exact new snapshot. The
pre-confirmation handle becomes stale and must be recovered again. Every other
handle snapshot is also stale, including a same-commitment recovery
replacement.

The internal record keeps `attempting_urls` distinct. The compatibility wire
view has no separate attempting field, so it merges those helpers into
`ambiguous_urls`. Older hosts therefore retain the required poll-only behavior
without learning a new state or making an interrupted POST eligible again.

Persisted helper URLs from older code are canonicalized when read. Legacy
identities that no longer satisfy helper URL rules are never contacted,
polled, or counted, and never make a round unreadable — but they are recorded
delivery history, so every rewrite of a delivery list preserves them
verbatim rather than silently erasing them.

Enforcement:
[`migrations.rs`](../zcash_voting/src/storage/migrations.rs),
[`001_init.sql`](../zcash_voting/src/storage/migrations/001_init.sql), and
`partition_stored_helper_urls` in
[`storage/queries/share_delegations.rs`](../zcash_voting/src/storage/queries/share_delegations.rs).

Regression tests: `migrate_from_launch_version_preserves_delegation_state`,
`migrate_v16_to_v17_installs_plan_lifecycle_invariants`,
`fresh_schema_enforces_plan_lifecycle_invariants`,
`migrate_from_launch_version_matches_a_fresh_schema`,
`incremental_migrations_form_an_unbroken_chain_to_current`,
`test_migrate_rejects_newer_database_version`,
`persisted_desired_target_replenishes_when_the_fleet_expands`,
`legacy_target_above_protocol_cap_is_effectively_clamped`,
`share_delegation_view_treats_attempting_helpers_as_ambiguous`, and
`test_share_delegation_lifecycle`. Confirmation synchronization is covered by
`records_vote_confirmation_atomically`,
`records_vote_batch_confirmation_replay_and_helper_positions`, and
`preconfirmation_plan_survives_confirmation_restart_and_submission`.

### Recovery cleanup

Explicit recovery cleanup removes share-delivery rows and retryable,
unconfirmed vote recovery artifacts. It preserves ballot intent, confirmed
vote positions, and imported delegation capabilities. Full round deletion is
a separate operation.

Enforcement:
[`recovery::clear`](../zcash_voting/src/recovery.rs) and
`clear_recovery_state` in
[`storage/queries/mod.rs`](../zcash_voting/src/storage/queries/mod.rs).

Regression tests:
`clear_preserves_recorded_positions_and_resets_unconfirmed_votes` and
`test_clear_recovery_state_resets_vote_recovery`, plus
`initial_delivery_does_not_recreate_share_after_recovery_cleanup` for cleanup
racing active helper delivery.

## Helper identity and payload invariants

Configured helper bases:

- MUST use HTTP or HTTPS;
- MUST NOT contain credentials, a query, or a fragment;
- may contain a mount path or non-default port;
- have default ports and trailing slashes removed; and
- are canonicalized before identity, placement, and persistence comparisons.

Every endpoint appends `/shielded-vote/v1` after any configured mount path.
Round IDs accepted by the client are 64 hexadecimal characters or base64 that
decodes to exactly 32 bytes; the bytes must encode a canonical Pallas
base-field element. Share IDs in status paths are exactly 64 hexadecimal
characters. Both are normalized to lowercase hexadecimal.

Direct POST APIs require the closed `VoteShareWire` schema. They reject unknown
or duplicate fields, bodies larger than 4096 bytes, noncanonical encodings,
unsafe integer values, and invalid round identity, proposal, option, share,
tree-position, or `submit_at` fields, then canonically reserialize the body
before dispatch. Crate-generated payloads additionally validate their
relationship to persisted recovery material. One helper request contains only
the selected encrypted share, never the complete `all_enc_shares` collection.

Enforcement:
[`helper/url.rs`](../zcash_voting/src/helper/url.rs),
[`helper/client.rs`](../zcash_voting/src/helper/client.rs),
[`wire_codec.rs`](../zcash_voting/src/wire_codec.rs), and
[`share.rs`](../zcash_voting/src/share.rs).

## Host responsibilities and trust boundaries

The crate cannot enforce the following properties without cooperation from the
host wallet:

1. **Network route.** The host owns `HelperTransport`. A Tor or proxy transport
   MUST fail closed and MUST NOT fall back to a direct connection. A host can
   inject route-aware I/O into `HyperTransport::with_http_connector`, but it
   remains responsible for invalidating pooled connections when their route is
   no longer allowed.
2. **Transport contract.** A custom transport MUST preserve route policy,
   classify definitely pre-dispatch failures separately from ambiguous
   failures, and return response content-type metadata. The client enforces
   complete-request deadlines, the 256 KiB response limit, and JSON content
   type around every transport implementation.
3. **Entropy.** The SDK owns production entropy for complete-plan timing and
   helper ordering. Hosts do not supply randomness to the planning lifecycle.
4. **Lifecycle.** The host owns the timer, app-lock and round-expiry behavior,
   invokes `track_pending_shares`, and supplies cancellation.
5. **Initial delivery invocation.** The host obtains `HelperFleetPreflight`
   from the SDK, calls
   `prepare_share_delivery` with the complete proposal roster from the
   authenticated round configuration, and waits for chain confirmation when
   necessary. It then recovers a fresh `CommittedVote` and calls
   `submit_prepared_shares`. It supplies the complete current configured fleet
   and cancellation signal. The SDK validates the stored plan against its
   original planning fleet while limiting delivery to that current fleet. The
   host does not select the immediate share, serialize plans, select helpers,
   derive targets, expose share payloads, filter missing shares, or replan
   after restart.
6. **Helper-operator trust.** The protocol assumes that the authority supplying
   the wallet's helper configuration is trusted to choose independent operators
   and govern changes. URLs are endpoint identities, not authenticated operator
   identities, so helper counts are not Sybil-resistant. Configuration churn
   can expose shares to new operators, and shrinking to one helper lowers the
   confirmation requirement to one response. Pinned keys, authenticated
   per-round rosters, fixed minimum quorums, and key-rotation rules are outside
   the current protocol.
7. **Confirmation trust.** Helper responses are not chain proofs. The crate
   treats two matching responses from distinct currently configured helpers as
   the trusted quorum and persists confirmation internally. The host does not
   poll, corroborate, or confirm shares separately.
8. **Immediate-share lifecycle.** The host MUST wait until proposal choices
   are terminal before consuming the derived immediate-share designation.
   Incremental submission can otherwise observe a provisional designation.

### Exported policy values versus enforced behavior

`share_server_selection_policy` describes a two-second preflight soft window,
a 30-second hard deadline, and 16 concurrent POSTs.
`HelperClient::preflight_fleet` enforces both windows and derives the readiness
target internally. `CommittedVote::submit_prepared_shares` enforces the
process-wide 16-POST ceiling with a shared semaphore. Complete-plan persistence
lets the SDK validate commitment-wide quota, current-fleet compatibility, and
restart reuse before network dispatch. These are enforced behavior, not host
integration metadata.

`SHARE_STATUS_MAX_CONCURRENT_POLLS` and
`SHARE_STATUS_POLL_BUDGET_MILLISECONDS` are enforced tracker behavior, not
descriptive metadata. `poll_share_helpers` limits each share to four in-flight
status requests and ten seconds of quorum search even when a configured
per-request timeout or retry sequence would run longer.

`HelperFleetPreflight`, complete-plan preparation, batch submission, and
tracking reject an empty fleet, invalid URLs, and distinct spellings of one
canonical identity with `InvalidInput` before storage or network effects.
Hosts remain responsible only for supplying the configured list from an
authenticated configuration source.

## Reviewer checklist

A change to helper submission or recovery should answer all of the following:

- Does every share still apply the independent protocol target cap `C`?
- Does the strict three-quarters assignment limit remain derived from `S`, and is
  minimum planning-pool capacity still calculated from `S`, `T`, and `M`?
- Does every complete normal batch assign each helper no more than
  `floor(3S / 4)` shares, except for the documented one-helper case?
- Is the complete plan persisted before every POST and reused unchanged after
  restart?
- Is `LegacyBestEffort` confined to metadata for preexisting delivery rows?
- Does the change preserve independent CSPRNG timing and helper ordering?
- Can `single_share = true` reach planning with any payload count other than
  exactly one?
- Can an ambiguous POST be repeated against the same helper outside the
  deliberate, duplicate-safe overdue retry?
- Can an invalid configured helper URL disappear silently instead of failing
  the entry point?
- Is every initial and recovery helper reserved durably before dispatch?
- Can overlapping initial and tracking operations for one share independently
  advance beyond its placement target?
- Are accepted, ambiguous, and attempting states separated and disjoint?
- Is every recovery outcome resolved durably before another helper is
  contacted?
- Does early replenishment preserve `submit_at`, and does overdue recovery use
  zero?
- Is the vote-end cutoff checked before every recovery POST?
- Can a definite failure repeat more than once in one tracking pass?
- Can an unconfigured, invalid, or ambiguous helper be contacted?
- Are complete-request and total-delivery timeouts still bounded?
- Is status polling still bounded to four concurrent requests and ten seconds
  per share?
- Can a stalled share prevent later durable shares from being processed?
- Are quorum and caller-cancellation aborts unscored while status-budget expiry
  degrades each genuinely aborted request exactly once without re-scoring a
  boundary completion?
- Does cancellation avoid starting additional work without erasing completed
  effects?
- Can cancellation interrupt a wait for the per-share operation lock?
- Is the trust placed in a helper `confirmed` response still explicit?
- Do schema and wire changes preserve legacy rows and safe helper identity?
- Are readiness, status, per-share timeout, and the process-wide 16-POST limit
  still enforced by their SDK entry points?
