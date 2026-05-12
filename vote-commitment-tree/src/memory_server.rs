//! [`SyncableServer`] — augments [`GenericTreeServer`] with per-block leaf
//! tracking and implements [`TreeSyncApi`] for in-process sync.
//!
//! [`MemoryTreeServer`] is a convenience alias for
//! `SyncableServer<MemoryShardStore<…>>`. Tests that do not need sync can use
//! `GenericTreeServer<MemoryShardStore<MerkleHashVote, u32>>` directly.
//!
//! For the production incremental path use [`crate::server::TreeServer`]
//! backed by [`crate::kv_shard_store::KvShardStore`].

use std::convert::Infallible;

use pasta_curves::Fp;
use shardtree::store::ShardStore;

use crate::hash::MerkleHashVote;
use crate::server::SyncableServer;
use crate::sync_api::{BlockCommitments, TreeState, TreeSyncApi};

// ---------------------------------------------------------------------------
// TreeSyncApi implementation for SyncableServer<S>
// ---------------------------------------------------------------------------

impl<S> TreeSyncApi for SyncableServer<S>
where
    S: ShardStore<H = MerkleHashVote, CheckpointId = u32>,
    S::Error: std::fmt::Debug,
{
    /// `SyncableServer` never fails when serving sync data — the `blocks` map
    /// is an in-memory `BTreeMap` and all root lookups are infallible.
    type Error = Infallible;

    fn get_block_commitments(
        &self,
        from_height: u32,
        to_height: u32,
    ) -> Result<Vec<BlockCommitments>, Infallible> {
        let blocks = self
            .blocks
            .range(from_height..=to_height)
            .map(|(_, bc)| bc.clone())
            .collect();
        Ok(blocks)
    }

    fn get_root_at_height(&self, height: u32) -> Result<Option<Fp>, Infallible> {
        Ok(self.root_at_height(height))
    }

    fn get_tree_state(&self) -> Result<TreeState, Infallible> {
        Ok(TreeState {
            next_index: self.size(),
            root: self.root(),
            height: self.latest_checkpoint().unwrap_or(0),
        })
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::anchor::Anchor;
    use crate::hash::EMPTY_ROOTS;
    use crate::server::{CheckpointError, MemoryTreeServer};

    fn fp(x: u64) -> Fp {
        Fp::from(x)
    }

    #[test]
    fn empty_tree_has_deterministic_root() {
        let t1 = MemoryTreeServer::empty();
        let t2 = MemoryTreeServer::empty();
        assert_eq!(t1.root(), t2.root());
        assert_eq!(t1.size(), 0);
    }

    #[test]
    fn empty_roots_are_consistent() {
        use crate::hash::{MerkleHashVote, TREE_DEPTH};
        use incrementalmerkletree::{Hashable, Level};

        let leaf = MerkleHashVote::empty_leaf();
        assert_eq!(EMPTY_ROOTS[0], leaf);
        let mut expected = leaf;
        for level in 0..TREE_DEPTH {
            assert_eq!(EMPTY_ROOTS[level], expected, "level {level}");
            expected = MerkleHashVote::combine(Level::from(level as u8), &expected, &expected);
        }
    }

    #[test]
    fn append_one_and_path() {
        let mut tree = MemoryTreeServer::empty();
        let idx = tree.append(fp(100)).unwrap();
        assert_eq!(idx, 0);
        assert_eq!(tree.size(), 1);
        tree.checkpoint(1).unwrap();
        let path = tree.path(0, 1).unwrap();
        assert!(path.verify(fp(100), tree.root()));
    }

    #[test]
    fn append_two_leaves_paths_verify() {
        let mut tree = MemoryTreeServer::empty();
        tree.append(fp(1)).unwrap();
        tree.append(fp(2)).unwrap();
        tree.checkpoint(1).unwrap();
        let root = tree.root();
        for i in 0..2u64 {
            let path = tree.path(i, 1).unwrap();
            assert!(path.verify(Fp::from(i + 1), root));
        }
    }

    #[test]
    fn checkpoint_preserves_root() {
        let mut tree = MemoryTreeServer::empty();
        tree.append(fp(1)).unwrap();
        tree.append(fp(2)).unwrap();
        tree.checkpoint(10).unwrap();
        let root_at_10 = tree.root_at_height(10).unwrap();
        tree.append(fp(3)).unwrap();
        tree.checkpoint(11).unwrap();
        assert_eq!(tree.root_at_height(10).unwrap(), root_at_10);
        assert_ne!(tree.root_at_height(11).unwrap(), root_at_10);
    }

    #[test]
    fn anchor_empty_tree() {
        let anchor = Anchor::empty_tree();
        let tree = MemoryTreeServer::empty();
        assert_eq!(anchor.inner(), tree.root());
    }

    #[test]
    fn checkpoint_monotonicity_returns_error_on_regression() {
        let mut tree = MemoryTreeServer::empty();
        tree.append(fp(1)).unwrap();
        tree.checkpoint(5).unwrap();
        tree.append(fp(2)).unwrap();

        // Equal height: must return NotMonotonic.
        let err = tree
            .checkpoint(5)
            .expect_err("expected error on duplicate checkpoint height");
        assert!(
            matches!(
                err,
                CheckpointError::NotMonotonic {
                    prev: 5,
                    requested: 5
                }
            ),
            "unexpected error variant: {:?}",
            err,
        );

        // Regressing height: must also return NotMonotonic.
        let err = tree
            .checkpoint(3)
            .expect_err("expected error on regressing checkpoint height");
        assert!(
            matches!(
                err,
                CheckpointError::NotMonotonic {
                    prev: 5,
                    requested: 3
                }
            ),
            "unexpected error variant: {:?}",
            err,
        );

        // The tree must still be usable: a strictly increasing height succeeds.
        tree.checkpoint(6)
            .expect("checkpoint with higher height must succeed");
    }

    /// Verifies that old checkpoints are evicted from the store once the
    /// in-memory `MemoryShardStore` exceeds its `MAX_CHECKPOINTS` window.
    #[test]
    fn old_checkpoints_pruned_after_max_checkpoints() {
        use crate::hash::MAX_CHECKPOINTS;

        let mut tree = MemoryTreeServer::empty();
        let total = MAX_CHECKPOINTS + 1;
        for h in 1u32..=(total as u32) {
            tree.append(Fp::from(h as u64)).unwrap();
            tree.checkpoint(h).unwrap();
        }

        assert!(
            tree.root_at_height(1).is_none(),
            "checkpoint at height 1 should be pruned after {} blocks",
            total
        );

        let first_retained = (total - MAX_CHECKPOINTS + 1) as u32;
        assert!(
            tree.root_at_height(first_retained).is_some(),
            "checkpoint at height {} should still be present",
            first_retained
        );
        assert!(
            tree.root_at_height(total as u32).is_some(),
            "latest checkpoint must be present"
        );
    }
}
