# zcash_voting

Client-side cryptographic library for Zcash shielded voting. Implements proof generation, vote construction, and tree synchronization for the [Zally governance protocol](https://github.com/valargroup/shielded-vote-book).

## Workspace Crates

| Crate | Description |
|-------|-------------|
| **zcash_voting** | Core library: ZKP delegation and vote proofs (Halo2), El Gamal encryption, governance PCZT construction, Merkle witness generation, SQLite round-state persistence |
| **vote-commitment-tree** | Append-only Poseidon Merkle tree for Vote Authority Notes and Vote Commitments |
| **vote-commitment-tree-client** | HTTP client and CLI for syncing the vote commitment tree from a chain node |

## Architecture

```
zcash_voting
├── vote-commitment-tree ──── imt-tree
├── vote-commitment-tree-client
├── pir-client
├── voting-circuits ── ZK delegation + vote proofs
└── Zcash crates ───── orchard, pczt, zcash_keys, zcash_primitives, ...
```

## Building

```bash
cargo check                    # check all crates
cargo build -p zcash_voting   # build just the core library
```

The workspace depends on the private [valargroup/voting-circuits](https://github.com/valargroup/voting-circuits) repo. The `.cargo/config.toml` enables `git-fetch-with-cli` so your local git credentials are used automatically.

## Dependency Strategy

This workspace tracks the upstream Zcash crates directly:

- **orchard 0.14** — Resolved from crates.io with the
  `unstable-voting-circuits` feature enabled for governance proof paths.

- **voting-circuits 0.8** — Resolved from
  [valargroup/voting-circuits](https://github.com/valargroup/voting-circuits)
  for the Orchard-backed delegation and vote proof circuits.

- **vote-nullifier-pir crates** — `imt-tree 0.2`, `pir-types 0.2`, and
  `pir-client 0.3` are resolved from crates.io.

- **librustzcash crates** — `pczt 0.7`, `zcash_keys 0.14`,
  `zcash_primitives 0.28`, and `zcash_protocol 0.9` are resolved from
  crates.io.

## FFI

Mobile FFI bindings live in [zcash-swift-wallet-sdk](https://github.com/valargroup/zcash-swift-wallet-sdk) (hand-rolled C FFI + Swift wrappers). This repo is a pure Rust workspace.

## License

TODO
