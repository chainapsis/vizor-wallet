use std::panic;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;
use crate::wallet::{keys, sync as wallet_sync, sync_engine};

// ======================== Sync Mode ========================
// 0 = None, 1 = Foreground, 2 = Background
pub(crate) static DESIRED_SYNC_MODE: AtomicU8 = AtomicU8::new(0);

/// Set the desired sync mode. 0=none, 1=foreground, 2=background.
/// The running sync loop checks this each batch and exits if mismatched.
#[frb(sync)]
pub fn set_sync_mode(mode: u8) {
    DESIRED_SYNC_MODE.store(mode, Ordering::SeqCst);
}

/// Get the current desired sync mode.
#[frb(sync)]
pub fn get_sync_mode() -> u8 {
    DESIRED_SYNC_MODE.load(Ordering::SeqCst)
}

// ======================== Full Sync ========================

/// Progress event streamed to Dart during sync.
pub struct ApiSyncProgressEvent {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub is_syncing: bool,
    pub is_complete: bool,
    pub has_new_tx: bool,
}

/// Start a full sync. Streams progress events to Dart via StreamSink.
/// mode: 1=foreground, 2=background. Sync exits if desired mode changes.
pub fn start_full_sync(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    mode: u8,
    sink: StreamSink<ApiSyncProgressEvent>,
) -> Result<(), String> {
    if SYNC_RUNNING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
        return Err("Sync already running".into());
    }

    DESIRED_SYNC_MODE.store(mode, Ordering::SeqCst);

    let result = catch(|| {
        let network = keys::parse_network(&network)?;
        let cancel = SYNC_CANCEL.clone();
        cancel.store(false, Ordering::Relaxed);

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            sync_engine::run_sync_inner(
                &db_path,
                &lightwalletd_url,
                network,
                cancel,
                mode,
                &DESIRED_SYNC_MODE,
                |progress| {
                    if sink.add(ApiSyncProgressEvent {
                        scanned_height: progress.scanned_height,
                        chain_tip_height: progress.chain_tip_height,
                        percentage: progress.percentage,
                        is_syncing: progress.is_syncing,
                        is_complete: progress.is_complete,
                        has_new_tx: progress.has_new_tx,
                    }).is_err() {
                        log::warn!("sync: StreamSink closed, progress not delivered");
                    }
                },
            )
            .await
        })
    });

    SYNC_RUNNING.store(false, Ordering::SeqCst);
    result
}

/// Cancel a running full sync.
#[frb(sync)]
pub fn cancel_full_sync() {
    SYNC_CANCEL.store(true, Ordering::Relaxed);
}

/// Check if a sync is currently running.
#[frb(sync)]
pub fn is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}

pub(crate) static SYNC_CANCEL: std::sync::LazyLock<Arc<AtomicBool>> =
    std::sync::LazyLock::new(|| Arc::new(AtomicBool::new(false)));

pub(crate) static SYNC_RUNNING: AtomicBool = AtomicBool::new(false);

// ======================== Data Structures ========================

pub struct SyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub is_syncing: bool,
}

pub struct WalletBalance {
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
    pub transparent_pending: u64,
    pub sapling_pending: u64,
    pub orchard_pending: u64,
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

pub struct AddressValidationResult {
    pub is_valid: bool,
    pub address_type: String,
}

// ======================== Panic Guard ========================

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() { s.to_string() }
            else if let Some(s) = e.downcast_ref::<String>() { s.clone() }
            else { "Unknown panic".to_string() };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

// ======================== Sync Functions ========================

pub fn update_chain_tip(db_path: String, network: String, height: u64) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::update_chain_tip(&db_path, network, height)
    })
}

pub struct SubtreeIndices {
    pub next_sapling: u64,
    pub next_orchard: u64,
}

pub fn get_next_subtree_indices(db_path: String, network: String) -> Result<SubtreeIndices, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let (s, o) = wallet_sync::get_next_subtree_indices(&db_path, network)?;
        Ok(SubtreeIndices { next_sapling: s, next_orchard: o })
    })
}

pub fn put_subtree_roots(
    db_path: String, network: String,
    sapling_start_index: u64, sapling_roots: Vec<SubtreeRoot>,
    orchard_start_index: u64, orchard_roots: Vec<SubtreeRoot>,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let sapling: Vec<(u64, Vec<u8>)> = sapling_roots.into_iter().map(|r| (r.completing_block_height, r.root_hash)).collect();
        wallet_sync::put_sapling_subtree_roots(&db_path, network, sapling_start_index, &sapling)?;
        let orchard: Vec<(u64, Vec<u8>)> = orchard_roots.into_iter().map(|r| (r.completing_block_height, r.root_hash)).collect();
        wallet_sync::put_orchard_subtree_roots(&db_path, network, orchard_start_index, &orchard)?;
        Ok(())
    })
}

pub fn suggest_scan_ranges(db_path: String, network: String) -> Result<Vec<ScanRangeInfo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let ranges = wallet_sync::suggest_scan_ranges(&db_path, network)?;
        Ok(ranges.into_iter().map(|r| ScanRangeInfo { start: r.start, end: r.end, priority: r.priority }).collect())
    })
}

pub fn write_block_metadata(cache_path: String, blocks: Vec<BlockMetaInfo>) -> Result<(), String> {
    catch(|| {
        let tuples: Vec<_> = blocks.into_iter().map(|b| (b.height, b.hash, b.time, b.sapling_outputs_count, b.orchard_actions_count)).collect();
        wallet_sync::write_block_metadata(&cache_path, &tuples)
    })
}

