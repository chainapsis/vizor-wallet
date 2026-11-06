# Automatic lightwalletd selection

On mainnet, the saved `default-mainnet` choice means Automatic. The settings
choice is independent of the currently selected physical server. Existing
explicit presets and literal custom URLs retain their intent. `us-zec-stardust`
is the explicit manual US preset; a custom URL is never inferred to be Automatic.
Testnet and regtest keep their existing policies.

## Selection and routing

Network callers obtain an endpoint through
`rpcEndpointFailoverProvider.notifier.ensureReady()`, or use the existing
`runWithEndpointFallback` / `getLatestBlockHeight` wrappers. Local network-name
reads need no selection. A read of the settings provider or a settings widget
must not start a probe. Keep an obtained endpoint snapshot through the operation.
Do not restart or duplicate a transaction merely because another caller selected
a different server. Ledger's durable-operation lease and broadcast acknowledgement
rules remain in force.

The automatic pool is an explicit subset of the presets. Selection rotates the
candidate ordering and limits parallelism. A probe opens the same policy-aware
Rust channel used by foreground wallet traffic, then requests only
`GetLightdInfo` and `GetLatestBlock`. No addresses, transaction IDs, or wallet
birthday heights are sent to candidates. Automatic fallback lists, including
Gift Card capability checks, use this same eight-server pool. Claim checks remove
the actual current server and duplicate URLs; the preference's compatibility URL
does not remove an otherwise eligible US server. Explicit/manual and custom
capability fallback behavior stays unchanged.

Automatic accepts only positive-u32 tip heights (`1..0xffffffff`). Rust rejects
malformed results before they can start the first-success comparison window,
so slower or queued healthy candidates still get an attempt. Dart applies the
same range check before ranking, warm readiness and ordinary tip-read success.
Malformed warm replies use the existing bounded replacement path; ordinary
Automatic reads treat an invalid server height as a specific endpoint failure
without broadening the classifier for unrelated parse errors.

Direct selection has a 6-second total network budget, 3-second per-candidate
budget, and at most four concurrent candidates. Tor uses 15 seconds, 8 seconds,
and two candidates. Once a valid candidate finishes, the batch waits at most
250 milliseconds for comparison results, then drops outstanding candidate
futures. Each claimed selection runs on one owning thread with a single-thread
I/O runtime and at most eight blocking threads. Results return before runtime
cleanup, so stalled OS DNS never makes the caller wait for cleanup. The worker
retains its selection slot until the runtime and every running blocking lookup
have actually stopped. The sixteen-slot admission bound includes draining
workers as well as queued and active selections. Cancelling again cannot free a
slot whose OS lookup is still running; capacity returns when that lookup exits.

Capacity exhaustion is local backpressure shared by Direct and Tor selections.
It does not prove a server outage, add a host cooldown, or permit a direct
fallback. Automatic probing is limited while all slots are occupied. Normal
connection paths outside selection retain their existing runtime and resolver.
No extra metadata RPCs are introduced. Rust owns the native timeouts and
cancellation; Dart also bounds bridge queue time and synchronously cancels on
expiry. Synchronous reservation keeps that cancellation attached until a queued
worker consumes it. Network budgets begin after route readiness, not while Tor
is bootstrapping. These are initial policy values rather than measured global
service-level guarantees.

The optional cache is keyed by network and direct/Tor route. It stores the
selected preset and normalized physical URL, successful-request time, peer
validation time, full benchmark time, network-name verification time, and a
latency summary. It never stores a tip height for reuse after restart. Old
`preset`/`observedAt` records remain compatible as candidate hints, without
implying verified health. A changed preset URL also invalidates warm confidence.
Cache reads are bounded and errors do not prevent connectivity.

## Restart, unlock and foreground fast paths

This policy is region-independent: it reuses whichever server most recently
worked on the selected route. A success within five minutes, peer corroboration
within fifteen minutes, and network-name verification within twelve hours permit
the bounded warm read. Missing, expired, or future peer timestamps keep a cached
server as a candidate hint: it gets the normal bounded head start and a fresh
`GetLightdInfo` / `GetLatestBlock` probe before use. The same evidence requirements
apply to in-memory health retained over lock and foreground transitions.

