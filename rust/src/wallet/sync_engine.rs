use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use rand::rngs::OsRng;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use zcash_client_backend::{
    data_api::{
        WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{self, scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::{ConfirmationsPolicy, decrypt_and_store_transaction},
        TransactionDataRequest, TransactionStatus,
    },
    proto::{
        compact_formats::CompactBlock,
        service::{
            self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange,
            ChainSpec, GetSubtreeRootsArg, TxFilter,
        },
    },
};
use zcash_client_sqlite::{WalletDb, util::SystemClock};
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, Network};

/// Progress event sent to caller (Dart or Swift).
#[derive(Clone, Debug)]
pub struct SyncProgressEvent {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub is_syncing: bool,
    pub is_complete: bool,
    pub has_new_tx: bool,
}

const BATCH_SIZE_FOREGROUND: u32 = 100;
const BATCH_SIZE_BACKGROUND: u32 = 100;
const SAPLING_ACTIVATION_HEIGHT: u32 = 419200;

/// Sync-scoped elapsed time reference. Set at sync start.
static SYNC_START: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

fn elapsed() -> String {
    SYNC_START.lock().ok()
        .and_then(|g| g.map(|t| format!("{:.1}s", t.elapsed().as_secs_f64())))
        .unwrap_or_default()
}

type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

// ==================== In-memory BlockSource ====================

struct MemoryBlockSource {
    blocks: Vec<CompactBlock>,
}

#[derive(Debug)]
struct MemoryBlockSourceError(String);

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
    ) -> Result<(), chain::error::Error<WalletErrT, Self::Error>>
    where
        F: FnMut(CompactBlock) -> Result<(), chain::error::Error<WalletErrT, Self::Error>>,
    {
        let start = from_height.map(u32::from).unwrap_or(0);
        let mut count = 0usize;
        for block in &self.blocks {
            if (block.height as u32) < start {
                continue;
            }
            if let Some(lim) = limit {
                if count >= lim { break; }
            }
            with_block(block.clone())?;
            count += 1;
        }
        Ok(())
    }
}

// ==================== Main sync ====================

/// Run the full sync loop with automatic retry on failure.
/// Retries up to 3 times with exponential backoff (2s, 4s, 8s).
/// This is the unified entry point called by both Dart (FRB) and Swift (C FFI).
pub async fn run_sync_inner(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: Network,
    cancel: Arc<AtomicBool>,
    running_mode: u8,
    desired_mode: &AtomicU8,
    progress_fn: impl Fn(SyncProgressEvent) + Send + Sync,
) -> Result<(), String> {
    const MAX_RETRIES: u32 = 3;
    let mut last_err = String::new();
    *SYNC_START.lock().unwrap() = Some(std::time::Instant::now());

    for attempt in 0..=MAX_RETRIES {
        if attempt > 0 {
            let delay_secs = 1u64 << attempt; // 2, 4, 8
            log::warn!("[{}] sync: retry {}/{} in {}s (error: {})", elapsed(), attempt, MAX_RETRIES, delay_secs, last_err);
            for _ in 0..delay_secs {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
                    log::warn!("[{}] sync: cancelled/mode changed during retry wait (pending error: {})", elapsed(), last_err);
                    return Ok(());
                }
            }
        }

        match run_sync_impl(db_data_path, lightwalletd_url, network, cancel.clone(), running_mode, desired_mode, &progress_fn).await {
            Ok(()) => return Ok(()),
            Err(e) => {
                last_err = e;
                if attempt == MAX_RETRIES {
                    log::error!("[{}] sync: all {} retries exhausted", elapsed(), MAX_RETRIES);
                }
            }
        }
    }

    Err(last_err)
}

