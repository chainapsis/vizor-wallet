use std::panic;

use crate::wallet::{keys, sync as wallet_sync};

pub struct SyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub is_syncing: bool,
}

pub struct WalletBalance {
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
    pub total: u64,
}

pub struct ScanRangeInfo {
    pub start: u64,
    pub end: u64,
    pub priority: u8,
}

pub struct ScanResult {
    pub blocks_scanned: u64,
}

pub struct SubtreeRoot {
    pub completing_block_height: u64,
    pub root_hash: Vec<u8>,
}

pub struct BlockMetaInfo {
    pub height: u64,
    pub hash: Vec<u8>,
    pub time: u32,
    pub sapling_outputs_count: u32,
    pub orchard_actions_count: u32,
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

pub fn update_chain_tip(db_path: String, network: String, height: u64) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::update_chain_tip(&db_path, network, height)
    })
}

pub fn put_subtree_roots(
    db_path: String,
    network: String,
    sapling_roots: Vec<SubtreeRoot>,
    orchard_roots: Vec<SubtreeRoot>,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;

        let sapling: Vec<(u64, Vec<u8>)> = sapling_roots
            .into_iter()
            .map(|r| (r.completing_block_height, r.root_hash))
            .collect();
        wallet_sync::put_sapling_subtree_roots(&db_path, network, &sapling)?;

        let orchard: Vec<(u64, Vec<u8>)> = orchard_roots
            .into_iter()
            .map(|r| (r.completing_block_height, r.root_hash))
            .collect();
        wallet_sync::put_orchard_subtree_roots(&db_path, network, &orchard)?;

        Ok(())
    })
}

pub fn suggest_scan_ranges(
    db_path: String,
    network: String,
) -> Result<Vec<ScanRangeInfo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let ranges = wallet_sync::suggest_scan_ranges(&db_path, network)?;
        Ok(ranges
            .into_iter()
            .map(|r| ScanRangeInfo {
                start: r.start,
                end: r.end,
                priority: r.priority,
            })
            .collect())
    })
}

pub fn write_block_metadata(
    cache_path: String,
    blocks: Vec<BlockMetaInfo>,
) -> Result<(), String> {
    catch(|| {
        let tuples: Vec<(u64, Vec<u8>, u32, u32, u32)> = blocks
            .into_iter()
            .map(|b| {
                (
                    b.height,
                    b.hash,
                    b.time,
                    b.sapling_outputs_count,
                    b.orchard_actions_count,
                )
            })
            .collect();
        wallet_sync::write_block_metadata(&cache_path, &tuples)
    })
}

/// Scan cached blocks with trial decryption.
/// TreeState fields passed individually. Empty hash = Sapling activation (empty tree state).
pub fn scan_blocks(
    db_path: String,
    cache_path: String,
    network: String,
    from_height: u64,
    tree_state_network: String,
    tree_state_height: u64,
    tree_state_hash: String,
    tree_state_time: u32,
    tree_state_sapling_tree: String,
    tree_state_orchard_tree: String,
    limit: u64,
) -> Result<ScanResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let scanned = wallet_sync::scan_blocks(
            &db_path,
            &cache_path,
            network,
            from_height,
            &tree_state_network,
            tree_state_height,
            &tree_state_hash,
            tree_state_time,
            &tree_state_sapling_tree,
            &tree_state_orchard_tree,
            limit,
        )?;
        Ok(ScanResult {
            blocks_scanned: scanned,
        })
    })
}

pub fn get_sync_status(db_path: String, network: String) -> Result<SyncProgress, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let p = wallet_sync::get_sync_progress(&db_path, network)?;
        Ok(SyncProgress {
            scanned_height: p.scanned_height,
            chain_tip_height: p.chain_tip_height,
            is_syncing: p.is_syncing,
        })
    })
}

pub fn get_balance(db_path: String, network: String) -> Result<WalletBalance, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let b = wallet_sync::get_wallet_balance(&db_path, network)?;
        Ok(WalletBalance {
            transparent: b.transparent,
            sapling: b.sapling,
            orchard: b.orchard,
            total: b.transparent + b.sapling + b.orchard,
        })
    })
}

/// Get the blocks directory path where Dart should write compact block files.
#[flutter_rust_bridge::frb(sync)]
pub fn get_blocks_dir(cache_path: String) -> String {
    wallet_sync::get_blocks_dir(&cache_path)
}
