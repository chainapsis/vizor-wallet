//! [`KvShardStore`] — a [`ShardStore`] implementation backed by Go's Cosmos KV
//! store via C function pointer callbacks.
//!
//! # Design
//!
//! Instead of maintaining an in-process copy of all shard data,
//! `KvShardStore` forwards every [`ShardStore`] read and write directly to
//! the Cosmos KV store through a set of C callbacks registered at creation
//! time. Go registers `//export` functions that dispatch to the current
//! block's `store.KVStore` through a stable proxy pointer.
//!
//! This gives `ShardTree` true lazy loading: on a cold start only the data
//! that is actually accessed (the frontier shard + cap + checkpoints) is read.
//! No explicit restore loop, no O(n) blob loading, no shard geometry in Go.
//!
//! # KV key schema (matches keys.go)
//!
//! | Prefix    | Key                              | Value           |
//! |-----------|----------------------------------|-----------------|
//! | `0x0F`    | `0x0F \|\| u64 BE shard_index`   | shard blob      |
//! | `0x10`    | `0x10`                           | cap blob        |
//! | `0x11`    | `0x11 \|\| u32 BE checkpoint_id` | checkpoint blob |
//!
//! # Buffer ownership
//!
//! `get` returns a C-malloc'd buffer that Rust frees with the provided
//! `free_buf` callback after copying the value. All write callbacks receive
//! a Rust-owned slice (pointer + length); they must copy the data if they
//! need it to outlive the call.
//!
//! # Iterator protocol
//!
//! `iter_create(ctx, prefix, prefix_len, reverse)` returns an opaque handle
//! (a `cgo.Handle` on the Go side). `iter_next` advances and writes
//! C-malloc'd key + value; Rust frees each pair with `free_buf` before the
//! next call. `iter_free` closes and drops the iterator. `iter_next` returns
//! 0 on a valid entry, 1 when exhausted, -1 on error.

use std::collections::BTreeSet;
use std::fmt;
use std::os::raw::c_void;

use incrementalmerkletree::{Address, Level};
use shardtree::{
    store::{Checkpoint, ShardStore},
    LocatedPrunableTree, LocatedTree, PrunableTree, Tree,
};

use crate::hash::{MerkleHashVote, SHARD_HEIGHT};
use crate::serde::{read_checkpoint, read_shard_vote, write_checkpoint, write_shard_vote};

// ---------------------------------------------------------------------------
// KvError
// ---------------------------------------------------------------------------

/// Error type for [`KvShardStore`] operations.
///
/// Replaces `Infallible` so that KV callback failures are visible to callers
/// rather than being silently swallowed. The three variants cover all
/// observable failure modes:
///
/// - `IoError`: a KV callback returned a non-zero error code (disk full,
///   store closed, etc.).
/// - `Deserialization`: a blob retrieved from KV failed to decode.
/// - `Serialization`: a shard or cap could not be encoded before writing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KvError {
    /// A KV callback returned an error code (set, delete, or iterator failure).
    IoError,
    /// Shard or checkpoint data retrieved from KV could not be decoded.
    Deserialization,
    /// Shard or cap data could not be serialized before writing.
    Serialization,
}

impl fmt::Display for KvError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            KvError::IoError => write!(f, "KV callback returned an error"),
            KvError::Deserialization => write!(f, "failed to deserialize KV data"),
            KvError::Serialization => write!(f, "failed to serialize data for KV"),
        }
    }
}

impl std::error::Error for KvError {}

// ---------------------------------------------------------------------------
// KV key constants (must match keys.go 0x0F / 0x10 / 0x11)
// ---------------------------------------------------------------------------

const SHARD_PREFIX: u8 = 0x0F;
const CAP_KEY: u8 = 0x10;
const CHECKPOINT_PREFIX: u8 = 0x11;

fn shard_key(index: u64) -> [u8; 9] {
    let mut k = [0u8; 9];
    k[0] = SHARD_PREFIX;
    k[1..].copy_from_slice(&index.to_be_bytes());
    k
}

