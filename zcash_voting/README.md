# zcash_voting

Client-side library for integrating [Zcash shielded voting](https://github.com/valargroup/vote-sdk) into a wallet. Wraps the Halo 2 ZKPs, hotkey derivation, share construction, and governance-PCZT assembly that a wallet needs to participate in an on-chain voting round.

## Usage

Wallets typically consume this through a language bridge:

- **Rust wallets**: add `zcash_voting = "0.11"` to `Cargo.toml`.
- **Mobile wallets**: expose the needed Rust APIs through the wallet SDK's FFI
  layer and keep platform-specific work, such as CSPRNG byte generation and
  HTTP submission, at the SDK boundary.

See the [wallet integration guide](https://github.com/valargroup/vote-sdk/blob/main/docs/wallet-integration.md) for the full flow.

## Crate layout

| Crate | Purpose |
|---|---|
| **`zcash_voting`** (this crate) | Top-level API: proof generation, hotkey derivation, share construction, PCZT assembly, round-state storage. |
| [`vote-commitment-tree`](../vote-commitment-tree) | Append-only Poseidon Merkle tree for VANs and vote commitments. |
| [`vote-commitment-tree-client`](../vote-commitment-tree-client) | HTTP client + CLI for syncing the vote commitment tree from a running chain node. |

## Shared wallet policy helpers

The `share_policy` module contains pure helpers for wallet-side voting behavior
that should stay consistent across SDKs:

- delayed helper-share `submit_at` scheduling
- helper target counts and randomized helper ordering
- batch share planning with independent entropy per share
- resubmission ordering with untried helpers before already-sent helpers
- share tracking summaries, readiness checks, retry thresholds, and polling delay

Wallet SDKs should provide fresh CSPRNG bytes from their platform RNG and let the
crate own the sampling and ordering policy.

## Dependency notes

`zcash_voting` tracks the upstream Zcash crates directly:

- **`orchard 0.14`** from crates.io, with the
  `unstable-voting-circuits` feature enabled for the governance proof paths.
- **`voting-circuits 0.8`** for the delegation and vote proof circuits.
- **`vote-commitment-tree 0.3`** and **`vote-commitment-tree-client 0.5`** for
  vote commitment tree state and optional HTTP sync.
- **`pczt`, `zcash_keys`, `zcash_primitives`, and `zcash_protocol`** from the
  published upstream Zcash crate line used by this release.

## License

Dual-licensed under MIT or Apache-2.0. See [LICENSE-MIT](../LICENSE-MIT) and [LICENSE-APACHE](../LICENSE-APACHE).
