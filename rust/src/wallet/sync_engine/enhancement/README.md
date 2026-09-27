# Transaction enhancement

This module recovers transaction information that compact-block scanning cannot
provide by itself:

- full transaction payloads,
- transaction status,
- transparent-address history,
- transaction fees.

The most important boundary is that **the wallet database chooses the payload
route**. This module executes that decision; it does not infer a public fallback
from a private-service failure.

## Functional map

```text
sync_engine
    |
    | post-scan checkpoint
    v
+------------------------- enhancement facade --------------------------+
|                                                                       |
|  status + auxiliary metadata           routed payload recovery         |
|  +----------------------+             +----------------------------+  |
|  | status observation   |             | private Enhance PIR        |  |
|  | fee backfill         |             | public lightwalletd        |  |
|  | transparent history  |             | scan-time queue seeding    |  |
|  +----------+-----------+             +-------------+--------------+  |
|             |                                           |              |
|             +----------------+--------------------------+              |
|                              v                                         |
|                    wallet database writes                              |
+-----------------------------------------------------------------------+
                               |
                               v
                    later snapshots may expose
                    newly actionable obligations
```

The facade is `mod.rs`. Its implementation is grouped into four packages:

```text
enhancement/
|-- auxiliary/       transparent history and fee completion
|-- payload/         coordinator, public retrieval, private Enhance PIR
|-- status/          coordinator, public source, private Status PIR, persistence
|-- transport/       routed HTTPS core and protocol adapters
|-- policy.rs        one immutable status/payload source decision
|-- tests.rs         cross-flow checkpoint and request-lifecycle tests
`-- mod.rs           sync-engine-facing entry points and phase order
```

The filesystem matches the module graph. Implementations stay private behind
their package or the parent session facade.

## The two wallet snapshots

Three database snapshots serve different purposes and must not be mixed.

```text
transaction_status_work() → Public / Private status lane

transaction_data_requests()
    |
    `-- TransactionsInvolvingAddress ----> transparent-history lane
        (no payload variant: payload work exists only in the snapshot below)


transaction_enhancement_work()
    |
    +-- Private(EnhancePirWork) ----------> private payload lane
    |
    `-- Public(Public...Request) ---------> public payload lane
```

`transaction_enhancement_work()` is the sole payload-routing authority. For one
durable obligation, it returns at most one route. The following events do not
authorize changing private work into public work:

- PIR transport failure,
- unavailable or stale private coverage,
- a suspended private obligation,
- an anchor mismatch,
- cancellation.

Only an authenticated private result that durably changes the wallet route may
cause a later snapshot to expose the transaction as public.

## Sync checkpoint flow

After compact-block scanning, work runs in this order:

```text
compact block downloaded
    |
    v
queue stored payloads before scan
    |
    v
scan_cached_blocks
    |
    v
+--------------- enhancement checkpoint ---------+
| 1. backfill missing fees                        |
| 2. observe transaction status                   |
| 3. stream transparent-address history           |
| 4. persist every streamed transaction           |
| 5. acknowledge a range only after stream EOF    |
+------------------------+------------------------+
                         |
                         | history may create payload obligations
                         v
+------------- routed payload pass ---------------+
| 1. read the atomic routed snapshot               |
| 2. perform rediscovery and private PIR work      |
| 3. reread durable routing                        |
| 4. fetch only explicitly public payloads         |
| 5. repeat while bounded progress changes work    |
+-------------------------------------------------+
```

`EnhancementSession::run_checkpoint` owns this ordering. Metadata and status
passes are bounded, as is the payload coordinator. Residual durable work is
left for a later checkpoint instead of allowing an unbounded loop.

## Routed payload recovery

The payload session lives for one full-sync invocation.

```text
                 transaction_enhancement_work()
                              |
                   +----------+----------+
                   |                     |
                   v                     v
              private work          public work
                   |                     |
                   v                     |
       compact-block rediscovery         |
                   |                     |
                   v                     |
         accept snapshot anchor          |
                   |                     |
                   v                     |
          query covered positions        |
                   |                     |
                   v                     |
       apply authenticated records       |
                   |                     |
                   +----------+----------+
                              |
                              v
                     reread wallet routing
                              |
                              v
              dispatch explicitly public work only
