# Private Ironwood transaction enhancement

Private Ironwood recovery is off by default and available on mainnet under
**Settings → Privacy → Private Ironwood recovery**. It uses randomized iPIR queries
for protected Ironwood transactions. Durable transaction-wide protection withholds
ordinary `GetTransaction(txid)` enhancement independently of whether private work
is active, suspended, or already finished. Mixed-pool transactions and the existing
status/address-history paths retain their backend routing rules.

## Shared client and build inputs

Vizor supplies application policy and its existing direct/Tor transport. The
`zakura-pir-enhance` client owns endpoint construction, initialization decoding,
parameter checks, generation binding, row coalescing, and record extraction.
Its optional `wallet` feature provides anchor conversion, scanned-state acceptance,
and mapping records to the original captured request identities:

```toml
[dependencies.zakura-pir-enhance]
git = "https://github.com/zakura-core/wallet-libraries.git"
rev = "8df21dfd8f61da72a1af4df61efd648f51c18210"
default-features = false
features = ["wallet"]
```

The backend depends on the separate `zakura-pir-enhance-types` crate. It does not
depend on the client, so enabling the client's wallet adapter cannot create a
cycle. SQLite remains a test dependency of the shared client.

The default service is `https://enhance-pir.valargroup.dev`.
`VIZOR_ENHANCE_PIR_URL` overrides it; `VIZOR_MEMO_PIR_URL` is the compatibility
fallback. HTTP endpoints are rejected. The local setup limit is 65,536 logical
rows, independent of the server's advertised resource requirements.

## Recovery behavior

1. Fetch and inspect a pending generation without allocating PIR setup.
2. Check network policy, resource limits, and its anchor against locally scanned
   block hash and Ironwood tree size. Wait when the anchor has not been scanned;
   invalidate mismatched sessions.
3. Allocate setup only after wallet acceptance. Each batch remains bound to its
   immutable generation. Duplicate positions and shared rows are coalesced by the
   client; successful results can be written before a later row fails.
4. Apply records through `EnhancePirWrite` using captured request identities.
   Incoming/outgoing note recovery is authenticated against wallet context.
   Schema-7 transaction metadata remains trusted indexer data under the existing
   backend rules. A service failure never authorizes public fallback.
5. For rediscovery, reuse `MemoryBlockSource` or fetch the requested height through
   the ordinary trusted LWD compact-block path. Apply valid partial reconstruction
   and retain unresolved jobs. Missing funding/anchor context and outgoing
   non-recovery remain incomplete suspensions.
6. Reread durable work after progress. Active deferred work retries through normal
   foreground polling even at an unchanged chain tip. Suspensions alone do not
   trigger network work. Initialization refresh is limited to once per minute for
   the current wallet, and accepted older coverage can run while a pending newer
   anchor awaits scanning.

No application write lock or database transaction spans network I/O. Counts are
logged in aggregate; local transaction/action identities are not sent to PIR.

## Preference transitions and status

Changing the setting blocks repeated interaction and new foreground starts,
quiesces native preparation, and waits for foreground sync to stop. Only then does
it persist the install preference, change Rust mode, publish visible state, and
resume eligible work with newly configured handles. Old batches are discarded.
Ordinary enhancement and fee-parent requests check cancellation before dispatch
and after completion. A dispatched request cannot be recalled, but cancellation
prevents subsequent queued dispatch.

A quiescence timeout or preference-write failure leaves the committed mode
unchanged and displays a retry message. The preference lives outside secure-store
reset data and is retained when deleting accounts, resetting, or reimporting.
Existing saved choices are migrated from the legacy secure-store key at bootstrap.
Enabling recovery does not initiate a rescan; it processes durable schema-7 work,
including metadata backfill and rediscovery obligations. Previously disclosed
transaction IDs cannot be made private retroactively.

`get_enhance_recovery_status` returns flat query, rediscovery, and suspension counts
from durable work, plus current-wallet transient service state. It is internal
polling data, not a user-facing surface: the client reads it every foreground poll
to decide whether outstanding obligations justify restarting sync at an unchanged
chain tip. Neither settings layout renders these counts. Queue depth is dominated by
obligations that can never complete — dummy actions, outputs the wallet cannot open —
so shown to a user they read as failures to act on. Both layouts therefore display
only the toggle and the feedback for the user's own setting transition.

