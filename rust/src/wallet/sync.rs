use rand::rngs::OsRng;
use zcash_client_backend::{
    data_api::{
        WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::ConfirmationsPolicy,
    },
    proto::service::TreeState,
};
use zcash_client_sqlite::{
    FsBlockDb,
    WalletDb,
    chain::{BlockMeta, init::init_blockmeta_db},
    util::SystemClock,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, Network};

type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

fn open_wallet_db(db_path: &str, network: Network) -> Result<WalletDatabase, String> {
    WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))
}

fn open_block_cache(cache_path: &str) -> Result<FsBlockDb, String> {
    std::fs::create_dir_all(cache_path)
        .map_err(|e| format!("Failed to create cache dir: {e}"))?;
    let mut db_cache = FsBlockDb::for_path(cache_path)
        .map_err(|e| format!("Failed to open block cache: {e:?}"))?;
    init_blockmeta_db(&mut db_cache)
        .map_err(|e| format!("Failed to init block cache: {e}"))?;
    Ok(db_cache)
}

/// Update chain tip height in wallet DB.
pub fn update_chain_tip(db_path: &str, network: Network, height: u64) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let tip = BlockHeight::from_u32(height as u32);
    db.update_chain_tip(tip)
        .map_err(|e| format!("Failed to update chain tip: {e}"))
}

