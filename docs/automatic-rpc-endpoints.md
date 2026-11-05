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

The optional 12-hour cache is keyed by network and direct/Tor route. A cached
candidate gets a short verification attempt (750ms direct, 2s Tor) deducted from
the total budget, before the rest of the pool is measured. Cache reads are
bounded and cache errors do not block connectivity. The existing wallet store
holds preset ID and observation time only. Reset cancels selection, drains cache
writes, and clears both route records before destroying wallet storage.

## Rechecks and failures

An isolated or cached winner is provisional until independent peers corroborate
its height. Background validation excludes the current server, so a very fast
but lagging winner cannot repeatedly cancel every slower freshness check. If
peers conflict, further distinct hosts are queried within the same validation
budget until heights corroborate or the candidates/budget are exhausted. Each
round excludes every host already observed; only an agreeing height cluster can
replace the current server for freshness. Unresolved checks retain the usable server and retry no more than
once a minute on subsequent network operations. No recurring timer is needed.
Lock, reset, and route changes cancel this work just like initial selection.

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
