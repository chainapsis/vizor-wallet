# Transparent UTXO recovery

Transparent outputs are recovered independently of shielded scanning. The first
successful lookup of each known external or internal/change address starts at
height zero. Subsequent lookups use the recorded next height minus the existing
100-block lookback, with the existing `min(birthday, utxo_query_height)` floor.
The shielded birthday and compact-block RPC construction are unchanged.

## Cache and upgrade policy

- The receive sidecar remains version 3. Existing external completions are
  retained; an upgrade does not force every external address to be queried again.
- Affected existing accounts can be deleted and re-imported after upgrading.
  Account deletion removes its receive-cache record; a re-import also obtains a
  new UUID. Deleting the last account in the UI resets the wallet.
- Internal/change completions use an optional address-keyed map in the same
  record. Older records lack that map, so their first internal lookup starts at
  zero. This is a one-time internal lookup, not a repeated full-history query.
- New external children are independently unchecked. Unchecked and checked
  addresses are batched separately so a new child does not rewind its neighbors.
- Completion (`tip + 1`) is persisted only after the complete stream's outputs
  and missing-transaction retrieval requests have committed to SQLite.
- Wallet rewinds, including the public `rewindToHeight` API, invalidate both
  completion maps before SQLite is truncated. Invalidation failure aborts the
  rewind; a later SQLite failure can only cause extra lookups.
  Resetting only to the rewind height would miss an old output resurrected by
  removal of a later spend. These exceptional full lookups favor correctness.

## Internal address scheduling

Internal/change addresses are queried at import or first discovery from height
zero, regardless of the periodic schedule. Known internal addresses are queried
together after 20 new blocks since their oldest successful lookup. A completion
of `tip + 1 = 1001` becomes due at tip 1020, not 1021. Discovering a new address
does not postpone an older address's refresh. After the grouped refresh succeeds,
the completion heights align to the current tip again.

This applies to small and large accounts and does not depend on whether an
address has been used. The previous age query, 100-block recent-address rule,
and rotating 20-address sweep are removed. Like main, each group uses a single
multi-address RPC; unchecked and checked addresses remain separate so discovery
does not rewind existing addresses. Standalone/imported receivers outside the
internal scope keep their ordinary refresh frequency.

The existing completion map is reused without a new state field or migration.
Planning alone never advances the schedule, and unchanged plans do not write the
cache. Cancellation or failed storage leaves the lookup due; successful storage
precedes completion. Cache rebuilding preserves progress. A wallet rewind clears
completion and therefore triggers genesis discovery again.

An additional payment to a known internal address in another wallet may remain
undiscovered until the next periodic lookup. The nominal interval is 20 blocks;
offline time, failed queries, and supported address discovery limits can delay it
further. Existing outputs retain their independent spend watches. Reducing UTXO
polling therefore does not imply a matching reduction in total RPCs or sync time.
For an unchanged address set over 20 successful one-block syncs, internal UTXO
polling goes from 20 grouped calls to one. This is a scheduling count, not a
mainnet latency benchmark.

## Spend tracking

An incremental UTXO response cannot establish whether an older output was spent.
Recovered transactions without full bytes are queued for enhancement in the same
transaction as UTXO storage. The existing full-transaction processor installs
durable spend detection. Completed address history requests advance that search;
decoding/storage failure must not mark a range checked. Such failures are logged
and other requests continue. A failed address is skipped for the remaining queue
passes of that enhancement invocation and retried by a later invocation. Network
failures retain the existing sync retry behavior.

Enhancement keeps the existing scheduling: after a block-scan batch, or during
eligible deferred inactive-account processing. A sync with no blocks to scan does
not run an extra enhancement pass. Newly discovered UTXOs and their retrieval
requests remain stored; full-transaction processing and spend-watch registration
may wait until a later enhancement invocation, normally after the next block scan.

`spend-index` is not enabled in the resolved dependency graph. This code uses
the existing address-based spend detection and does not change server RPCs.

## Address-history query scheduling

Enhancement coalesces identical, overlapping, and adjacent bounded history
requests for the same address when their filters and scheduling constraints
match. The merged range is split at the backend's existing expiry-window bound.
Unbounded requests retain their existing skipped behavior. Distinct addresses
have up to four streams in flight; each address advances in height order only
after its current stream has ended and all transactions and completion have been
stored. Download futures hold at most one decoded wire message per active address,
not the entire history. DB writes and fee processing remain sequential.

A parse or storage failure drops the remaining ranges for that address for this
invocation while other addresses continue. Network failures retain the outer
sync retry behavior. Cancellation drops the pending streams without acknowledging
unfinished ranges; already committed transactions can safely be seen on retry.
No detached background task or new persistent scheduling state is introduced.
This reduces duplicate requests and overlaps network waits; it does not lower
spend-check frequency or promise a fourfold overall sync speedup.

## Limits

This searches addresses already generated within the wallet's supported gap
windows. Newly generated children are eligible on a following sync. It does not
reconstruct the use of fully spent historical addresses to cross arbitrary gaps.
Software additional-account discovery still uses its existing birthday-bounded
first-address history check. Ephemeral address scheduling, arbitrary derivation
paths, Sprout shielded funds, and Keystone device signing are outside this change.

## Validation

Run the focused offline tests with:

```sh
cd rust
cargo test --lib transparent
```

The opt-in test below creates and removes its own Docker containers and temporary
chain. It does not reset existing regtest services. It mines external/internal
receipts at heights 1 and 2, activates Sapling at 200, imports at birthday 350,
then shields the recovered outputs and checks their spend from another wallet.
The wallet scans only after all regtest upgrades it uses have activated.

```sh
cd rust
cargo test --lib pre_sapling_recovery_shields_and_other_wallet_detects_the_spend -- --ignored --nocapture
```
