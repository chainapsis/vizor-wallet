use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use rand::rngs::OsRng;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use zcash_client_backend::{
    data_api::{
        Account as _, InputSource, WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::{self, ConfirmationsPolicy, decrypt_and_store_transaction},
        TransactionDataRequest, TransactionStatus,
    },
    proto::service::{
        self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange,
        ChainSpec, GetSubtreeRootsArg, TreeState, TxFilter,
    },
};
use zcash_client_sqlite::{
    FsBlockDb,
    WalletDb,
    chain::{BlockMeta, init::init_blockmeta_db},
    util::SystemClock,
};
use zcash_keys::encoding::AddressCodec as _;
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, Network, Parameters};

/// Progress event sent to caller (Dart or Swift).
#[derive(Clone, Debug)]
pub struct SyncProgressEvent {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub is_syncing: bool,
    pub is_complete: bool,
    // Balance
    pub transparent_balance: u64,
    pub sapling_balance: u64,
    pub orchard_balance: u64,
    pub total_balance: u64,
}

const BATCH_SIZE: u32 = 1000;
const SAPLING_ACTIVATION_HEIGHT: u32 = 419200;

/// Run the full sync loop. This is the unified entry point called by both Dart (FRB) and Swift (C FFI).
pub async fn run_sync_inner(
    db_data_path: &str,
    db_cache_path: &str,
    lightwalletd_url: &str,
    network: Network,
    cancel: Arc<AtomicBool>,
    progress_fn: impl Fn(SyncProgressEvent) + Send + Sync,
) -> Result<(), String> {
    // 1. Connect gRPC
    let channel = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| format!("Invalid URL: {e}"))?
        .tls_config(ClientTlsConfig::new().with_webpki_roots())
        .map_err(|e| format!("TLS error: {e}"))?
        .connect()
        .await
        .map_err(|e| format!("gRPC connect failed: {e}"))?;

    let mut client = CompactTxStreamerClient::new(channel);

    // Init block cache
    std::fs::create_dir_all(db_cache_path).map_err(|e| format!("Cache dir: {e}"))?;
    let mut db_cache = FsBlockDb::for_path(db_cache_path).map_err(|e| format!("Block cache: {e:?}"))?;
    init_blockmeta_db(&mut db_cache).map_err(|e| format!("Init cache: {e}"))?;

    // 2. Get chain tip
    let tip = client
        .get_latest_block(ChainSpec::default())
        .await
        .map_err(|e| format!("get_latest_block: {e}"))?
        .into_inner();
    let tip_height = BlockHeight::from_u32(tip.height as u32);

    {
        let mut db_data = open_db(db_data_path, network)?;
        db_data.update_chain_tip(tip_height).map_err(|e| format!("update_chain_tip: {e}"))?;
    }

    // 3. Download subtree roots (incremental)
    download_subtree_roots(&mut client, db_data_path, network).await?;

    // 4. Sync loop
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Ok(());
        }

        let ranges = {
            let db = open_db(db_data_path, network)?;
            db.suggest_scan_ranges().map_err(|e| format!("{e}"))?
        };

        let range = match ranges.iter().find(|r| {
            r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned
        }) {
            Some(r) => r.clone(),
            None => break, // Fully synced
        };

        let start = range.block_range().start;
        let end = std::cmp::min(start + BATCH_SIZE, range.block_range().end);

        // Download blocks
        download_blocks(&mut client, &db_cache, db_cache_path, start, end - 1).await?;

        // Get tree state
        let from_state = if u32::from(start) <= SAPLING_ACTIVATION_HEIGHT {
            zcash_client_backend::data_api::chain::ChainState::empty(
                start - 1, BlockHash([0u8; 32]),
            )
        } else {
            let ts = client
                .get_tree_state(BlockId { height: u32::from(start - 1) as u64, hash: vec![] })
                .await
                .map_err(|e| format!("get_tree_state: {e}"))?
                .into_inner();
            ts.to_chain_state().map_err(|e| format!("parse tree state: {e}"))?
        };

        // Scan
        {
            let mut db_data = open_db(db_data_path, network)?;
            scan_cached_blocks(&network, &db_cache, &mut db_data, start, &from_state, BATCH_SIZE as usize)
                .map_err(|e| format!("scan: {e}"))?;
        }

        // Enhancement
        run_enhancement(&mut client, db_data_path, network).await?;

        // Report progress
        let progress = get_progress(db_data_path, network)?;
        progress_fn(progress);
    }

    // Final progress
    let mut progress = get_progress(db_data_path, network)?;
    progress.is_complete = true;
    progress.is_syncing = false;
    progress_fn(progress);

    Ok(())
}