fn cap_key() -> [u8; 1] {
    [CAP_KEY]
}

fn checkpoint_key(id: u32) -> [u8; 5] {
    let mut k = [0u8; 5];
    k[0] = CHECKPOINT_PREFIX;
    k[1..].copy_from_slice(&id.to_be_bytes());
    k
}

// ---------------------------------------------------------------------------
// Callback function pointer types
// ---------------------------------------------------------------------------

/// Retrieve a value from the KV store.
///
/// On success (key found) writes a C-malloc'd buffer to `*out_val` and its
/// length to `*out_val_len`, then returns 0.
/// Returns 1 if the key was not found (out pointers are unchanged).
/// Returns -1 on error.
pub type KvGetFn = unsafe extern "C" fn(
    ctx: *mut c_void,
    key: *const u8,
    key_len: usize,
    out_val: *mut *mut u8,
    out_val_len: *mut usize,
) -> i32;

/// Write a key-value pair. Returns 0 on success, -1 on error.
pub type KvSetFn = unsafe extern "C" fn(
    ctx: *mut c_void,
    key: *const u8,
    key_len: usize,
    val: *const u8,
    val_len: usize,
) -> i32;

/// Delete a key. Returns 0 on success, -1 on error.
pub type KvDeleteFn = unsafe extern "C" fn(ctx: *mut c_void, key: *const u8, key_len: usize) -> i32;

/// Create an iterator over the given prefix.
///
/// `reverse` is 1 for a reverse (descending) iterator, 0 for ascending.
/// Returns an opaque iterator handle, or null on error.
pub type KvIterCreateFn = unsafe extern "C" fn(
    ctx: *mut c_void,
    prefix: *const u8,
    prefix_len: usize,
    reverse: u8,
) -> *mut c_void;

/// Advance the iterator and return the next key-value pair as C-malloc'd
/// buffers. Caller frees with `free_buf`.
///
/// Returns 0 if a valid entry was written, 1 if exhausted, -1 on error.
pub type KvIterNextFn = unsafe extern "C" fn(
    iter: *mut c_void,
    out_key: *mut *mut u8,
    out_key_len: *mut usize,
    out_val: *mut *mut u8,
    out_val_len: *mut usize,
) -> i32;

/// Close and free an iterator handle.
pub type KvIterFreeFn = unsafe extern "C" fn(iter: *mut c_void);

/// Free a C-malloc'd buffer returned by a KV callback.
pub type KvFreeBufFn = unsafe extern "C" fn(ptr: *mut u8, len: usize);

// ---------------------------------------------------------------------------
// KvCallbacks
// ---------------------------------------------------------------------------

/// Bundle of C function pointers + context passed to [`KvShardStore`].
///
/// # Safety
/// All function pointers must remain valid for the lifetime of the
/// `KvShardStore`. The `ctx` pointer must remain stable; Go achieves this
/// via a `KvStoreProxy` whose address never changes across blocks.
#[derive(Clone, Copy)]
pub struct KvCallbacks {
    pub ctx: *mut c_void,
    pub get: KvGetFn,
    pub set: KvSetFn,
    pub delete: KvDeleteFn,
    pub iter_create: KvIterCreateFn,
    pub iter_next: KvIterNextFn,
    pub iter_free: KvIterFreeFn,
    pub free_buf: KvFreeBufFn,
}

// SAFETY: EndBlocker is single-threaded; all callbacks are called only on
// the goroutine that owns the KV store.
unsafe impl Send for KvCallbacks {}
unsafe impl Sync for KvCallbacks {}

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

impl KvCallbacks {
    /// Fetch a value by key.
    ///
    /// Returns `Ok(Some(bytes))` if found, `Ok(None)` if not present, or
    /// `Err(KvError::IoError)` if the callback signalled a hard error (rc=-1).
    pub fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, KvError> {
        let mut out_ptr: *mut u8 = std::ptr::null_mut();
        let mut out_len: usize = 0;
        let rc = unsafe {
            (self.get)(
                self.ctx,
                key.as_ptr(),
                key.len(),
                &mut out_ptr,
                &mut out_len,
            )
        };
        match rc {
            0 => {
                let val = unsafe { std::slice::from_raw_parts(out_ptr, out_len).to_vec() };
                unsafe { (self.free_buf)(out_ptr, out_len) };
                Ok(Some(val))
            }
            1 => Ok(None),              // not found
            _ => Err(KvError::IoError), // rc=-1 or any other error code
        }
    }

