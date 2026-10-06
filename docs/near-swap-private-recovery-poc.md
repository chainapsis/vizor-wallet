# Private swap recovery POC

This software-wallet build restores refund and incoming swap notes through the
receiver directory and Enhance PIR. Use a separate mainnet test wallet identity.
The earlier POC wallets remain intact. The application rejects their prerelease
schema until its upgrade path is qualified. Databases from later prerelease
builds of this branch cannot migrate either; restore those wallets from the
recovery phrase into a new database.

Swap keys issued on this device never use the directory. They are trial-decrypted
from issuance until their swap closes, including while catching up after time
offline; a refund key starts when the wallet stores the swap's funding
transaction. The directory is used only for keys recovered from the seed.

## Recovery flow

1. Scan ordinary account history from before the funding transaction. Temporarily
   retain Ironwood nullifiers and spend locations already delivered by compact
   scanning so an old payment can be checked for a later spend.
2. At the accepted tip, authenticate pending Ironwood memos through ordinary
   enhancement, following the general Private queries setting.
   Funding memos register refund keys. Incoming recovery registers 30 lookahead
   keys. Each key gets one private directory sweep instead of a block rescan.
3. Accept the receiver publication against a locally scanned block. Download its
   common witness file and privately query the swept receivers. Fetch each
   matching payment's ciphertext suffix through Enhance PIR.
4. In a database transaction, authenticate ownership and memo, check the position
   and inclusion path against local chain state, and establish spend status from
   retained history. Store the note, key, memo, witness and known spend together.
   Missing evidence leaves a candidate pending without crediting balance.
5. Complete each sweep at its block anchor. A refund key then scans from the next
   block until 30 days after its funding block, and an unpaid incoming key for
   24 hours, to catch a payment from a swap in flight at restore. Paid incoming
   indices extend the lookahead, and the new keys are swept too. Rewinds below a
   sweep reopen it and invalidate affected candidates and spend coverage.
6. After all funding memos, own-send evidence, lookahead, sweeps and candidate
   imports are resolved, release old unrelated Ironwood spend evidence. Normal
   recent history and wallet-owned spend links remain. New scans retain their
   evidence until the next completed recovery pass.

The shared witness file contains deduplicated Merkle sibling hashes for all
published payments. Every participating wallet downloads identical bytes before
receiver lookup. At height 3,497,852 it was 4,033,115 bytes. The 32 MiB directory
row file is downloaded only for large jobs (see below). The wallet verifies each
proof against its own accepted root. It never trusts the file's root on its own.

## Build and services

Use the mainnet build. NEAR address recovery always uses private directory discovery, independently of
**NEAR swap privacy** and the general **Private queries** setting. This exception
covers receiver discovery and matching note data. Ordinary transaction retrieval
still follows Private queries. Refund memos sit on internal Ironwood change, so
recovery needs no funding transaction. Creating a new private swap requires both
switches on. Both default off.
The [software-wallet guide](near-swap-software-poc.md) defines toggle behavior.
The complete software implementation is saved on `adam/near-swap-complete-20260929`
in the wallet, library and receiver service repositories. These are integration
branches to preserve the complete state before extracting review-sized PRs.

Dependencies are pinned in `rust/Cargo.toml` and `rust/Cargo.lock`. No sibling
math compatibility checkout or compile-time privacy environment variable is required.
Regenerate the bridge with the repository wrapper after API changes.

The POC uses the public Enhance v9 native two-mask protocol at the configured
Enhance endpoint, `https://enhance-pir.valargroup.dev` unless
`VIZOR_ENHANCE_PIR_URL` overrides it. Receiver PIR is independently hosted at
`https://161-35-182-172.sslip.io`. No Mac or SSH tunnel is required for serving.
Requests are bounded, redirects are disabled, and Enhance routes must remain on
that exact HTTPS origin with standard TLS validation. Receiver and Enhance
requests reuse ordinary Enhance PIR's route-aware HTTPS transport, including
Tor, cancellation and bounded responses. Vizor supplies that transport, the
service origins, its wallet write lock and the run budget to the library's
sweep. Manifest, setup, query and witness requests all follow the same route.
There is no direct fallback when Tor fails and no public transaction fallback
when PIR fails.

Signing, bundle identity and secure-store overrides stay local. Record the app
path, bundle ID, secure-store service and new wallet DB path before opening it.
Use the same secure-store override in Dart and Rust. Do not open either earlier
POC database with this build or reuse its secure-store namespace.

## Manual test

- Restore into the new isolated wallet with a birthday before the swap funding
  transaction. Enter the seed locally. Never include it in logs or a handoff.
- Confirm refund and incoming keys are registered after ordinary scanning, and
  the private phase applies their notes without a receiver-specific block replay.
- Compare receipt amounts, nullifiers, positions and spend status with the prior
  test evidence. The spent refund must remain spent. Unspent receipts must appear
  exactly once after closing and reopening the application.
