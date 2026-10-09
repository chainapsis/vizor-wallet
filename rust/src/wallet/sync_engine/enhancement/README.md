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
account discovery, the import balance preview, address history, ZIP 320
ephemeral address checks (`sync_engine/ephemeral_checks.rs`), public
payloads, public status, and the public status checks that unbroadcast
migration recovery runs before retiring a run. The raw `GetAddressUtxos`,
`GetTaddressTxids`, and `GetTransaction` helpers are private to `lwd`, so a
lane cannot reach them any other way; the public status source is wrapped by
`status::lightwalletd_source`. Fee enrichment and migration stop send no
transaction identifiers, so they need no gate. The iOS FFI
`zcash_lightwalletd_observe_transaction` takes the wallet's path and network:
it opens the wallet read-only, adopts a durable `PrivateRequired`, and returns
`STATUS_RESULT_UNSUPPORTED` without sending anything when lookups are withheld
or the transaction's status work is private. An unreadable wallet is
`STATUS_RESULT_INCONCLUSIVE`. Otherwise its request goes through the gate.

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
  discovery progress are not advanced; an ephemeral address check is neither
  notified, rescheduled, nor allowed to observe outputs of expired spends, so
  the address stays due. Later passes re-cover them. The history
  acknowledgement, public status persistence, payload `NotFound` retirement,
  the ephemeral check's notification and expired-spend observation, and Ledger
  checkpoints (`transactionally_with_extension`) read the
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
cannot be undone. The in-process **policy fence** closes it. Each wallet
database has its own fence, so a transition on one wallet never waits for
another's lookups. Every dispatch holds a shared lease from its check until its
request has been handed to the transport, and
`apply_transparent_policy_fenced_if`, the only way this build applies a
transparent policy, takes the exclusive side. A gate that knows its transport
(the sync's registered transport for its lanes, or the one a one-off lookup
opened) sends through `DispatchSignalService` and releases the lease once the
request body has been handed to the connection, never waiting for a slow
response; a gate without one holds it until the call returns. A waiting
transition blocks new leases at once, waits up to its drain deadline for
in-flight requests to be sent, and takes the wallet write lock only within the
same deadline; if either does not come in time it applies nothing and fails,
and the caller retries. A lookup that cannot get a lease within 45 s is
withheld. Lookups queued behind a transition resume under the new generation
and are withheld. No wallet-libraries hook is needed: the fence lives beside
the only code that sends lookups. A transition made by another process is
outside the fence, and the per-RPC check still bounds it to requests already in
flight. Generation checks at store time are unchanged. The private queries setting and the coordinator's raise are the only
transitions (`transparent_ledger/policy.rs`). Both decide under the fence, so
neither acts on a policy the other is about to change: a toggle-off that lands
while a raise waits wins, and one that waits behind a raise lowers what it
applied. A raise that cannot apply checks first and never takes the fence.

The setting transition pauses recovery and saves an explicit opt-out before
lowering the durable policy. A failed preference save leaves the wallet's
private policy untouched, even in a default build that cannot raise it again.
If lowering fails, it changes no durable policy; the transition restores the
runtime preference to private and attempts to restore the saved preference
before resuming. A second storage failure leaves the wallet and native work
private even if the saved opt-out remains. A crash between the
preference save and lowering can leave a stricter wallet policy than the saved
setting. Startup preserves that restriction; explicitly toggling Private
queries on and then off retries the transition.

- Every handle opener selects a mode, then adopts a durable `PrivateRequired`,
  so lookups on such a wallet are withheld in every build. A handle opened
  before the transition cannot read it; the gate then returns an error, which
  also sends nothing.
- A default build captures `Public`. With the
  `ZCASH_PRIVATE_TRANSPARENT_RECOVERY` development flag, private queries on
  mainnet capture `PrivateRequired`.

## Private transparent recovery and activation

The recovery coordinator, `sync_engine/transparent_ledger.rs`, is a discovery
loop beside this module: it shares only the captured `EnhancementPolicy` and
the sync lifetime. Candidate state lives in wallet-libraries' `tpir_*` tables,
and balances, input selection, locks, address allocation and history ignore it
until an account is promoted.

- **Source boundary.** A `RecoverySource` answers one pass over one account
  (`SourceRequest`: the account, its watch set and an exit signal) with a
  `SourceBatch`, and says whether its commits come from a `trusted()` origin.
  The transparent PIR source is the only production source (see below). The
  deterministic `FixtureSource` is test-only; its revisions carry the
  `vizor-fixture` source id, and `trust()` makes it trusted. No source falls
  back to lightwalletd, and the coordinator takes no lightwalletd client.
- **Batch states.** Only `Ready { next, behind_by }` has commits, which the
  source keeps, opaque, until it settles the batch. `Pending { next }` (the publication is behind what the source
  recorded) and `Withdrawn(cause)` (the publication contradicts it:
  `Regression`, `Equivocation`, `ChangedSealed` or `Retired`) apply nothing and
  are never acknowledged. A source fails with `Unavailable`, which stops the
  run, `Failed`, which skips the account, or `Cancelled`; none carries detail.