/// Inner sync implementation. Called by run_sync_inner (with retry wrapper).
async fn run_sync_impl(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: Network,
    cancel: Arc<AtomicBool>,
    running_mode: u8,
    desired_mode: &AtomicU8,
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
) -> Result<(), String> {
    let batch_size = if running_mode == 2 { BATCH_SIZE_BACKGROUND } else { BATCH_SIZE_FOREGROUND };
    log::info!("[{}] sync: starting (mode={}, batch={})", elapsed(), running_mode, batch_size);

    // 1. Connect gRPC
    let channel = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| err(&format!("Invalid URL: {e}")))?
        .tls_config(ClientTlsConfig::new().with_webpki_roots())
        .map_err(|e| err(&format!("TLS error: {e}")))?
        .connect()
        .await
        .map_err(|e| err(&format!("gRPC connect failed: {e}")))?;

    let mut client = CompactTxStreamerClient::new(channel);

    // Open DB once — reused for the entire sync
    let mut db = open_db(db_data_path, network)?;

    // 2. Get chain tip
    let tip = client
        .get_latest_block(ChainSpec::default())
        .await
        .map_err(|e| err(&format!("get_latest_block: {e}")))?
        .into_inner();
    let tip_height = BlockHeight::from_u32(tip.height as u32);
    log::info!("[{}] sync: chain tip = {}", elapsed(), tip.height);

    db.update_chain_tip(tip_height).map_err(|e| err(&format!("update_chain_tip: {e}")))?;

    // 3. Download subtree roots (incremental)
    download_subtree_roots(&mut client, &mut db).await?;

    // 4. Calculate initial scan target (before any scanning)
    let mut initial_total: u64 = {
        let ranges = db.suggest_scan_ranges().map_err(|e| err(&format!("suggest_scan_ranges: {e}")))?;
        ranges.iter()
            .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
            .map(|r| u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64)
            .sum()
    };
    let mut prev_remaining = initial_total;
    log::info!("[{}] sync: {} blocks to scan", elapsed(), initial_total);

    // 5. Sync loop
    loop {
        if cancel.load(Ordering::Relaxed) {
            log::info!("[{}] sync: cancelled", elapsed());
            return Ok(());
        }
        if desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: mode changed, exiting", elapsed());
            return Ok(());
        }

        let ranges = db.suggest_scan_ranges().map_err(|e| err(&format!("suggest_scan_ranges: {e}")))?;

        let range = match ranges.iter().find(|r| {
            r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned
        }) {
            Some(r) => r.clone(),
            None => break, // Fully synced
        };

        let start = range.block_range().start;
        let end = std::cmp::min(start + batch_size, range.block_range().end);
        log::info!("[{}] sync: scanning {}-{} (priority {:?})", elapsed(), u32::from(start), u32::from(end) - 1, range.priority());

        // Download blocks into memory
        let block_source = download_blocks(&mut client, start, end - 1).await?;

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after download", elapsed());
            return Ok(());
        }

        // Get tree state
        let from_state = if u32::from(start) <= SAPLING_ACTIVATION_HEIGHT {
            chain::ChainState::empty(start - 1, BlockHash([0u8; 32]))
        } else {
            let ts = client
                .get_tree_state(BlockId { height: u32::from(start - 1) as u64, hash: vec![] })
                .await
                .map_err(|e| err(&format!("get_tree_state: {e}")))?
                .into_inner();
            ts.to_chain_state().map_err(|e| err(&format!("parse tree state: {e}")))?
        };

        // Scan from memory
        let scan_summary = scan_cached_blocks(&network, &block_source, &mut db, start, &from_state, batch_size as usize)
            .map_err(|e| err(&format!("scan: {e}")))?;

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after scan", elapsed());
            return Ok(());
        }

        // Enhancement
        run_enhancement(&mut client, &mut db, network).await?;

        // Report progress
        let has_new_tx = scan_summary.received_sapling_note_count() > 0
            || scan_summary.spent_sapling_note_count() > 0
            || scan_summary.received_orchard_note_count() > 0
            || scan_summary.spent_orchard_note_count() > 0;
        let post_ranges = db.suggest_scan_ranges().map_err(|e| err(&format!("suggest_scan_ranges: {e}")))?;
        let remaining: u64 = post_ranges.iter()
            .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
            .map(|r| u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64)
            .sum();
        // If remaining increased (e.g. new account added mid-sync), expand initial_total
        // so progress never goes backward.
        if remaining > prev_remaining {
            let added = remaining - prev_remaining;
            initial_total += added;
            log::info!("[{}] sync: new scan ranges detected (+{}), adjusted total to {}", elapsed(), added, initial_total);
        }
        prev_remaining = remaining;
        let pct = if initial_total > 0 { 1.0 - (remaining as f64 / initial_total as f64) } else { 1.0 };
        let progress = SyncProgressEvent {
            scanned_height: u32::from(end) as u64,
            chain_tip_height: tip.height as u64,
            percentage: pct.clamp(0.0, 1.0),
            is_syncing: true,
            is_complete: false,
            has_new_tx,
        };
        log::info!("[{}] sync: {:.1}% (remaining={}/{}, scanned={})", elapsed(), pct * 100.0, remaining, initial_total, initial_total - remaining);
        progress_fn(progress);
    }

    log::info!("[{}] sync: completed", elapsed());
    // Final progress
    let final_progress = SyncProgressEvent {
        scanned_height: tip.height as u64,
        chain_tip_height: tip.height as u64,
        percentage: 1.0,
        is_syncing: false,
        is_complete: true,
        has_new_tx: false,
    };
    progress_fn(final_progress);

    Ok(())
}

// ==================== Helpers ====================

/// Log and return an error string.
fn err(msg: &str) -> String {
    log::error!("sync: {msg}");
    msg.to_string()
}

fn open_db(path: &str, network: Network) -> Result<WalletDatabase, String> {
    WalletDb::for_path(path, network, SystemClock, OsRng)
        .map_err(|e| err(&format!("DB open: {e}")))
}


