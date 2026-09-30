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

For a previously mined outbound transaction awaiting status, a conclusive
non-mined observation is held in the checkpoint's resubmission set while its
status row stays pending. The sync caller completes that status work only after
verifying an unchanged remote tip hash. Cancellation, an unverified tip, or an
advanced tip retains the durable guard; an advanced tip schedules scanning
before resubmission. This applies to both status sources. See
[`docs/transaction-resubmission.md`](../../../../../docs/transaction-resubmission.md).

The unselected source is lazy and is never opened. A selected private source
does not fall back to public lightwalletd after initialization or observation
failure.

Private Status PIR validates:

1. mainnet identity,
2. local scan height through the manifest anchor,
3. the local block hash at that anchor,
4. coverage constraints for the requested observation,
5. the anchor again after the query.

HTTP 409/410 permits one private-session refresh. Most other failures remain
inconclusive and never fail the sync. After the first private failure other
than coverage, the session stops querying the private service and leaves the
remaining private status work pending until the next sync.

Each lookup carries the wallet's chain tip as its decision height. When the
snapshot anchor is below it, the lookup drops the bound and accepts only
positive records; a missing record is then `CoverageIncomplete`. `Mempool` and
`Forked` are distinct source observations but both persist as the wallet's
not-in-main-chain state.

`CoverageIncomplete` is an explicit, retryable feedback gate. `GetStatus` work
is expected to be highly unlikely in private mode, so Vizor surfaces a clear
Settings action and pauses automatic sync after bounded retry instead of
silently weakening privacy. If production users encounter the gate, its
complete negative-coverage recovery needs a dedicated design; there is no
automatic public fallback.

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

Fee enrichment is best effort after transaction ingestion. Only wallet-funded transactions are selected. Transparent input values come
from wallet outputs or locally stored parent transactions; missing values leave
the fee unknown without network lookups. Fully shielded transactions can compute
their fee locally. Fee persistence updates only a still-missing fee.

## Transparent policy gate

Every request that sends a transparent address, outpoint, or txid to public
lightwalletd goes through `TransparentLookupGate`
(`sync_engine/lwd/transparent_lookup.rs`): UTXO refresh, Ledger and software
account discovery, the import balance preview, address history, public
payloads, public status, and the public status checks that unbroadcast
migration recovery runs before retiring a run. The raw `GetAddressUtxos`,
`GetTaddressTxids`, and `GetTransaction` helpers are private to `lwd`, so a
lane cannot reach them any other way; the public status source is wrapped by
`status::lightwalletd_source`. Fee enrichment and migration stop send no
transaction identifiers, so they need no gate. The iOS FFI
`zcash_lightwalletd_observe_transaction` has no wallet context and stays out of
scope: gating it needs wallet context across the C ABI and Swift. Production
keeps `Public` authority throughout preparation, so it cannot disclose under a
private policy yet, but it is a blocker for production private activation.

A lane captures `EnhancementPolicy::public_transparent_lookups` once: the
stricter of the captured mode and the policy durably applied to the wallet,
stamped with the policy generation. The gate keeps its own read-only policy
handle and re-checks that generation at two kinds of check point:

- **Every dispatch.** Each RPC is authorized as it is first polled, including
  each request of a concurrent UTXO group, Ledger batch, or address-history
  fill, so a transition landing between two requests of one batch withholds
  the later ones. A withheld request sends nothing.
- **Every completing write.** Received data is still stored, but nothing is
  acknowledged or marked complete after the transition: an in-flight history
  range, even one answered empty, stays unchecked; a public status observation
  or payload `NotFound` is not committed; UTXO refresh metadata and Ledger
  discovery progress are not advanced. Later passes re-cover them. The history
  acknowledgement, public status persistence, payload `NotFound` retirement,
  and Ledger checkpoints (`transactionally_with_extension`) read the
  generation in the writing SQLite
  transaction, so a concurrent transition fails the write instead of slipping
  past the check. The UTXO receive cache lives outside the wallet database and
  re-checks just before writing, not atomically.

`Withheld` sends nothing and completes nothing. Queued work, unchecked ranges,
and UTXO query heights stay durable for a later authorized pass. A later
operation resolves lookups afresh under the new generation, and a withheld
lane never regains the generation it captured.

