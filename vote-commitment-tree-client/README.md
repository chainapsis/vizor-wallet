# vote-commitment-tree-client

HTTP client and CLI for syncing and verifying the [vote commitment tree](../vote-commitment-tree) against a running Zcash shielded-voting chain node.

Provides the library functions `zcash_voting` uses to incrementally pull new leaves from the chain after each delegation or cast-vote, and a `vote-tree-cli` binary for operator-level inspection.

The default `zakura` feature uses the stable Zakura 1.0 cryptography family.
An LRZ consumer uses `default-features = false, features = ["lrz"]`. The two
backend features are mutually exclusive; `http` and `cli` remain
independent transport features.

## Binary

```bash
vote-tree-cli --endpoint https://vote1.example.com \
              --round-id <64-hex-chars> \
              sync
```

## Library

```rust
use vote_commitment_tree_client::Client;

let client = Client::new("https://vote1.example.com")?;
let leaves = client.leaves(round_id, from_height, to_height).await?;
```

## License

Dual-licensed under MIT or Apache-2.0. See [LICENSE-MIT](../LICENSE-MIT) and [LICENSE-APACHE](../LICENSE-APACHE).
