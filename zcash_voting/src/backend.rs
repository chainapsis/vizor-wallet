//! Selected wallet and proving crates.
//!
//! `zakura-wallet-lib` and `voting-crypto-deps` each pick one family. This
//! module re-exports them under the upstream names the rest of the crate
//! already uses, so backend selection stays in `Cargo.toml`.

pub use voting_crypto_deps::{halo2_gadgets, halo2_proofs, pasta_curves};
pub use zakura_wallet_lib::{
    client_backend as zcash_client_backend, client_sqlite as zcash_client_sqlite,
    keys as zcash_keys, orchard, pczt, primitives as zcash_primitives,
};
