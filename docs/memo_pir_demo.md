# Ironwood memo-PIR demo

Vizor now completes Ironwood memos from compact-sync results through iPIR+SP. It does not request the containing transaction by transaction ID on mainnet.

## Build inputs

This demo depends on the wallet-library implementation reviewed in
[`zakura-core/wallet-libraries#13`](https://github.com/zakura-core/wallet-libraries/pull/13).
The Cargo manifest pins that PR's revision until the new APIs have a published release:

```text
e0dd978eb4f0ee06f507234c351c5539d281d37e
```

The Cargo manifest enables the `zakura-pir-memo` backend and SQLite features and consumes the transport-neutral `zakura-pir-memo` client from that revision.

The sharded full-pool server and its design/operations specification are reviewed in
[`valargroup/spendability-pir#27`](https://github.com/valargroup/spendability-pir/pull/27).

The default service is:

```text
https://memo-pir.167.99.42.60.sslip.io
```

For a different HTTPS deployment, set `VIZOR_MEMO_PIR_URL` in the environment used to launch/build Vizor. Plain HTTP endpoints are rejected.

## Demo procedure

1. Import a mainnet wallet using the **Block height** wallet-birthday option.
2. Enter `3428143`, the mainnet NU6.3/Ironwood activation height.
3. Start sync normally. Both direct mode and the process-wide Tor mode are supported. If Tor is requested but unavailable, PIR fails closed instead of falling back to a direct connection.
4. Watch the Rust logs. Successful private completion is reported only as aggregate counts:

   ```text
   sync: memo PIR privately completed N Ironwood memo(s) in M row query/queries
   ```

   Any legacy enhancement requests are kept inert and reported without identifiers:

   ```text
   sync: suppressed N legacy transaction enhancement request(s); no transaction IDs were sent
   ```

5. Open a received Ironwood transaction after sync and confirm its memo is present.

The client first compares the advertised snapshot block hash and Ironwood tree size with its locally scanned chain state. It sends no query before that anchor has been scanned, and rejects a mismatch. Pending notes newer than the advertised snapshot remain queued for a future sync/snapshot; they never fall back to `GetTransaction(txid)`.

## Verification commands

From `rust/`:

```sh
cargo check
cargo test wallet::sync_engine::memo_pir
cargo test wallet::sync_engine::enhance::tests::privacy_gate_makes_enhancement_inert_but_keeps_status_actionable
cargo test --lib wallet::sync_engine::memo_pir::tests::deployed_endpoint_accepts_and_decodes_a_private_query -- --ignored --exact
```

The ignored test downloads and validates the live full-pool snapshot, issues one randomized cover query, and decodes the response. It contains no wallet note position.

## Privacy boundary

- The memo server receives a randomized PIR query, not a transaction ID or note index. Requests for notes packed into the same row are coalesced.
- The returned full ciphertext is authenticated by reproducing the compact-scanned Ironwood note under the wallet's incoming viewing key before the memo is stored.
- PIR hides which row is read, but this demo does not hide request timing or the number of queried rows.
- Mainnet `TransactionDataRequest::Enhancement` is disabled in this demo. `GetStatus` for wallet-originated pending transactions and transparent-address history remain separate existing lightwalletd operations.
- The current integration targets Ironwood memo completion. Older Orchard/Sapling full-transaction enhancement is not replaced by this PIR service and therefore remains inert on mainnet under the strict no-txid-fallback policy.