Per-RPC checks narrow the check-to-dispatch window but cannot close it alone: a
transition could commit between a check and its request, and a disclosure
cannot be undone. The in-process **policy fence** closes it. Every dispatch
holds a shared lease from its check until its request has been sent, and
`apply_transparent_policy_fenced`, the only way this build applies a
transparent policy, takes the exclusive side. A waiting transition blocks new
leases at once, waits up to its drain deadline for in-flight requests, and only
then commits; if they do not drain in time it applies nothing and fails, and
the caller retries. Lookups queued behind it resume under the new generation
and are withheld. No wallet-libraries hook is needed: the fence lives beside
the only code that sends lookups. A transition made by another process is
outside the fence, and the per-RPC check still bounds it to requests already in
flight. Production never applies a transition yet; fixture activation does.

- This build's Public handle cannot read a wallet whose durable policy is
  `PrivateRequired`; the gate then returns an error, which also sends nothing.
- Production always captures `Public`. `PrivateRequired` is reachable only in
  tests (`EnhancementPolicy::with_transparent_mode`) until private transparent
  recovery exists.

## Private transparent recovery and activation

Phase 3 adds a candidate-recovery coordinator beside this module,
`sync_engine/transparent_ledger.rs`. It is a separate discovery loop from
enhancement: it shares only the captured `EnhancementPolicy` and the sync
lifetime. Candidate state lives in wallet-libraries' `tpir_*` tables, and
balances, input selection, locks, address allocation and history ignore it.

- **Source boundary.** `RecoverySource::recover` takes one account's watched
  addresses, open pages and target, plus `SourceBounds` (queries, bytes, pages
  and time). It returns a normalized `SourceResult`: a revision, an anchor,
  receives, spends, checked and unsupported ranges, and opened and completed
  pages. `DisabledSource` always answers `Unavailable`. The deterministic
  `FixtureSource` is test-only, and its revisions carry the `vizor-fixture`
  source id. No source falls back to lightwalletd, and the coordinator takes no
  lightwalletd client.
- **Passes.** For each account the coordinator reads `transparent_watch_set`,
  calls the source with no database lock held, and applies the answer through
  `apply_transparent_ledger_commit` under the wallet write lock. It repeats at
  the same target while the window grows, the watch set changes, or open pages
  make progress. The cap is 8 passes per account.
  - A stale commit (reorg, deleted account, superseded revision, or a changed
    policy generation) is retried up to three times from a fresh watch set.
  - A newer provisional revision retracts the older revision's observations.
    Events survive only when another independent or sealed observation supports
    them; a complete replacement can therefore withdraw receives and spends.
  - An integrity rejection stops the run: the source's session is no longer
    trusted.
  - A malformed commit is logged and skips the account.
  - A timeout or source failure leaves the account for a later run.
  - Cancellation and mode changes stop between passes. Applied commits and
    open pages stay durable for the next run.
- **Scheduling.** `run_sync_impl` calls the coordinator once per completed
  sync, at the fully scanned height, before locks are reconciled. Its errors are
  logged and never fail the sync. It has its own progress, retries and
  completion, and it does not touch UTXO refresh, the `.receive.redb` cache, or
  the shielded checkpoints; neither of those becomes private evidence.
- **Production is unchanged.** Production captures `Public` and passes
  `DisabledSource`, so the coordinator returns `NotEnabled` before any read. A
  private handle on a durably `Public` wallet does not start either.
- **Diagnostics.** Logs carry only outcome counts. Rejection payloads, which
  name addresses and outpoints, are never logged. Candidate amounts from
  `transparent_candidate_recovery` are unverified: they can be above or below
  the real balance.

### Activation (Phase 4)

Under `PrivateRequired`, the coordinator offers each account whose passes
finished to `promote_transparent_account`, one account at a time. The library
rechecks everything in one transaction: the account is complete through a
target equal to the chain tip, not quarantined, every contributing revision is
qualified, and legacy public evidence agrees. A blocked promotion changes
nothing, logs only its blocker count, and is retried after a later run; one
account's blockers never hold back another. Nothing in this build can qualify
a revision. Production has no enabled recovery source; empty required intervals
can promote without granting funds, while nonempty intervals need qualification. Tests qualify fixture revisions
through the library's `test-dependencies` hook
(`FixtureSource::qualified_in`).

- **Active accounts.** Their later commits project into the wallet's outputs
  and spends in the same transaction. A commit refused because the source is
  quarantined stops the run; one refused because the account is quarantined,
  or because an active account's revision is unqualified, skips that account.
- **Balances.** `get_wallet_balances` reads the durable policy, wallet summary,
  and each account's `transparent_ledger_snapshot` in one SQLite transaction.
  A reopened Public handle on a durable PrivateRequired wallet is configured
  privately for this read only; it never changes durable policy or spending
  configuration. `WalletBalance` reports `Current`, `LastKnown`, or `Unavailable`.
  Last-known amounts are informational and the spendable fields stay zero.
  This composite read bypasses the summary-only cache to prevent mixing generations.
