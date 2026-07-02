//! Zwap: BTC<>ZEC shielded atomic-swap client (in development).
//!
//! This module is the in-wallet, Rust-side client for the `shielded-zwap`
//! atomic-swap protocol. The wallet keeps custody throughout: all per-swap
//! secrets derive deterministically from the wallet seed, the joint Orchard
//! key combines additively with the solver's verified material, and the
//! final ZEC settlement is an ordinary in-process Orchard spend.
//!
//! Current contents:
//! - [`orchard_claim`] — joint-note trial-decrypt, joint UA derivation, and
//!   the Orchard sweep spend (vendored from `orchard-wasm`, native).
//! - [`joint_orchard`] — additive joint Orchard `ak/nk/rivk` + UA/UFVK encode
//!   (vendored from `solver-v3`, canonical Rust).
//! - [`joint_keys`] — joint spend-auth scalar reconstruction `ask = k_a + k_b`
//!   (vendored from `solver-v3`).
//! - [`dkm`] — initiator-side deterministic key material from `(seed, swap_id)`.
//! - [`btc_lock`] — redesign single-script P2WSH HTLC + witness shapes
//!   (vendored from `solver-v3`, byte-pinned to btc-batcher's golden vector).
//!
//! Planned (see integration plan): cross-curve DLEq / hashbind verification
//! (fund-safety gate), BTC claim/refund signing (BIP143), orderbook / indexer
//! HTTP clients, and the b2z/z2b orchestrator.

pub mod adaptor;
pub mod b2z;
pub mod bech32_segwit;
pub mod btc_claim;
pub mod btc_lock;
pub mod dkm;
pub mod e2z;
pub mod evm;
pub mod joint_keys;
pub mod joint_orchard;
pub mod orchard_claim;
pub mod pallas_dleq;
pub mod z2b;
pub mod z2e;
