# Private Ironwood transaction enhancement

Vizor can privately complete incoming and outgoing Ironwood transaction details discovered by compact sync. The feature is off by default and is available under **Settings → Advanced → Private Ironwood recovery**.

When enabled, Vizor queries by Ironwood commitment-tree position through iPIR+SP. It suppresses lightwalletd `GetTransaction(txid)` enhancement only for transactions protected by the independent position queue. Non-Ironwood transactions and ordinary status/address-history requests keep their existing behavior.

## Build inputs

The Cargo manifest pins [`zakura-core/wallet-libraries#18`](https://github.com/zakura-core/wallet-libraries/pull/18) at:

```text
97553d530618d90219949c5df19c4a506b20731b
```

The wallet dependency exposes the `zakura-pir-enhance` client, incoming memo authentication, outgoing OVK recovery, durable recovery queues, and selective transaction-protection markers.

The default service is:

```text
https://enhance-pir.valargroup.dev
```

Set `VIZOR_ENHANCE_PIR_URL` to use another HTTPS deployment. `VIZOR_MEMO_PIR_URL` remains a temporary compatibility fallback. Plain HTTP endpoints are rejected.

## Behavior

1. Vizor loads and validates one immutable `/v1/enhance/generation`.
2. Parameter and public-parameter requests are pinned to that generation.
3. No private query is sent until the advertised block hash and Ironwood tree size agree with the locally scanned chain.
4. Requests sharing a packed row are coalesced locally.
5. Returned records are authenticated against compact-scanned state. Incoming details use the incoming viewing key; outgoing details use candidate funding accounts' external outgoing viewing keys.
6. Successful work is logged only as aggregate counts.

Enabling the setting does not rescan or reprocess past history. It protects future compact scanning and future seed-recovery work. Details previously fetched by transaction ID remain stored, and that earlier disclosure cannot be undone.

## Verification commands

From `rust/`:

```sh
cargo check
cargo test
cargo test deployed_endpoint_accepts_and_decodes_a_private_query -- --ignored --nocapture
```

The ignored live test validates the deployed generation and completes one randomized dummy query without using a wallet position.

## Privacy boundary

- The enhancement service receives randomized PIR queries rather than explicit transaction IDs or commitment-tree positions.
- Timing and the number of row queries remain observable. Vizor does not add cover traffic.
- Tor routing follows the app-wide foreground network policy and fails closed when Tor is requested but unavailable.
- Disabling the setting restores standard lightwalletd transaction enhancement.
