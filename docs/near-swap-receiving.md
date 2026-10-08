# NEAR swap receiving

Software accounts receive NEAR swap refunds and incoming swap payouts at per-swap
Ironwood addresses derived from the account's viewing key, so swaps cannot be
linked through a shared address. Every address is recoverable from the seed. A
software account is one Vizor derives from a seed, including accounts added from
another seed; hardware and view-only accounts keep their existing swap addresses.

## Settings

On mainnet, turn on **Private queries**, then **NEAR swap privacy** in Settings. Both
default off and are saved for this installation. A new swap address needs both on.
Turning Private queries off also turns NEAR swap privacy off, and turning Private
queries back on does not re-enable it. Desktop and mobile share the preference.

Turning NEAR swap privacy off only stops new addresses. Existing reservations,
funding memos, keys, notes and status tracking remain, received notes stay
spendable, and recovery runs for every software account with either setting off.
Turning NEAR swap privacy on sweeps every closed swap key once more (see
[Closing](#closing)).

## Issuing addresses

The first quote fetches the live chain height without updating the wallet tip or
starting sync. Issuance requires the wallet scanned contiguously to within ten
blocks of that height. Refund and incoming addresses use independent index
sequences.

- **Refund address** (sending ZEC). Reserving first recovers confirmed funding
  records, and waits while one still lacks its memo, so an index the seed already
  used is never issued again. An accepted quote records its deposit address
  against the refund key before it is shown, and funding requires that record. The
  funding transaction carries the refund index in a binary memo on ordinary
  internal Ironwood change and pays only the transparent deposit address; a
  zero-value change note is valid. Funding spends only Ironwood notes, so the
  change stays in Ironwood; Orchard or Sapling funds must be moved to Ironwood
  first. Quotes whose deposit needs a memo, and
  multi-step funding, are rejected. A refund can only follow a deposit, so the
  refund key starts scanning when the wallet stores the funding transaction, and a
  quote never funded never scans.
- **Incoming address** (receiving ZEC). The key scans from the first unscanned
  block until its swap closes. Missing outgoing enhancement metadata does not
  block it. See [Incoming reservations](#incoming-reservations).

Quote errors, amount edits and refreshes keep the same address for the current
account and direction. Starting a swap, quoting for another account or direction,
or restarting the app needs a new refund address; the incoming draft is stored in
the wallet and resumed until a swap starts with it. Errors never roll back a key
that may already have been sent to the provider.

Received notes keep their derived key for reconstruction and software spending,
and change returns to the ordinary internal key.

## Closing

Keys issued on this device are trial-decrypted, with no key-count cap, until their
swap closes. A key closes as soon as every provider status on it is final and its
expected Zcash receipts are in. Refunds, positive `refundedAmount` values and
exact-output `SUCCESS` leftovers are expected receipts for a refund key; an
incoming key expects `amountOut`. A source-chain refund of an incoming swap is not
a Zcash receipt, and `FAILED` is inconclusive. A key also closes 30 days after its
quote deadline, whatever the provider reports, except an incoming key with an open
reservation. An abandoned incoming address stops scanning when its reservation is
reclaimed. Either way, no key closes while a receipt is unmined
and unexpired or has fewer than 10 confirmations (ZIP 315's untrusted depth), so a
reorg cannot strand a receipt. A rewind that un-mines a closed key's receipt, such
as Vizor's own repair rewinds, reopens the key until the receipt is confirmed
again. Incoming payouts show as pending as soon as they reach the mempool.

Statuses are recorded as they are fetched, by the activity refresh and by deposit
submission; cached UI status and failed polls record nothing. Keys close only at
the end of a sync, once the tip is revalidated and scanned, so blocks mined while
the app was offline are checked first. Closing uses the earlier of the device clock
and the tip's block time, so a clock that runs fast cannot close a key early.

A payment after its key closed, such as a second refund, is found by turning NEAR
swap privacy off and on, which sweeps every closed key once through the receiver
directory, or by a seed restore. Swap addresses are not permanent receive
addresses.

## Restore

A seed restore finds swap keys without trial-decrypting history for every index:

1. Ordinary scanning runs from the account birthday. Ironwood spend evidence that
   compact scanning already delivered is retained, so an old payment can be
   checked for a later spend.
2. At the tip, confirmed internal funding memos register refund keys, but only when
   the same account supplied an input to the funding transaction. Thirty incoming
   lookahead keys are registered from the birthday or Ironwood activation,
   whichever is later.
3. Each restored key gets one receiver-directory sweep. The wallet accepts a
   publication at a block it scanned and downloads its filters, which every wallet
   downloads alike, then tests each receiver locally. Only a receiver the paid
   filter holds is queried over PIR, with the common witness file, and each
   matching payment's note data comes over Enhance PIR in batches, saved as it
   arrives. A wallet with nothing to look up makes no PIR query. The wallet
   authenticates the note and memo with the derived key, checks the inclusion path
   against its own chain and the spend state against retained history, then stores
   the note, key, memo, witness and known spend together. Missing evidence leaves
   a candidate pending without crediting balance; an answer that fails a check is
   asked for again.
4. A key the recent filter holds, because NEAR was given its address in the last
   day, keeps scanning for 24 hours after its sweep, catching a payout or refund
   from a swap in flight at restore. Any other key closes at its sweep. The wallet
   trusts the recent filter only while it is current, NEAR's feed having been read
   within the last fifteen minutes, and covers the whole day; otherwise every
   restored key keeps scanning for 24 hours. Paid incoming indices extend
   the lookahead, and the new keys are swept too. A key the seen filter holds,
   because NEAR was ever given its address, is marked quoted, so this device does not
   hand out the old device's addresses again.
5. Once memos, lookahead, sweeps and candidates are resolved, old unrelated spend
   evidence is released. Other pools keep their ordinary retention.

Restore makes no NEAR status request and cannot recreate a swap's activity record
or an incoming swap's provider association. Incoming recovery has a gap limit of
30 consecutive unpaid indices. A payment before the account birthday is not
tracked, as with any note, but once its inclusion is checked its index is marked
used and counts toward that window.

Sweeps resume after interruption without repeating finished lookups. Failed
lookups back off from one minute to twelve hours, one recovery run takes at most
three minutes, and an unavailable service is retried on the next sync; none of
these fails ordinary sync or makes recovery appear complete. Rewinds below a sweep
reopen it. If an included candidate needs pruned spend history, the library
replays the account's public Ironwood recovery interval once.

## Incoming reservations

Incoming swaps persist a reservation separately from notes and activity. Each quote
request is recorded with its deposit deadline just before it is sent, and each
accepted deposit instruction is kept even if the user leaves the review screen. An
explicit quote rejection releases the request; an uncertain outcome holds the
address until its deadline is two hours past. Starting a swap locks the draft whose
quote matches the deposit address and memo, and the next swap gets another address.

- Issuance takes the lowest address never quoted and reuses the lowest abandoned
  one only when nothing else fits. It never goes more than 30 indices past the
  highest receipt with 10 confirmations, and waits for incoming restore sweeps,
  which may reveal paid or quoted indices. When swaps in progress hold all 30, a
  new quote is refused with a message to wait for one to finish; an unused quote
  frees its address two hours after its deadline.
- An unpaid reservation is reclaimed two hours after its creation and every
  quote's deposit deadline, given a fresh conclusive provider status and the
  wallet scanned to its tip with no payment to the address. The status refresh
  loop also checks reservations missing from the activity list. A reclaimed key
  stops scanning: every quote is past its deadline with a conclusive status, so no
  swap can pay it.
- Quoting requires the address unpaid, with no queued restore candidate, and the
  wallet scanned to its tip. A paid address is permanently excluded.

Installations of the same seed do not share pending reservations.

## Services

Swap recovery uses the configured Enhance endpoint
(`https://enhance-pir.valargroup.dev` unless `VIZOR_ENHANCE_PIR_URL` overrides it)
and the receiver directory at `https://161-35-182-172.sslip.io`. Both use the
route-aware HTTPS transport of ordinary Enhance PIR, honoring Tor and cancellation,
with bounded requests, no redirects and no direct or public fallback. Receiver
discovery and its note data always use PIR, whatever the Private queries setting;
ordinary transaction and memo retrieval follows that setting.

A publication must commit to mainnet's genesis, cover history from Ironwood
activation, and end within 100 blocks of the wallet's scanned tip. The directory
polls every ten seconds and publishes the latest canonical tip. The common witness
file holds deduplicated sibling hashes for every published payment; each wallet
downloads the same bytes and verifies every path against its own accepted root.
Large jobs download the row file (32 MiB today) instead of querying over PIR, and
a key with more than 16 payments switches to it; the directory can see either.

Inclusion authenticates a note and its position; transaction IDs and action indices
remain directory assertions, checked against local data. Directory omission
detection, production sizing and hardware qualification remain release work.

## Building

Dependencies are pinned in `rust/Cargo.toml` and `rust/Cargo.lock`. Regenerate the
bridge with `scripts/generate-rust-bridge.sh` after API changes. For a test install,
use an isolated bundle, wallet database and secure-store service, the same in Dart
and Rust, and do not reuse an installed app's wallet identity. A database from a
prerelease build cannot migrate; restore that wallet from its recovery phrase into
a new database.

## Tests

The shared library covers derivation, funding records, scanning, closing, restore
sweeps and reservations. In this repository:

```sh
cargo test --manifest-path rust/Cargo.toml --lib swap
fvm flutter test test/features/swap
```

Manual checks use a disposable software wallet. Live funding is a separate,
explicitly authorized exercise.

- Run an outgoing swap that refunds and an incoming swap. Close the app before
  settlement and reopen after it; catch-up must find each payment.
- Restore the seed into a fresh wallet with a birthday before funding, once with
  Private queries on and once off, both with NEAR swap privacy off. Both runs must
  recover the same notes without duplicates, and following the tip must not repeat
  finished sweeps. Interrupt one restore once; it must resume without duplicates.
- Spend recovered notes together with ordinary funds; the change must belong to
  the ordinary internal key.
- Check that both settings default off and persist across a restart, and that
  disabling Private queries keeps NEAR swap privacy off after re-enabling it.
- Turn NEAR swap privacy off during a pending swap; its refund must still be found.
  After a key closes, turn the setting off and on; the next sync must sweep closed
  keys once and add no duplicate notes.
- Confirm hardware accounts keep their existing address flow, and that quote
  refreshes keep the same incoming address.
