//! Selected wallet and proving crates for the example.
//!
//! Mirrors `zcash_voting::backend` so the example can keep upstream-shaped
//! imports while the workspace feature selects LRZ or Zakura.

pub use voting_crypto_deps::pasta_curves;
pub use zakura_wallet_lib::{client_sqlite as zcash_client_sqlite, keys as zcash_keys, orchard};
