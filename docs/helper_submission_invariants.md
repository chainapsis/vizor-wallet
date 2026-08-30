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
  validated fleet, initial fan-out, polling, and recovery implemented in
  [`configured_fleet.rs`](../zcash_voting/src/share_tracking/configured_fleet.rs),
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
threshold. For a complete normal commitment planned as one batch with at least
two configured helpers, an adversary controlling that threshold together with
one helper can obtain at most 12 of the 16 plaintext shares from that helper's
returned initial target assignments.

This is a 75-percent share-count bound, not necessarily a bound on the
percentage of voting balance revealed. It is an initial-planning statement,
not a lifetime possession bound: ambiguous delivery, initial-delivery
fallback, replenishment, overdue recovery, fleet changes, incomplete or
independently planned batches, and single-share mode fall outside it. The
statement also makes no claim about the combined view of colluding helpers.

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
restart it is treated as outcome-unknown and remains poll-only.

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

overdue only: ambiguous_urls or attempting_urls --> duplicate-safe re-POST
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

A helper in either outcome-unknown set is poll-only for early replenishment.
Overdue recovery, which is liveness-critical, MAY re-POST an outcome-unknown
helper — after every untried helper and at most once per tracking pass —
because helper-side duplicate detection (`duplicate` is a definite acceptance)
makes the re-POST converge instead of double-counting. A definite acceptance
of the re-POST moves the helper to `sent_to_urls`; a definite failure of the
re-POST says nothing about the original POST and leaves the outcome-unknown
state in place.

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

The normal protocol MUST have `S >= 2`. Single-share mode is a separate mode;
it does not change `S` and is exempt from the commitment-wide distribution
bound below. `C = 10` is an independent protocol choice: it bounds initial
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
- incomplete batches and independently planned shares have no
  commitment-wide usage history and therefore provide no percentage bound;
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
- incomplete or independently planned batches do not advertise the complete
  batch guarantee;
- fallback and recovery remain able to exceed the initial-only quota; and
- `legacy_target_above_protocol_cap_is_effectively_clamped` ensures a durable
  target above the protocol cap cannot drive new placements above the
  canonical target.

### Share count and identity

1. A normal vote commitment contains 16 encrypted shares. Single-share mode
   emits only domain share index 0.
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
   single-share planning can assign `submit_at = 0` to undesignated shares.

Enforcement:
[`round_immediate_share_key`](../zcash_voting/src/share_policy/initial_placement.rs)
and
[`plan_share_submissions`](../zcash_voting/src/share_policy/initial_placement.rs).

Regression tests:
`round_immediate_share_key_uses_highest_bundle_lowest_voted_proposal_and_share_zero`,
`immediate_batch_position_stays_aligned_and_does_not_perturb_other_plan`,
`immediate_marker_is_distinct_when_all_shares_submit_immediately`, and the
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

An empty helper list is invalid for initial planning even though the pure
target-count function returns zero. Exactly duplicated input URL strings are
also invalid because placement is intended to count distinct endpoints. The
planner itself checks exact strings; it does not parse or canonicalize URLs, so
the host MUST canonicalize and validate helper identities before planning.
`canonicalize_helper_base_url` and `canonical_helper_url_list` are exported
for exactly that purpose.

The delivery and tracking entry points enforce the stronger trust-boundary
contract through `ConfiguredHelperFleet`: `submit_share_to_helpers` and
`track_pending_shares` reject empty fleets, URLs that fail canonicalization,
and distinct spellings that canonicalize to the same helper identity with
`InvalidInput` before any storage or network effect. Misconfiguration must
surface as an error; configured entries are never silently dropped or
collapsed.

Planning clamps an explicitly requested target to the available list. The
crate-private raw fan-out routine preserves its caller's requested target in
the durable report, but the public typed delivery boundary admits only a
validated `ConfiguredHelperFleet`.

`target_count` is a target for definite acceptances, not an upper bound on the
number of helpers that may physically hold a share. An ambiguous helper may
have accepted the POST, while recovery must still obtain enough definite
acceptances. Recovery can therefore cause more than `target_count` helpers to
hold the same share.

Enforcement:
[`share_submission_target_count`](../zcash_voting/src/share_policy/server_order.rs),
`require_share_servers` in
[`share_policy/initial_placement.rs`](../zcash_voting/src/share_policy/initial_placement.rs),
and `ConfiguredHelperFleet` plus `submit_share_to_helpers` in
[`share_tracking/configured_fleet.rs`](../zcash_voting/src/share_tracking/configured_fleet.rs)
and
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