```

### Private Enhance PIR states

```text
disabled
    |
    | mainnet + preference enabled
    v
waiting for snapshot
    |
    | manifest fetched
    v
waiting for scanning ---- anchor mismatch ----> retrying later
    |
    | local scan covers and matches anchor
    v
recovering
    |
    +-- outside coverage ----------------------> remains durable
    |
    +-- HTTP 409/410 --> refresh once ---------> retry unfinished work
    |
    +-- ordinary failure ----------------------> retrying later
    |
    `-- authenticated result ------------------> persist partial progress
```

Accepted routing, pending routing, rediscovery attempts, and
`private_failed_for_sync` are session-scoped. Successfully persisted records
remain committed even if a later record fails. The next attempt rereads the
database and processes only unfinished obligations.

Recovery phases in `payload/diagnostics.rs` are advisory UI state. They must
never drive routing, persistence, or privacy decisions.

## Status observation

Status source selection happens once when the reader is constructed.

```text
                  status reader
                       |
          +------------+-------------+
          |                          |
          v                          v
shared private mode          shared public mode
          |                          |
          v                          v
private Status PIR          public lightwalletd
          |                          |
          +------------+-------------+
                       |
                       v
              validated observation
                       |
                       v
           set_transaction_status()
```

The unselected source is lazy and is never opened. A selected private source
does not fall back to public lightwalletd after initialization or observation
failure.

Private Status PIR validates:

1. mainnet identity,
2. local scan height through the manifest anchor,
3. the local block hash at that anchor,
4. coverage constraints for the requested observation,
5. the anchor again after the query.

HTTP 409/410 permits one private-session refresh. Other failures remain
inconclusive. `Mempool` and `Forked` are distinct source observations but both
persist as the wallet's not-in-main-chain state.

## Transparent history and fees

```text
TransactionsInvolvingAddress
           |
           v
plan and coalesce bounded ranges
           |
           v
GetTaddressTxids stream
           |
           v
parse -> decrypt -> store -> enrich fee
           |
           v
stream reaches EOF
           |
           v
notify_address_checked(end - 1)
```

A range is acknowledged only after every streamed transaction has been stored
and the stream has completed. Decode, storage, transport, or completion-write
failure leaves the range retryable.

Fee enrichment is best effort after transaction ingestion. Transactions with
transparent inputs require their parent outputs; fully shielded transactions
can compute their fee without parent requests. Fee persistence updates only a
still-missing fee.

## Transport and cancellation

```text
protocol adapter
    |
    +-- Enhance PIR: 120-second whole-request deadline
    |
    `-- Status PIR:   20-second deadline
              |
              v
privacy-routed HTTPS core
    |
    +-- wallet route policy --> Tor when desired, otherwise direct
    |
    `-- force direct --------> iOS read-only background status path
```

All endpoints require HTTPS. Response bodies are bounded, error statuses are
handled before their bodies, and cancellation is checked before dispatch,
during the request, and after completion. No wallet write lock is held across
network I/O.

## Failure outcomes

```text
private payload failure       keep private work; retry in a later full sync
private outside coverage      keep work; wait for a newer snapshot
private authenticated reroute reread DB; public dispatch is now permitted
public explicit NotFound      complete payload work only
public other failure          keep payload work retryable
private status failure        keep status inconclusive; no public fallback
address-history failure       keep range unacknowledged
cancellation                  stop before the next network dispatch
```

## Stable entry points

The sync engine should use only the parent facade:

- `EnhancementSession::new`
- `EnhancementSession::run_checkpoint`
- `EnhancementSession::run_payload_recovery`
- `queue_stored_transactions`
- `phase`

iOS read-only FFI and migration reconciliation use the explicit `status`
facade plus the same `EnhancementPolicy`. The old native status symbol fails
closed; callers use the versioned ABI with explicit network and coverage context.

Status work is read separately from transparent discovery. The returned variant is
the dispatch authority. Private work carries the wallet's conservative inclusion
evidence; the checkpoint supplies its decision height. Incomplete coverage leaves
the obligation pending and is attempted at most once per checkpoint, without
public fallback. Foreground, migration recovery, and the versioned native ABI use
the same routing contract. Mainnet private preference enables private status;
there is no separate release gate.
