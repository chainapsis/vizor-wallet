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
- Wallet rewinds invalidate both completion maps before SQLite is truncated.
  Resetting only to the rewind height would miss an old output resurrected by
  removal of a later spend. These exceptional full lookups favor correctness.

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