### Helper selection and balancing

1. Production planning MUST use CSPRNG entropy supplied by the host. Helper
   order uses a Fisher-Yates shuffle with eight bytes per shuffle step.
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
7. Plans remain positionally aligned with their input shares. The immediate
   index passed to the batch planner is a batch position, not a domain share
   index.
8. The commitment-wide bound applies only when all `S` shares are planned in
   one batch. Single-share mode and incomplete or independently planned
   batches do not claim it.

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

`HelperClient::preflight` canonicalizes the caller's list, starts every valid
probe concurrently, and takes the readiness `target_count` explicitly. It
collects responses through the two-second soft window. If the target is still
unmet, pending probes remain alive until enough helpers are ready, every probe
finishes, or the shared 30-second hard deadline expires. If the target is met
before the soft boundary, pending probes are stopped at that boundary; a zero
target still produces the ordered canonicalized result list but returns before
creating the probe task set, so it opens no connections even on a multi-threaded
runtime. Probes are not retried. Results preserve caller order, use canonical
spellings for valid URLs, and report invalid or unfinished entries as not ready.

### Default limits

| Operation or limit | Default | Enforced by |
| --- | ---: | --- |
| Initial readiness window | 2 seconds (from `SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS`) | `HelperClient::preflight` |
| Absolute readiness deadline | 30 seconds (from `SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS`) | `HelperClient::preflight` |
| One status GET | 5 seconds | `HelperClient::share_status` |
| Concurrent status GETs per share | 4 (from `SHARE_STATUS_MAX_CONCURRENT_POLLS`) | `poll_share_helpers` |
| Total status quorum search for one share | 10 seconds (from `SHARE_STATUS_POLL_BUDGET_MILLISECONDS`) | `poll_share_helpers` |
| One helper POST | 30 seconds | `HelperClient` |
| Total initial fan-out | 60 seconds | `submit_share_to_helpers` |
| Minimum budget to start an initial POST | 1 second | `submit_share_to_helpers` |
| Retry backoffs | 200 ms, then 600 ms | `HelperClient::with_retry` |
| Accepted response body | 256 KiB | `HelperClient` and `HyperTransport` |
| Ready-share poll interval | 15 seconds | `next_tracking_delay_seconds` |
| Recovery cutoff | 10 seconds before vote end | `track_pending_shares` |

