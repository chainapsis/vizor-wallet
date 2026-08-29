# vote-commitment-tree

Append-only Poseidon Merkle tree for Vote Authority Notes (VANs) and vote commitments in the [Zcash shielded-voting protocol](https://github.com/valargroup/vote-sdk).

The tree is maintained per vote round. Each delegation appends a VAN leaf; each cast-vote appends a new VAN plus a vote-commitment leaf. The chain publishes the tree root at every block height, which wallets use as a public input to ZKP2 (vote-commitment proof).

The default `zakura` feature uses the stable Zakura 1.0 cryptography family.
An LRZ consumer uses `default-features = false, features = ["lrz"]`. The two
backend features are mutually exclusive.

## Usage

Sibling crate of [`zcash_voting`](../zcash_voting); typically consumed transitively by wallets that pull that top-level crate. Standalone usage:

```rust
use vote_commitment_tree::TreeHandle;

let mut tree = TreeHandle::open("/path/to/tree.kv")?;
tree.append(&leaf_cmx)?;
let root = tree.root()?;
let path = tree.path(leaf_position)?;
```

See [`vote-commitment-tree-client`](../vote-commitment-tree-client) for the HTTP/CLI client that syncs this tree from a running Zcash voting chain node.

## License

Dual-licensed under MIT or Apache-2.0. See [LICENSE-MIT](../LICENSE-MIT) and [LICENSE-APACHE](../LICENSE-APACHE).
