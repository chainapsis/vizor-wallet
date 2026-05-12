//! Append-only Poseidon Merkle tree for the Vote Commitment Tree (Gov Steps V1).
//!
//! This tree holds both **Vote Authority Notes (VANs)** and **Vote Commitments (VCs)** as leaves.
//! Domain separation (DOMAIN_VAN / DOMAIN_VC) is applied when *constructing* leaf values
//! (in circuits / chain); this crate stores and hashes already-committed field elements.
//!
//! Insertion order (per cosmos-sdk-messages-spec):
//! - `MsgDelegateVote` → append 1 leaf (VAN)
//! - `MsgCastVote` → append 2 leaves (new VAN, then VC)
//!
//! ## Architecture
//!
//! The crate is split into server and client layers with a sync API boundary:
//!
//! - **Shared types** ([`MerkleHashVote`], [`Anchor`], [`MerklePath`]) — used by both sides.
//! - **[`TreeServer`]** — authoritative full tree: append, checkpoint, serve data via [`TreeSyncApi`].
//! - **[`TreeClient`]** — sparse tree: sync from server, mark positions, generate witnesses.
//! - **[`TreeSyncApi`]** — trait defining the communication boundary (in-process for POC,
//!   maps to Cosmos SDK endpoints in production).
//!
//! Built on `incrementalmerkletree` / `shardtree` (same crates that back Orchard's
//! note commitment tree), with two substitutions:
//! - **Hash:** Poseidon (no layer tagging) instead of Sinsemilla
//! - **Empty leaf:** `poseidon_hash(0, 0)` instead of `Fp::from(2)`

// -- Modules ---------------------------------------------------------------

mod anchor;
pub mod client;
mod hash;
pub mod kv_shard_store;
pub mod memory_server;
mod path;
pub mod serde;
pub mod server;
pub mod sync_api;

// -- Re-exports (public API) -----------------------------------------------

pub use anchor::Anchor;
pub use client::{SyncError, TreeClient};
pub use hash::{MerkleHashVote, TREE_DEPTH};
pub use path::{MerklePath, MERKLE_PATH_BYTES};
pub use server::{AppendFromKvError, MemoryTreeServer, SyncableServer, TreeServer};
pub use sync_api::TreeSyncApi;

// -- Shared utilities ------------------------------------------------------

use pasta_curves::Fp;

/// Domain tag for Vote Commitments (matches `orchard::vote_proof::circuit::DOMAIN_VC`).
pub const DOMAIN_VC: u64 = 1;

/// Poseidon hash of two field elements (delegates to imt-tree for circuit consistency).
#[inline]
pub fn poseidon_hash(left: Fp, right: Fp) -> Fp {
    imt_tree::poseidon_hash(left, right)
}

/// Poseidon hash of six field elements (`ConstantLength<6>`, width 3, rate 2).
pub fn poseidon_hash_6(a: Fp, b: Fp, c: Fp, d: Fp, e: Fp, f: Fp) -> Fp {
    use halo2_gadgets::poseidon::primitives::{self as poseidon, ConstantLength, P128Pow5T3};

    poseidon::Hash::<_, P128Pow5T3, ConstantLength<6>, 3, 2>::init().hash([a, b, c, d, e, f])
}

/// Compute the vote commitment leaf hash (arity-5 Poseidon).
///
/// ```text
/// vote_commitment_hash(voting_round_id, shares_hash, proposal_id, vote_decision) =
///     Poseidon(DOMAIN_VC, voting_round_id, shares_hash, proposal_id, vote_decision)
/// ```
///
/// This must produce identical output to `orchard::vote_proof::vote_commitment_hash`.
pub fn vote_commitment_hash(
    voting_round_id: Fp,
    shares_hash: Fp,
    proposal_id: Fp,
    vote_decision: Fp,
) -> Fp {
    use halo2_gadgets::poseidon::primitives::{self as poseidon, ConstantLength, P128Pow5T3};

    poseidon::Hash::<_, P128Pow5T3, ConstantLength<5>, 3, 2>::init().hash([
        Fp::from(DOMAIN_VC),
        voting_round_id,
        shares_hash,
        proposal_id,
        vote_decision,
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vote_commitment_hash_basic() {
        // Sanity: different inputs → different outputs.
        let round = Fp::from(99u64);
        let a = vote_commitment_hash(round, Fp::from(1u64), Fp::from(2u64), Fp::from(0u64));
        let b = vote_commitment_hash(round, Fp::from(1u64), Fp::from(2u64), Fp::from(1u64));
        assert_ne!(a, b);
    }

    #[test]
    fn test_vote_commitment_hash_deterministic() {
        let round = Fp::from(99u64);
        let h1 = vote_commitment_hash(round, Fp::from(42u64), Fp::from(3u64), Fp::from(1u64));
        let h2 = vote_commitment_hash(round, Fp::from(42u64), Fp::from(3u64), Fp::from(1u64));
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_vote_commitment_hash_cross_validates_with_orchard() {
        use voting_circuits::vote_proof;

        let voting_round_id = Fp::from(0xCAFEu64);
        let shares_hash = Fp::from(0xDEAD_BEEFu64);
        let proposal_id = Fp::from(5u64);
        let vote_decision = Fp::from(1u64);

        let ours = vote_commitment_hash(voting_round_id, shares_hash, proposal_id, vote_decision);
        let theirs = vote_proof::vote_commitment_hash(
            voting_round_id,
            shares_hash,
            proposal_id,
            vote_decision,
        );
        assert_eq!(
            ours, theirs,
            "vote_commitment_hash must match orchard circuit helper"
        );
    }

    #[test]
    fn test_domain_vc_matches_orchard() {
        assert_eq!(DOMAIN_VC, voting_circuits::vote_proof::DOMAIN_VC);
    }
}
