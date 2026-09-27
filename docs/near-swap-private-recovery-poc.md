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

The POC uses the existing v7 Enhance protocol. Local SSH tunnels must provide
receiver PIR at `127.0.0.1:18380` and Enhance PIR at `127.0.0.1:18280`. Requests
are bounded, redirects are disabled, and Enhance routes must stay within that
tunnel. Tor must be off for this explicit tunnel configuration. Enabling Tor or
cancelling sync cancels outstanding recovery requests. There is no public
transaction fallback on PIR failure.

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

Registered keys remain active after recovery. Terminal-status retirement and
its delayed reconciliation schedule still need application integration. The
private mode retains the shared nullifier map without pruning. Use a fresh
restore because evidence already pruned by an older build cannot be recreated
by enabling the mode. Witness publications must be within 100 blocks of the
accepted tip. The local test service refreshes every five minutes.

Outgoing enhancement that needs missing historical compact context remains
private and pending. It is logged explicitly. This does not authenticate missing
transaction metadata or permit a public fallback. Inclusion authenticates a note
and position. Transaction IDs and Action indices remain indexer assertions,
checked for conflicts with local data. Directory omission detection, production
capacity, bounded key retirement and hardware qualification remain release work.
