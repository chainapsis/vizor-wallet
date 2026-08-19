//! Merkle authentication path for the vote commitment tree.

use incrementalmerkletree::Hashable;
use voting_crypto_deps::pasta_curves::Fp;

use crate::anchor::Anchor;
use crate::hash::{MerkleHashVote, TREE_DEPTH};

/// Serialized size: 4 bytes (position u32 LE) + 32 * TREE_DEPTH bytes (auth path).
pub const MERKLE_PATH_BYTES: usize = 4 + 32 * TREE_DEPTH;

// ---------------------------------------------------------------------------
// MerklePath
// ---------------------------------------------------------------------------

/// Merkle authentication path from a leaf to the tree root.
///
/// Used by ZKP #2 (VAN membership) and ZKP #3 (VC membership).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MerklePath {
    position: u32,
    auth_path: [MerkleHashVote; TREE_DEPTH],
}

impl From<incrementalmerkletree::MerklePath<MerkleHashVote, { TREE_DEPTH as u8 }>> for MerklePath {
    fn from(path: incrementalmerkletree::MerklePath<MerkleHashVote, { TREE_DEPTH as u8 }>) -> Self {
        let position: u64 = path.position().into();
        Self {
            position: position as u32,
            auth_path: path.path_elems().try_into().unwrap(),
        }
    }
}

impl MerklePath {
    /// Construct from raw parts.
    pub fn from_parts(position: u32, auth_path: [MerkleHashVote; TREE_DEPTH]) -> Self {
        Self {
            position,
            auth_path,
        }
    }

    /// Recompute the root from the given leaf and this authentication path.
    pub fn root(&self, leaf: MerkleHashVote) -> Anchor {
        self.auth_path
            .iter()
            .enumerate()
            .fold(leaf, |node, (l, sibling)| {
                let l = l as u8;
                if self.position & (1 << l) == 0 {
                    MerkleHashVote::combine(l.into(), &node, sibling)
                } else {
                    MerkleHashVote::combine(l.into(), sibling, &node)
                }
            })
            .into()
    }

    /// Verify that this path produces the expected `root` when combined with `leaf`.
    pub fn verify(&self, leaf: Fp, root: Fp) -> bool {
        let computed = self.root(MerkleHashVote::from_fp(leaf));
        computed.inner() == root
    }

    /// Leaf position in the tree.
    pub fn position(&self) -> u32 {
        self.position
    }

    /// The authentication path (sibling hashes from leaf to root).
    pub fn auth_path(&self) -> &[MerkleHashVote; TREE_DEPTH] {
        &self.auth_path
    }

    /// Serialize to bytes for FFI / network transport.
    ///
    /// Format (little-endian, [`MERKLE_PATH_BYTES`] bytes total):
    /// - Bytes `[0..4)`: position (`u32` LE)
    /// - Remaining bytes: auth path (`TREE_DEPTH` sibling hashes, 32 bytes each,
    ///   in order from leaf level to root level)
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(MERKLE_PATH_BYTES);
        buf.extend_from_slice(&self.position.to_le_bytes());
        for hash in &self.auth_path {
            buf.extend_from_slice(&hash.to_bytes());
        }
        buf
    }

    /// Deserialize from bytes produced by [`to_bytes`](Self::to_bytes).
    ///
    /// Returns `None` if the data is too short or contains non-canonical
    /// field element encodings.
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < MERKLE_PATH_BYTES {
            return None;
        }

        let position = u32::from_le_bytes(bytes[0..4].try_into().ok()?);

        let mut auth_path = [MerkleHashVote::from_fp(Fp::zero()); TREE_DEPTH];
        for (i, hash) in auth_path.iter_mut().enumerate() {
            let start = 4 + i * 32;
            let chunk: [u8; 32] = bytes[start..start + 32].try_into().ok()?;
            *hash = MerkleHashVote::from_bytes(&chunk)?;
        }

        Some(Self {
            position,
            auth_path,
        })
    }
}