    /// Write a key-value pair. Returns `Err(KvError::IoError)` if the
    /// callback returned a non-zero code.
    pub fn set(&self, key: &[u8], val: &[u8]) -> Result<(), KvError> {
        let rc = unsafe { (self.set)(self.ctx, key.as_ptr(), key.len(), val.as_ptr(), val.len()) };
        if rc != 0 {
            Err(KvError::IoError)
        } else {
            Ok(())
        }
    }

    /// Delete a key. Returns `Err(KvError::IoError)` if the callback failed.
    pub fn delete(&self, key: &[u8]) -> Result<(), KvError> {
        let rc = unsafe { (self.delete)(self.ctx, key.as_ptr(), key.len()) };
        if rc != 0 {
            Err(KvError::IoError)
        } else {
            Ok(())
        }
    }

    /// Create a forward or reverse iterator over the given prefix.
    fn iter(&self, prefix: &[u8], reverse: bool) -> KvIter<'_> {
        let handle =
            unsafe { (self.iter_create)(self.ctx, prefix.as_ptr(), prefix.len(), reverse as u8) };
        KvIter { handle, cb: self }
    }
}

struct KvIter<'a> {
    handle: *mut c_void,
    cb: &'a KvCallbacks,
}

impl<'a> KvIter<'a> {
    /// Advance and return `Some((key, value))`, or `None` when exhausted.
    fn next(&mut self) -> Option<(Vec<u8>, Vec<u8>)> {
        if self.handle.is_null() {
            return None;
        }
        let mut key_ptr: *mut u8 = std::ptr::null_mut();
        let mut key_len: usize = 0;
        let mut val_ptr: *mut u8 = std::ptr::null_mut();
        let mut val_len: usize = 0;
        let rc = unsafe {
            (self.cb.iter_next)(
                self.handle,
                &mut key_ptr,
                &mut key_len,
                &mut val_ptr,
                &mut val_len,
            )
        };
        if rc != 0 {
            return None;
        }
        let key = unsafe { std::slice::from_raw_parts(key_ptr, key_len).to_vec() };
        unsafe { (self.cb.free_buf)(key_ptr, key_len) };
        let val = unsafe { std::slice::from_raw_parts(val_ptr, val_len).to_vec() };
        unsafe { (self.cb.free_buf)(val_ptr, val_len) };
        Some((key, val))
    }
}

impl<'a> Drop for KvIter<'a> {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { (self.cb.iter_free)(self.handle) };
        }
    }
}

// ---------------------------------------------------------------------------
// KvShardStore
// ---------------------------------------------------------------------------

/// A [`ShardStore`] that stores all state in the Cosmos KV store via Go
/// callbacks. Gives `ShardTree` true lazy loading: only the data it actually
/// accesses is read from KV.
pub struct KvShardStore {
    pub(crate) cb: KvCallbacks,
}

impl KvShardStore {
    pub fn new(cb: KvCallbacks) -> Self {
        Self { cb }
    }
}

// ---------------------------------------------------------------------------
// ShardStore implementation
// ---------------------------------------------------------------------------

impl ShardStore for KvShardStore {
    type H = MerkleHashVote;
    type CheckpointId = u32;
    type Error = KvError;

    fn get_shard(
        &self,
        shard_root: Address,
    ) -> Result<Option<LocatedPrunableTree<MerkleHashVote>>, KvError> {
        let idx = shard_root.index();
        let key = shard_key(idx);
        let Some(blob) = self.cb.get(&key)? else {
            return Ok(None);
        };
        match read_shard_vote(&blob) {
            Ok(tree) => Ok(LocatedTree::from_parts(shard_root, tree).ok()),
            Err(_) => Err(KvError::Deserialization),
        }
    }