For a trusted warm restore, the first `GetLatestBlock` runs directly against
that server, with no selection-only
`GetLightdInfo`. Generic operations still await this public read before consuming
proposals or entering their native network operation. Concurrent first readers
share one read. Selection and warm probes do not publish their responses to the
native transaction-tip cache. Transaction preparation can still reuse tips
recorded by ordinary sync/RPC reads under the existing fifteen-second policy;
without such an observation it performs its own public tip read. Each native
observation also carries the route generation captured before opening its
channel. A route change (including direct → Tor → direct) prevents reuse of
the previous generation. Late responses from an old route or a cancelled
sync/mempool task cannot publish to this cache or replace a current observation.
Reused transaction channels retain their original generation through authority
waits; pre-submission expiry checks reject a stale channel. These checks add no
RPCs to the same-route cache fast path. Native and Dart failover classifiers
exclude the canonical `network privacy blocked` errors before checking transport
words, so route changes, cancellation and Tor readiness do not cool down hosts.

The warm read adapts to the recent successful latency on the selected route.
Its deadline is three times that latency plus 500ms direct / one second Tor,
clamped to 1.5–4 seconds direct / 5–8 seconds Tor. Without a positive latency it
uses the route's lower bound. This wall budget includes bridge queue time and
never consumes more than two thirds of the total recovery budget.
If it fails or is too slow, the host is excluded from this recovery and regular
selection uses the remainder of the same six-/fifteen-second total budget. Only this public
read is retried; transaction submission, durable operation leases and ambiguous
broadcast handling keep their existing contracts.

A warm-read failure leaves host health unconfirmed and does not create the
one-minute host cooldown: it can originate in local runtime work, and native
probes may hide the underlying error. A subsequent selection can evaluate the
host again, and every recovery still requires a fresh successful sample.
Ordinary RPC failure recovery retains its existing cooldown policy.

A freshly selected server already supplied a tip during its probe. The first
preflight can consume that live result once, within five seconds and only for
the same endpoint, route and cancellation epoch. A warm read can likewise supply
the tip to its waiting preflight. Later sequential reads are fresh. Cancellation
always drops both the reusable tip and any in-flight-read admission pointer.

Lock and mobile backgrounding stop native selection work and advance its epoch,
but retain recent public server health. After unlock/foreground the existing tip
read performs bounded verification; peer corroboration that is still fresh
is reused after a short lock. Expired peer evidence on return takes the bounded
candidate-selection path before the operation. Longer absences, expired evidence,
preference and route changes invalidate readiness. Reset pauses admission, drains cache writes,
and removes both durable route records before destroying wallet storage.

Successful actual tip reads update only success time. They do not renew peer,
benchmark or network-name evidence. Independent peer confidence lasts fifteen
minutes; full network-name verification has its own twelve-hour ceiling. Cache
writes are serialized and ordinary successful-read writes are limited to once
per minute, while selection/corroboration records are persisted immediately.

These are request-count improvements, not measured global latency claims. With
a recently verified cache on either direct or Tor, the first tip/preflight makes
one `GetLatestBlock` call, zero candidate probes and zero selection-only
`GetLightdInfo` calls. If peer confidence is fresh, no immediate peer sweep is
needed. The same request-count contract applies after a short lock/foreground
cycle, with all stale-result and privacy-route guards still enforced.

## New-account birthday confirmation

`getCreationBirthdayHeight` requires a valid positive-u32 height from the
selected server. It reuses a selected observation no more than five seconds old
on the same network, route and cancellation epoch, or refreshes that server once.
No height evidence is restored from the durable route cache. Receipt timestamps
come from Rust immediately after each tip response, so an early response in a
long batch does not become fresh again at batch completion.

Peer comparison is best effort. If another distinct URL in the fixed public pool
has a fresh observation within two blocks of the selected height, the lower
height is preferred. A different operator is preferred among available matching
peers, but a regional peer under the same operator is sufficient. If a fresh
peer already disagrees, the selected height is used without further requests.
Otherwise, up to two peers race once, interleaving other-operator and same-operator
regions with the ordinary early-return probe. There are no further peer retries.

Disagreement, missing or invalid peer responses, timeout, and local worker or
capacity failures use the selected height and allow creation to continue. This
call retains its selected observation even if it ages beyond five seconds while
waiting for that optional comparison; it cannot then form a fresh matching pair
and is not reused by later calls after expiry. Failure does not confer peer
validation on the endpoint or change normal Automatic cache confidence.

The six-second direct or fifteen-second Tor wall budget starts after route
readiness and covers readiness, selected-height retrieval and optional peers.
Cancellation, lock, reset, disposal, preference or route changes (including native
privacy-blocked/cancelled signals) still abort. Failure to obtain a valid selected
height also aborts before account creation, existing DB replacement or secret
persistence. Concurrent callers share this operation; optional performance/peer
rechecks give way while it runs. Manual/custom choices retain their single-server
policy. Rust rejects zero or out-of-u32 birthdays for every mode instead of
truncating or underflowing them.