- **Trusted qualification (D1).** The source settles a `Ready` batch
  (`RecoverySource::apply`): the transparent PIR source hands it to the
  adapter's `apply_and_acknowledge`, which applies the commits in order, each
  in its own library transaction, under the wallet write lock; no lock is held
  across a source call or any network request. Under `PrivateRequired`, on the
  handle and durably, a trusted source's commits are applied with
  `Trust::Trusted` (`qualify_and_apply_transparent_ledger_commit`), which
  qualifies the exact revision, supersedes its source's older provisional
  evidence, and applies the facts in one transaction. This is the
  trusted-indexer decision: the wallet trusts the configured indexer and does
  not verify the publication; nothing here is publication verification. A superseded revision's events
  survive only where another independent or sealed observation supports
  them, so a complete replacement can withdraw receives and spends. Shadow
  runs and untrusted sources only apply (`apply_transparent_ledger_commit`)
  and never qualify.
- **Acknowledgment and withdrawals.** A batch is acknowledged only after every
  commit's wallet transaction committed; the companion and the wallet are
  separate databases and are never treated as atomic. A batch can resolve
  provisional revisions that an earlier batch exported, each succeeded by one
  of its commits. Only trusted commits withdraw their evidence, so observed
  settlement refuses such a batch before applying anything; nothing is
  acknowledged, the account is held, and the source reports the retirements
  again until a trusted run reconciles them. A stale commit, a policy change, a
  failed write or acknowledgment, or a crash leaves the batch unacknowledged
  with its committed prefix counted; the next pass replays it, and the replay
  changes nothing already applied. A withdrawn publication holds the account
  too, and both show as `Stopped(Withdrawn)`.
- **Rejections.** A stale commit (reorg, deleted account, superseded revision,
  or a changed policy generation) is retried up to three times from a fresh
  watch set, without acknowledgment. An integrity rejection, which
  quarantines in the same transaction, a refusal (quarantined source or
  account, or an unqualified revision for an active account), or a malformed
  commit skips the account. `TransparentRecoveryNotEnabled` stops the run.
  Commits applied before a rejection stay durable, and replaying them changes
  nothing. Cancellation stops between passes and discards an answer that
  raced it; applied commits and open pages stay durable for the next run.
- **Continuations and waits.** `next` comes from the adapter's outcome:
  `Complete`, `More` (pass again at once), `RetryAfter` (10 s behind a lagging
  publication, 30 s after an overload) and `Stalled`. A further pass also
  needs a grown window or a changed watch set. One run waits at most 90 s in
  all; the lag is logged in blocks and the wait in seconds.
- **Bounds and order.** The active account goes first and the rest follow
  from a per-wallet rotating cursor. Each account gets at most 8 passes and
  120 s, and the run 180 s. A source call that ignores its exit signal is
  abandoned 30 s after the pass deadline.
- **Holds.** A withdrawal, unreconciled retirements, legacy evidence the
  complete ledger cannot explain (`LegacyDiscrepancy`), or three stalled runs
  since the last complete one hold the account for an hour. Holds live in
  memory, so a restart retries once. Held and quarantined accounts, and under
  `PrivateRequired` Ledger accounts, are skipped without a source call. The
  balance read reports why as the account's stop reason.
- **Raise and confirmation.** A default build captures `Public`, so `run`
  returns `NotEnabled` before any read. Under a captured `PrivateRequired` it
  first raises a weaker durable policy behind the policy fence, only while
  `may_raise` holds: the selection is `PrivateRequired` and the preference was
  read from storage, rechecked under the fence. An unreadable preference or a
  concurrent toggle-off raises nothing, and a private handle on a durably
  `Public` wallet that it may not raise does not start.
- **Scheduling.** `transparent_followup` runs once per completed sync, after
  `mark_sync_completed` and the final progress event and before the deferred
  inactive-account UTXO refresh, so waiting for a publication never delays the
  sync's result. Unless the run exited or was not enabled, it reports
  completion again, flagged with new transactions, so the UI re-reads balances
  and shielding state. Its errors are logged and never fail the sync. It does
  not touch UTXO refresh, the `.receive.redb` cache, or the shielded
  checkpoints. While public lookups are withheld, Ledger discovery counts as
  ready, so a paused Ledger account never holds back a sync.
- **Diagnostics.** Logs carry variant, cause and blocker names, counts and
  lag. Rejection payloads, which name addresses and outpoints, are never
  logged. Candidate amounts from `transparent_candidate_recovery` are
  unverified: they can be above or below the real balance.

### Activation (Phase 4)

