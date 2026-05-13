//! Client-side vote commitment tree.
//!
//! [`TreeClient`] maintains a sparse local copy of the tree for witness generation.
//! It syncs from a [`TreeSyncApi`] source (the server), marks positions of interest,
//! and generates Merkle authentication paths.
//!
//! This mirrors how Zcash wallets use `ShardTree` via `WalletCommitmentTrees`:
//! the client receives all leaves (no trial decryption needed since all vote-tree
//! leaves are public), inserts them, and generates witnesses only for its own
//! marked positions.

use std::collections::BTreeSet;
use std::fmt;

use incrementalmerkletree::{Hashable, Level, Retention};
use pasta_curves::Fp;
use shardtree::{store::memory::MemoryShardStore, ShardTree};

use crate::hash::{MerkleHashVote, MAX_CHECKPOINTS, SHARD_HEIGHT, TREE_DEPTH};
use crate::path::MerklePath;
use crate::sync_api::TreeSyncApi;

// ---------------------------------------------------------------------------
// SyncError
// ---------------------------------------------------------------------------

/// Errors that can occur during [`TreeClient::sync`].
#[derive(Debug)]
pub enum SyncError<E: fmt::Debug> {
    /// Error from the underlying [`TreeSyncApi`] transport.
    Api(E),
    /// Block's `start_index` doesn't match the client's expected next position.
    ///
    /// This indicates missed or duplicated blocks, wrong ordering, or a
    /// protocol-level desync between server and client.
    StartIndexMismatch {
        height: u32,
        expected: u64,
        got: u64,
    },
    /// Client's computed root doesn't match the server's root at a block height.
    ///
    /// This indicates corrupted leaf data, a hash mismatch, or a
    /// different tree implementation between server and client.
    RootMismatch {
        height: u32,
        local: Option<Fp>,
        server: Fp,
    },
    /// The server ended pagination before the client reached the advertised tip.
    IncompleteSync {
        local_next_index: u64,
        server_next_index: u64,
    },
    /// The server returned a pagination cursor that does not move forward.
    InvalidPagination { current: u32, next: u32 },
}

impl<E: fmt::Debug> fmt::Display for SyncError<E> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SyncError::Api(e) => write!(f, "sync API error: {:?}", e),
            SyncError::StartIndexMismatch {
                height,
                expected,
                got,
            } => write!(
                f,
                "start_index mismatch at height {}: expected {}, got {}",
                height, expected, got
            ),
            SyncError::RootMismatch {
                height,
                local,
                server,
            } => write!(
                f,
                "root mismatch at height {}: local={:?}, server={:?}",
                height, local, server
            ),
            SyncError::IncompleteSync {
                local_next_index,
                server_next_index,
            } => write!(
                f,
                "incomplete sync: local next_index={}, server next_index={}",
                local_next_index, server_next_index
            ),
            SyncError::InvalidPagination { current, next } => write!(
                f,
                "invalid pagination cursor: current={}, next={}",
                current, next
            ),
        }
    }
}

impl<E: fmt::Debug> From<E> for SyncError<E> {
    fn from(err: E) -> Self {
        SyncError::Api(err)
    }
}

// ---------------------------------------------------------------------------
// TreeClient
// ---------------------------------------------------------------------------

/// Client-side sparse vote commitment tree.
///
/// Mirrors the server tree via incremental sync. Marks specific positions for
/// witness generation:
/// - **Wallet**: marks its own VAN position (for ZKP #2)
/// - **Helper server**: marks delegated VC positions (for ZKP #3)
pub struct TreeClient {
    inner: ShardTree<MemoryShardStore<MerkleHashVote, u32>, { TREE_DEPTH as u8 }, { SHARD_HEIGHT }>,
    /// Next leaf position expected (mirrors server's next_position).
    next_position: u64,
    /// Latest synced block height.
    last_synced_height: Option<u32>,
    /// Positions registered for witness generation.
    ///
    /// During [`sync`], positions in this set are inserted with `Retention::Marked`;
    /// all other positions use `Retention::Ephemeral`. This gives ShardTree the
    /// signal to retain the sibling hashes needed for witnesses at marked positions
    /// while pruning everything else.
    ///
    /// Register positions via [`mark_position`] **before** syncing past them.
    marked_positions: BTreeSet<u64>,
}

impl TreeClient {
    /// Create an empty client tree.
    pub fn empty() -> Self {
        Self {
            inner: ShardTree::new(MemoryShardStore::empty(), MAX_CHECKPOINTS),
            next_position: 0,
            last_synced_height: None,
            marked_positions: BTreeSet::new(),
        }
    }

    /// Register a leaf position for witness generation.
    ///
    /// When [`sync`] encounters this position, the leaf is inserted with
    /// `Retention::Marked` so that [`witness`] can later produce a Merkle
    /// authentication path for it. All other positions are inserted as
    /// `Retention::Ephemeral` (prunable).
    ///
    /// Must be called **before** syncing past the position. This matches
    /// the production pattern where the wallet knows its VAN index from
    /// `MsgDelegateVote` before it syncs the block that contains it, and
    /// the helper server knows the delegated VC index from the share
    /// payload before it syncs.
    ///
    /// Calling this for a position that has already been synced has no
    /// effect (the leaf is already in the tree as ephemeral).
    pub fn mark_position(&mut self, position: u64) {
        self.marked_positions.insert(position);
    }

