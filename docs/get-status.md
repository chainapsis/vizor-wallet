# Transaction status architecture

## Current behavior

Wallet-libraries `zakura-transaction-status::StatusReader` selects exactly one
public or private source per batch, opens it lazily, and reuses its session.
Vizor returns one internal `TransactionObservation` type from either source:
`NotFound`, `Mempool`, `Mined(height)`, or `Forked`. It never returns transaction
bytes to status callers. The wallet-libraries public source accepts a typed
`TxId`, a lazily opened lightwalletd client, and a cancellation predicate.
The private path is separately guarded by the existing private enhancement
preference and the `VIZOR_STATUS_PIR_RELEASE_READY=1` build/runtime gate. The
private endpoint defaults to the existing Enhance PIR origin and can be
overridden with `VIZOR_STATUS_PIR_URL`. Without that release
gate, the existing public behavior remains active. When the gate is active, a
private failure never falls back to a public txid lookup.

The public adapter calls lightwalletd
`GetTransaction`. That RPC discloses the txid and downloads the full raw
transaction. The adapter parses it, verifies its txid against the request,
validates the height, and discards the bytes. Height `0` means mempool,
`u64::MAX` means forked, and heights from `1` through `u32::MAX` mean mined.
Only an explicit gRPC `NotFound` becomes `TransactionObservation::NotFound`.
Malformed payloads, mismatched identities, unsupported service, timeouts,
transport failures, and cancellation are errors. Server error messages are not
included in the adapter's log-safe error classification. The existing 20-second
unary timeout and before/during/after cancellation checks remain in place.

The public source is the single auditable status use of `GetTransaction`.
`payload::get_transaction_payload` remains the separate explicit capability
for enhancement, transparent parent resolution, and migration reconciliation.

## What an observation means

A result is what the selected lightwalletd server reported. `NotFound` means it
could not provide an observation of the txid at lookup time. It is not proof
that the transaction was never broadcast or that every historical chain and
mempool source was searched. `GetTransaction` does not supply an observation
snapshot, coverage assertion, or chain anchor, so the public adapter must not
claim independent freshness or complete coverage. Callers retain their existing
endpoint trust, route, expiry, and retry policies.

This distinction matters for migration retirement: only `NotFound` can permit
retirement, and only after the existing expiry and durable-attempt checks.
`Mempool`, `Mined`, and `Forked` block retirement. Errors are inconclusive and
preserve recovery state. Gift Card tracking makes no status requests: funding
is observed only through the observer's own compact-block scan.

## Independent wallet work

The wallet-libraries SDK tracks status observations and payload enhancement as
independent requests. The sync coordinator reads one combined request snapshot
and uses its typed status and public-enhancement views. A status observation
calls `set_transaction_status` and cannot retire payload work. Successful
payload ingestion completes enhancement. An explicit payload `NotFound` calls
`notify_transaction_enhancement_not_found`; retryable or malformed payload
responses leave enhancement pending. A failed payload request does not prevent
an independent status request from being processed before the sync retry error
is returned. No database write lock spans network I/O.

Enhance PIR protects eligible Ironwood payload recovery. The SDK can still
request status for the same txid, and the public status source reveals that
txid to the selected lightwalletd server when public status is selected.
The public C ABI and Swift method-path validation continue to use the
`GetTransaction` adapter. The iOS pinned-direct route remains unchanged.

## Private status integration and release boundary

`zakura-pir-status` defines a release-specific encrypted-row client. Vizor
supplies its private source to the wallet-libraries reader; its private session
accepts a fresh manifest only when its network and anchor hash
match locally scanned wallet state. The query is routed over the existing
Tor/direct policy; iOS background work uses its direct route. The result maps
to the same four internal observations. Uncovered txids, stale generations,
malformed rows, transport failures, and cancellation leave status work
inconclusive. The native iOS ABI adds a private entrypoint while retaining the
public one.

The current integration supplies no earliest-inclusion bound for ordinary or
imported status requests. Positive records are usable; a missing
record is `CoverageIncomplete`, never `NotFound`. Migration retirement also
requires coverage through its decision height and therefore cannot retire on a
private negative until durable local creation evidence is implemented. This is
an intentional fail-closed limit of the current wiring.

The Status PIR integration remains unqualified for production. Synthetic
qualification is not proof of live ingestion or durable publication; the
wallet client and service must agree on the current wire protocol and pass
live-source qualification before setting the release gate.
No public `GetStatus` wire RPC is planned.

Tests cover response identity and height validation, explicit absence versus
errors, cancellation, lazy source selection and session reuse, private
fail-closed behavior, independent status and payload completion, and the C
ABI's four existing observation states.