- Interrupt the private phase once and reopen. Queued candidates and completed
  sweeps must resume without duplicate balances.
- For an unspent privately recovered note, review an ordinary software send,
  confirm that note is selected, then let the user authorize the send. Verify its
  change belongs to the ordinary internal key.

## POC boundaries

Keys issued on this device are trial-decrypted with no key-count cap until their
swap closes. A refund key starts only when the wallet stores the swap's funding
transaction, so a quote that is never funded never scans. A key closes as soon
as every provider status on it is final and its expected Zcash receipts have 10
confirmations, the ZIP 315 depth for untrusted notes, so a reorg cannot strand a
receipt on a closed key. Refunds, positive `refundedAmount` values and
exact-output `SUCCESS` leftovers are expected receipts for refund keys; an
incoming key expects `amountOut`. Incoming source-chain refunds do not imply a
Zcash receipt. A `FAILED` status is inconclusive. Every key closes 30 days after
its quote deadline whatever the provider reports. Cached UI status and failed
polls do not record an observation. Keys close only at the end of a sync, once
the tip is revalidated and scanned, so blocks mined while the app was offline
are checked first. Closing uses the earlier of the device clock and the tip's
block time, so a clock that runs fast cannot close a key early.

A restored key scans new blocks after its sweep only as described in the
recovery flow, and a restored incoming key issued later starts at the tip. A
payment that arrives after its key closed, such as a second refund, is found by
turning **NEAR swap privacy** off and on, which sweeps every closed swap key once
through the directory, or by a later seed restore. Swap addresses are not
permanent receive addresses.

The retention floor follows unfinished sweeps and pending candidates,
independent of provider completion. Missing memos or unavailable directory data
can extend temporary retention. Sapling and Orchard keep their ordinary
policies. Reorgs reopen affected sweeps. Pruning permits SQLite to reuse rows
without forcing a vacuum.

If an authenticated, included candidate needs pruned spend history, the library
coalesces replay of the whole public account recovery interval. Repeated attempts
do not restart the same replay. A candidate before that interval stays explicitly
unresolved until the range is widened. Pending candidates never enter balances.

Witness publications must be within 100 blocks of the
accepted tip. The receiver droplet polls every ten seconds and publishes the
latest canonical tip with no confirmation delay, following Enhance's reorg rules.

Outgoing enhancement that needs missing historical compact context remains
private and pending. It is logged explicitly. This does not authenticate missing
transaction metadata or permit a public fallback. Inclusion authenticates a note
and position. Transaction IDs and Action indices remain indexer assertions,
checked for conflicts with local data. Directory omission detection, production
resource sizing, temporary-cache sizing under long outages and hardware qualification remain release work.

### Recovery completion and ordinary sync

`WalletDb::prepare_swap_discovery_batch` selects bounded metadata batches without
deriving historical keys. It counts the whole job's remaining uncached lookups.
Retries retain fixed canonical targets. Attempts are leased individually before
network I/O so interruption cannot postpone the unstarted tail. A failed key does
not prevent other selected work from progressing.

The sweep runs in wallet-libraries' `zakura-pir-receiver` crate, which reuses
one directory session and common witness file across batches. Small jobs use
PIR. Large jobs download the common row file after checking its length, digest
and independently accepted chain coverage. At current geometry, remaining PIR
upload plus response bytes cross the 32 MiB file at about 240 one-page lookups.
The initial 50/250/10,000 lookup test measured 7,034,703, 33,555,199 and
33,555,199 HTTP body bytes respectively, including setup. These loopback
measurements exclude headers and TLS. Common witnesses and note data are
separate costs for both modes.

Complete lookup results and authenticated ciphertexts are persisted atomically.
A restart resumes queued notes without another receiver lookup or ciphertext
retrieval. Already imported output identities are checked rather than imported
again. Inclusion, witness and spend validation still precede balance changes.
A sweep completes only after its candidates are applied. Backoff and an
unavailable publication never make incomplete historical recovery appear complete.
Failed key lookups back off from one minute to twelve hours, and an unavailable
service is retried on the next sync; neither fails ordinary sync. One recovery
run takes at most three minutes, and sweeps it does not reach wait for the next
sync. When a finished sweep starts a key scanning from its anchor, sync scans
those blocks before it completes.

New memos and paid receive indices extend recovery. A completed sweep makes no
further requests unless a rewind or a history recheck queues it again. Both
issuance settings may be off during recovery. File mode sends no
receiver-dependent public ranges, and PIR failure has no public fallback.

Funding memo recovery now persists completion per note together with its key.
Maintenance retries missing memos and missing own-send evidence, but returns
only newly processed records. Changed memo data or funding heights make a record
eligible again. The forward migration starts with no inferred completion.
Registry lookup by key ID, receiver or reservation derives only the selected
key. Scanning reuses that validated derivation.