    /// Sync the client tree from a [`TreeSyncApi`] source.
    ///
    /// Fetches block commitments from the server (incrementally, from the last
    /// synced height) and inserts them into the local tree. Each block's leaves
    /// are checkpointed at the block's height.
    ///
    /// **Retention**: Positions registered via [`mark_position`] are inserted
    /// with `Retention::Marked` so witnesses can be generated for them.
    /// All other positions use `Retention::Ephemeral`, allowing `ShardTree`
    /// to prune their subtree data once it's no longer needed. This keeps
    /// the client tree sparse — only the subtrees touching marked positions
    /// are fully materialized.
    ///
    /// **Safety checks** (these catch corrupted data or protocol mismatches):
    /// - Each block's `start_index` must match the client's expected next position.
    /// - After checkpointing each block, the client's root is verified against the
    ///   server's root at that height (the consistency check described in the README).
    /// - After pagination completes, the client must match the tip advertised by
    ///   `get_tree_state()`.
    pub fn sync<A: TreeSyncApi>(&mut self, api: &A) -> Result<(), SyncError<A::Error>> {
        let state = api.get_tree_state()?;
        if state.next_index == self.next_position {
            if state.next_index > 0 {
                let local = self.root();
                if local != state.root {
                    return Err(SyncError::RootMismatch {
                        height: state.height,
                        local: Some(local),
                        server: state.root,
                    });
                }
            }
            return Ok(());
        }

        let from_height = self.last_synced_height.map(|h| h + 1).unwrap_or(0);
        let to_height = state.height;

        if from_height > to_height {
            return Ok(()); // Already up to date.
        }

        let mut page_from = from_height;
        loop {
            let page = api.get_block_commitments(page_from, to_height)?;

            for block in &page.blocks {
                // Validate start_index continuity: the block's first leaf index must
                // match exactly where the client expects the next leaf. A mismatch
                // means missed blocks, duplicates, or wrong ordering.
                if !block.leaves.is_empty() && block.start_index != self.next_position {
                    return Err(SyncError::StartIndexMismatch {
                        height: block.height,
                        expected: self.next_position,
                        got: block.start_index,
                    });
                }

                for leaf in &block.leaves {
                    // Use Marked retention for positions the client registered
                    // interest in; Ephemeral for everything else. This gives
                    // ShardTree the signal to retain witness data only where needed.
                    let retention = if self.marked_positions.contains(&self.next_position) {
                        Retention::Marked
                    } else {
                        Retention::Ephemeral
                    };
                    self.inner
                        .append(*leaf, retention)
                        .expect("append must succeed (tree not full)");
                    self.next_position += 1;
                }

                // Checkpoint after each block's leaves, mirroring the server's
                // EndBlocker snapshots.
                self.inner
                    .checkpoint(block.height)
                    .expect("checkpoint must succeed");
                self.last_synced_height = Some(block.height);

                // Root consistency check: verify the client's computed root matches
                // the server's root at this height. This catches corrupted leaf data,
                // hash mismatches, or tree implementation differences.
                let local = self.root_at_height(block.height);
                if local != Some(block.root) {
                    return Err(SyncError::RootMismatch {
                        height: block.height,
                        local,
                        server: block.root,
                    });
                }
            }

            // A zero cursor means this page completed the requested height range.
            if page.next_from_height == 0 {
                break;
            }

            // Nonzero cursors must move forward and stay inside the advertised
            // tip range. Otherwise a broken server could make sync loop forever
            // or skip past data that should have been returned.
            if page.next_from_height <= page_from {
                return Err(SyncError::InvalidPagination {
                    current: page_from,
                    next: page.next_from_height,
                });
            }
            if page.next_from_height > to_height {
                return Err(SyncError::InvalidPagination {
                    current: page_from,
                    next: page.next_from_height,
                });
            }
            page_from = page.next_from_height;
        }

        // Pagination is only complete if the leaves we applied reach the same
        // next index the server advertised before the loop started.
        if self.next_position != state.next_index {
            return Err(SyncError::IncompleteSync {
                local_next_index: self.next_position,
                server_next_index: state.next_index,
            });
        }

        // The final root check binds the full paginated sync result to the
        // tree state fetched at the beginning of sync.
        if state.next_index > 0 {
            let local = self.root();
            if local != state.root {
                return Err(SyncError::RootMismatch {
                    height: state.height,
                    local: Some(local),
                    server: state.root,
                });
            }
        }

        Ok(())
    }

    /// Generate a Merkle authentication path for the leaf at `position`,
    /// valid at the given checkpoint `anchor_height`.
    ///
    /// Returns `None` if the position or checkpoint is invalid, or if the
    /// position was not marked.
    pub fn witness(&self, position: u64, anchor_height: u32) -> Option<MerklePath> {
        let pos = incrementalmerkletree::Position::from(position);
        self.inner
            .witness_at_checkpoint_id(pos, &anchor_height)
            .ok()
            .flatten()
            .map(MerklePath::from)
    }

    /// Root at a specific checkpoint height (for anchor verification).
    ///
    /// After sync, this should match the server's root at the same height.
    pub fn root_at_height(&self, height: u32) -> Option<Fp> {
        self.inner
            .root_at_checkpoint_id(&height)
            .ok()
            .flatten()
            .map(|h| h.0)
    }

    /// Current root (at the latest synced checkpoint).
    pub fn root(&self) -> Fp {
        if let Some(id) = self.last_synced_height {
            self.inner
                .root_at_checkpoint_id(&id)
                .ok()
                .flatten()
                .map(|h| h.0)
                .unwrap_or_else(|| MerkleHashVote::empty_root(Level::from(TREE_DEPTH as u8)).0)
        } else {
            MerkleHashVote::empty_root(Level::from(TREE_DEPTH as u8)).0
        }
    }

    /// Number of leaves synced.
    pub fn size(&self) -> u64 {
        self.next_position
    }

    /// Latest synced block height.
    pub fn last_synced_height(&self) -> Option<u32> {
        self.last_synced_height
    }
}