Under `PrivateRequired`, the coordinator offers each account whose passes
finished to `promote_transparent_account`, one account at a time. The library
rechecks everything in one transaction: the account is complete through a
target equal to the chain tip, not quarantined, every contributing revision is
qualified, and legacy public evidence agrees. A blocked promotion changes
nothing, logs only its blocker kinds, and is retried after a later run,
except that `LegacyDiscrepancy` holds the account for an hour; one account's
blockers never hold back another. Revisions are qualified only by the trusted
operation as their commits apply, so only a trusted source under
`PrivateRequired` can promote an account; empty required intervals can promote
without granting funds. Tests use the trusted fixture, not the library's
`test-dependencies` hook.

- **Active accounts.** Their later commits project into the wallet's outputs
  and spends in the same transaction, and need a qualified revision. A refused
  commit skips the account.
- **Balances.** `get_wallet_balances` reads the durable policy, wallet summary,
  and each account's `transparent_ledger_snapshot` in one SQLite transaction.
  A reopened Public handle on a durable PrivateRequired wallet is configured
  privately for this read only; it never changes durable policy or spending
  configuration. `WalletBalance` reports `Current`, `LastKnown`, `Unavailable`,
  or `Stopped`. Last-known amounts are informational and the spendable fields
  stay zero. An account that recovery will not restore on its own is
  `Stopped`, with `transparent_stop` saying why: `Quarantined`, `Ledger`, `LegacyDiscrepancy`,
  `Withdrawn`, `Stalled`, or `NotSelected` for a durably private wallet in a
  build that does not select private recovery. `transparent_private` reports a
  durable `PrivateRequired`.
  This composite read bypasses the summary-only cache to prevent mixing generations.
- **Operations.** Shielding and software proposals use library selectors and
  store authorization. Every hardware submission path (Ledger outbox, Keystone
  full/compact batches, and legacy PCZT) additionally checks transparent inputs
  through `WalletDb::check_transparent_transaction_inputs` at the current network
  target before dispatch. An exact stored transaction may retry its own recorded
  spend; the exception requires full serialized-byte equality and never permits
  a competing live or mined spender.
  A SQLite `BEGIN IMMEDIATE` reservation prevents policy, evidence, and rewind
  writes from the check until the request body has been handed to the transport,
  then rolls back without storing the transaction. A request that has left cannot
  be recalled by a later write, so the reservation does not wait for the response;
  it normally lasts milliseconds. HTTP/2 flow control can stretch it by about one
  round trip for a body larger than the stream window. A body that never finishes
  leaving keeps the reservation through the bounded RPC attempt, and holds of
  250 ms or more are logged. Chained TEX inputs
  must name an existing output of an earlier finalized transaction in the batch.
  Definite rejection still persists nothing; accepted or ambiguous prefixes retain
  existing storage and recovery behavior. Cancellation drops the reservation.
  After PCZT validation, exact stored mined rounds complete without an RPC or
  expiry rejection, after checking database compatibility. Unmined rounds retain
  expiry checks and retry their exact bytes. Wallet storage and Ledger outbox
  outcomes remain separate commits: recovery can retry between them, and an
  outcome committed before acknowledgement remains available for metadata repair.
- **Account deletion.** Vizor borrows its existing SQLite transaction through
  `SqlTransaction::new` and delegates wallet rows to library `WalletWrite::delete_account`.
  Newer reader requirements or missing recorded policy metadata refuse deletion.
  Retrieval detachment, enhancement retirement and ledger/provenance cleanup share
  the transaction with Vizor receive addresses, Ledger discovery, migration runs,
  signed operations and orphaned scan-range cleanup. Every transactional failure
  rolls back all of these; cache and process-local cleanup run after commit.
  Per-account deletion includes the initial Derived account while another remains;
  the Accounts UI still treats the last account as a full wallet reset.
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
  shows no fee. An exact whole-transaction fee remains reconstruction
  evidence: it does not replace an unknown account fee in the receipt, since
  other funders may have shared it.
- `amount_includes_fee`: whether the amount is a balance movement retaining
  the account's fee share rather than an established payment. Activity and
  receipts label it "Net change". A proven fee-only self-transfer also stays
  neutral and shows its amount once. An unknown account fee stays "Unknown";
  no whole fee is subtracted from the amount. The richer whole-fee display
  and "Network fee" presentation are maintained in a child PR.
- `details_complete`: whether the recipients, payment amounts, and memos are
  known. A missing recipient row does not mean there was no payment.
- `provisional`: whether later discovery or enhancement can still change the
  Activity entry. Unsettled pool effects keep it true. A mined mixed transaction
  with a library-provided outgoing residual can establish its existing Sent/Received
  rows while payment classification stays provisional: owned effects must be
  settled, owned transparent scopes known, and the visible residual must cover
  owned receipts after excluding internal funding. The receipt retains the
  transaction-wide provisional classification and incomplete payment details.
  Local construction can know every payment detail before scanning discovers
  a receipt to the account's own external shielded address.

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