/// Store Sapling subtree roots. Each root is (completing_block_height, root_hash_32bytes).
pub fn put_sapling_subtree_roots(
    db_path: &str,
    network: Network,
    roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<CommitmentTreeRoot<sapling_crypto::Node>> = roots
        .iter()
        .map(|(height, hash_bytes)| {
            let bytes: [u8; 32] = hash_bytes[..32]
                .try_into()
                .map_err(|_| "Sapling root hash must be 32 bytes".to_string())?;
            let node: sapling_crypto::Node =
                Option::from(sapling_crypto::Node::from_bytes(bytes))
                    .ok_or("Invalid Sapling root hash")?;
            Ok(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(*height as u32),
                node,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;

    if !parsed.is_empty() {
        db.put_sapling_subtree_roots(0, parsed.as_slice())
            .map_err(|e| format!("Failed to store Sapling roots: {e}"))?;
    }
    Ok(())
}

/// Store Orchard subtree roots. Each root is (completing_block_height, root_hash_32bytes).
pub fn put_orchard_subtree_roots(
    db_path: &str,
    network: Network,
    roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<CommitmentTreeRoot<orchard::tree::MerkleHashOrchard>> = roots
        .iter()
        .map(|(height, hash_bytes)| {
            let bytes: [u8; 32] = hash_bytes[..32]
                .try_into()
                .map_err(|_| "Orchard root hash must be 32 bytes".to_string())?;
            let node: orchard::tree::MerkleHashOrchard =
                Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes))
                    .ok_or("Invalid Orchard root hash")?;
            Ok(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(*height as u32),
                node,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;

    if !parsed.is_empty() {
        db.put_orchard_subtree_roots(0, parsed.as_slice())
            .map_err(|e| format!("Failed to store Orchard roots: {e}"))?;
    }
    Ok(())
}

/// Scan range info returned to Dart.
pub(crate) struct ScanRangeInfo {
    pub start: u64,
    pub end: u64,
    pub priority: u8,
}

/// Get suggested scan ranges from the wallet DB.
pub fn suggest_scan_ranges(db_path: &str, network: Network) -> Result<Vec<ScanRangeInfo>, String> {
    let db = open_wallet_db(db_path, network)?;
    let ranges = db
        .suggest_scan_ranges()
        .map_err(|e| format!("Failed to get scan ranges: {e}"))?;

    Ok(ranges
        .into_iter()
        .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
        .map(|r| ScanRangeInfo {
            start: u32::from(r.block_range().start) as u64,
            end: u32::from(r.block_range().end) as u64,
            priority: match r.priority() {
                ScanPriority::Ignored => 0,
                ScanPriority::Scanned => 1,
                ScanPriority::Historic => 2,
                ScanPriority::OpenAdjacent => 3,
                ScanPriority::FoundNote => 4,
                ScanPriority::ChainTip => 5,
                ScanPriority::Verify => 6,
            },
        })
        .collect())
}

/// Register block metadata after Dart writes block files to the cache directory.
/// blocks: Vec of (height, hash_32bytes, time, sapling_outputs_count, orchard_actions_count)
pub fn write_block_metadata(
    cache_path: &str,
    blocks: &[(u64, Vec<u8>, u32, u32, u32)],
) -> Result<(), String> {
    let db_cache = open_block_cache(cache_path)?;

    let metas: Vec<BlockMeta> = blocks
        .iter()
        .map(|(height, hash, time, sapling_count, orchard_count)| {
            let mut hash_arr = [0u8; 32];
            let len = std::cmp::min(hash.len(), 32);
            hash_arr[..len].copy_from_slice(&hash[..len]);
            BlockMeta {
                height: BlockHeight::from_u32(*height as u32),
                block_hash: BlockHash(hash_arr),
                block_time: *time,
                sapling_outputs_count: *sapling_count,
                orchard_actions_count: *orchard_count,
            }
        })
        .collect();

    db_cache
        .write_block_metadata(&metas)
        .map_err(|e| format!("Failed to write block metadata: {e:?}"))
}

/// Scan cached blocks using trial decryption.
/// Dart passes the TreeState fields individually (from lightwalletd gRPC response).
pub fn scan_blocks(
    db_path: &str,
    cache_path: &str,
    network: Network,
    from_height: u64,
    tree_state_network: &str,
    tree_state_height: u64,
    tree_state_hash: &str,
    tree_state_time: u32,
    tree_state_sapling_tree: &str,
    tree_state_orchard_tree: &str,
    limit: u64,
) -> Result<u64, String> {
    let db_cache = open_block_cache(cache_path)?;
    let mut db_data = open_wallet_db(db_path, network)?;

    let from_state = if tree_state_hash.is_empty() {
        // Empty tree state — used at Sapling activation height where no prior state exists
        let prior_height = BlockHeight::from_u32(tree_state_height as u32);
        zcash_client_backend::data_api::chain::ChainState::empty(
            prior_height,
            BlockHash([0u8; 32]),
        )
    } else {
        let tree_state = TreeState {
            network: tree_state_network.to_string(),
            height: tree_state_height,
            hash: tree_state_hash.to_string(),
            time: tree_state_time,
            sapling_tree: tree_state_sapling_tree.to_string(),
            orchard_tree: tree_state_orchard_tree.to_string(),
        };
        tree_state
            .to_chain_state()
            .map_err(|e| format!("Failed to parse chain state: {e}"))?
    };

    let height = BlockHeight::from_u32(from_height as u32);

    let scan_result = scan_cached_blocks(
        &network,
        &db_cache,
        &mut db_data,
        height,
        &from_state,
        limit as usize,
    )
    .map_err(|e| format!("Failed to scan blocks: {e}"))?;

    let scanned = u32::from(scan_result.scanned_range().end)
        - u32::from(scan_result.scanned_range().start);
    Ok(scanned as u64)
}

/// Get the expected block file path.
/// Dart writes downloaded compact blocks to this path before calling write_block_metadata.
pub fn get_blocks_dir(cache_path: &str) -> String {
    format!("{cache_path}/blocks")
}

/// Progress information.
pub(crate) struct SyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub is_syncing: bool,
}

/// Get sync progress from the wallet database.
pub fn get_sync_progress(db_path: &str, network: Network) -> Result<SyncProgress, String> {
    let db = open_wallet_db(db_path, network)?;
    let summary = db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("Failed to get wallet summary: {e}"))?;

    match summary {
        Some(s) => Ok(SyncProgress {
            scanned_height: u32::from(s.fully_scanned_height()) as u64,
            chain_tip_height: u32::from(s.chain_tip_height()) as u64,
            is_syncing: s.fully_scanned_height() < s.chain_tip_height(),
        }),
        None => Ok(SyncProgress {
            scanned_height: 0,
            chain_tip_height: 0,
            is_syncing: false,
        }),
    }
}

/// Wallet balance in zatoshi.
pub(crate) struct WalletBalance {
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
}

/// Get wallet balance.
pub fn get_wallet_balance(db_path: &str, network: Network) -> Result<WalletBalance, String> {
    let db = open_wallet_db(db_path, network)?;
    let summary = db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("Failed to get wallet summary: {e}"))?;

    match summary {
        Some(s) => {
            let mut sapling: u64 = 0;
            let mut orchard: u64 = 0;
            let mut transparent: u64 = 0;
            for (_account_id, balance) in s.account_balances() {
                sapling += u64::from(balance.sapling_balance().spendable_value());
                orchard += u64::from(balance.orchard_balance().spendable_value());
                transparent += u64::from(balance.unshielded_balance().spendable_value());
            }
            Ok(WalletBalance { transparent, sapling, orchard })
        }
        None => Ok(WalletBalance { transparent: 0, sapling: 0, orchard: 0 }),
    }
}
