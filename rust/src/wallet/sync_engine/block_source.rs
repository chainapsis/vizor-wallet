//! In-memory [`BlockSource`] used by the sync loop.
//!
//! `scan_cached_blocks` expects a `BlockSource`-shaped input so it can
//! iterate compact blocks one at a time. Historically librustzcash
//! wallets pointed that input at an on-disk SQLite cache
//! (`FsBlockDb`). We deliberately skip the file-cache step and keep
//! compact blocks in memory: the batch being scanned and the few
//! downloaded ahead of it.
//!
//!   1. Batches are sized by a compact-block byte budget where the
//!      compiled mainnet estimate reaches, and by a smaller block cap past
//!      it, so the memory footprint stays bounded. Blocks stay encoded
//!      until the scan reads them: decoded, every output field is its own
//!      small allocation, and a batch takes about 1.8 times its wire size.
//!   2. Avoiding the cache DB means one less file format to keep in
//!      sync with librustzcash migrations and one less thing to clear
//!      on reorg / rewind.
//!   3. The sync loop was already downloading the blocks directly from
//!      lightwalletd; tee'ing them through a file would just slow the
//!      scan down.
//!
//! The type is visible only to the `sync_engine` module tree
//! (`pub(super)`); the download fills one with
//! [`MemoryBlockSource::with_capacity`] and [`MemoryBlockSource::push`],
//! and the scan reads it straight from there.

use std::collections::BTreeSet;
use std::fmt;

use prost::Message;
use zcash_client_backend::{
    data_api::chain::{self, error::Error as ChainError},
    proto::compact_formats::CompactBlock,
};
use zcash_protocol::consensus::BlockHeight;

/// Holds a single batch of compact blocks in memory for one
/// `scan_cached_blocks` call, each as its protobuf encoding. A block is
/// decoded every time it is read; `scan_cached_blocks` reads each twice.
pub(super) struct MemoryBlockSource {
    blocks: Vec<EncodedBlock>,
    /// Every block's transaction ids, for the enhancement queue.
    txids: Vec<Vec<u8>>,
}

struct EncodedBlock {
    height: u64,
    has_orchard_actions: bool,
    bytes: Vec<u8>,
}

impl EncodedBlock {
    fn decode(&self) -> Result<CompactBlock, MemoryBlockSourceError> {
        CompactBlock::decode(self.bytes.as_slice())
            .map_err(|e| MemoryBlockSourceError(format!("decode block {}: {e}", self.height)))
    }
}

impl MemoryBlockSource {
    pub(super) fn block_at(&self, height: BlockHeight) -> Option<CompactBlock> {
        self.blocks
            .iter()
            .find(|block| block.height == u64::from(u32::from(height)))
            .and_then(|block| block.decode().ok())
    }

    #[cfg(test)]
    pub(super) fn new(blocks: Vec<CompactBlock>) -> Self {
        let mut source = Self::with_capacity(blocks.len());
        for block in blocks {
            source.push(block);
        }
        source
    }

    pub(super) fn with_capacity(blocks: usize) -> Self {
        Self {
            blocks: Vec::with_capacity(blocks),
            txids: Vec::new(),
        }
    }

    /// Appends `block`, keeping only its encoding and what the accessors
    /// below read without decoding.
    pub(super) fn push(&mut self, block: CompactBlock) {
        self.txids
            .extend(block.vtx.iter().map(|tx| tx.txid.clone()));
        self.blocks.push(EncodedBlock {
            height: block.height,
            has_orchard_actions: block.vtx.iter().any(|tx| !tx.actions.is_empty()),
            bytes: block.encode_to_vec(),
        });
    }

    fn first_block(&self) -> Option<CompactBlock> {
        self.blocks.first().and_then(|block| block.decode().ok())
    }

    pub(super) fn height_range(&self) -> Option<std::ops::RangeInclusive<u64>> {
        Some(self.blocks.first()?.height..=self.blocks.last()?.height)
    }

    /// The encoded size of the blocks, as downloaded.
    pub(super) fn encoded_bytes(&self) -> usize {
        self.blocks.iter().map(|block| block.bytes.len()).sum()
    }

    pub(super) fn transaction_hashes(&self) -> impl Iterator<Item = &[u8]> {
        self.txids.iter().map(Vec::as_slice)
    }

    /// Returns whether this source contains exactly the requested half-open
    /// range in ascending, contiguous order.
    pub(super) fn contains_exact_range(&self, start: u32, end: u32) -> bool {
        let expected_len = end.saturating_sub(start) as usize;
        self.blocks.len() == expected_len
            && self
                .blocks
                .iter()
                .enumerate()
                .all(|(offset, block)| block.height == u64::from(start) + offset as u64)
    }

    pub(super) fn first_block_prev_hash(&self) -> Option<Vec<u8>> {
        self.first_block().map(|block| block.prev_hash)
    }

    /// Whether the preceding tree state and first compact block have matching
    /// identities and satisfy the commitment-count invariant that `put_blocks`
    /// enforces. The zero hash identifies the synthetic pre-activation state.
    pub(super) fn starts_after(&self, from_state: &chain::ChainState) -> bool {
        self.first_block().is_some_and(|block| {
            let metadata = block.chain_metadata.unwrap_or_default();
            let sapling_commitments: usize = block.vtx.iter().map(|tx| tx.outputs.len()).sum();
            let orchard_commitments: usize = block.vtx.iter().map(|tx| tx.actions.len()).sum();
            let ironwood_commitments: usize =
                block.vtx.iter().map(|tx| tx.ironwood_actions.len()).sum();
            let from_hash = from_state.block_hash().0;
            let predecessor_matches =
                from_hash == [0u8; 32] || block.prev_hash.as_slice() == from_hash;

            predecessor_matches
                && from_state.final_sapling_tree().tree_size() + sapling_commitments as u64
                    == metadata.sapling_commitment_tree_size as u64
                && from_state.final_orchard_tree().tree_size() + orchard_commitments as u64
                    == metadata.orchard_commitment_tree_size as u64
                && from_state.final_ironwood_tree().tree_size() + ironwood_commitments as u64
                    == metadata.ironwood_commitment_tree_size as u64
        })
    }

