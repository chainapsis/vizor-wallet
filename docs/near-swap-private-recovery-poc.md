# Private swap recovery POC

This software-wallet build restores refund and incoming swap notes through the
receiver directory and Enhance PIR. Use a separate mainnet test wallet identity.
The earlier POC wallets remain intact. The application rejects their prerelease
schema until its upgrade path is qualified.

## Recovery flow

1. Scan ordinary account history from before the funding transaction. Temporarily
   retain Ironwood nullifiers and spend locations already delivered by compact
   scanning so an old payment can be checked for a later spend.
2. At the accepted tip, authenticate pending Ironwood memos through ordinary
   enhancement, following the general Private queries setting.
   Funding memos register refund keys. Incoming recovery registers 50 lookahead
   keys. Historical key registration uses private discovery rather than queuing
   another block scan.
3. Accept the receiver publication against a locally scanned block. Download its
   common witness file and privately query the registered receivers. Fetch each
   matching payment's ciphertext suffix through Enhance PIR.
4. In a database transaction, authenticate ownership and memo, check the position
   and inclusion path against local chain state, and establish spend status from
   retained history. Store the note, key, memo, witness and known spend together.
   Missing evidence leaves a candidate pending without crediting balance.
5. Record completed directory checks by key and block anchor. Paid incoming
   indices extend the lookahead. Check the extended window before completing sync.
   Rewinds invalidate affected candidates, spend coverage and directory checks.
6. After all funding memos, own-send evidence, lookahead, directory checks and
   candidate imports are resolved, release old unrelated Ironwood spend evidence.
   Normal recent history and wallet-owned spend links remain. New scans retain
   their evidence until the next completed recovery pass.

The shared witness file contains deduplicated Merkle sibling hashes for all
published payments. Every participating wallet downloads identical bytes before
receiver lookup. At height 3,497,852 it was 4,033,115 bytes. The 32 MiB directory
row file stays on the server. The wallet verifies each proof against its own
accepted root. It never trusts the file's root on its own.

## Build and services

Use the mainnet build. NEAR address recovery always uses private directory discovery, independently of
**NEAR swap privacy** and the general **Private queries** setting. This exception
covers receiver discovery and matching note data. Ordinary transaction retrieval
still follows Private queries. Funding transactions pay transparent deposits, so
their refund memos and deposit addresses come from a public lightwalletd fetch
until transparent PIR exists. Creating a new private swap requires both switches
on. Both default off.
The [software-wallet guide](near-swap-software-poc.md) defines toggle behavior.
The complete software implementation is saved on `adam/near-swap-complete-20260929`
in the wallet, library and receiver service repositories. These are integration
branches to preserve the complete state before extracting review-sized PRs.

Dependencies are pinned in `rust/Cargo.toml` and `rust/Cargo.lock`. No sibling
math compatibility checkout or compile-time privacy environment variable is required.
Regenerate the bridge with the repository wrapper after API changes.

The POC uses the public Enhance v9 native two-mask protocol at
`https://enhance-pir.valargroup.dev`. Receiver PIR is independently hosted at
`https://161-35-182-172.sslip.io`. No Mac or SSH tunnel is required for serving.
Requests are bounded, redirects are disabled, and Enhance routes must remain
on that exact HTTPS origin with standard TLS validation. Receiver and Enhance
requests reuse ordinary Enhance PIR's route-aware HTTPS transport, including Tor,
cancellation and bounded responses. Manifest, setup, query and witness requests
all follow the same route. Incoming-address verification uses the same client.
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
  key checks must resume without duplicate balances.
- For an unspent privately recovered note, review an ordinary software send,
  confirm that note is selected, then let the user authorize the send. Verify its
  change belongs to the ordinary internal key.

## POC boundaries

New local operations use temporary compact scanning with no key-count cap.
Restored funding memos register directory work without adding historical keys to
trial decryption. Supported pending statuses keep a local watch active. A terminal
observation is persisted immediately, then a later fresh chain request anchors
ten more scanning blocks. Repeated observations preserve that horizon. Cached UI
status and failed polls do not refresh the observation time.

After two days without a supported observation, an unknown local operation moves
to directory follow-ups without being marked complete. Follow-ups back off from
one to twelve hours. Terminal operations also require a separate check twelve
hours after the first terminal observation. An expected Zcash refund cannot close
with an empty lookup. Incoming source-chain refunds do not imply a Zcash receipt.

The retention floor follows processed coverage and pending candidates, independent
of provider completion. Missing memos or unavailable directory data can extend
temporary retention. Sapling and Orchard keep their ordinary policies. Reorgs
rewind affected coverage. Pruning permits SQLite to reuse rows without forcing a
vacuum.

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

The coordinator reuses one directory session and common witness file across
batches. Small jobs use PIR. Large jobs download the common row file after checking
its length, digest and independently accepted chain coverage. At current geometry,
remaining PIR upload plus response bytes cross the 32 MiB file at about 240
one-page lookups. The initial 50/250/10,000 lookup test measured 7,034,703,
33,555,199 and 33,555,199 HTTP body bytes respectively, including setup. These
loopback measurements exclude headers and TLS. Common witnesses and note data
are separate costs for both modes.

Complete lookup results and authenticated ciphertexts are persisted atomically.
A restart resumes queued notes without another receiver lookup or ciphertext
retrieval. Already imported output identities are checked rather than imported
again. Inclusion, witness and spend validation still precede balance changes.
Processed coverage and final scheduling are committed together. Backoff and an
unavailable publication never make incomplete historical recovery appear complete.

New memos and paid receive indices extend recovery. Completed work makes no routine
requests. Both issuance settings may be off during recovery. File mode sends no
receiver-dependent public ranges, and PIR failure has no public fallback.