While Private queries is enabled, Activity rows mark an uncertain summary
"Details incomplete"; established summaries keep their dates even when the
payment details are missing. Receipts show a "Details: Incomplete" row and an
"Unknown" fee when necessary. This is temporary integration feedback while
private history approaches public-history completeness. With Private queries
disabled, the existing presentation is preserved: no completeness notice and
the previous placeholder or omitted fee row for an unrecorded fee. History
refreshes on the sync events that already
refresh it (`hasNewTx` or `isComplete`). Private recovery runs after
completion is reported and then reports completion again, flagged with new
transactions, so its commits refresh history on that event. No history gap
starts any public lookup.

Under `Public` handles, which is every default build, transparent effects
count as settled, so an entry is provisional only while a shielded pool is not
yet scanned through its height, or while the account spent in it and its
payment details are missing.

### Qualification

`transparent_ledger/tests/qualification.rs` runs the coordinator through the
Rust entry points FRB exposes (`get_wallet_balance`,
`get_shield_transparent_status`, `get_transaction_history`, `propose_send`)
and the sync lanes, across the whole lifecycle, on regtest wallets scanned by
writing `blocks` and `scan_queue` rows directly. Recovery uses the trusted
fixture. Legacy receipts are synthetic v1 transparent transactions stored the
way public discovery stores them (UTXO refresh plus payload retrieval).

| Scenario | Result |
| --- | --- |
| Public → shadow → private | Shadow leaves every non-`tpir_*` table unchanged and qualifies nothing; activation shows the public amount as last-known; the first trusted run qualifies, promotes, and restores the same amount, shielding, and one history row. |
| Unreported legacy UTXO | Promotion stays blocked (`LegacyDiscrepancy`), and the account is held and shows `Stopped(LegacyDiscrepancy)` with its last-known amount. Once the source reports it, the run after the hold promotes. |
| Shadow reuse | Shadow evidence survives activation but is unqualified, so promotion refuses. At the same tip, one trusted pass qualifies the same revision and promotes; after the chain advances, a pass covering the new tip does. |
| Interrupted activation | A run cancelled mid-source-call keeps the account a candidate; after a restart, lookups stay withheld and a later run promotes. |
| Restart | Private authority survives new handles; a replayed pass changes no production row. |
| Discovery order and payload replay | Ledger-first and payload-first reach the same balance, history, and rows (one transaction, one output); a second replay changes nothing. |
| Account add and delete | A rescan pauses the active account until the next pass; the new account is promoted on its own; deleting it leaves the active one current. |
| Shielded-funded send while incomplete | It is refused only for lack of shielded funds, never as transparent recovery unavailable. |
| Every lane, before the raise | On a mainnet wallet with public work queued and a Ledger account, in a flag build with Private queries on but unread, so the durable policy stays `Public` and only each lane's captured policy withholds: under the flag build's policy, Ledger discovery, the UTXO refresh and the deferred refresh, ephemeral checks, import discovery and the import preview (into the wallet and as a first account), the recovery follow-up with the real source, and the iOS observe ABI; under its transparent mode with public routes, which the live private services would otherwise answer, payload recovery and the status and history checkpoint. None sends lightwalletd a `GetAddressUtxos*`, `GetTaddress*`, or `GetTransaction` request. The follow-up does not raise the wallet, sends the source's service nothing, creates no companion, and reports nothing again; the queued work stays durable. |
| Every lane, after the raise, including the transparent PIR source | On the same wallet, once startup reconcile has raised it: Ledger discovery, the UTXO refresh and the deferred refresh, payload recovery, the status and history checkpoint, and ephemeral checks, each under both a default build's policy and the flag build's transparent mode; import discovery and the import preview; the recovery follow-up with the real source; and the iOS observe ABI. None sends lightwalletd a disclosing request, the queued work stays durable, and the follow-up reports completion again. The source sends only service routes, on the wallet's route, with no watched script or txid in any path or body. Turning Private queries off then sends `GetAddressUtxos*`: the positive control. |

The upgrade probe (`examples/db_upgrade.rs`, run by
`scripts/test-db-upgrade.sh`) requires the recovery and activation migrations
and checks that their thirteen tables are empty after an upgrade.
`transparent_ledger/tests/live.rs` holds the opt-in live test (below).

## Transparent PIR source (development flag)

`transparent_ledger/pir.rs` is the production `RecoverySource`: the reference
adapter `zakura_pir_transparent` over the wallet's routed transport. It is
trusted, since every commit comes from the configured origin.

- **Enablement.** Only a build launched with
  `--dart-define=ZCASH_PRIVATE_TRANSPARENT_RECOVERY=true`, on mainnet, with
  Private queries on and the preference read from storage, raises a wallet to
  `PrivateRequired` and runs the source. Off mainnet the source has no origin,
  and every pass is `Unavailable` without a request.
- **Endpoint.** `https://transparent-pir.valargroup.dev`. Debug builds honor
  `VIZOR_TRANSPARENT_PIR_URL`; release builds ignore it, and Dart cannot set
  it. Each companion binds the source `vizor/transparent-pir/v1`, the
  account's UUID and the origin, so another origin derives other revision
  sources.
