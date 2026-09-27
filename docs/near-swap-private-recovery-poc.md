# Private swap recovery POC

This software-wallet build restores refund and incoming swap notes through the
receiver directory and Enhance PIR. Use a separate mainnet test wallet identity.
The earlier POC wallets remain intact. The application rejects their prerelease
schema until its upgrade path is qualified.

## Recovery flow

1. Scan ordinary account history from before the funding transaction. Retain
   scanned nullifiers so an old payment can be checked for a later spend.
2. At the accepted tip, use Enhance PIR to authenticate pending Ironwood memos.
   Funding memos register refund keys. Incoming recovery registers 20 lookahead
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
   indices extend the lookahead. Newly added keys are checked on the next sync.
   Rewinds invalidate affected candidates, spend coverage and directory checks.

The shared witness file contains deduplicated Merkle sibling hashes for all
published payments. Every participating wallet downloads identical bytes before
receiver lookup. At height 3,497,852 it was 4,033,115 bytes. The 32 MiB directory
row file stays on the server. The wallet verifies each proof against its own
accepted root. It never trusts the file's root on its own.

## Build and services

Use these sibling checkout names so the local Cargo overrides resolve:

```text
vizor-wallet/
wallet-libraries-pir/
wallet-pir/
ipir-sp-compat/
```

Enable Rust feature `swap-receiving-poc` and set the compile-time environment
variable `VIZOR_SWAP_PRIVATE_RECOVERY=1`. The latter also selects private
Ironwood enhancement on every wallet connection. Keep both set through the
Flutter/Cargokit build. No generated FFI API changed.

The compatibility checkout keeps the same Spiral math version used by Vizor's
voting dependencies. Its receiver and Enhance responses were compared with the
real public refund fixture through the exact Vizor dependency graph.

The POC uses the public Enhance v9 native two-mask protocol at
`https://enhance-pir.valargroup.dev`, enabled through the client's
`native-reinspiring` feature. Receiver PIR is independently hosted at
`https://161-35-182-172.sslip.io`. No Mac or SSH tunnel is required for serving.
Requests are bounded, redirects are disabled, and Enhance routes must remain
on that exact HTTPS origin with standard TLS validation. This POC transport is
still direct-only: Tor must be off, and enabling it or cancelling sync cancels
outstanding recovery requests. There is no public transaction fallback on PIR
failure. Public service reachability does not itself add Tor transport support.

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

Private recovery scans only locally recorded operations while pending and through
ten blocks after the first supported NEAR terminal status. Repeated observations
and restarts preserve that deadline. Unknown statuses and transport failures do
not retire or reopen a watch. PIR closeout can outlive scanning without extending
it. Restored and lookahead keys never join ordinary scanning by themselves.

The private mode retains the shared nullifier map without pruning. Use a fresh
restore because evidence already pruned by an older build cannot be recreated
by enabling the mode. Witness publications must be within 100 blocks of the
accepted tip. The receiver droplet polls every ten seconds and publishes the
latest canonical tip with no confirmation delay, following Enhance's reorg rules.

Outgoing enhancement that needs missing historical compact context remains
private and pending. It is logged explicitly. This does not authenticate missing
transaction metadata or permit a public fallback. Inclusion authenticates a note
and position. Transaction IDs and Action indices remain indexer assertions,
checked for conflicts with local data. Directory omission detection, production
capacity, bounded nullifier storage and hardware qualification remain release work.

### Recovery completion and ordinary sync

Each key has a durable recovery target. A local operation targets the saved grace
height once that height has been scanned. Restored keys use their first accepted
restore tip. The receiver publication must cover that target before lookup; a
lagging publication causes no receiver queries or common witness download.
Completed targets stay fixed when new blocks arrive, so normal tip following needs
no receiver PIR requests. Newly found funding memos and paid receive indices expand
the deterministic key discovery window and create their own recovery targets.

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

Run `scripts/prepare-swap-pir-compat.sh` once before Cargo or Flutter. It creates or
verifies the sibling `ipir-sp-compat` checkout at commit
`79ca43b92c71bc33b99ba71a9841cc5da4d5e3b2`, preserving any existing different or dirty
checkout. Cargo cannot patch a Git URL with a different revision at the same URL,
so this small math compatibility dependency needs the verified checkout. The other
wallet and receiver dependencies use exact Git commits in `rust/Cargo.toml`, with
published crates patched at the root. `rust/Cargo.lock` captures the resolved graph.
Use Rust 1.98.0 and `scripts/generate-rust-bridge.sh` when regenerating the bridge.
The script only normalizes expanded inspection text for FRB's older parser.

Build with Rust feature `swap-receiving-poc`, Rust environment
`VIZOR_SWAP_PRIVATE_RECOVERY=1`, and matching mainnet Dart configuration. Preserve
the established local bundle, signing, and secure-store identity. Those local
settings are intentionally absent from this branch. The receiver runs only on its
DigitalOcean droplet; the Mac Studio needs no receiver daemon or ingestion job.