    fn last_shard(&self) -> Result<Option<LocatedPrunableTree<MerkleHashVote>>, KvError> {
        let prefix = [SHARD_PREFIX];
        let mut iter = self.cb.iter(&prefix, true /* reverse */);
        let Some((key, val)) = iter.next() else {
            return Ok(None);
        };
        if key.len() < 9 {
            return Ok(None);
        }
        let idx = u64::from_be_bytes(key[1..9].try_into().unwrap());
        let level = Level::from(SHARD_HEIGHT);
        let addr = Address::from_parts(level, idx);
        match read_shard_vote(&val) {
            Ok(tree) => Ok(LocatedTree::from_parts(addr, tree).ok()),
            Err(_) => Err(KvError::Deserialization),
        }
    }

    fn put_shard(&mut self, subtree: LocatedPrunableTree<MerkleHashVote>) -> Result<(), KvError> {
        let idx = subtree.root_addr().index();
        let key = shard_key(idx);
        let blob = write_shard_vote(subtree.root()).map_err(|_| KvError::Serialization)?;
        self.cb.set(&key, &blob)
    }

    fn get_shard_roots(&self) -> Result<Vec<Address>, KvError> {
        let prefix = [SHARD_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let level = Level::from(SHARD_HEIGHT);
        let mut roots = Vec::new();
        while let Some((key, _)) = iter.next() {
            if key.len() < 9 {
                continue;
            }
            let idx = u64::from_be_bytes(key[1..9].try_into().unwrap());
            roots.push(Address::from_parts(level, idx));
        }
        Ok(roots)
    }

    fn truncate_shards(&mut self, shard_index: u64) -> Result<(), KvError> {
        let prefix = [SHARD_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let mut to_delete = Vec::new();
        while let Some((key, _)) = iter.next() {
            if key.len() < 9 {
                continue;
            }
            let idx = u64::from_be_bytes(key[1..9].try_into().unwrap());
            if idx >= shard_index {
                to_delete.push(key);
            }
        }
        drop(iter);
        for key in to_delete {
            self.cb.delete(&key)?;
        }
        Ok(())
    }

    fn get_cap(&self) -> Result<PrunableTree<MerkleHashVote>, KvError> {
        let key = cap_key();
        let Some(blob) = self.cb.get(&key)? else {
            return Ok(Tree::empty());
        };
        read_shard_vote(&blob).map_err(|_| KvError::Deserialization)
    }

    fn put_cap(&mut self, cap: PrunableTree<MerkleHashVote>) -> Result<(), KvError> {
        let key = cap_key();
        let blob = write_shard_vote(&cap).map_err(|_| KvError::Serialization)?;
        self.cb.set(&key, &blob)
    }

    fn min_checkpoint_id(&self) -> Result<Option<u32>, KvError> {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        Ok(iter.next().and_then(|(k, _)| {
            if k.len() >= 5 {
                Some(u32::from_be_bytes(k[1..5].try_into().unwrap()))
            } else {
                None
            }
        }))
    }

    fn max_checkpoint_id(&self) -> Result<Option<u32>, KvError> {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, true /* reverse */);
        Ok(iter.next().and_then(|(k, _)| {
            if k.len() >= 5 {
                Some(u32::from_be_bytes(k[1..5].try_into().unwrap()))
            } else {
                None
            }
        }))
    }

    fn add_checkpoint(
        &mut self,
        checkpoint_id: u32,
        checkpoint: Checkpoint,
    ) -> Result<(), KvError> {
        let key = checkpoint_key(checkpoint_id);
        let blob = write_checkpoint(&checkpoint);
        self.cb.set(&key, &blob)
    }

    fn checkpoint_count(&self) -> Result<usize, KvError> {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let mut count = 0usize;
        while iter.next().is_some() {
            count += 1;
        }
        Ok(count)
    }

    fn get_checkpoint_at_depth(
        &self,
        checkpoint_depth: usize,
    ) -> Result<Option<(u32, Checkpoint)>, KvError> {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, true /* reverse */);
        let mut seen = 0usize;
        while let Some((key, val)) = iter.next() {
            if seen == checkpoint_depth {
                if key.len() < 5 {
                    return Ok(None);
                }
                let id = u32::from_be_bytes(key[1..5].try_into().unwrap());
                return Ok(read_checkpoint(&val).ok().map(|cp| (id, cp)));
            }
            seen += 1;
        }
        Ok(None)
    }