- **Companions.** One per account, `{db}.tpir/{uuid}-{tag}.sqlite`, where the
  tag is 16 hex digits of `sha256(origin || 0 || SCHEMA)`. A companion holds
  the adapter's retrieval cache and revision catalog, never wallet state. It
  is created on the account's first pass, and losing one costs a re-download:
  revision identities come from the publication, so a recreated companion
  derives the ones the wallet holds. Opening one deletes the account's
  companions for other origins or schemas and those of deleted accounts.
  Deleting an account removes its companion and SQLite sidecars once the
  deletion commits; one that removal leaves behind is deleted at the next sync
  start, in every build, with the companions of any other deleted account.
  A reset deletes the `.tpir` directory with the database,
  and a failure keeps the database name for a retry; startup and reset delete
  `.tpir` directories of no current wallet. On iOS a flag build excludes the
  directory from device backups.
- **Repair.** A companion is rebuilt only when SQLite confirms it is not a
  database or is corrupt, or when it is in the earlier format the adapter asks
  to recreate: once per companion per process, under its path lock, keeping
  every catalog row the damaged file still yields. A busy, locked or
  unreadable companion, one bound to another account, origin or schema, and a
  publication change never delete or reset anything. A regular file where the
  `.tpir` directory belongs is moved aside (`.tpir.displaced-<secs>`), never
  deleted; if it cannot be, the run stops as unavailable.
- **Locking.** One lock per companion path serializes passes, settlements and
  removals. A source parks each companion it opened, with its lock, until it is
  dropped, so a pass and its settlement see the same companion and nothing
  removes it in between.
- **Passes.** A pass runs on a blocking thread (`spawn_blocking`) over a
  read-only wallet handle, whose blocks answer the adapter's chain view up to
  the watch set's target. It stops at cancellation or the 90 s pass
  deadline, counted from the call, so it ends before the coordinator's
  backstop. On cancellation the async side joins the thread, so no companion
  or handle outlives a cancelled pass, and a pass that raced cancellation is
  discarded; a dropped call stops its pass at the next request. A
  publication whose set identity changed is retried once on the same
  companion, which the adapter has reset, keeping its catalog. A pass that
  failed because the service could not be reached or was not serving (a
  failed connection or route, a timeout, a 429 or 5xx on the map, a filter or
  init, or any other 5xx) is `Unavailable` and ends the whole run instead of
  failing each account in turn.
- **Limits per pass.** 10,000 scripts, 1,024 shards, 500,000 events, 256
  private queries, 96 MiB of private bytes, and 8 MiB per response.
- **Transport.** `enhancement/transport/transparent_pir.rs` gives the adapter
  its filter source and shard transport over one routed HTTPS client: HTTPS
  only, Tor when the wallet wants it and the direct-route lease otherwise, no
  User-Agent, a 60 s bound per request, and the sync's cancellation. Nothing
  is retried and no filter is memoized. A shard-bound 429, or 503 without
  `Retry-After`, is still capacity: it is reported as `Overloaded`, so the
  adapter's own bounded backoff (at most four attempts, two seconds at most
  between them) and the run's 90 s wait cap apply. The adapter's dependency graph has no
  reqwest. Requests use only the service's six routes: the shard map, a
  shard's filter, init, a revision's manifest, setup segments, and posted
  queries.
- **Logs.** One debug line per request, with the method, the route template
  (for example `POST /v1/shards/{id}/revisions/{rev}/query/pages`), the status
  and the body length. Pass lines carry the batch state, the outcome and the
  lag in blocks, and failures a variant name. No log carries an id, digest,
  address, script, txid, outpoint or body.
- **Accepted leaks.** The service sees shard ids, which reveal activity
  ranges; the filter range from the account's birthday to the tip; request
  counts, sizes and timing; and the network origin when Tor is off.
  Broadcasting a shield or spend still publishes its transparent outpoints
  through `SendTransaction`. Turning Private queries off lowers the wallet to
  `Public` in every build and queues the transactions routed to lightwalletd
  for public retrieval, so txids learned privately are disclosed at once.
- **Limitations.** Spends and shields can be refused between a new block and
  the next pass, or while a publication lags past a run's 90 s wait; the
  store-time recheck refuses them, so funds are never at risk. Ledger accounts
  are `Stopped(Ledger)`, and a restore under private mode does not find
  transparent-only accounts. Nothing clears a quarantine; deleting and
  re-importing the account, or turning Private queries off, recovers. The
  library's `docs/transparent-pir-private-recovery.md`, at the pinned
  revision, lists every accepted limitation and the release gates that keep
  private authority behind the flag.
