//! Communication boundary between server and client.
//!
//! The [`TreeSyncApi`] trait defines the contract for fetching tree data.
//! In the POC: in-process trait object.
//! In production: maps to Cosmos SDK gRPC/REST endpoints.

use pasta_curves::Fp;

use crate::hash::MerkleHashVote;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Response from `get_block_commitments`: leaves appended in a single block.
#[derive(Clone, Debug)]
pub struct BlockCommitments {
    /// Block height.
    pub height: u32,
    /// Index of the first leaf in this block.
    pub start_index: u64,
    /// Leaves appended in this block (in append order).
    pub leaves: Vec<MerkleHashVote>,
    /// Commitment tree root after this block's leaves.
    pub root: Fp,
}

/// Paginated response from `get_block_commitments`.
#[derive(Clone, Debug)]
pub struct BlockCommitmentsPage {
    /// Blocks returned in this page.
    pub blocks: Vec<BlockCommitments>,
    /// Next height to request, or zero when the sync range is complete.
    pub next_from_height: u32,
}

/// Current state of the server tree.
#[derive(Clone, Debug)]
pub struct TreeState {
    /// Next leaf index (= number of leaves appended so far).
    pub next_index: u64,
    /// Current Merkle root.
    pub root: Fp,
    /// Latest checkpointed block height.
    pub height: u32,
}

// ---------------------------------------------------------------------------
// TreeSyncApi trait
// ---------------------------------------------------------------------------

/// The contract between server and client.
///
/// In the POC: in-process (server implements this directly).
/// In production: maps to Cosmos SDK gRPC/REST endpoints:
/// - `get_block_commitments` → custom compact-block endpoint or Tendermint block queries
/// - `get_root_at_height` → `GET /zally/v1/commitment-tree/{height}`
/// - `get_tree_state` → `GET /zally/v1/commitment-tree/latest`
pub trait TreeSyncApi {
    type Error: std::fmt::Debug;

    /// Fetch commitments per block in a height range (primary sync method).
    ///
    /// Returns blocks in ascending height order. Empty blocks (no appends) may
    /// be omitted from the result.
    fn get_block_commitments(
        &self,
        from_height: u32,
        to_height: u32,
    ) -> Result<BlockCommitmentsPage, Self::Error>;

    /// Fetch tree root at a checkpoint height (anchor verification).
    ///
    /// Maps to: `GET /zally/v1/commitment-tree/{height}`
    fn get_root_at_height(&self, height: u32) -> Result<Option<Fp>, Self::Error>;

    /// Fetch current tree state (next_index, root, latest height).
    ///
    /// Maps to: `GET /zally/v1/commitment-tree/latest`
    fn get_tree_state(&self) -> Result<TreeState, Self::Error>;
}