async fn download_subtree_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
) -> Result<(), String> {
    let (sap_start, orch_start) = {
        let summary = db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))?;
        match summary {
            Some(s) => (s.next_sapling_subtree_index(), s.next_orchard_subtree_index()),
            None => (0, 0),
        }
    };
    log::info!("[{}] sync: subtree roots start: sapling={}, orchard={}", elapsed(), sap_start, orch_start);

    // Sapling
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: sap_start as u32,
            shielded_protocol: service::ShieldedProtocol::Sapling.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| err(&format!("sapling subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream.message().await.map_err(|e| format!("{e}"))? {
        let bytes: [u8; 32] = root.root_hash[..32].try_into().map_err(|_| "bad hash")?;
        let node = Option::from(sapling_crypto::Node::from_bytes(bytes)).ok_or("bad sapling node")?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    log::info!("[{}] sync: downloaded {} sapling subtree roots", elapsed(), roots.len());
    if !roots.is_empty() {
        db.put_sapling_subtree_roots(sap_start, roots.as_slice()).map_err(|e| err(&format!("put_sapling_subtree_roots: {e}")))?;
    }

    // Orchard
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: orch_start as u32,
            shielded_protocol: service::ShieldedProtocol::Orchard.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| err(&format!("orchard subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream.message().await.map_err(|e| format!("{e}"))? {
        let bytes: [u8; 32] = root.root_hash[..32].try_into().map_err(|_| "bad hash")?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes)).ok_or("bad orchard node")?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    log::info!("[{}] sync: downloaded {} orchard subtree roots", elapsed(), roots.len());
    if !roots.is_empty() {
        db.put_orchard_subtree_roots(orch_start, roots.as_slice()).map_err(|e| err(&format!("put_orchard_subtree_roots: {e}")))?;
    }

    log::info!("[{}] sync: subtree roots done", elapsed());
    Ok(())
}

async fn download_blocks(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
) -> Result<MemoryBlockSource, String> {
    let mut stream = client
        .get_block_range(BlockRange {
            start: Some(BlockId { height: u32::from(start) as u64, hash: vec![] }),
            end: Some(BlockId { height: u32::from(end) as u64, hash: vec![] }),
        })
        .await
        .map_err(|e| err(&format!("get_block_range: {e}")))?
        .into_inner();

    let mut blocks = Vec::new();
    while let Some(block) = stream.message().await.map_err(|e| format!("{e}"))? {
        blocks.push(block);
    }

    Ok(MemoryBlockSource { blocks })
}

async fn run_enhancement(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    network: Network,
) -> Result<(), String> {
    let mut failed_txids = std::collections::HashSet::new();

    for _ in 0..3 {
        let requests = db.transaction_data_requests().map_err(|e| err(&format!("transaction_data_requests: {e}")))?;
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

                    let hash = txid.as_ref().to_vec();

                    match client.get_transaction(TxFilter { block: None, index: 0, hash }).await {
                        Ok(response) => {
                            let raw = response.into_inner();
                            if !raw.data.is_empty() {
                                match Transaction::read(&raw.data[..], BranchId::Sapling) {
                                    Ok(tx) => {
                                        let height = if raw.height > 0 { Some(BlockHeight::from_u32(raw.height as u32)) } else { None };
                                        if let Err(e) = decrypt_and_store_transaction(&network, db, &tx, height) {
                                            log::error!("sync: decrypt_and_store_transaction failed: {e}");
                                        }
                                    }
                                    Err(e) => log::warn!("sync: Transaction::read failed for {txid_str}: {e}"),
                                }
                            }
                            if matches!(req, TransactionDataRequest::GetStatus(_)) {
                                let height = raw.height;
                                let status = if height > 0 {
                                    TransactionStatus::Mined(BlockHeight::from_u32(height as u32))
                                } else {
                                    TransactionStatus::NotInMainChain
                                };
                                if let Err(e) = db.set_transaction_status(*txid, status) {
                                    log::error!("sync: set_transaction_status failed: {e}");
                                }
                            }
                        }
                        Err(e) => {
                            log::warn!("sync: get_transaction failed for {txid_str}: {e}");
                            failed_txids.insert(txid_str);
                            if let Err(e) = db.set_transaction_status(*txid, TransactionStatus::TxidNotRecognized) {
                                log::error!("sync: set_transaction_status failed: {e}");
                            }
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
                                    match Transaction::read(&raw.data[..], BranchId::Sapling) {
                                        Ok(tx) => {
                                            let height = if raw.height > 0 { Some(BlockHeight::from_u32(raw.height as u32)) } else { None };
                                            if let Err(e) = decrypt_and_store_transaction(&network, db, &tx, height) {
                                                log::error!("sync: decrypt_and_store_transaction (addr) failed: {e}");
                                            }
                                        }
                                        Err(e) => log::warn!("sync: Transaction::read (addr) failed: {e}"),
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            log::warn!("sync: get_taddress_txids failed: {e}");
                        }
                    }
                }
            }
        }
    }
    Ok(())
}