    fn get_checkpoint(&self, checkpoint_id: &u32) -> Result<Option<Checkpoint>, KvError> {
        let key = checkpoint_key(*checkpoint_id);
        let Some(blob) = self.cb.get(&key)? else {
            return Ok(None);
        };
        Ok(read_checkpoint(&blob).ok())
    }

    fn with_checkpoints<F>(&mut self, limit: usize, mut callback: F) -> Result<(), KvError>
    where
        F: FnMut(&u32, &Checkpoint) -> Result<(), KvError>,
    {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let mut count = 0usize;
        while count < limit {
            let Some((key, val)) = iter.next() else {
                break;
            };
            if key.len() < 5 {
                continue;
            }
            let id = u32::from_be_bytes(key[1..5].try_into().unwrap());
            if let Ok(cp) = read_checkpoint(&val) {
                callback(&id, &cp)?;
            }
            count += 1;
        }
        Ok(())
    }

    fn for_each_checkpoint<F>(&self, limit: usize, mut callback: F) -> Result<(), KvError>
    where
        F: FnMut(&u32, &Checkpoint) -> Result<(), KvError>,
    {
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let mut count = 0usize;
        while count < limit {
            let Some((key, val)) = iter.next() else {
                break;
            };
            if key.len() < 5 {
                continue;
            }
            let id = u32::from_be_bytes(key[1..5].try_into().unwrap());
            if let Ok(cp) = read_checkpoint(&val) {
                callback(&id, &cp)?;
            }
            count += 1;
        }
        Ok(())
    }

    fn update_checkpoint_with<F>(&mut self, checkpoint_id: &u32, update: F) -> Result<bool, KvError>
    where
        F: Fn(&mut Checkpoint) -> Result<(), KvError>,
    {
        let key = checkpoint_key(*checkpoint_id);
        let Some(blob) = self.cb.get(&key)? else {
            return Ok(false);
        };
        let Ok(mut cp) = read_checkpoint(&blob) else {
            return Ok(false);
        };
        update(&mut cp)?;
        let new_blob = write_checkpoint(&cp);
        self.cb.set(&key, &new_blob)?;
        Ok(true)
    }

    fn remove_checkpoint(&mut self, checkpoint_id: &u32) -> Result<(), KvError> {
        let key = checkpoint_key(*checkpoint_id);
        self.cb.delete(&key)
    }

    fn truncate_checkpoints_retaining(&mut self, checkpoint_id: &u32) -> Result<(), KvError> {
        // Delete all checkpoints with id < checkpoint_id; clear marks_removed
        // on the retained checkpoint itself (matches MemoryShardStore semantics).
        let prefix = [CHECKPOINT_PREFIX];
        let mut iter = self.cb.iter(&prefix, false);
        let mut to_delete = Vec::new();
        while let Some((key, _)) = iter.next() {
            if key.len() < 5 {
                continue;
            }
            let id = u32::from_be_bytes(key[1..5].try_into().unwrap());
            if id < *checkpoint_id {
                to_delete.push(key);
            } else {
                break;
            }
        }
        drop(iter);
        for key in to_delete {
            self.cb.delete(&key)?;
        }
        // Clear marks_removed on the retaining checkpoint.
        let retain_key = checkpoint_key(*checkpoint_id);
        if let Some(blob) = self.cb.get(&retain_key)? {
            if let Ok(cp) = read_checkpoint(&blob) {
                let cleared = Checkpoint::from_parts(cp.tree_state(), BTreeSet::new());
                self.cb.set(&retain_key, &write_checkpoint(&cleared))?;
            }
        }
        Ok(())
    }
}