Suspended work is not retryable, so it is excluded from the restart decision on its
own. Retryable work (queries plus rediscovery) that stays at exactly the same count
across attempts is backed off — 30 seconds, doubling to a 10-minute ceiling — so a
service with no usable snapshot cannot turn every 10-second poll into a full
foreground sync. Any change in the count, in either direction, restores the base
interval. Syncs driven by a new chain tip or an incomplete previous sync are
unaffected and run recovery as usual.

## Verification and generation

From `rust/`, run `cargo test --lib wallet::sync_engine::enhance` for the affected
Rust tests. From the project root:

```sh
python3 scripts/generate-frb.py
fvm flutter analyze
fvm flutter test test/providers/enhance_pir_provider_test.dart test/providers/sync_provider_test.dart test/features/settings/settings_screen_test.dart
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/settings/mobile_settings_screen_test.dart
```

FRB 2.11 cannot parse the compiler's expanded `pin!` `super let` syntax in the
voting dependency. The generation wrapper normalizes that expansion for parsing
only. It changes neither dependency sources nor compiled program semantics.

Deterministic visual fixtures are `settings-recovery`,
`settings-recovery-changing`, and `mobile-settings-recovery`. Render with
`scripts/figma-compare.sh widget --scenario <id> --theme dark`, adding
`--form-factor mobile` for the mobile fixture.

The client and wallet-library patches are pinned to shared revision
`8df21dfd8f61da72a1af4df61efd648f51c18210`; no absolute local library paths are required.
The existing locally modified voting checkout
was preserved. This checkout's manifest resolves `zcash_voting 5.0.0` from the
registry; verification used that resolution without changing voting sources. Any
local voting override used by another development environment remains a separate
portability prerequisite.

Deterministic tests do not validate deployed end-to-end recovery. Live service
smoke tests and heavy regtest/device suites remain separate acceptance steps.
Timing and query counts remain observable; Vizor does not add cover traffic.

## Review fixes

- Snapshot refresh failures retain a revalidated older session and process its
  covered records. Cancellation still exits immediately; uncovered work retries
  under the existing one-minute initialization backoff.
- Recovery-setting quiescence and cleanup have bounded deadlines. Native iOS
  callbacks check their own lease before pausing managers; releasing an expired
  lease wakes its drain waiter without cancelling an admitted broadcast. Each
  transition uses a distinct scoped lease, including retries.
- Ordinary enhancement runs before completion even without a new scan batch,
  covering newly exposed fallback work and disabling private recovery at the tip.
- `scripts/test-ios-migration-outbox-gate.sh` exercises lease retirement and late
  callbacks alongside the existing broadcast/drain tests. Provider tests execute
  the real setting transition with a controlled native channel.

### Accepted traffic-analysis limitation

Batch coalescing is intentionally retained without padding. For two known,
distinct covered positions, one request indicates a shared packed row and two
requests indicate different rows. The PIR service does not learn the row index
from this count, but it can learn relationships between queries when batch size
is known. Query counts also depend on duplicates, coverage, and early termination.
This leakage is accepted for now to reduce PIR computation and bandwidth; Vizor
makes no fixed-volume, timing-unlinkability, or row-relationship privacy claim.
See the shared integration document's accepted batch traffic-analysis section.
Custom transports return opaque checked `ResponseBody` values; both direct and
Tor routes stream chunks through the request-provided collector.

Rediscovery first reuses the current in-memory compact-block batch. When the
required block is no longer cached, Vizor downloads a trailing 100-block range
ending at that height. This avoids an isolated one-block request but remains an
accepted limitation: an informed lightwalletd can infer that the range endpoint
is the rediscovery height. No transaction ID is disclosed by this request.

### Typed policy and partial progress

Vizor supplies its typed `WalletNetwork` to the safe shared wallet adapter, which
derives the network identifier and NU6.3 activation height. An unscheduled upgrade,
pre-activation anchor, or wrong advertised network cannot authorize setup.
The shared batch stream processes covered rows before reporting uncovered positions
and yields cancellation for remaining covered positions lazily. Uncovered work is
retained for a later snapshot; only authenticated backend routing can require LWD.
