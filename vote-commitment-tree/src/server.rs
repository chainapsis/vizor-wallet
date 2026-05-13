//! Generic and production vote commitment tree servers.
//!
//! [`GenericTreeServer`] is a single parameterised struct that backs both the
//! production server ([`TreeServer`], KV-backed) and the in-memory test/POC
//! server. The only difference between the two is the shard store
//! implementation they use.
//!
//! [`SyncableServer`] wraps [`GenericTreeServer`] and adds per-block leaf
//! tracking (`blocks`, `pending_leaves`, `pending_start`) needed to implement
//! [`crate::sync_api::TreeSyncApi`]. This is a sync-protocol concern, not a
//! tree concern, so it lives in a separate wrapper rather than on the core
//! tree type. [`MemoryTreeServer`] is a convenience alias for
//! `SyncableServer<MemoryShardStore<…>>`.
//!
//! In production, [`TreeServer`] is backed by a [`KvShardStore`] so all shard
//! reads/writes go directly to the Cosmos KV store through Go callbacks,
//! giving `ShardTree` true lazy loading.

use std::collections::BTreeMap;

use incrementalmerkletree::{Hashable, Level, Retention};
use pasta_curves::{group::ff::PrimeField, Fp};
use shardtree::{
    error::ShardTreeError,
    store::{memory::MemoryShardStore, ShardStore},
    ShardTree,
};

use crate::hash::{MerkleHashVote, MAX_CHECKPOINTS, SHARD_HEIGHT, TREE_DEPTH};
use crate::kv_shard_store::{KvCallbacks, KvError, KvShardStore};
use crate::path::MerklePath;
use crate::sync_api::BlockCommitments;

// ---------------------------------------------------------------------------
// GenericTreeServer
// ---------------------------------------------------------------------------

/// An append-only Poseidon Merkle tree server backed by any [`shardtree::store::ShardStore`].
///
/// Use the type aliases [`TreeServer`] (KV-backed) and [`MemoryTreeServer`]
/// (in-memory) rather than naming this type directly.
///
/// Methods that mutate the tree return `Result` so storage failures are visible to
/// callers. For [`MemoryTreeServer`] the error type is `Infallible`, so those
/// results can be safely `.unwrap()`-ed; for [`TreeServer`] the error type is
/// [`crate::kv_shard_store::KvError`] and must be propagated.
pub struct GenericTreeServer<
    S: shardtree::store::ShardStore<H = MerkleHashVote, CheckpointId = u32>,
> {
    pub(crate) inner: ShardTree<S, { TREE_DEPTH as u8 }, { SHARD_HEIGHT }>,
    /// Latest checkpoint id (block height) that has been recorded.
    pub(crate) latest_checkpoint: Option<u32>,
    /// Number of leaves appended so far.
    pub(crate) next_position: u64,
}

/// Production vote commitment tree backed by the Cosmos KV store.
pub type TreeServer = GenericTreeServer<KvShardStore>;

/// A [`GenericTreeServer`] augmented with per-block leaf tracking for the
/// [`crate::sync_api::TreeSyncApi`].
///
/// The sync protocol needs to know which leaves were appended in each block so
/// that clients can download compact-block diffs. That tracking is a sync
/// concern, not a tree concern, so it lives here rather than on
/// [`GenericTreeServer`].
///
/// Use the [`MemoryTreeServer`] type alias for the common in-memory case.
pub struct SyncableServer<S: ShardStore<H = MerkleHashVote, CheckpointId = u32>> {
    pub(crate) tree: GenericTreeServer<S>,
    /// Completed blocks: height → commitments (populated on `checkpoint`).
    pub(crate) blocks: BTreeMap<u32, BlockCommitments>,
    /// Leaves accumulated for the current (not yet checkpointed) block.
    pending_leaves: Vec<MerkleHashVote>,
    /// Start index for the pending block.
    pending_start: u64,
}

/// In-memory vote commitment tree for tests and the POC helper server.
///
/// This is a type alias for [`SyncableServer`] backed by [`MemoryShardStore`].
/// It supports [`crate::sync_api::TreeSyncApi`] via per-block leaf tracking
/// inside `SyncableServer`. Tests that do not need sync can use
/// `GenericTreeServer<MemoryShardStore<MerkleHashVote, u32>>` directly.
pub type MemoryTreeServer = SyncableServer<MemoryShardStore<MerkleHashVote, u32>>;