- **Operations.** Shielding and software proposals use library selectors and
  store authorization. Every hardware submission path (Ledger outbox, Keystone
  full/compact batches, and legacy PCZT) additionally checks transparent inputs
  through the library selector at the current network target before dispatch.
  A SQLite `BEGIN IMMEDIATE` reservation prevents policy, evidence, and rewind
  writes through that bounded send attempt, then rolls back without storing the
  transaction. It may delay other writers for the RPC timeout. Chained TEX inputs
  must name an existing output of an earlier finalized transaction in the batch.
  Definite rejection still persists nothing; accepted or ambiguous prefixes retain
  existing storage and recovery behavior. Cancellation drops the reservation.
- **Lag, outage and rewind.** When the chain passes the covered height, or a
  rewind clips coverage, authority pauses and Home shows the last-known amount.
  A source outage never falls back to lightwalletd. The next run that covers
  the new chain restores authority; activation survives rewinds.
- **Tests.** `transparent_ledger/tests/activation.rs` drives the production
  handle openers, balance reads and shielding entry point under a per-wallet
  mode override (`enhancement::test_mode`), after a fenced transition.

### History completeness (Phase 5)

Activity reads the library's `transaction_history_details` for every history
transaction, through a configured handle over the same read transaction as the
history rows, so both describe one database state. Each entry carries:

- `fee_state`: `Known`, `Unknown`, or `NotApplicable`. The raw fee is no
  longer coalesced to 0, and `fee` is 0 unless the state is `Known`. Receipts
  in Private queries mode show an unknown fee as "Unknown", and a receive
  shows no fee.
- `details_complete`: whether the recipients, payment amounts, and memos are
  known. A missing recipient row does not mean there was no payment.
- `provisional`: whether later discovery or enhancement can still change the
  entry. It is true for provisional classifications or any unsettled pool
  effect. Local construction can know every payment detail before scanning
  discovers a receipt to the account's own external shielded address.

Classification follows the facts it has:

- **Shielding** is inferred only when the payment details are complete. With
  partial details, a transparent spend that funded a shielded output cannot be
  told apart from a payment.
- **A provisional debit** whose outputs are unknown, or known only as change,
  is one `sent` row for the net debit less any recorded fee, with pool
  `unknown` and no recipient. Its change is not shown as a receive, and the
  net amount is not presented as a payment amount.
- **Transaction identity is stable.** Rows keep their txid while details
  arrive, but their role can change, such as a provisional `sent` becoming
  `shielded`. A receipt follows a changed role only when that transaction has
  a single row, so separate self-send legs are not conflated.

While Private queries is enabled, Activity rows mark an incomplete entry
"Details incomplete", and receipts show a "Details: Incomplete" row and an
"Unknown" fee when necessary. This is temporary integration feedback while
private history approaches public-history completeness. With Private queries
disabled, the existing presentation is preserved: no completeness notice and
the previous placeholder or omitted fee row for an unrecorded fee. History
refreshes on the sync events that already
refresh it (`hasNewTx` or `isComplete`); recovery runs before a pass completes,
so its commits are visible on the next refresh. No history gap starts any
public lookup.

Under `Public` handles, which is all of production, transparent effects count
as settled, so an entry is provisional only while a shielded pool is not yet
scanned through its height, or while the account spent in it and its payment
details are missing.

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
private status failure        keep status inconclusive; skip private status for
                              the rest of the session; no public fallback
public status failure         fail the sync attempt (retried by the sync loop)
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

## Phase 4 dependency update

The four patched library crates use main revision
`3bbc469932446f23e564e0eecb7bdd00dbf48dbb`. Trusted qualification, rather than
candidate observation, now authorizes provisional revision replacement. The
replacement regression explicitly qualifies fixture revisions at that boundary.
Reader version 6 state is not supported by version 5 rollback readers; this pin
remains preparatory work, with production private activation and real-source
verification deferred.

### History refresh and batch receipt totals

Activity lists and open receipts reload when sync completes, even when the ten
recent transactions are unchanged. This exposes newly enhanced older entries
without reopening the screen. Repeated completed snapshots do not trigger a
reload by themselves.

In Private queries mode, a batch gift-card receipt with an unknown network fee
shows an unknown total and an unknown network-fee breakdown. It does not add
zero to the card amount and redemption reserves to manufacture an exact total.
Known fees, including zero, retain exact totals. Public-mode presentation is
unchanged.
