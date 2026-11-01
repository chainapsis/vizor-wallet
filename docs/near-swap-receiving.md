# Private swap recovery

Software accounts can receive NEAR swap payouts and refunds at derived Ironwood addresses (one-time IVKs). Each account has its own receive and refund index sequences. Hardware and view-only accounts keep their existing swap addresses.

## Settings

The feature runs on mainnet. It uses the selected private query server and waits while none is selected. Private queries don't gate it.

NEAR swap privacy (`set_near_swap_privacy_enabled`) decides whether new swaps get one-time addresses. Turning it off blocks new reservations, but a quote for an address that's already reserved still finishes.

## Account set

Each round and each filter step works out which accounts to watch. A software account is in the set if any of these holds:
- NEAR swap privacy is on
- the account's use marker is set
- a history check is running for the account, or the round is that check's own round

Accounts outside the set make no receiver requests. Hardware accounts are never in it. An account that leaves the set just stops being queried. Nothing is paused or deleted.

The use marker records that an account has used one-time addresses. It's set once and stays set, through reorgs too, so the account keeps being watched with NEAR swap privacy off. These set it:
- handing out a receive address or a refund address
- recording the account's own swap funding
- storing an authenticated payment at or after the birthday
- a mined refund memo for the account, found by syncing its funding transaction

Handing out an address and the quote that follows enable recovery on that account alone.

With NEAR swap privacy off, a second device doesn't watch an account whose swaps only ever paid into ZEC, until the setting goes on or a history check runs. A swap out of ZEC always leaves a funding memo, and the memo sets the marker. A memo held back by the 100-index gap rule still sets it, but that refund address itself isn't watched until the gap closes or the wallet proves it owns the funding input.

## Receive addresses

The wallet hands out at most four indexes past the highest paid receive index. It hands out an index only once that index's own history lookup completed and the account's filter marker is within 10 blocks of the chain tip. Otherwise it answers `ReceiveHistory`, and the app runs a round and asks again. Hand-out doesn't wait for new blocks, so it can't see a payment mined in those last few blocks, or the same address reserved at the same moment on another device. NEAR could then link the two swaps, but no funds are at risk. A payment counts from the block that mines it, so the next index opens as soon as a payout lands. Issuance reuses the lowest unpaid hole once its quote ownership ends. When unresolved quotes hold every eligible index it answers `Limit`. A started quote is released by a recent conclusive provider status, or 24 hours after its deadline if its address is unpaid with no payment pending. A released address stays monitored.

Seed recovery starts at receive index zero and stops after four consecutive empty histories.

## Before the birthday

The wallet doesn't handle payments before the account birthday. A payment record below the birthday is skipped: it isn't stored, credited or counted as use. History lookups still start at Ironwood activation.

Complete recovery therefore needs a birthday before the account's first one-time-address use. For example, say I0 was paid before the birthday, I1 to I3 are empty, and I4 was paid after it. Skipping I0 ends the seed walk at I3, so I4 isn't found, and I0 can be handed out again. A late birthday can hide later payments too, not just earlier ones. After lowering a birthday, run Check swap history.

## Refund addresses

A refund index needs no lookup. After funding history sync the wallet hands out the next index above every known key. The funding transaction records the refund index in an authenticated memo to the account's ordinary internal Ironwood address. Another device with the same seed learns that index by syncing the funding transaction. The wallet never sweeps arbitrary refund indexes.

A funded refund address stays monitored while any of its operations is active or inconclusive, or a receipt on it is disputed or unplaced. A refund address known only from its funding memo, with no swap on this device, is watched for 90 days of blocks after its funding. That's twice the longest refund delay seen in NEAR's data. A later refund is found by Check swap history. If the funding transaction predates the wallet birthday, restore from an earlier birthday first.

## Detection

Ordinary block sync never tries this feature's keys. Detection asks the receiver service, over PIR, whether an address has been paid. The address is the tag, and the service can't tell which address a query is for.

**History by PIR.** Every address that starts being watched gets one bootstrap lookup from its history start. History starts at Ironwood activation for a receive address and at the funding height for a refund address. That covers the seed walk, a funding memo, a payment that widens the receive window, and an address watched again after a reorg. A failed lookup is never counted as an empty history. A request lost in transit, or a changed publication, leaves the lookup due for the next round, while a bad answer backs it off.

**Lookups.** Each segment of the receiver service has a directory of address tags and a companion of payment records. A lookup sends one directory query per segment it needs. On a hit whose last payment is at or past the lookup's start and the birthday, it sends one companion query per record, and each record carries its Merkle path, so there's no separate witness request. A step reads at most four records, so a long history is credited a few records at a time over a slow route, and is recorded whole or not at all. A resumed step reads the directory entry again, one extra directory query. Sealed shards' own receiver filters let a lookup skip a shard when they cost less than reading it blind (`shard_filters_cheaper`).