// ---------------------------------------------------------------------------
// AppendFromKvError
// ---------------------------------------------------------------------------

/// Error returned by [`TreeServer::append_from_kv`].
#[derive(Debug)]
pub enum AppendFromKvError {
    /// A KV callback failed while reading a leaf.
    Kv(KvError),
    /// A leaf key was missing from the application KV store.
    MissingLeaf(u64),
    /// A leaf blob had an unexpected length or a non-canonical Fp encoding.
    MalformedLeaf(u64),
    /// The underlying `ShardTree` rejected the append (e.g. tree full or
    /// storage error).
    Tree(ShardTreeError<KvError>),
}

impl From<KvError> for AppendFromKvError {
    fn from(e: KvError) -> Self {
        AppendFromKvError::Kv(e)
    }
}

impl std::fmt::Display for AppendFromKvError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AppendFromKvError::Kv(e) => write!(f, "KV error reading leaf: {}", e),
            AppendFromKvError::MissingLeaf(i) => {
                write!(f, "leaf at index {} is missing from KV", i)
            }
            AppendFromKvError::MalformedLeaf(i) => {
                write!(
                    f,
                    "leaf at index {} is malformed (wrong length or non-canonical Fp)",
                    i
                )
            }
            AppendFromKvError::Tree(e) => write!(f, "ShardTree error: {:?}", e),
        }
    }
}

impl std::error::Error for AppendFromKvError {}

// ---------------------------------------------------------------------------
// CheckpointError
// ---------------------------------------------------------------------------

/// Error returned by [`GenericTreeServer::checkpoint`] and [`SyncableServer::checkpoint`].
#[derive(Debug)]
pub enum CheckpointError<E> {
    /// The requested checkpoint height is not strictly greater than the most
    /// recently recorded one. Checkpoint IDs must increase monotonically.
    NotMonotonic { prev: u32, requested: u32 },
    /// The underlying [`ShardTree`] rejected the checkpoint (storage error).
    Tree(ShardTreeError<E>),
}

impl<E: std::fmt::Debug> std::fmt::Display for CheckpointError<E> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CheckpointError::NotMonotonic { prev, requested } => write!(
                f,
                "checkpoint height must be strictly increasing: {} <= {}",
                requested, prev
            ),
            CheckpointError::Tree(e) => write!(f, "ShardTree error: {:?}", e),
        }
    }
}

impl<E: std::fmt::Debug + 'static> std::error::Error for CheckpointError<E> {}

impl<E> From<ShardTreeError<E>> for CheckpointError<E> {
    fn from(e: ShardTreeError<E>) -> Self {
        CheckpointError::Tree(e)
    }
}

// ---------------------------------------------------------------------------
// TreeServer constructor
// ---------------------------------------------------------------------------

impl TreeServer {
    /// Create a new KV-backed tree server.
    ///
    /// `next_position` is `CommitmentTreeState.NextIndex` from KV (0 on first
    /// boot). On a cold start, `latest_checkpoint` is initialised from the
    /// maximum checkpoint ID persisted in the KV store, so that `root()`
    /// returns the correct value even before the first checkpoint after restart.
    pub fn new(cb: KvCallbacks, next_position: u64) -> Self {
        let store = KvShardStore::new(cb);
        // Initialise latest_checkpoint from the KV store before handing the
        // store to ShardTree (which takes ownership). Errors are treated as
        // "no checkpoint" — the tree will re-checkpoint on the next append.
        let latest_checkpoint = store.max_checkpoint_id().unwrap_or(None);
        Self {
            inner: ShardTree::new(store, MAX_CHECKPOINTS),
            latest_checkpoint,
            next_position,
        }
    }
}

// ---------------------------------------------------------------------------
// TreeServer: append_from_kv (delta-append directly from KV)
// ---------------------------------------------------------------------------