    /// Returns the block heights that scanning will add as Orchard subtree
    /// checkpoints before Orchard checkpoint pruning runs.
    pub(super) fn orchard_checkpoint_heights(&self) -> BTreeSet<u32> {
        self.blocks
            .iter()
            .filter(|block| block.has_orchard_actions)
            .filter_map(|block| u32::try_from(block.height).ok())
            .collect()
    }
}

/// Error type for the in-memory block source.
///
/// Decoding a block this source encoded fails only if its memory is
/// corrupted; otherwise iterating cannot fail. All other `with_blocks`
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
            with_block(block.decode().map_err(ChainError::BlockSource)?)?;
            count += 1;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::proto::compact_formats::{CompactOrchardAction, CompactTx};
    use zcash_primitives::block::BlockHash;

    #[test]
    fn blocks_read_back_as_they_were_pushed() {
        let blocks: Vec<CompactBlock> = (10..13)
            .map(|height| CompactBlock {
                height,
                prev_hash: vec![height as u8; 32],
                vtx: vec![CompactTx {
                    txid: vec![height as u8 + 100; 32],
                    actions: vec![CompactOrchardAction {
                        cmx: vec![7; 32],
                        ciphertext: vec![9; 52],
                        ..Default::default()
                    }],
                    ..Default::default()
                }],
                ..Default::default()
            })
            .collect();
        let source = MemoryBlockSource::new(blocks.clone());

        let mut read = Vec::new();
        chain::BlockSource::with_blocks::<_, ()>(&source, None, None, |block| {
            read.push(block);
            Ok(())
        })
        .unwrap();
        assert_eq!(read, blocks);
        assert_eq!(
            source.block_at(BlockHeight::from_u32(11)),
            Some(blocks[1].clone())
        );
        assert_eq!(source.block_at(BlockHeight::from_u32(13)), None);
        assert_eq!(
            source.transaction_hashes().collect::<Vec<_>>(),
            vec![&[110u8; 32][..], &[111u8; 32][..], &[112u8; 32][..]],
        );
        assert_eq!(source.first_block_prev_hash(), Some(vec![10u8; 32]));
    }

    #[test]
    fn orchard_checkpoint_heights_exclude_later_cross_pool_checkpoints() {
        let block = |height, tx: CompactTx| CompactBlock {
            height,
            vtx: vec![tx],
            ..Default::default()
        };
        let sapling = CompactTx {
            outputs: vec![Default::default()],
            ..Default::default()
        };
        let orchard = CompactTx {
            actions: vec![CompactOrchardAction::default()],
            ..Default::default()
        };
        let ironwood = CompactTx {
            ironwood_actions: vec![CompactOrchardAction::default()],
            ..Default::default()
        };

        let source = MemoryBlockSource::new(vec![
            block(10, CompactTx::default()),
            block(11, sapling),
            block(12, orchard),
            block(13, ironwood),
        ]);

        assert_eq!(source.orchard_checkpoint_heights(), BTreeSet::from([12]));
    }

    #[test]
    fn exact_range_requires_contiguous_order_and_no_extra_blocks() {
        let blocks = |heights: &[u64]| {
            MemoryBlockSource::new(
                heights
                    .iter()
                    .map(|height| CompactBlock {
                        height: *height,
                        ..Default::default()
                    })
                    .collect(),
            )
        };

        assert!(blocks(&[10, 11, 12]).contains_exact_range(10, 13));
        assert!(!blocks(&[10, 12]).contains_exact_range(10, 13));
        assert!(!blocks(&[10, 11, 12, 13]).contains_exact_range(10, 13));
        assert!(!blocks(&[11, 10, 12]).contains_exact_range(10, 13));
    }

    #[test]
    fn first_block_must_extend_every_commitment_tree() {
        let from_state = chain::ChainState::empty(BlockHeight::from_u32(9), BlockHash([0u8; 32]));
        let mut block = CompactBlock {
            height: 10,
            prev_hash: vec![0u8; 32],
            chain_metadata: Some(Default::default()),
            vtx: vec![CompactTx {
                outputs: vec![Default::default()],
                actions: vec![CompactOrchardAction::default()],
                ironwood_actions: vec![CompactOrchardAction::default()],
                ..Default::default()
            }],
            ..Default::default()
        };
        let metadata = block.chain_metadata.as_mut().unwrap();
        metadata.sapling_commitment_tree_size = 1;
        metadata.orchard_commitment_tree_size = 1;
        metadata.ironwood_commitment_tree_size = 1;

        assert!(MemoryBlockSource::new(vec![block.clone()]).starts_after(&from_state));

        let identified_state =
            chain::ChainState::empty(BlockHeight::from_u32(9), BlockHash([1u8; 32]));
        assert!(!MemoryBlockSource::new(vec![block.clone()]).starts_after(&identified_state));
        block.prev_hash = vec![1u8; 32];
        assert!(MemoryBlockSource::new(vec![block.clone()]).starts_after(&identified_state));

        block
            .chain_metadata
            .as_mut()
            .unwrap()
            .orchard_commitment_tree_size = 0;
        assert!(!MemoryBlockSource::new(vec![block]).starts_after(&from_state));
        assert!(!MemoryBlockSource::new(vec![]).starts_after(&from_state));
    }
}