// ==================== Helpers ====================

fn open_db(path: &str, network: Network) -> Result<WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>, String> {
    WalletDb::for_path(path, network, SystemClock, OsRng)
        .map_err(|e| format!("DB open: {e}"))
}

fn get_progress(db_path: &str, network: Network) -> Result<SyncProgressEvent, String> {
    let db = open_db(db_path, network)?;
    let summary = db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))?;
    match summary {
        Some(s) => {
            let scanned = u32::from(s.fully_scanned_height()) as u64;
            let tip = u32::from(s.chain_tip_height()) as u64;
            let pct = if tip > 0 { scanned as f64 / tip as f64 } else { 0.0 };
            let (mut t, mut sa, mut or) = (0u64, 0u64, 0u64);
            for (_, b) in s.account_balances() {
                t += u64::from(b.unshielded_balance().spendable_value());
                sa += u64::from(b.sapling_balance().spendable_value());
                or += u64::from(b.orchard_balance().spendable_value());
            }
            Ok(SyncProgressEvent {
                scanned_height: scanned, chain_tip_height: tip, percentage: pct,
                is_syncing: scanned < tip, is_complete: false,
                transparent_balance: t, sapling_balance: sa, orchard_balance: or,
                total_balance: t + sa + or,
            })
        }
        None => Ok(SyncProgressEvent {
            scanned_height: 0, chain_tip_height: 0, percentage: 0.0,
            is_syncing: false, is_complete: false,
            transparent_balance: 0, sapling_balance: 0, orchard_balance: 0, total_balance: 0,
        }),
    }
}

async fn download_subtree_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    network: Network,
) -> Result<(), String> {
    let (sap_start, orch_start) = {
        let db = open_db(db_path, network)?;
        let summary = db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))?;
        match summary {
            Some(s) => (s.next_sapling_subtree_index(), s.next_orchard_subtree_index()),
            None => (0, 0),
        }
    };

    // Sapling
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: sap_start as u32,
            shielded_protocol: service::ShieldedProtocol::Sapling.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| format!("sapling subtree roots: {e}"))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream.message().await.map_err(|e| format!("{e}"))? {
        let bytes: [u8; 32] = root.root_hash[..32].try_into().map_err(|_| "bad hash")?;
        let node = Option::from(sapling_crypto::Node::from_bytes(bytes)).ok_or("bad sapling node")?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    if !roots.is_empty() {
        let mut db = open_db(db_path, network)?;
        db.put_sapling_subtree_roots(sap_start, roots.as_slice()).map_err(|e| format!("{e}"))?;
    }

    // Orchard
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: orch_start as u32,
            shielded_protocol: service::ShieldedProtocol::Orchard.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| format!("orchard subtree roots: {e}"))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream.message().await.map_err(|e| format!("{e}"))? {
        let bytes: [u8; 32] = root.root_hash[..32].try_into().map_err(|_| "bad hash")?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes)).ok_or("bad orchard node")?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    if !roots.is_empty() {
        let mut db = open_db(db_path, network)?;
        db.put_orchard_subtree_roots(orch_start, roots.as_slice()).map_err(|e| format!("{e}"))?;
    }

    Ok(())
}

async fn download_blocks(
    client: &mut CompactTxStreamerClient<Channel>,
    db_cache: &FsBlockDb,
    db_cache_path: &str,
    start: BlockHeight,
    end: BlockHeight,
) -> Result<(), String> {
    use tonic_prost::prost::Message;

    let mut stream = client
        .get_block_range(BlockRange {
            start: Some(BlockId { height: u32::from(start) as u64, hash: vec![] }),
            end: Some(BlockId { height: u32::from(end) as u64, hash: vec![] }),
        })
        .await
        .map_err(|e| format!("get_block_range: {e}"))?
        .into_inner();

    let blocks_dir_path = format!("{db_cache_path}/blocks");
    std::fs::create_dir_all(&blocks_dir_path).ok();

    let mut metas = Vec::new();
    while let Some(block) = stream.message().await.map_err(|e| format!("{e}"))? {
        let height = BlockHeight::from_u32(block.height as u32);
        let block_hash: [u8; 32] = block.hash.clone().try_into().unwrap_or([0u8; 32]);

        // Write block file (encode using tonic-prost's prost)
        let data = block.encode_to_vec();
        let meta = BlockMeta {
            height,
            block_hash: BlockHash(block_hash),
            block_time: block.time,
            sapling_outputs_count: block.vtx.iter().map(|tx| tx.outputs.len() as u32).sum(),
            orchard_actions_count: block.vtx.iter().map(|tx| tx.actions.len() as u32).sum(),
        };

        let block_path = meta.block_file_path(&blocks_dir_path);
        std::fs::write(&block_path, &data).map_err(|e| format!("write block: {e}"))?;
        metas.push(meta);
    }

    if !metas.is_empty() {
        db_cache.write_block_metadata(&metas).map_err(|e| format!("write metadata: {e:?}"))?;
    }
    Ok(())
}