impl TreeServer {
    /// Append `count` leaves starting at `cursor` by reading them directly
    /// from the application KV store via KV callbacks, skipping the Go-side
    /// leaf fetch and CGO serialization round-trip.
    ///
    /// Each leaf is stored at `0x02 || u64 BE index` in the Cosmos KV store
    /// (the `CommitmentLeafKey` format from `types/keys.go`). On success, the
    /// tree's internal leaf count advances by `count`.
    ///
    /// This is the production delta-append path: a single CGO call to this
    /// function replaces the `newLeaves` allocation + per-leaf KV read loop
    /// that was previously done in `ensureTreeLoaded`.
    pub fn append_from_kv(&mut self, cursor: u64, count: u64) -> Result<(), AppendFromKvError> {
        for i in cursor..cursor + count {
            let key = Self::leaf_key(i);
            let blob = self
                .inner
                .store()
                .cb
                .get(&key)?
                .ok_or(AppendFromKvError::MissingLeaf(i))?;
            if blob.len() != 32 {
                return Err(AppendFromKvError::MalformedLeaf(i));
            }
            let mut repr = [0u8; 32];
            repr.copy_from_slice(&blob);
            let fp: Option<Fp> = Fp::from_repr(repr).into();
            let fp = fp.ok_or(AppendFromKvError::MalformedLeaf(i))?;
            self.append(fp).map_err(AppendFromKvError::Tree)?;
        }
        Ok(())
    }

    /// KV key for an app-level commitment leaf: `0x02 || u64 BE index`.
    ///
    /// Matches `types.CommitmentLeafKey(index)` in keys.go.
    fn leaf_key(index: u64) -> [u8; 9] {
        let mut k = [0u8; 9];
        k[0] = 0x02;
        k[1..].copy_from_slice(&index.to_be_bytes());
        k
    }
}

// ---------------------------------------------------------------------------
// SyncableServer constructor
// ---------------------------------------------------------------------------

impl SyncableServer<MemoryShardStore<MerkleHashVote, u32>> {
    /// Create an empty in-memory syncable tree.
    pub fn empty() -> Self {
        Self {
            tree: GenericTreeServer {
                inner: ShardTree::new(MemoryShardStore::empty(), MAX_CHECKPOINTS),
                latest_checkpoint: None,
                next_position: 0,
            },
            blocks: BTreeMap::new(),
            pending_leaves: Vec::new(),
            pending_start: 0,
        }
    }
}

// ---------------------------------------------------------------------------
// SyncableServer: shared impl for all S
// ---------------------------------------------------------------------------

impl<S> SyncableServer<S>
where
    S: ShardStore<H = MerkleHashVote, CheckpointId = u32>,
    S::Error: std::fmt::Debug,
{
    /// Wrap an existing [`GenericTreeServer`] with sync tracking.
    pub fn new(tree: GenericTreeServer<S>) -> Self {
        Self {
            tree,
            blocks: BTreeMap::new(),
            pending_leaves: Vec::new(),
            pending_start: 0,
        }
    }

    /// Append a single leaf and record it in the pending block.
    pub fn append(&mut self, leaf: Fp) -> Result<u64, ShardTreeError<S::Error>> {
        let hash = MerkleHashVote::from_fp(leaf);
        let idx = self.tree.append(leaf)?;
        self.pending_leaves.push(hash);
        Ok(idx)
    }

    /// Append two leaves (e.g. new VAN + VC from `MsgCastVote`).
    pub fn append_two(&mut self, first: Fp, second: Fp) -> Result<u64, ShardTreeError<S::Error>> {
        let idx = self.append(first)?;
        self.append(second)?;
        Ok(idx)
    }

    /// Snapshot the current tree state and record block-level commitments.
    ///
    /// # Errors
    /// Returns [`CheckpointError::NotMonotonic`] if `height` is not strictly
    /// greater than the previous checkpoint height.
    pub fn checkpoint(&mut self, height: u32) -> Result<(), CheckpointError<S::Error>> {
        self.tree.checkpoint(height)?;
        let root = self
            .root_at_height(height)
            .unwrap_or_else(|| self.tree.root());
        let commitments = BlockCommitments {
            height,
            start_index: self.pending_start,
            leaves: std::mem::take(&mut self.pending_leaves),
            root,
        };
        self.blocks.insert(height, commitments);
        self.pending_start = self.tree.next_position;
        Ok(())
    }

    /// Current Merkle root (at the latest checkpoint).
    pub fn root(&self) -> Fp {
        self.tree.root()
    }

    /// Root at a specific checkpoint height.
    pub fn root_at_height(&self, height: u32) -> Option<Fp> {
        self.tree.root_at_height(height)
    }

    /// Number of leaves appended.
    pub fn size(&self) -> u64 {
        self.tree.size()
    }

    /// Build a Merkle path for the leaf at `position` at `anchor_height`.
    pub fn path(&self, position: u64, anchor_height: u32) -> Option<MerklePath> {
        self.tree.path(position, anchor_height)
    }

    /// Latest checkpoint height.
    pub fn latest_checkpoint(&self) -> Option<u32> {
        self.tree.latest_checkpoint
    }
}

