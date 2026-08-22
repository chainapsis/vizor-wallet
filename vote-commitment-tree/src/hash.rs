//! Vote commitment tree hash types: [`MerkleHashVote`], `EMPTY_ROOTS`, and tree constants.
//!
//! These types are shared between the server and client sides of the vote commitment tree.

use core::iter;

use incrementalmerkletree::{Hashable, Level};
use lazy_static::lazy_static;
use voting_crypto_deps::pasta_curves::{group::ff::PrimeField, Fp};

use crate::poseidon_hash;

/// Fixed depth of the Vote Commitment Tree (2^24 ≈ 16.7M leaf capacity).
///
/// Reduced from Zcash's depth 32 (~4.3B) because governance voting produces
/// far fewer leaves than a full shielded pool. Each voter generates 1 leaf per
/// delegation + 2 per vote, so even 10K voters × 50 proposals = ~1M leaves per
/// round — well within 2^24. This saves 8 Poseidon hashes per ZKP proof
/// (~2,000 fewer constraints) and shrinks Merkle paths from 1,028 to 772 bytes.
pub const TREE_DEPTH: usize = 24;

/// Shard height for the underlying `ShardTree` (each shard covers 2^4 = 16 leaves).
pub(crate) const SHARD_HEIGHT: u8 = 4;

/// Maximum number of checkpoints retained by the tree.
pub(crate) const MAX_CHECKPOINTS: usize = 1000;

lazy_static! {
    /// Precomputed empty subtree hashes for each level.
    ///
    /// `EMPTY_ROOTS[0]` = `empty_leaf()` = `poseidon_hash(0, 0)`
    /// `EMPTY_ROOTS[i]` = `combine(i-1, EMPTY_ROOTS[i-1], EMPTY_ROOTS[i-1])`
    pub(crate) static ref EMPTY_ROOTS: Vec<MerkleHashVote> = {
        iter::empty()
            .chain(Some(MerkleHashVote::empty_leaf()))
            .chain(
                (0..TREE_DEPTH).scan(MerkleHashVote::empty_leaf(), |state, l| {
                    let l = l as u8;
                    *state = MerkleHashVote::combine(l.into(), state, state);
                    Some(*state)
                }),
            )
            .collect()
    };
}

// ---------------------------------------------------------------------------
// MerkleHashVote
// ---------------------------------------------------------------------------

/// Leaf and internal node digest for the vote commitment tree.
///
/// Wraps a Pallas base field element (`Fp`). Implements `Hashable` so it plugs
/// directly into `incrementalmerkletree` / `shardtree`.
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct MerkleHashVote(pub(crate) Fp);

impl MerkleHashVote {
    /// Create a digest from a raw field element (e.g. a VAN or VC commitment).
    pub fn from_fp(value: Fp) -> Self {
        MerkleHashVote(value)
    }

    /// Extract the inner field element.
    pub fn inner(&self) -> Fp {
        self.0
    }

    /// Serialize to canonical 32-byte little-endian representation.
    pub fn to_bytes(&self) -> [u8; 32] {
        self.0.to_repr()
    }

    /// Deserialize from 32 bytes. Returns `None` for non-canonical encodings.
    pub fn from_bytes(bytes: &[u8; 32]) -> Option<Self> {
        Option::from(Fp::from_repr(*bytes).map(MerkleHashVote))
    }
}

impl Hashable for MerkleHashVote {
    fn empty_leaf() -> Self {
        MerkleHashVote(poseidon_hash(Fp::zero(), Fp::zero()))
    }

    /// Poseidon(left, right) — no layer tagging (unlike Orchard's Sinsemilla
    /// which prepends the level index).
    fn combine(_level: Level, left: &Self, right: &Self) -> Self {
        MerkleHashVote(poseidon_hash(left.0, right.0))
    }

    fn empty_root(level: Level) -> Self {
        EMPTY_ROOTS[usize::from(level)]
    }
}