async fn run_enhancement(
    client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    network: Network,
) -> Result<(), String> {
    let mut failed_txids = std::collections::HashSet::new();

    for _ in 0..3 {
        let requests = {
            let db = open_db(db_path, network)?;
            db.transaction_data_requests().map_err(|e| format!("{e}"))?
        };
        if requests.is_empty() { break; }

        let actionable = requests.iter().any(|r| match r {
            TransactionDataRequest::Enhancement(_) | TransactionDataRequest::GetStatus(_) => true,
            TransactionDataRequest::TransactionsInvolvingAddress(req) => req.block_range_end().is_some(),
        });
        if !actionable { break; }

        for req in &requests {
            match req {
                TransactionDataRequest::GetStatus(txid) | TransactionDataRequest::Enhancement(txid) => {
                    let txid_str = format!("{txid}");
                    if failed_txids.contains(&txid_str) { continue; }

                    // txid bytes: Display is byte-reversed, TxFilter needs original order
                    let mut hash = txid.as_ref().to_vec();
                    // TxId::as_ref() returns original bytes, no reverse needed for TxFilter

                    match client.get_transaction(TxFilter { block: None, index: 0, hash: hash.clone() }).await {
                        Ok(response) => {
                            let raw = response.into_inner();
                            if !raw.data.is_empty() {
                                if let Ok(tx) = Transaction::read(&raw.data[..], BranchId::Sapling) {
                                    let height = if raw.height > 0 { Some(BlockHeight::from_u32(raw.height as u32)) } else { None };
                                    let mut db = open_db(db_path, network)?;
                                    let _ = decrypt_and_store_transaction(&network, &mut db, &tx, height);
                                }
                            }
                            if matches!(req, TransactionDataRequest::GetStatus(_)) {
                                let height = raw.height;
                                let mut db = open_db(db_path, network)?;
                                let status = if height > 0 {
                                    TransactionStatus::Mined(BlockHeight::from_u32(height as u32))
                                } else {
                                    TransactionStatus::NotInMainChain
                                };
                                let _ = db.set_transaction_status(*txid, status);
                            }
                        }
                        Err(_) => {
                            failed_txids.insert(txid_str);
                            let mut db = open_db(db_path, network)?;
                            let _ = db.set_transaction_status(*txid, TransactionStatus::TxidNotRecognized);
                        }
                    }
                }
                TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                    let end_height = match req.block_range_end() {
                        Some(h) => h,
                        None => continue,
                    };
                    let addr_str = zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
                    let start = u32::from(req.block_range_start()) as u64;
                    let end = u32::from(end_height) as u64;

                    match client.get_taddress_txids(service::TransparentAddressBlockFilter {
                        address: addr_str,
                        range: Some(BlockRange {
                            start: Some(BlockId { height: start, hash: vec![] }),
                            end: Some(BlockId { height: end.saturating_sub(1), hash: vec![] }),
                        }),
                    }).await {
                        Ok(response) => {
                            let mut stream = response.into_inner();
                            while let Ok(Some(raw)) = stream.message().await {
                                if !raw.data.is_empty() {
                                    if let Ok(tx) = Transaction::read(&raw.data[..], BranchId::Sapling) {
                                        let height = if raw.height > 0 { Some(BlockHeight::from_u32(raw.height as u32)) } else { None };
                                        let mut db = open_db(db_path, network)?;
                                        let _ = decrypt_and_store_transaction(&network, &mut db, &tx, height);
                                    }
                                }
                            }
                        }
                        Err(_) => {} // Skip failed address queries
                    }
                }
            }
        }
    }
    Ok(())
}