The timeout passed to a `HelperTransport` covers connection setup, response
headers, and the complete response body. `HelperClient` wraps every transport
future in that deadline and rejects responses larger than 256 KiB, so these
limits also hold when a custom transport ignores the supplied timeout or
buffers an oversized response. `HyperTransport` additionally enforces both
while streaming. Successful responses MUST carry `application/json` (optional
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
| `GET /share-status/{round_id}/{share_id}` | Up to 3 | Retry transient failures, including ambiguous transport failures |
| Initial `POST /shares` | Up to 3 | Retry only definite transient failures |
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
| Malformed caller-supplied JSON | Local definite failure | No request |

Malformed caller JSON is rejected before the submission enters the scored
network path. It therefore performs no request and does not increment or clear
the selected helper's health state.

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

`CommittedVote::submit_share_to_helpers` accepts only a committed share index,
a planner-produced `ShareSubmissionPlan`, the complete configured fleet, and
the current health-ordering time. It derives the round, bundle, proposal,
payload, confirmed VC-tree position, target, and schedule from the committed
vote and durable confirmation state. It rejects an empty, duplicated, or
noncanonical fleet, a plan that does not exactly match that fleet, or a missing
confirmed VC position before touching storage or the network. The raw
journaled submission routine is crate-private, and there is no public
post-hoc delivery mutator.

The `test-fixtures` feature exposes hidden `share::record` and
`share::record_delivery_fixture` seed helpers for external integration tests.
They do not exist in production builds and MUST NOT be used to model wallet
submission behavior.

After validation it creates or merges the durable share record. Planned
targets are attempted first, followed by the remaining configured fleet.
Health ranking is applied independently within those groups, so a healthy
fallback never moves ahead of a degraded planned target. For every selected
helper it writes
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
state that has already been journaled; the tracker is responsible for
repairing any remaining deficit.

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
`failed_outcome_write_leaves_attempting_marker`, and
`failed_attempt_write_prevents_network_dispatch`. Typed-boundary coverage is
provided by
`committed_vote_submission_keeps_degraded_planned_target_before_healthy_fallback`,
`repeated_committed_submission_preserves_the_original_schedule`,
`committed_vote_submission_rejects_mismatched_plan_before_side_effects`, and
`invalid_candidate_url_does_not_create_a_share_record`.

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
- `track_pending_shares` is the only public confirmation mutation path. The
  raw storage transition is crate-private so supported integrations cannot
  bypass the configured-fleet quorum.
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
`stalled_status_poll_does_not_starve_a_later_share`,
`cancellation_aborts_bounded_in_flight_status_polls`,
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
3. When the ten-second status budget expires, the tracker records one failure
   for each helper whose request is still in flight. Quorum and caller
   cancellation abort outstanding tasks without charging the abort itself as a
   helper failure.
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
`stalled_status_poll_does_not_starve_a_later_share`. Local submission
validation is covered by `invalid_share_bodies_are_not_sent_or_scored`.

## Recovery invariants

For each unconfirmed share, `track_pending_shares` computes timing and current
definite placement from the intersection of durable state and the currently
configured helper set.

### Replenishment and ordering

1. Under-placement starts replenishment immediately; it does not wait for the
   share to become status-checkable or overdue.
2. Early replenishment preserves the durable `submit_at` and considers only
   helpers that have not definitely accepted the share.
3. Overdue recovery rebuilds the payload with `submit_at = 0`. It tries
   untried helpers first, then outcome-unknown helpers, then previously
   accepted helpers. Outcome-unknown and accepted retries rely on their
   existing durable history instead of trying to add a fresh attempt marker.
4. The untried and previously accepted groups are independently randomized
   from host-supplied CSPRNG bytes. The outcome-unknown retry group is a
   deterministic last resort whose membership is already persisted; health
   ordering is applied within every group.
5. An ambiguous helper stays poll-only for early replenishment. Overdue
   recovery re-POSTs it at most once per pass; a definite acceptance
   (including `duplicate`) moves it to `sent_to_urls`, while a definite
   failure of the re-POST leaves the outcome-unknown state untouched because
   it says nothing about the original POST.
6. A definite failure is attempted at most once in one tracking pass. It can
   become eligible again in a later pass.
7. One pass continues until it fills the complete definite-placement deficit
   or has no eligible helper that accepts.
8. Recovery may use any configured helper for liveness; initial balancing is
   not a recovery cap.

Regression tests: `under_placed_share_preserves_delayed_submit_at`,
`overdue_share_reaches_an_untried_helper_and_records_it`,
`one_tracking_pass_fills_the_complete_placement_deficit`,
`early_replenishment_never_reposts_to_an_accepted_helper`,
`one_tracking_pass_does_not_repeat_a_definite_failure`,
`a_definite_failure_is_eligible_again_on_a_later_pass`,
`early_replenishment_excludes_ambiguous_helpers`,
`overdue_recovery_retries_ambiguous_helper_after_untried`,
`overdue_recovery_reposts_to_accepted_helper_after_untried_helpers_fail`,
`ambiguous_accepted_helper_retry_preserves_the_stronger_delivery_state`,
`small_fleet_all_ambiguous_still_recovers`, and
`ambiguous_repost_failure_keeps_ambiguous_state` in
[`share_tracking/tests/recovery.rs`](../zcash_voting/src/share_tracking/tests/recovery.rs).

### Durability and cutoff

Before dispatching any initial or recovery POST, the helper MUST be durably
journaled: a fresh target is added to `attempting_urls`, while an overdue
re-POST to an outcome-unknown or accepted helper relies on its already-
persisted delivery history. A definite acceptance moves the helper to
`sent_to_urls`; an ambiguous result moves a fresh helper to `ambiguous_urls`;
and a definite failure of a fresh attempt removes the reservation so the
helper can be retried in a later pass. A definite failure of an overdue
outcome-unknown re-POST leaves that earlier unknown state in place, while a
failure of an accepted fallback leaves the earlier acceptance intact. Each
transition is persisted before the workflow contacts another helper.

A process interruption during an in-flight initial or recovery request leaves
the helper in `attempting_urls`. On restart, that state is exposed as
outcome-unknown: poll-only for early replenishment, with any further POST
deferred to the deliberate, duplicate-safe overdue retry above. A failed
outcome write has the same conservative behavior: the attempting marker
remains rather than making the helper eligible for a fresh reservation.

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
reported as unrecoverable rather than retried across helpers.

Enforcement:
[`helper_recovery_material`](../zcash_voting/src/recovery.rs) and
`resubmit_to_next_helper` in
[`share_tracking/recovery.rs`](../zcash_voting/src/share_tracking/recovery.rs).

Regression tests: `missing_recovery_material_is_reported_not_retried` and
`resubmission_waits_for_the_confirmed_vc_position`.

### Cancellation

The cancellation callback is checked between shares, POST targets, attempts,
and retry backoffs. While concurrent status tasks are pending, the tracker also
checks it on a 50-millisecond interval. Cancellation prevents additional
requests from starting, returns the effects already recorded, sets
`ShareTrackingReport::cancelled`, and is not charged to helper health when it
suppresses pending work. Once the final observed request has completed, its
result takes precedence: cancellation observed afterward does not replace that
result or suppress its health score.

The concurrent status poller responds to caller cancellation, confirmation
quorum, or its ten-second budget by signalling its status clients and aborting
the task set. This drops in-flight status transport futures instead of waiting
for their individual request timeouts. Outside that poller, cancellation does
not generally interrupt an already-running custom transport request because
`HelperTransport` does not receive the callback. Initial fan-out's outer
60-second deadline can additionally drop the in-flight POST future; that
result is treated as ambiguous.

Regression tests: `cancellation_aborts_bounded_in_flight_status_polls`,
`cancelled_pass_reports_cancellation_and_keeps_durable_effects`,
`cancellation_before_request_is_not_scored`,
`late_cancellation_does_not_replace_final_failed_poll`, and
`late_cancellation_does_not_replace_final_failed_resubmission`.

## Persistence and compatibility invariants

### Durable record semantics

1. The persisted key is wallet, round, bundle, proposal, and share index.
2. The share nullifier is derived from persisted recovery material rather than
   accepted from a wallet caller. Re-recording the key with a different
   nullifier fails.
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

Enforcement:
[`share.rs`](../zcash_voting/src/share.rs),
[`storage/operations.rs`](../zcash_voting/src/storage/operations.rs), and
[`storage/queries/share_delegations.rs`](../zcash_voting/src/storage/queries/share_delegations.rs).

Regression coverage: `test_share_delegation_lifecycle` in
`storage/operations.rs`,
`pending_rounds_return_session_context_until_all_shares_confirm` in
`share.rs`, and `changed_choice_ignores_stale_share_confirmations` and
`skipped_intent_clears_and_blocks_stale_share_rows` in `session.rs`.

### Configuration and migration

The effective target is capped to both the protocol target cap `C = 10` and the
current valid configured fleet size. Persisted accepted or ambiguous helpers
removed from configuration are neither polled nor counted. A durable target
above `C` remains historical data but cannot drive additional placement above
the protocol cap. If a legacy row has `target_count = 0`, tracking derives
`min(ceil(N / 2), C)` from the current helper set.

Schema version 16 adds `ambiguous_urls` and `attempting_urls` with default `[]`
and `target_count` with default `0`. Databases from launch schema version 13
onward migrate in place; the migration MUST preserve existing round and
delivery rows. A schema newer than the crate supports is rejected.

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
`incremental_migrations_form_an_unbroken_chain_to_current`,
`test_migrate_rejects_newer_database_version`,
`persisted_desired_target_replenishes_when_the_fleet_expands`,
`legacy_target_above_protocol_cap_is_effectively_clamped`,
`share_delegation_view_treats_attempting_helpers_as_ambiguous`, and
`test_share_delegation_lifecycle`.

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
`test_clear_recovery_state_resets_vote_recovery`.

## Helper identity and payload invariants

Configured helper bases:

- MUST use HTTP or HTTPS;
- MUST NOT contain credentials, a query, or a fragment;
- may contain a mount path or non-default port;
- have default ports and trailing slashes removed; and
- are canonicalized before identity, placement, and persistence comparisons.

Every endpoint appends `/shielded-vote/v1` after any configured mount path.
Round IDs accepted by the client are 64 hexadecimal characters or base64 that
decodes to exactly 32 bytes. Share IDs in status paths are nonempty
hexadecimal. Both are normalized to lowercase hexadecimal.

Direct POST APIs validate that a supplied body is JSON, but do not
schema-validate arbitrary caller JSON. Crate-generated payloads additionally
validate round identity, proposal and option fields, share lengths and indexes,
tree position, `submit_at`, and the relationship to persisted recovery
material. One helper request contains only the selected encrypted share, never
the complete `all_enc_shares` collection.

Enforcement:
[`helper/url.rs`](../zcash_voting/src/helper/url.rs),
[`helper/client.rs`](../zcash_voting/src/helper/client.rs),
[`wire_codec.rs`](../zcash_voting/src/wire_codec.rs), and
[`share.rs`](../zcash_voting/src/share.rs).

## Host responsibilities and trust boundaries

The crate cannot enforce the following properties without cooperation from the
host wallet:

1. **Network route.** The host owns `HelperTransport`. A Tor or proxy transport
   MUST fail closed and MUST NOT fall back to a direct connection.
2. **Transport contract.** A custom transport MUST preserve route policy,
   classify definitely pre-dispatch failures separately from ambiguous
   failures, and return response content-type metadata. The client enforces
   complete-request deadlines, the 256 KiB response limit, and JSON content
   type around every transport implementation.
3. **Entropy.** Production hosts MUST supply fresh CSPRNG bytes for every
   timing and ordering input. `os_random_bytes` is provided for Rust hosts.
4. **Lifecycle.** The host owns the timer, app-lock and round-expiry behavior,
   invokes `track_pending_shares`, and supplies cancellation.
5. **Initial identity.** The host MUST retain the `CommittedVote`, pass the
   exact planner-produced plan and complete configured fleet, and call its
   typed `submit_share_to_helpers` method. The crate derives the durable
   identity and wire payload and journals every POST before dispatch.
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

`share_server_selection_policy` exports a two-second preflight soft window, a
30-second preflight hard deadline, and a maximum of 16 concurrent POSTs.
`HelperClient::preflight` enforces both readiness windows and the caller-supplied
target: it starts all probes concurrently, waits through the soft window, and
keeps slower probes alive through the hard window only when the target remains
unmet.

The maximum concurrent POST count remains policy metadata:
`submit_share_to_helpers` is sequential. A host that implements concurrent
initial delivery MUST still preserve all target, timeout, ambiguity,
distinct-helper, persistence, and routing invariants in this document.

`SHARE_STATUS_MAX_CONCURRENT_POLLS` and
`SHARE_STATUS_POLL_BUDGET_MILLISECONDS` are enforced tracker behavior, not
descriptive metadata. `poll_share_helpers` limits each share to four in-flight
status requests and ten seconds of quorum search even when a configured
per-request timeout or retry sequence would run longer.

The initial planner checks only for empty and exactly duplicated URL strings;
it does not parse or canonicalize helper endpoints. Hosts MUST canonicalize
their helper configuration before computing targets and plans, using the
exported `canonicalize_helper_base_url` / `canonical_helper_url_list`. The
delivery entry points independently construct `ConfiguredHelperFleet` and
reject an empty fleet, any URL that fails canonicalization, or distinct
spellings of one canonical identity with `InvalidInput` before storage or
network effects.

## Reviewer checklist

A change to helper submission or recovery should answer all of the following:

- Does every share still apply the independent protocol target cap `C`?
- Does the strict three-quarters assignment limit remain derived from `S`, and is
  minimum planning-pool capacity still calculated from `S`, `T`, and `M`?
- Does every complete normal batch assign each helper no more than
  `floor(3S / 4)` shares, except for the documented one-helper case?
- Does the change preserve independent CSPRNG timing and helper ordering?
- Can an ambiguous POST be repeated against the same helper outside the
  deliberate, duplicate-safe overdue retry?
- Can an invalid configured helper URL disappear silently instead of failing
  the entry point?
- Is every initial and recovery helper reserved durably before dispatch?
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
  degrades helpers whose requests remain in flight?
- Does cancellation avoid starting additional work without erasing completed
  effects?
- Is the trust placed in a helper `confirmed` response still explicit?
- Do schema and wire changes preserve legacy rows and safe helper identity?
- Are exported policy values correctly distinguished between readiness and
  status limits enforced by the crate and the concurrent-POST limit that
  remains host integration metadata?
