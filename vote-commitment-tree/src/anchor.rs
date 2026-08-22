//! Anchor type for committed vote commitment tree roots.

use incrementalmerkletree::{Hashable, Level};
use voting_crypto_deps::pasta_curves::{group::ff::PrimeField, Fp};

use crate::hash::{MerkleHashVote, TREE_DEPTH};

// ---------------------------------------------------------------------------
// Anchor
// ---------------------------------------------------------------------------

/// A committed vote commitment tree root at a specific block height.
///
/// This is the value that ZKP #2 and ZKP #3 verify Merkle inclusion proofs
/// against. It must be a valid Pallas base field element.
#[derive(Eq, PartialEq, Clone, Copy, Debug)]
pub struct Anchor(Fp);

impl From<Fp> for Anchor {
    fn from(value: Fp) -> Self {
        Anchor(value)
    }
}

impl From<MerkleHashVote> for Anchor {
    fn from(hash: MerkleHashVote) -> Self {
        Anchor(hash.0)
    }
}

impl Anchor {
    /// The anchor of the empty vote commitment tree.
    pub fn empty_tree() -> Self {
        Anchor(MerkleHashVote::empty_root(Level::from(TREE_DEPTH as u8)).0)
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
    pub fn from_bytes(bytes: [u8; 32]) -> Option<Self> {
        Option::from(Fp::from_repr(bytes).map(Anchor))
    }
}