- **Live test.** `a_fresh_mainnet_account_recovers_and_promotes_against_the_live_service`
  is ignored by default because it needs the network. It reads the live map,
  gives a fresh mainnet account a birthday at the start of the last sealed
  shard, and records synthetic blocks through the end of the map whose hashes
  at the shard boundaries are the map's own. Through the real source and
  transport, with the request observer only recording, it expects promotion
  with a current balance of zero, service routes only, no watched script in a
  path or body, and filter requests only for shards overlapping the birthday
  through the target, at most one each. Set
  `VIZOR_TRANSPARENT_PIR_LIVE_TOR=1` to run it through Tor:

  ```sh
  cargo test --manifest-path rust/Cargo.toml -- --ignored a_fresh_mainnet_account
  ```

## Transparent txid enhancement

A sync runs four loops. The first three keep their code and scheduling; the
fourth fills in detail views. Its private path stores display facts only; its
public path stores the raw transaction through `decrypt_and_store_transaction`,
as payload enhancement does, which can update balances and history.

| Loop | What it does | Where |
|---|---|---|
| 1. Compact scan | Trial-decrypts compact blocks; decides shielded balances | `sync_engine/mod.rs` |
| 2. Ironwood enhancement | Payload coordinator: private Enhance PIR or public lightwalletd, as the database routes each obligation | `enhancement/payload/` |
| 3. Transparent discovery | Public lightwalletd lanes (UTXO refresh, address history), or under `PrivateRequired` the private recovery follow-up | `sync_engine/mod.rs`, `transparent_ledger.rs` |
| 4. Transparent txid enhancement | For each mined transparent or mixed transaction of the wallet with no raw bytes, fetches its details by txid | `transparent_details.rs` |

Loop 4 runs after the private recovery follow-up in `run_sync_impl`, once
completion has been reported, under the same sync stream: its lock and reset
cancellation and the global running guard own its lifetime. Background
preparation syncs skip it.

```text
captured policy ── PrivateRequired ──> txid display PIR  (PirSource)
               └── otherwise ────────> GetTransaction via TransparentLookupGate (GateSource)
                                       only while the durable policy authorizes it
```

- **Source.** Chosen once per run from the policy the sync captured.
  `PrivateRequired` builds only the private source:
  `https://transparent-pir.valargroup.dev/v1/txid/`, mainnet only, with the
  transparent PIR origin's debug override (`VIZOR_TRANSPARENT_PIR_URL`). It
  holds no lightwalletd client, so a failure can never become a public
  lookup. Any other capture builds only the gate source, which re-checks the
  durable policy generation before each `GetTransaction` and again, in the
  same SQLite transaction, before storing the payload with
  `decrypt_and_store_transaction`. A capture of `Public` over a wallet whose
  durable policy withholds public lookups runs nothing.
- **Private lookups.** wallet-pir's `transparent-txid-client`, re-exported by
  `zakura-pir-transparent` with `display_facts` and `deferral`, follows the
  tiered display publication: the init document, the recent map and, for an
  archive, its index chunk (cached and refreshed by the client), the shard's
  manifest and setup (cached per revision), then exactly two queries of the
  bucket's one table, for a found and an absent txid alike. Placement comes
  from the wallet's own mined height. Requests name the tier, shard,
  revision, table and segment, never the txid or a selected row. The result
  is one fixed-size display v2 entry: the coinbase and shielded flags, the
  exact fee, input and output counts, the first address-shaped source, the
  first two outputs (value and address) and flags naming what it omits
  (several source scripts, more than two outputs, transparent inputs with
  net shielded funding). The wallet shows the omissions and offers a public
  lookup of the whole transaction only when the user asks for one. One client per origin lives for the whole
  process, so the derived native profiles are built once. These are process
  statics: a restart starts with a fresh client, no map and no map check
  time. A client that
  found the service's display unsupported is replaced by a fresh one that
  keeps only those profiles, so the next lookup asks for the init document
  and map again: a service that comes to support the client is found once
  the wallet retries the transaction.
- **Display metadata.** Work a lookup held for a map (not covered,
  unsupported, contradicted) waits for that map to change, and no lookup may
  be due to fetch a newer one. So when nothing is due and the wallet reports
  work parked for want of a map change (`transparent_detail_parked`), the
  private source waits for the reported refresh time, then fetches the map alone (`refresh_map`: one
  `GET /v1/txid/map`, no txid, validated as a lookup validates it) and the
  run lists again under its hash. The check is due six hours after the later
  of the newest parked attempt and the last attempted map check. The process
  keeps that check time by origin across sync runs, including failed checks.
  A restart starts without a map or check time and fetches when the parked
  work permits it. A failed or cancelled fetch leaves the map the
  client held, and the work held under it; it is logged by kind and never
  becomes a public lookup. Parking is private only: under public authority
  the gate source has no map, and held work is due at its ordinary retry.
