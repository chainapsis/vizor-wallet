//! Selected wallet and proving crates.
//!
//! Exactly one crate feature selects the concrete dependency family. This
//! module re-exports that family's crates under stable internal names so the
//! rest of the implementation remains backend-agnostic.

pub use voting_crypto_deps::{halo2_gadgets, halo2_proofs, pasta_curves};
pub use zakura_wallet_lib::{
    client_backend as zcash_client_backend, client_sqlite as zcash_client_sqlite,
    keys as zcash_keys, orchard, pczt, primitives as zcash_primitives,
};