// ---------------------------------------------------------------------------
// Shared impl for all GenericTreeServer<S>
// ---------------------------------------------------------------------------

impl<S> GenericTreeServer<S>
where
    S: shardtree::store::ShardStore<H = MerkleHashVote, CheckpointId = u32>,
    S::Error: std::fmt::Debug,
{
    /// Append a single leaf (e.g. one VAN from `MsgDelegateVote`).
    ///
    /// The leaf is marked so witnesses can be generated for it later.
    /// Returns the leaf index.
    pub fn append(&mut self, leaf: Fp) -> Result<u64, ShardTreeError<S::Error>> {
        let index = self.next_position;
        let hash = MerkleHashVote::from_fp(leaf);
        self.inner.append(hash, Retention::Marked)?;
        self.next_position += 1;
        Ok(index)
    }

    /// Append two leaves (e.g. new VAN + VC from `MsgCastVote`).
    ///
    /// Returns the index of the first leaf.
    pub fn append_two(&mut self, first: Fp, second: Fp) -> Result<u64, ShardTreeError<S::Error>> {
        let index = self.append(first)?;
        self.append(second)?;
        Ok(index)
    }

    /// Snapshot the current tree state at the given block height.
    ///
    /// Called by EndBlocker after processing all transactions in a block.
    /// The root at this checkpoint becomes a valid anchor for ZKP #2 / ZKP #3.
    ///
    /// # Errors
    /// Returns [`CheckpointError::NotMonotonic`] if `height` is not strictly
    /// greater than the previous checkpoint height.
    /// Returns [`CheckpointError::Tree`] if the underlying shard store fails.
    pub fn checkpoint(&mut self, height: u32) -> Result<(), CheckpointError<S::Error>> {
        if let Some(prev) = self.latest_checkpoint {
            if height <= prev {
                return Err(CheckpointError::NotMonotonic {
                    prev,
                    requested: height,
                });
            }
        }
        self.inner.checkpoint(height)?;
        self.latest_checkpoint = Some(height);
        Ok(())
    }

    /// Current Merkle root (at the latest checkpoint).
    pub fn root(&self) -> Fp {
        if let Some(id) = self.latest_checkpoint {
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

    /// Root at a specific checkpoint height (anchor lookup).
    ///
    /// Returns `None` if the checkpoint does not exist.
    pub fn root_at_height(&self, height: u32) -> Option<Fp> {
        self.inner
            .root_at_checkpoint_id(&height)
            .ok()
            .flatten()
            .map(|h| h.0)
    }

    /// Number of leaves appended.
    pub fn size(&self) -> u64 {
        self.next_position
    }

    /// Set the leaf count directly (e.g. to restore after a cold start when
    /// `next_position` was not passed to [`TreeServer::new`]).
    pub fn set_next_position(&mut self, pos: u64) {
        self.next_position = pos;
    }

    /// Build a Merkle path for the leaf at `position`, valid at the given
    /// checkpoint `anchor_height`.
    ///
    /// Returns `None` if the position or checkpoint is invalid.
    pub fn path(&self, position: u64, anchor_height: u32) -> Option<MerklePath> {
        let pos = incrementalmerkletree::Position::from(position);
        self.inner
            .witness_at_checkpoint_id(pos, &anchor_height)
            .ok()
            .flatten()
            .map(MerklePath::from)
    }
}