**Recent blocks by filters.** The service publishes sparse filters only for a rolling window, about 7 days, starting at the first height its filter head advertises. A range lists only the blocks that pay some receiver. A match queues a PIR lookup of that address from its history start. A miss proves nothing about history, so filters only trigger lookups and move the account's marker, the block through which filters were read.

**Catching up.** A round and a filter step read filters the same way: one range per distinct marker, from just past the marker to the lower of the filter tip and the scanned tip, shared by every account at that marker. A round's filter reads are capped at a third of its time, so lookups keep theirs. When the marker is missing, below the window or on another history revision, when a range disagrees with the wallet's chain, or when filters are unavailable, the round runs a complete check instead: one lookup per watched address from its last PIR check through the publication's end, paid receive addresses and refund addresses in their window included. History is never skipped. A complete check reveals to the server how many addresses the account watches, but not which ones.

**Chain checks.** A round captures the receiver service's shard inventory, accepts it only if its end is a block the wallet scanned, and saves the verified descriptors in the wallet database (`ext_vizor_receiver_inventory`). A filter range commits only if it starts just past the marker, with the marker's hash as its parent, and ends at or below the wallet's fully scanned block with the same hash. Anything else waits for sync or goes to a complete check. A reorg moves the marker back to the fork, and an indexing correction clears it. Switching to another private query server forgets every account's Receiver history from the old one, so the next round reads every watched address again from its history start. The service is trusted for which chain it indexed, as it is for completeness.

Every returned payment must authenticate with its derived key, prove inclusion against the wallet's own tree and pass spend reconciliation. Network requests hold no wallet database handle. Provider statuses only attribute a recovered payment to its operation, never find or credit one. If the service speaks a version this app doesn't support, the worker records that the app needs an update and keeps pending work.

## Filter step

While the app is open (desktop, or mobile in the foreground and unlocked), the app runs a filter step after each completed sync that moved the scanned tip, when no round is owed or running. A step shares a round's admission. It reads the filter head and catches every account's marker up as a round does, matching the watched addresses. It captures no inventory and runs no lookup.

A hit queues its lookup, which makes a round due. A step reports `needs_round` when a filter request fails, the gap is bigger than one range, the service's history changed, or an account needs a complete check because its marker is missing or outside the window. A failed filter request, or a step that fails, owes a round so its complete check covers what filters can't, and filters that stay unavailable don't stall detection. Every step starts at the committed marker, so a skipped or cancelled step is covered by the next one.

## Triggers

Rounds aren't tied to sync polling. The app owes one on launch, unlock, return to the app, an account switch, choosing a private query server, turning NEAR swap privacy on, a NEAR payout or refund status, a retry after a failure, the wallet reporting a round due (`SwapRecoveryStatus.round_due`: a queued lookup, an unfinished seed walk, or a marker more than 10 blocks behind the scanned tip), and a filter step's `needs_round`. It runs the owed round after the next completed sync, or at once when the wallet is already at the tip. A round does the active account's work first. It reports `more` when work is left that another round can run right away, so the app chains rounds, and otherwise says why the rest waits: no server, sync, a newer publication or a lookup's retry delay. A round that queued a rescan says so, and the app starts sync.

## Check swap history

Check swap history is the manual fallback, only needed if a swap payment or refund is missing, or after lowering a birthday. It watches every software account until it ends and queries every address the wallet has enrolled, older ones and refund addresses past their window included. A new check first forgets the answers earlier lookups gave, as a server switch does, so every address is read again from its history start and a payment an earlier answer left out is found. Afterwards an account it found nothing for leaves the set if NEAR swap privacy is off. Pausing keeps the job's position, and the next check resumes it without starting over.

## Tachyon

The design follows the payment discovery the Tachyon book proposes: the wallet asks a PIR service by tag whether that tag was paid, with no trial decryption, from bounded tables, at most one query per tag per unsynced chunk. Our tag is the one-time address at an index, the receive gap window plays the role of their per-channel counter, and a NEAR payout or refund plays the role of their first-contact transaction.

It's an analogy, not a drop-in. We reuse one tag across payments, in pages, where their tags are one per note. Our shards seal by payment count, not by epoch, and our inventory limits would need an epoch bound to hold at 100 transactions per second. The book has no public filters. Ours are a low-volume optimization that only triggers lookups, at about 2.7 bytes per payment. Witnesses and seed restore are Ironwood specific and don't carry over.

## Implementation

The wallet library owns issuance, the recovery queue, bootstrap obligations, authentication, inclusion and spending. `rust/src/wallet/one_time_ivk.rs` supplies account eligibility. `rust/src/wallet/sync_engine/swap_private.rs` supplies routed network steps, the shard-filter cost rule, the filter step and the descriptor store. `rust/src/api/one_time_ivk.rs` exposes reservations, provider statuses, bounded recovery rounds, filter steps and history controls.