- **Locks and budget.** No runtime worker waits for the shared client: the
  run reads the map digest with `try_lock`, falling back to the digest its
  source last saw, and lookups and map fetches take the client on a thread
  of their own, polling their cancellation. Once the sync exits or the 45 s
  lookup budget is spent, a lookup gets 2 s to return; one that does not is
  abandoned and its result never read, so it stores nothing. It runs on its
  own thread, not the runtime's blocking pool, so it cannot hold the sync's
  runtime shutdown, and later requests wait for the client it may still hold
  only while they are wanted. Stores and deferrals wait for the wallet write
  lock by yielding, and give up 2 s past the budget or at the exit, checked
  again once the lock is taken: what was stored stays, and an unrecorded
  transaction stays due. A run therefore ends within 47 s, plus at most one
  SQLite write already under way.
- **Transport.** `enhancement/transport/txid_pir.rs`: the shared routed HTTPS
  core (HTTPS only, Tor when desired, direct-route lease otherwise), a 30 s
  bound per request, bodies bounded per route, error bodies never read,
  cancellation before dispatch, during the request and after it. One debug
  line per request with the route template only.
- **Work and bounds.** The wallet owns the work (`transparent_detail_work`):
  private recovery and Enhance PIR's mixed transactions queue it; public
  discovery never does, since its payloads go through `tx_retrieval_queue`.
  A run reads the due work once, with the mode and policy generation the
  listing read in the same snapshot: a generation that moved since the sync
  captured its source ends the run, the gate source runs only while that
  mode retains public authority, and stores are checked against that
  generation. When nothing is due but lookups are parked on the display map
  they last saw (`transparent_detail_parked`), the private source refreshes
  its map once (`refresh_map`) when the six-hour check interval permits it,
  then lists again under the new hash. The run
  puts transactions a detail view asked for
  (`prioritize_transparent_details`, an in-memory interest set) first within
  the 64 due rows selected in the wallet's priority order. An older opened receipt outside that
  window waits to enter it and can stay behind a sustained newer backlog. The run
  makes at most 8 lookups in 45 s, one at a time. Lookups run on a thread
  of their own with no database lock held; each store or deferral takes the wallet
  write lock for one short transaction, within the budget above.