Every compact scan batch includes all active keys and derives only those.
Activating a key queues a rescan of blocks already scanned from its start height,
and a batch that missed a newly activated key requeues its range. Closing a key
removes trial decryption, preserving key IDs, note ownership, witnesses, and
nullifiers needed to spend recovered notes. Reorgs invalidate affected sweep
anchors and candidates.

NEAR activity persistence and loading replay outgoing swap statuses into the
wallet DB, matching each record to its refund key by the refund address. Incoming
quotes record theirs through their reservation instead. The wallet deletion drain
covers the status request and its resulting writes.

Private enhancement is requested only for concrete query batches. Outgoing work
that needs local rediscovery remains durably queued without creating network
retries or repeated warnings by itself. This does not claim that unresolved
outgoing enrichment has been completed.

### Restore comparison instrumentation

`pir_metric` records private recovery wall time; `sync_metric` records block
download, exposed download wait and scan/store durations. Logs omit keys,
receivers, transaction identifiers, URLs and payloads from these metric events.

Phase durations are inclusive; prefetch download overlaps scanning. Use sync
start/completion for wall time instead of summing nested timers. A cancelled
recovery emits no `pir_metric`, so report cancelled runs separately.

### Reproducing this checkpoint

The earlier checkpoint used the POC build flags and a sibling math compatibility
checkout. The current integration uses the saved settings and published math family.
Use Rust 1.98.0 and `scripts/generate-rust-bridge.sh` for bridge generation.
Preserve the established local bundle, signing, and secure-store identity. These
local settings are intentionally absent from the branch. The Mac Studio needs no
receiver daemon or ingestion job.

### Incoming address reservations

Incoming swaps persist a reservation separately from received notes and UI activity.
Retries and quote edits reuse the current draft, including after restart. Each
request is recorded with its deposit deadline just before it is sent to NEAR,
after local validation, and each accepted deposit instruction is retained, even if
the user leaves the review screen. An explicit quote validation rejection removes
that request's scan watch; an uncertain outcome stays reserved until its deadline
is 24 hours past. Starting a swap locks the draft whose quote matches both the
deposit address and memo, and the next swap gets another eligible address. At
most 15 distinct unfunded incoming reservations (half the 30-slot gap) may be open
for an account, across all source chains. Provider deposit evidence or the ZEC
payment arriving removes that reservation from the unfunded count.

The existing status refresh loop also checks reservations absent from the activity
UI. An unpaid slot can be reclaimed after 24 hours from creation and from every
accepted quote's deposit deadline. Every attempt must have a fresh successful
provider check, with no pending or unknown funded operation. The key has been
trial-decrypted since issuance, so reclamation then only requires the wallet to
be scanned to its tip with no payment to that address. Provider errors, unknown
quote outcomes before their deadline has passed by 24 hours, an unscanned tail,
or a payment retain the reservation. Cleanup
runs while the app is active and before requesting another address; it does not
need an operating-system service.

Allocation picks the lowest eligible never-paid index, except during the 24-hour
watch after a restore, when it picks the highest one in the recovery window: the
lowest unpaid indices may belong to the old device's swaps still in flight. A
sticky used marker keeps paid addresses excluded after spending or a rewind.
Reclaimed reservations and quote associations remain in the database for
late-payment attribution. Address reuse does not invalidate old deposit
instructions and cannot prove that no future payment will arrive. A reclaimed key
keeps scanning, so the slot is reissued with no gap in its history and a late
payment is still found locally.

The seed-recovery gap is 30, and issuance may not exceed 30 slots after the highest
canonical receipt (indices 0 through 29 before the first receipt). Provider deposit
status and local issuance do not advance that boundary. This bound is enforced
before a draft is resumed as well as before a new reservation is created. New
reservations wait for incoming restore sweeps, which may reveal paid indices.

Quoting requires the address to be unpaid, with no queued candidate, and the
wallet scanned to its tip. This needs no directory lookup or extra block download.
A discovered payment permanently excludes
the address and is credited through ordinary scanning. Quote issuance rechecks
these conditions atomically. Missing old outgoing enhancement metadata does not
block incoming address preparation; refund allocation still waits for unresolved
internal funding memos.

Independent installations of the same seed do not share local pending
reservations; coordinating concurrent issuance across devices remains outside
this POC.

Automated tests cover the paid/empty/paid/paid/paid example, restart, explicit quote
rejection versus lost responses, the 15-reservation cap, the 30-slot bound,
late-payment races, stale statuses, reissuing a swept key, and deletion draining.
For a manual check, confirm that quote refreshes keep the same receive slot and
that funding an attempt frees its slot for another swap. The 15-reservation cap is
covered by automated tests, and the 24-hour reclaim case is exercised with
controlled test time, not by changing production wallet timestamps.