This policy accepts the selected public server's height when comparison is
inconclusive; it is not header-chain or consensus verification. The existing Rust
sync policy for adopting its own tip RPC into the wallet DB is separate from
this birthday and probe-cache boundary.

## Rechecks and failures

An isolated or legacy-cache winner is provisional until independent peers corroborate
its height. Background validation excludes the current server, so a very fast
but lagging winner cannot repeatedly cancel every slower freshness check. If
peers conflict, further distinct hosts are queried within the same validation
budget until heights corroborate or the candidates/budget are exhausted. Each
round excludes every host already observed; only an agreeing height cluster can
replace the current server for freshness. Unresolved checks retain the usable server and retry no more than
once a minute on subsequent network operations. No recurring timer is needed.
Lock, reset, and route changes cancel this work just like initial selection;
short transient cancellation preserves previously corroborated public health
while its evidence remains fresh. A start from an untrusted cache hint also
schedules the existing complete-pool comparison once after sync starts; a
trusted warm restore continues to skip that comparison.

A corroborated healthy selection is reused for 15 minutes. Periodic rechecks start
with the current server. Performance-only changes respect a five-minute minimum residence
and, when both candidates respond, require at least 150ms and 30% improvement.
Two slow successful tip reads (2s direct / 5s Tor) also request a recheck without
holding up the successful read. A failed exploratory recheck preserves a working
connection.

The one-shot full-pool pass distinguishes a latency improvement from a measured
height disagreement. If the current server replied outside a uniquely largest
height cluster (at least two distinct URLs within two blocks), the fastest member
of that cluster is recommended even when slower than the current server. Tied
or overlapping equally large clusters, missing current replies, and an absent
cluster remain inconclusive; they do not mark a host failed or add cooldowns.
This correction retains the active stream and applies at the next sync boundary.
The existing idle poll starts that next cycle even if the old server's tip has
stopped advancing, and repeated requests coalesce behind a still-open stream.
If an unowned native guard or an operation lease defers the start, periodic
polling remains active for another attempt without a recursive resume check.
A performance-only recommendation continues to use the 150ms / 30% thresholds.

A measured height disagreement removes the current route's peer confidence.
While a usable correction is pending, optional rechecks yield to it and single
successful reads preserve the saved replacement without extending its evidence.
A newer current tip that fits the winning cluster cancels the correction; peer
confidence then retains the comparison's original observation time. Observations
use actual receipt times (or the sweep's start when absent), including on
restart and application, rather than refreshing evidence at sweep completion.
The existing five-minute recommendation lifetime and route/epoch checks apply.
Lock, mobile background, preference changes, and reset revoke pending changes.
Normal starts and successful warm restores require no additional RPCs or timers.
This endpoint correction does not rewrite an already persisted wallet chain tip.

Transient failures of ordinary RPC operations exclude the attempted endpoint
for one minute and run another bounded selection. Complete selection failure backs off
from 5 to 60 seconds. A route change clears route-specific failure/backoff state.
Automatic mode never returns to a fixed US primary simply because it recovered.
Manual-preset failover and custom endpoint isolation retain their existing policy.

Candidates must report the expected chain. Height comparison rejects lagging
responses and, where peers agree, isolated high outliers. A lone success is
provisional: metadata comparison is a health heuristic, not independent chain
verification or a consensus protocol. Existing slow-height checks can require a
replacement to be ahead of the current server.

Ordinary compact-block downloads (also shared by background preparation) have
a body-only budget: 60 seconds plus
received encoded bytes at 4KiB/s, capped at five minutes. This bounds trickle
streams that evade the per-message idle timeout. The explicit slow-download
error bypasses repeated retries against the same endpoint, allowing Dart's
failover policy to choose a replacement. Incomplete batches are discarded and
the existing persisted scan ranges determine where the next sync resumes.
CPU scanning and database work do not count toward this receive budget. Gift
Card and other specialized collectors retain their existing budgets.

Settings changes, privacy-route changes, lock, mobile backgrounding, shutdown,
and reset cancel or invalidate outstanding selection results. Mobile follows
foreground-only process-work policy; hidden desktop windows retain desktop work
policy. Native background migration retains its saved URL and pinned direct
transport; it does not start this foreground selection workflow.

## Validation

Use fake candidate probes and stores for Dart policy/lifecycle tests. Rust tests
use local lightwalletd stubs and paused time to cover bounded parallelism, total
budgets, cancellation, route transitions, wrong-network candidates, dropping
outstanding futures, and sustained trickle streams. Keep both Flutter token
lanes passing. Heavy regtest E2E runs remain explicitly opt-in under AGENTS.md.
Global validation should compare connection-ready and failover p95/p99 times,
compact-block throughput, and the number of probes and switches per session.