- **Failures.** Every failure is deferred to the wallet
  (`defer_transparent_detail`) with the original requested mined height, so
  a failure after a remine or rewind cannot postpone replacement work.
  The wallet schedules the retry: unavailable,
  stale, transport or protocol failures from 30 s doubling to an hour (at
  least the service's `Retry-After`), a height above the newest shard from a
  minute to five (shown pending), an absent record from an hour to a day,
  and an uncovered height, an unsupported service or a contradiction after
  at least a day, then parked until the display map changes (seven days at
  most). An outage ends the run. A public `GetTransaction` that lightwalletd
  answers "not found" is an absent record, not an outage, so the run's
  remaining lookups proceed. A lookup the budget
  stopped is deferred as unavailable. A store refused for a moved policy
  generation ends the run without storing; facts that contradict the wallet
  are held, not stored. Failures are logged by kind, never by txid, a panic
  is caught, and nothing returns an error to the sync. Balances,
  spendability, sends and history never read the display facts the private
  path stores; the public path's raw transaction is ordinary wallet data.
- **Storage.** `store_transparent_display` validates the facts against what
  the wallet knows (owned outputs, coinbase flag, recovered metadata and fee)
  and stores them; raw bytes arriving later supersede them. A run that stored
  anything reports completion again with `has_new_tx`.

Detail-view states (`TransactionDetail.transparent_details_state`):

| State | Meaning | Receipt shows |
|---|---|---|
| `available` | Every transparent output: from the raw transaction, or from validated display facts | With no recorded recipient, eligible receipts list only unowned outputs as "Transaction outputs", with "Recipient not confirmed"; no output is promoted to a payment recipient |
| `pending` | Eligible work has not answered yet | With no recorded recipient, eligible receipts show "Details unavailable — will update when the service is reachable" |
| `unavailable` | The details are unavailable; eligible work may retry in a later sync | the same notice where eligible |
| `notCovered` | Private mode cannot look it up | Where eligible, "Not available in private mode" |
| absent | No transparent part the account takes part in | nothing |

Receives, shieldings and migrations add neither this output list nor its notice;
their shared receipt shows the account's recorded outputs. A recorded payment
recipient also makes the addition unnecessary. Other receipts keep the recovered
transaction outputs explicitly unattributed, in transaction order, without the
account's own outputs.

The view belongs to the account. It shows when the account has a transparent
output or spend in the transaction, or a shielded part (a received, spent or
sent note, a payment to a transparent recipient among them) in a transaction
the wallet durably records as mixed: by detail work, stored display facts or
the route-2 marker. Storing display facts deletes the work but keeps the
facts and the marker, so the view stays. Storing raw bytes deletes the work
and the facts; for an account whose part is shielded, the raw transaction
then decides, and a view shows only when it has a transparent input or
output. Another account's mixed transaction, and a fully shielded one, have
no view.

While the state is `pending` or `unavailable`, a receipt asks for the
transaction to be prioritized within that work window (once per open) and re-reads its detail every
five seconds, stopping when it is available or not covered. Re-reads are
serialized: a poll does not start while another read, or a full receipt
load, is in flight, and a read that a newer load or an account switch has
superseded is discarded rather than shown. Development
builds (`ZCASH_PRIVATE_TRANSPARENT_RECOVERY`) add a button that runs one
private lookup through `debug_lookup_transparent_details` and stores nothing.

**Privacy.** The txid display service learns which shard, tier and bucket a
lookup touches, the page count of a display v2 overflow record, and timing;
with Tor off, the network origin. The shard and tier give the height range.
The bucket is a hash of the txid modulo the shard's bucket count, at most 64,
so it reveals up to six bits of that hash, and repeated lookups of one
transaction always touch the same bucket, which links them. It never learns
the txid itself. A public
lookup discloses the txid to lightwalletd, which is why `PrivateRequired`
never makes one. The live test `txid_live` (ignored by default) looks up a
known mainnet transaction, an absent txid, and an unplaced height through the
real client and transport, and checks the routes and that no request carries
the txid. It covers display facts only: it does not exercise raw bytes
superseding them, the public lookup, or the per-lookup runtime limits above
(the 30 s request bound, the 45 s run budget and the 2 s abandon grace), which
the in-process tests cover:

```sh
cargo test --manifest-path rust/Cargo.toml -- --ignored txid_live
VIZOR_TRANSPARENT_PIR_LIVE_TOR=1 cargo test --manifest-path rust/Cargo.toml -- --ignored txid_live
```

## Transport and cancellation

```text
protocol adapter
    |
    +-- Enhance PIR:     120-second whole-request deadline
    |
    +-- Status PIR:       20-second deadline
    |
    +-- Transparent PIR:  60-second request bound, 90-second pass deadline
    |
    `-- Txid display PIR: 30-second request bound, 45-second run budget
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
transparent PIR unavailable   stop the recovery run; no public fallback
transparent PIR pass failure  skip the account until a later run
transparent PIR pending       apply and acknowledge nothing; retry later
transparent PIR withdrawn     hold the account for an hour (Stopped)
txid details failure          defer the transaction with backoff; the view
                              shows details unavailable; no public fallback
                              under PrivateRequired; never fails the sync
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

## Library dependency

The four patched library crates and the `zakura-pir-transparent` adapter share
one wallet-libraries revision, `bdebaffcb5d52138c702fde6c78bd079293ebb3d`:
merged `main` after #97–#103, which carry every library change this branch
needs. It adds the trusted operation
`qualify_and_apply_transparent_ledger_commit` (#98), removes the unused
recovery-work query (#99), and gives the adapter caller transports and a
narrowed API (#100), the wallet chain view, birthday floor, publication-lag
clamp and mainnet check (#101), stable sources, published lineage, batch
states, cache pruning and explicit reconciliation of resolved withdrawals
(#102), and the end-to-end test against an in-process shard service (#103).
Trusted qualification, rather than candidate observation,
authorizes provisional revision replacement; the replacement regression runs a
trusted fixture under `PrivateRequired`. The pin adds no wallet migration and
no reader-version change. Reader version 6 state is not supported by version 5
rollback readers; this pin is unreleased, and private activation stays behind
the development flag.

The adapter is a direct git dependency rather than a patched crates.io
package: it depends on wallet-pir's transparent crates, which exist only in git
(`pir-native` has `publish = false`). #783 requires a published release
before merge, which the adapter cannot meet while those crates are git-only;
that is recorded as a release gate, not worked around. Vizor repins after any
restack of the library stacks, and to `main` once they merge.

- **#77** adds source-bound transparent transaction metadata and the
  `transaction_metadata`, `aggregate_payment`, and `account_movement` fields of
  `TransactionHistoryDetails`. Public handles have no recovery source that
  supplies them. Under private recovery, Activity shows a reconstructed exact
  payment. Whole-fee evidence supports reconstruction but does not replace
  an unknown account fee in the receipt; the account fee keeps its
  `fee_state` for every amount. Two migrations add empty tables
  (`tpir_transaction_metadata`, `tpir_shared_derivations`); writing either
  raises the reader version, and neither changes policy, balances, or
  authority.
- **#86** retains `transactions.zip318_kind` and its view field throughout upgrades
  from published schemas. The explicit rollback preparation API is removed; Vizor
  removes its unused wrapper. Development databases that already dropped the column
  and writable downgrades after a private-ledger upgrade are outside this change's
  supported upgrade path. Unknown migration IDs still cause initialization to refuse.
- **#79** adds `WalletDb::check_transparent_transaction_inputs` and
  `SqlTransaction::new`, which hardware submission checks and account deletion
  use (see "Operations" and "Account deletion" above).
- **#81** exposes the Tor-routed lightwalletd channel, which the hardware
  broadcast path wraps to release its reservation once the request leaves
  ("Operations" above). It adds no migration.

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