Funding memo recovery now persists completion per note together with its key and
provider watch. Maintenance retries missing memos and missing own-send evidence,
but returns only newly processed records. Changed memo data or funding heights
make a record eligible again. The forward migration starts with no inferred
completion. Registry lookup by key ID, receiver or reservation derives only the
selected key. Scanning reuses that validated derivation.

The SQLite scanner splits a batch at a watch boundary and derives only active keys.
Retirement removes trial decryption, preserving key IDs, note ownership, witnesses,
and nullifiers needed to spend recovered notes. Reorgs invalidate affected PIR
anchors and scan coverage; replay below a saved deadline uses that bounded watch.
The operation's deadline is a height budget, not a claim that its observed block
can never reorg. Late payments after the completed one-time closeout need a later
explicit recovery; swap addresses are not permanent receive addresses.

NEAR activity persistence and loading both replay supported statuses into the
wallet DB. The wallet deletion drain covers the status request and its resulting
writes. Existing records are linked by their registered refund or recipient
address, including records written before lifecycle integration.

Private enhancement is requested only for concrete query batches. Outgoing work
that needs local rediscovery remains durably queued without creating network
retries or repeated warnings by itself. This does not claim that unresolved
outgoing enrichment has been completed.

### Restore comparison instrumentation

`pir_http` records each completed HTTP attempt with service, request class,
application request/response byte counts, elapsed microseconds and success.
Receiver request classes distinguish manifest, public parameters, witness and
query pages. Enhance distinguishes GET setup requests and POST requests.
`pir_metric` records full receiver lookup, validation/insertion and private
recovery wall time; `sync_metric` records block download, exposed download wait,
scan/store and ordinary enhancement durations. Logs omit keys, receivers,
transaction identifiers, URLs and payloads from these new metric events.

Phase durations are inclusive; prefetch download overlaps scanning. Use sync
start/completion for wall time instead of summing nested timers. In-flight
cancelled HTTP attempts do not emit completion metrics, so report cancelled runs
separately. The baseline disables swap-receiving-poc entirely; it measures
ordinary wallet work and is not expected to recover the special swap receipts.

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
request is recorded before contacting NEAR and each accepted deposit instruction
is retained, even if the user leaves the review screen. An explicit quote
validation rejection removes that request's scan watch; an uncertain outcome
stays reserved. Starting a swap locks the draft and the next swap gets another
eligible address. At most three distinct unfunded incoming reservations may be
open for an account, across all source chains. Provider deposit evidence removes
that reservation from the unfunded count.

The existing status refresh loop also checks reservations absent from the activity
UI. An unpaid slot can be reclaimed after 48 hours from creation and from every
accepted quote's deposit deadline. Every attempt must have a fresh successful
provider check, with no pending or unknown funded operation. Reclamation then
requires a fresh complete empty receiver PIR lookup plus verified per-address
coverage through the wallet's accepted tip. The publication may lag by at most
five blocks only when those missing blocks have also been checked with this key.
Provider errors, unknown quote outcomes, incomplete PIR coverage, or a payment
retain the reservation. Cleanup runs while the app is active and before requesting
another address; it does not need an operating-system service.

Allocation picks the lowest eligible never-paid index. A sticky used marker keeps
paid addresses excluded after spending or a rewind. Reclaimed reservations and
quote associations remain in the database for late-payment attribution. Address
reuse does not invalidate old deposit instructions and cannot prove that no future
payment will arrive. A late payment still belongs to the same key; receipt during
an active watch is detected locally, while receipt after final PIR closeout needs
an explicit later recovery as described above.

The seed-recovery gap is 50, and issuance may not exceed 50 slots after the highest
canonical receipt (indices 0 through 49 before the first receipt). Provider deposit
status and local issuance do not advance that boundary. This bound is enforced
before a draft is resumed as well as before a new reservation is created. Every
address must have complete verified history before quoting, with no sync restart.
An existing draft reuses its durable empty-address check when continuous per-key
scanning covers the tail. That evidence is independent of PIR closeout checkpoints
and survives quote edits and restart. A newly checked or reclaimed address can use
a publication up to five blocks behind if its local scan ranges cover the gap.
Otherwise the wallet downloads and checks all missing compact blocks with that
key, bounded to five blocks. This uses the same trusted lightwalletd source as
normal compact scanning. It checks canonical hashes, predecessor links and action
counts before accepting the result. A discovered payment permanently excludes
the address and queues private recovery without crediting balance prematurely.

Quote issuance rechecks used markers and coverage atomically. Rewinds invalidate
affected address checks. Missing blocks, malformed responses or coverage holes
hold the reservation. These address checks do not relax full seed recovery or
fixed retirement targets, and do not add permanent scanning keys. Missing old
outgoing enhancement metadata no longer blocks incoming address preparation;
refund allocation still waits for unresolved internal funding memos.

Older allocated unpaid keys without durable quote records are conservatively
reserved during migration. They are not automatically reclaimed based on missing
history. Independent installations of the same seed do not share local pending
reservations; coordinating concurrent issuance across devices remains outside
this POC.

Automated tests cover the paid/empty/paid/paid/paid example, restart, explicit quote
rejection versus lost responses, the three-reservation cap, the 50-slot bound,
late-payment races, stale statuses, canonical anchors, and deletion draining.
For a manual check, start three small incoming attempts without funding them and
confirm a fourth is blocked; quote refreshes should keep the same receive slot.
Fund one existing attempt and check that provider deposit evidence permits another.
The 48-hour reclaim case is exercised with controlled test time, not by changing
production wallet timestamps.