pub fn scan_blocks(
    db_path: String, cache_path: String, network: String, from_height: u64,
    tree_state_network: String, tree_state_height: u64, tree_state_hash: String,
    tree_state_time: u32, tree_state_sapling_tree: String, tree_state_orchard_tree: String,
    limit: u64,
) -> Result<ScanResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let scanned = wallet_sync::scan_blocks(
            &db_path, &cache_path, network, from_height,
            &tree_state_network, tree_state_height, &tree_state_hash,
            tree_state_time, &tree_state_sapling_tree, &tree_state_orchard_tree, limit,
        )?;
        Ok(ScanResult { blocks_scanned: scanned })
    })
}

// ======================== Balance & Progress ========================

pub fn get_sync_status(db_path: String, network: String) -> Result<SyncProgress, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let p = wallet_sync::get_sync_progress(&db_path, network)?;
        Ok(SyncProgress { scanned_height: p.scanned_height, chain_tip_height: p.chain_tip_height, is_syncing: p.is_syncing })
    })
}

pub fn get_balance(db_path: String, network: String) -> Result<WalletBalance, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let b = wallet_sync::get_wallet_balance(&db_path, network)?;
        Ok(WalletBalance {
            transparent: b.transparent, sapling: b.sapling, orchard: b.orchard,
            transparent_pending: b.transparent_pending, sapling_pending: b.sapling_pending, orchard_pending: b.orchard_pending,
            total: b.transparent + b.sapling + b.orchard + b.transparent_pending + b.sapling_pending + b.orchard_pending,
        })
    })
}

// ======================== Rewind ========================

pub fn rewind_to_height(db_path: String, network: String, height: u64) -> Result<u64, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::rewind_to_height(&db_path, network, height)
    })
}

// ======================== Address Validation ========================

pub fn validate_address(address: String) -> Result<AddressValidationResult, String> {
    catch(|| {
        match wallet_sync::validate_address(&address) {
            Ok(addr_type) => Ok(AddressValidationResult { is_valid: true, address_type: addr_type }),
            Err(_) => Ok(AddressValidationResult { is_valid: false, address_type: "invalid".into() }),
        }
    })
}

// ======================== Send (2-step: propose then execute) ========================

pub struct ProposalResult {
    pub proposal_id: u64,
    pub needs_sapling_params: bool,
    pub fee_zatoshi: u64,
}

/// Step 1: Propose a transfer. Returns proposal info including whether Sapling params are needed.
pub fn propose_send(
    db_path: String, network: String,
    to_address: String, amount_zatoshi: u64, memo: Option<String>,
) -> Result<ProposalResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let r = wallet_sync::propose_send(&db_path, network, &to_address, amount_zatoshi, memo.as_deref())?;
        Ok(ProposalResult {
            proposal_id: r.proposal_id,
            needs_sapling_params: r.needs_sapling_params,
            fee_zatoshi: r.fee_zatoshi,
        })
    })
}

/// Step 2: Execute a previously proposed transfer and broadcast to the network.
/// spend_params_path and output_params_path are required only if needs_sapling_params was true.
pub fn execute_proposal(
    db_path: String, lightwalletd_url: String, proposal_id: u64, seed: Vec<u8>,
    spend_params_path: Option<String>, output_params_path: Option<String>,
) -> Result<String, String> {
    catch(|| {
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(wallet_sync::execute_proposal(
            &db_path, &lightwalletd_url, proposal_id, &seed,
            spend_params_path.as_deref(), output_params_path.as_deref(),
        ))
    })
}

// ======================== Diversified Address ========================

pub fn get_next_available_address(db_path: String, network: String) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::get_next_available_address(&db_path, network)
    })
}

// ======================== Enhancement ========================

pub struct TxDataRequest {
    pub request_type: String,
    pub txid: Option<String>,
    pub address: Option<String>,
    pub block_range_start: Option<u64>,
    pub block_range_end: Option<u64>,
}

pub fn get_transaction_data_requests(db_path: String, network: String) -> Result<Vec<TxDataRequest>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let reqs = wallet_sync::get_transaction_data_requests(&db_path, network)?;
        Ok(reqs.into_iter().map(|r| TxDataRequest {
            request_type: r.request_type, txid: r.txid, address: r.address,
            block_range_start: r.block_range_start, block_range_end: r.block_range_end,
        }).collect())
    })
}

pub fn decrypt_and_store_transaction(
    db_path: String, network: String, tx_bytes: Vec<u8>, mined_height: Option<u64>,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::decrypt_and_store_transaction(&db_path, network, &tx_bytes, mined_height)
    })
}

pub fn set_transaction_status(
    db_path: String, network: String, txid_hex: String, status: i64,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::set_transaction_status(&db_path, network, &txid_hex, status)
    })
}

// ======================== Transaction History ========================

pub struct TransactionInfo {
    pub txid_hex: String,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub account_balance_delta: i64,
    pub fee: u64,
    pub block_time: u64,
}

pub fn get_transaction_history(db_path: String, network: String, limit: Option<u32>) -> Result<Vec<TransactionInfo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let txs = wallet_sync::get_transaction_history(&db_path, network, limit)?;
        Ok(txs.into_iter().map(|t| TransactionInfo {
            txid_hex: t.txid_hex, mined_height: t.mined_height, expired_unmined: t.expired_unmined,
            account_balance_delta: t.account_balance_delta, fee: t.fee, block_time: t.block_time,
        }).collect())
    })
}

// ======================== Utility ========================

#[flutter_rust_bridge::frb(sync)]
pub fn get_blocks_dir(cache_path: String) -> String {
    wallet_sync::get_blocks_dir(&cache_path)
}
