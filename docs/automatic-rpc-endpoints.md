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
birthday heights are sent to candidates.

Direct selection has a 6-second total network budget, 3-second per-candidate
budget, and at most four concurrent candidates. Tor uses 15 seconds, 8 seconds,
and two candidates. Once a valid candidate finishes, the batch waits at most
250 milliseconds for comparison results, then drops outstanding candidate
futures. Native runtime cleanup uses the existing bounded two-second shutdown
grace so a stuck OS DNS resolver cannot retain a bridge worker indefinitely. Rust owns the native timeouts and cancellation. Dart also bounds time spent
waiting for a bridge worker and synchronously cancels on expiry. A synchronous
reservation before dispatch retains cancellation until a queued worker consumes
it, with bounded outstanding reservations providing backpressure. The budgets begin after route readiness, not
while Tor is bootstrapping. Tor failures remain route failures and never permit
a direct fallback. These are initial policy values rather than measured global
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
worked on the selected route. A success within five minutes and a network-name
verification within twelve hours permit the bounded warm read. The real first
`GetLatestBlock` runs directly against that server, with no selection-only
`GetLightdInfo`. Generic operations still await this public read before consuming
proposals or entering their native network operation. Concurrent first readers
share one read. Native tip caching also lets subsequent transaction preparation
reuse the tip under the existing fifteen-second native cache policy.

The warm read has a 750ms direct / 2s Tor wall budget, including bridge queue time.
If it fails or is too slow, the failed host is excluded and regular selection
uses the remainder of the same six-/fifteen-second total budget. Only this public
read is retried; transaction submission, durable operation leases and ambiguous
broadcast handling keep their existing contracts.

A freshly selected server already supplied a tip during its probe. The first
preflight can consume that live result once, within five seconds and only for
the same endpoint, route and cancellation epoch. A warm read can likewise supply
the tip to its waiting preflight. Later sequential reads are fresh. Cancellation
always drops both the reusable tip and any in-flight-read admission pointer.

Lock and mobile backgrounding stop native selection work and advance its epoch,
but retain recent public server health. After unlock/foreground the existing tip
read performs bounded verification; a fresh peer check is not repeated merely
because the app was locked. Longer absences, expired evidence, preference and
route changes invalidate readiness. Reset pauses admission, drains cache writes,
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
short transient cancellation preserves previously corroborated public health.

A corroborated healthy selection is reused for 15 minutes. Periodic rechecks start
with the current server. Performance-only changes respect a five-minute minimum residence
and, when both candidates respond, require at least 150ms and 30% improvement.
Two slow successful tip reads (2s direct / 5s Tor) also request a recheck without
holding up the successful read. A failed exploratory recheck preserves a working
connection.

Transient network failures immediately exclude the attempted endpoint for one
minute and run another bounded selection. Complete selection failure backs off
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
