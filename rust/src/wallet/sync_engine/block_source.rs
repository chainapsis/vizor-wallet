//! In-memory [`BlockSource`] used by the sync loop.
//!
//! `scan_cached_blocks` expects a `BlockSource`-shaped input so it can
//! iterate compact blocks one at a time. Historically librustzcash
//! wallets pointed that input at an on-disk SQLite cache
//! (`FsBlockDb`). We deliberately skip the file-cache step and keep a
//! bounded set of compact-block batches in memory:
//!
//!   1. Batch count and estimated decoded size are bounded by the sync
//!      engine's prefetch policy.
//!   2. Avoiding the cache DB means one less file format to keep in
//!      sync with librustzcash migrations and one less thing to clear
//!      on reorg / rewind.
//!   3. The sync loop was already downloading the blocks directly from
//!      lightwalletd; tee'ing them through a file would just slow the
//!      scan down.
//!
//! The type is visible only to the `sync_engine` module tree
//! (`pub(super)`); callers construct one via
//! [`MemoryBlockSource::new`] and hand it straight to
//! `scan_cached_blocks`.

use std::fmt;

use zcash_client_backend::{
    data_api::chain::{self, error::Error as ChainError},
    proto::compact_formats::CompactBlock,
};
use zcash_protocol::consensus::BlockHeight;

/// Holds a single batch of compact blocks in memory for one
/// `scan_cached_blocks` call.
pub(super) struct MemoryBlockSource {
    blocks: Vec<CompactBlock>,
    wire_bytes: u64,
}

impl MemoryBlockSource {
    pub(super) fn new(blocks: Vec<CompactBlock>) -> Self {
        let wire_bytes = blocks
            .iter()
            .map(|block| prost::Message::encoded_len(block) as u64)
            .sum();
        Self { blocks, wire_bytes }
    }

    pub(super) fn wire_bytes(&self) -> u64 {
        self.wire_bytes
    }

    pub(super) fn block_count(&self) -> usize {
        self.blocks.len()
    }

    pub(super) fn first_block(&self) -> Option<&CompactBlock> {
        self.blocks.first()
    }

    pub(super) fn last_block(&self) -> Option<&CompactBlock> {
        self.blocks.last()
    }

    pub(super) fn blocks(&self) -> &[CompactBlock] {
        &self.blocks
    }
}

/// Error type for the in-memory block source.
///
/// The `BlockSource` trait requires an associated `Error` type, but
/// iterating a `Vec<CompactBlock>` cannot actually fail — this is a
/// placeholder so the trait signature type-checks. All `with_blocks`
/// failures come from the caller closure via `ChainError`, not from
/// the source itself.
#[derive(Debug)]
pub(super) struct MemoryBlockSourceError(pub(super) String);

impl fmt::Display for MemoryBlockSourceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for MemoryBlockSourceError {}

impl chain::BlockSource for MemoryBlockSource {
    type Error = MemoryBlockSourceError;

    fn with_blocks<F, WalletErrT>(
        &self,
        from_height: Option<BlockHeight>,
        limit: Option<usize>,
        mut with_block: F,
    ) -> Result<(), ChainError<WalletErrT, Self::Error>>
    where
        F: FnMut(CompactBlock) -> Result<(), ChainError<WalletErrT, Self::Error>>,
    {
        let start = from_height.map(u32::from).unwrap_or(0);
        let mut count = 0usize;
        for block in &self.blocks {
            if (block.height as u32) < start {
                continue;
            }
            if let Some(lim) = limit {
                if count >= lim {
                    break;
                }
            }
            with_block(block.clone())?;
            count += 1;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_wire_size_and_boundaries() {
        let first = CompactBlock {
            height: 10,
            hash: vec![1; 32],
            prev_hash: vec![0; 32],
            ..Default::default()
        };
        let last = CompactBlock {
            height: 11,
            hash: vec![2; 32],
            prev_hash: vec![1; 32],
            ..Default::default()
        };

        let source = MemoryBlockSource::new(vec![first, last]);

        assert_eq!(source.block_count(), 2);
        assert!(source.wire_bytes() >= 128);
        assert_eq!(source.first_block().unwrap().height, 10);
        assert_eq!(source.last_block().unwrap().height, 11);
    }
}
