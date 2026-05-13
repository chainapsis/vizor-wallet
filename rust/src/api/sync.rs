use std::panic;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use secrecy::ExposeSecret;

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
    /// UI-only smoothed progress target. Dart increments toward this
    /// assuming one virtual block per 500ms, capped at the next batch.
    pub display_target_percentage: f64,
    pub display_target_blocks: u64,
    pub is_syncing: bool,
    pub is_complete: bool,
    pub has_new_tx: bool,
    /// Current sync phase: `"download"`, `"scan"`, `"enhance"`, or
    /// `""` (completion / unspecified).
    pub phase: String,
}

fn run_full_sync_internal<F>(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    mode: u8,
    on_progress: F,
) -> Result<(), String>
where
    F: Fn(&sync_engine::SyncProgressEvent) + Send + Sync,
{
    if SYNC_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("Sync already running".into());
    }

    DESIRED_SYNC_MODE.store(mode, Ordering::SeqCst);

    let result = catch(panic::AssertUnwindSafe(|| {
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
                |progress| on_progress(&progress),
            )
            .await
        })
    }));

    SYNC_RUNNING.store(false, Ordering::SeqCst);
    result
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
    run_full_sync_internal(db_path, lightwalletd_url, network, mode, |progress| {
        if sink
            .add(ApiSyncProgressEvent {
                scanned_height: progress.scanned_height,
                chain_tip_height: progress.chain_tip_height,
                percentage: progress.percentage,
                display_target_percentage: progress.display_target_percentage,
                display_target_blocks: progress.display_target_blocks,
                is_syncing: progress.is_syncing,
                is_complete: progress.is_complete,
                has_new_tx: progress.has_new_tx,
                phase: progress.phase.clone(),
            })
            .is_err()
        {
            log::warn!("sync: StreamSink closed, progress not delivered");
        }
    })
}

/// Blocking sync entrypoint that uses the same API-layer network parsing,
/// desired-mode globals, and running guard as `start_full_sync`, but without
/// a StreamSink. Used by Rust integration tests that want to stay on the
/// public API surface.
pub fn run_full_sync_blocking(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    mode: u8,
) -> Result<(), String> {
    run_full_sync_internal(db_path, lightwalletd_url, network, mode, |_| {})
}

/// Cancel a running full sync.
#[frb(sync)]
pub fn cancel_full_sync() {
    SYNC_CANCEL.store(true, Ordering::Relaxed);
}

/// Check whether a sync cancel has been requested.
#[frb(sync)]
pub fn is_sync_cancel_requested() -> bool {
    SYNC_CANCEL.load(Ordering::Relaxed)
}

/// Check if a sync is currently running.
#[frb(sync)]
pub fn is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}

pub(crate) static SYNC_CANCEL: std::sync::LazyLock<Arc<AtomicBool>> =
    std::sync::LazyLock::new(|| Arc::new(AtomicBool::new(false)));

pub(crate) static SYNC_RUNNING: AtomicBool = AtomicBool::new(false);

// ======================== Mempool Observer ========================

/// Event emitted by the mempool observer when a wallet-relevant
/// transaction appears on lightwalletd's mempool stream. Mirrored
/// one-to-one from `sync_engine::mempool::MempoolTxEvent` for FRB
/// codegen.
pub struct ApiMempoolTxEvent {
    /// Lower-case hex of the tx id.
    pub txid_hex: String,
    /// Account UUIDs that this event is known to affect. Empty means the
    /// tx is wallet-relevant but not account-scoped enough for Rust to
    /// name the account, so Dart keeps the legacy behavior of refreshing
    /// the active account.
    pub account_uuids: Vec<String>,
    /// `true` when the tx is wallet-relevant: either the wallet DB
    /// already has this txid as unmined, or the observer decrypted
    /// and stored a new inbound transaction from the mempool. Dart
    /// uses this flag to decide whether to refresh balance + history
    /// immediately.
    pub matched: bool,
}

/// Shared lifecycle state for the background mempool observer.
///
/// The previous revision of this file used a plain
/// `MEMPOOL_RUNNING: AtomicBool` + `MEMPOOL_CANCEL:
/// LazyLock<Arc<AtomicBool>>` pair, which was racy: `start` would
/// reset the shared cancel flag *after* the running-bit CAS, and a
/// `stop` call that landed in between would set `cancel=true` only
/// to have `start` immediately clear it back to `false`. That lost
/// the stop signal entirely and let the observer keep talking to
/// lightwalletd after the UI had asked for shutdown.
///
/// This replacement pairs each run with its own `Arc<AtomicBool>`
/// cancel token held inside a mutex-protected state struct. `start`
/// installs a fresh token while holding the mutex; `stop` takes
/// the same mutex and writes `true` to whichever token is
/// currently installed. A `stop` that lands in the middle of a
/// `start` is serialized by the mutex and sees the new token, and
/// a `stop` that lands after the observer exits becomes a no-op
/// because `cancel` is `None`. There is no longer a window in
/// which a stop can be lost.
pub(crate) struct MempoolObserverState {
    /// `true` while an observer coroutine is in flight. Mirrors
    /// the old `MEMPOOL_RUNNING` atomic.
    running: bool,
    /// Cancel token for the current run. `Some` while `running`
    /// is `true`; `None` otherwise. Holding a strong reference
    /// here lets `stop` write to the same flag the observer's
    /// sleep loop is already polling.
    cancel: Option<Arc<AtomicBool>>,
}

pub(crate) static MEMPOOL_OBSERVER_STATE: std::sync::LazyLock<
    std::sync::Mutex<MempoolObserverState>,
> = std::sync::LazyLock::new(|| {
    std::sync::Mutex::new(MempoolObserverState {
        running: false,
        cancel: None,
    })
});

/// Start the background mempool observer.
///
/// Blocks until [`stop_mempool_observer`] is called or the
/// observer returns on an unrecoverable setup error. Only parsed
/// wallet-relevant mempool txs are pushed to `sink` as
/// [`ApiMempoolTxEvent`]s; unrelated txs are filtered inside Rust.
///
/// The FRB layer runs this on the Rust isolate thread pool, so
/// Dart can `await` the call while the observer keeps polling
/// lightwalletd in the background. Dart is expected to fire this
/// alongside `start_full_sync` and call `stop_mempool_observer`
/// alongside `cancel_full_sync` — the two lifecycles are parallel
/// but separately controlled (intentional: the same bug in one
/// path must not silently take down the other).
pub fn start_mempool_observer(
    db_path: String,
    network: String,
    lightwalletd_url: String,
    sink: StreamSink<ApiMempoolTxEvent>,
) -> Result<(), String> {
    // Install a fresh cancel token under the state mutex. The
    // mutex serializes with `stop_mempool_observer`, so a stop
    // that raced us cannot leak into the *next* run: it either
    // runs first (and sees `running == false`, which is a no-op)
    // or runs after us (and finds this new token, which the
    // observer will then honour).
    let cancel = {
        let mut state = MEMPOOL_OBSERVER_STATE
            .lock()
            .map_err(|e| format!("mempool state mutex poisoned: {e}"))?;
        if state.running {
            return Err("Mempool observer already running".into());
        }
        let token = Arc::new(AtomicBool::new(false));
        state.running = true;
        state.cancel = Some(token.clone());
        token
    };

    let result = catch(|| {
        let network = keys::parse_network(&network)?;
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            crate::wallet::sync_engine::mempool::run_mempool_observer(
                db_path,
                network,
                lightwalletd_url,
                cancel,
                move |event| {
                    if sink
                        .add(ApiMempoolTxEvent {
                            txid_hex: event.txid_hex,
                            account_uuids: event.account_uuids,
                            matched: event.matched,
                        })
                        .is_err()
                    {
                        log::warn!("mempool: StreamSink closed, event not delivered");
                    }
                },
            )
            .await
        })
    });

    // Clear running + drop the cancel token so a subsequent
    // `stop_mempool_observer` call is a no-op rather than
    // incorrectly flipping a token the observer never consumes.
    // A poisoned mutex here is best-effort logged; `result`
    // still carries the actual observer outcome.
    match MEMPOOL_OBSERVER_STATE.lock() {
        Ok(mut state) => {
            state.running = false;
            state.cancel = None;
        }
        Err(e) => {
            log::error!("mempool: state mutex poisoned during teardown: {e}");
        }
    }

    result
}

/// Ask the running mempool observer to exit at the next cancel
/// check (inside the 100ms sleep slices or between stream
/// messages). Safe to call when no observer is running — the
/// stored cancel token is `None` in that case and this becomes a
/// no-op.
#[frb(sync)]
pub fn stop_mempool_observer() {
    match MEMPOOL_OBSERVER_STATE.lock() {
        Ok(state) => {
            if let Some(token) = state.cancel.as_ref() {
                token.store(true, Ordering::Relaxed);
            }
        }
        Err(e) => {
            log::error!("mempool: state mutex poisoned in stop: {e}");
        }
    }
}

/// Check whether the mempool observer task is currently running.
#[frb(sync)]
pub fn is_mempool_observer_running() -> bool {
    MEMPOOL_OBSERVER_STATE
        .lock()
        .map(|s| s.running)
        .unwrap_or(false)
}

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
    /// Sum of spendable shielded balances. Use this for "available to send".
    pub spendable: u64,
    /// Sum of spendable + pending balances across all pools. Use this for "total holdings".
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

pub fn get_next_subtree_indices(
    db_path: String,
    network: String,
) -> Result<SubtreeIndices, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let (s, o) = wallet_sync::get_next_subtree_indices(&db_path, network)?;
        Ok(SubtreeIndices {
            next_sapling: s,
            next_orchard: o,
        })
    })
}

pub fn put_subtree_roots(
    db_path: String,
    network: String,
    sapling_start_index: u64,
    sapling_roots: Vec<SubtreeRoot>,
    orchard_start_index: u64,
    orchard_roots: Vec<SubtreeRoot>,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let sapling: Vec<(u64, Vec<u8>)> = sapling_roots
            .into_iter()
            .map(|r| (r.completing_block_height, r.root_hash))
            .collect();
        wallet_sync::put_sapling_subtree_roots(&db_path, network, sapling_start_index, &sapling)?;
        let orchard: Vec<(u64, Vec<u8>)> = orchard_roots
            .into_iter()
            .map(|r| (r.completing_block_height, r.root_hash))
            .collect();
        wallet_sync::put_orchard_subtree_roots(&db_path, network, orchard_start_index, &orchard)?;
        Ok(())
    })
}

pub fn suggest_scan_ranges(db_path: String, network: String) -> Result<Vec<ScanRangeInfo>, String> {
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

pub fn write_block_metadata(cache_path: String, blocks: Vec<BlockMetaInfo>) -> Result<(), String> {
    catch(|| {
        let tuples: Vec<_> = blocks
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

// ======================== Balance & Progress ========================

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

pub fn get_balance(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<WalletBalance, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let b = wallet_sync::get_wallet_balance(&db_path, network, &account_uuid)?;
        let spendable = b.sapling + b.orchard;
        let total_spendable = b.transparent + b.sapling + b.orchard;
        let pending = b.transparent_pending + b.sapling_pending + b.orchard_pending;
        Ok(WalletBalance {
            transparent: b.transparent,
            sapling: b.sapling,
            orchard: b.orchard,
            transparent_pending: b.transparent_pending,
            sapling_pending: b.sapling_pending,
            orchard_pending: b.orchard_pending,
            spendable,
            total: total_spendable + pending,
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
    catch(|| match wallet_sync::validate_address(&address) {
        Ok(addr_type) => Ok(AddressValidationResult {
            is_valid: true,
            address_type: addr_type,
        }),
        Err(_) => Ok(AddressValidationResult {
            is_valid: false,
            address_type: "invalid".into(),
        }),
    })
}

// ======================== Send (2-step: propose then execute) ========================

pub struct ProposalResult {
    pub proposal_id: u64,
    pub needs_sapling_params: bool,
    pub fee_zatoshi: u64,
}

pub struct ExecuteProposalResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
}

pub struct ExtractAndBroadcastPcztResult {
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
}

pub struct SendMaxEstimateResult {
    pub amount_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub needs_sapling_params: bool,
}

pub struct ShieldTransparentResult {
    pub txids: String,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
}

pub struct ShieldTransparentStatus {
    pub can_shield: bool,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
    pub reason: String,
}

pub struct ShieldTransparentPcztResult {
    pub pczt_bytes: Vec<u8>,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
    pub needs_sapling_params: bool,
}

/// Step 1: Propose a transfer. Returns proposal info including whether Sapling params are needed.
pub fn propose_send(
    db_path: String,
    network: String,
    account_uuid: String,
    send_flow_id: String,
    to_address: String,
    amount_zatoshi: u64,
    memo: Option<String>,
) -> Result<ProposalResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let r = wallet_sync::propose_send(
            &db_path,
            network,
            &account_uuid,
            &send_flow_id,
            &to_address,
            amount_zatoshi,
            memo.as_deref(),
        )?;
        Ok(ProposalResult {
            proposal_id: r.proposal_id,
            needs_sapling_params: r.needs_sapling_params,
            fee_zatoshi: r.fee_zatoshi,
        })
    })
}

/// Estimate the fee for a transfer without storing a proposal.
pub fn estimate_fee(
    db_path: String,
    network: String,
    account_uuid: String,
    to_address: String,
    amount_zatoshi: u64,
    memo: Option<String>,
) -> Result<u64, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::estimate_fee(
            &db_path,
            network,
            &account_uuid,
            &to_address,
            amount_zatoshi,
            memo.as_deref(),
        )
    })
}

/// Estimate the maximum recipient amount for the current recipient and memo.
pub fn estimate_send_max(
    db_path: String,
    network: String,
    account_uuid: String,
    to_address: String,
    memo: Option<String>,
) -> Result<SendMaxEstimateResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let r = wallet_sync::estimate_send_max(
            &db_path,
            network,
            &account_uuid,
            &to_address,
            memo.as_deref(),
        )?;
        Ok(SendMaxEstimateResult {
            amount_zatoshi: r.amount_zatoshi,
            fee_zatoshi: r.fee_zatoshi,
            needs_sapling_params: r.needs_sapling_params,
        })
    })
}

/// Step 2: Execute a previously proposed transfer and broadcast to the network.
/// spend_params_path and output_params_path are required only if needs_sapling_params was true.
pub fn execute_proposal(
    db_path: String,
    lightwalletd_url: String,
    proposal_id: u64,
    send_flow_id: String,
    mnemonic: String,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<ExecuteProposalResult, String> {
    catch(|| {
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::execute_proposal(
            &db_path,
            &lightwalletd_url,
            proposal_id,
            &send_flow_id,
            seed.expose_secret(),
            spend_params_path.as_deref(),
            output_params_path.as_deref(),
        ))?;
        Ok(ExecuteProposalResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
        })
    })
}

/// Dry-run transparent shielding without creating or broadcasting a transaction.
pub fn get_shield_transparent_status(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<ShieldTransparentStatus, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let r = wallet_sync::get_shield_transparent_status(&db_path, network, &account_uuid)?;
        Ok(ShieldTransparentStatus {
            can_shield: r.can_shield,
            fee_zatoshi: r.fee_zatoshi,
            shielded_zatoshi: r.shielded_zatoshi,
            reason: r.reason,
        })
    })
}

/// Create a PCZT for shielding spendable transparent funds on a hardware account.
pub fn create_shield_transparent_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<ShieldTransparentPcztResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let r = wallet_sync::create_shield_transparent_pczt(&db_path, network, &account_uuid)?;
        Ok(ShieldTransparentPcztResult {
            pczt_bytes: r.pczt_bytes,
            fee_zatoshi: r.fee_zatoshi,
            shielded_zatoshi: r.shielded_zatoshi,
            needs_sapling_params: r.needs_sapling_params,
        })
    })
}

/// Shield spendable transparent funds into the account's shielded balance.
/// Software-account only; hardware shielding uses `create_shield_transparent_pczt`
/// followed by the PCZT QR signing flow.
pub fn shield_transparent_balance(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    mnemonic: String,
) -> Result<ShieldTransparentResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::shield_transparent_balance(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            seed.expose_secret(),
        ))?;
        Ok(ShieldTransparentResult {
            txids: r.txids,
            fee_zatoshi: r.fee_zatoshi,
            shielded_zatoshi: r.shielded_zatoshi,
        })
    })
}

// ======================== Diversified Address ========================

pub fn get_next_available_address(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::get_next_available_address(&db_path, network, &account_uuid)
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

pub fn get_transaction_data_requests(
    db_path: String,
    network: String,
) -> Result<Vec<TxDataRequest>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let reqs = wallet_sync::get_transaction_data_requests(&db_path, network)?;
        Ok(reqs
            .into_iter()
            .map(|r| TxDataRequest {
                request_type: r.request_type,
                txid: r.txid,
                address: r.address,
                block_range_start: r.block_range_start,
                block_range_end: r.block_range_end,
            })
            .collect())
    })
}

pub fn decrypt_and_store_transaction(
    db_path: String,
    network: String,
    tx_bytes: Vec<u8>,
    mined_height: Option<u64>,
) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::decrypt_and_store_transaction(&db_path, network, &tx_bytes, mined_height)
    })
}

pub fn set_transaction_status(
    db_path: String,
    network: String,
    txid_hex: String,
    status: i64,
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
    pub is_transparent: bool,
    pub tx_kind: String,
    pub display_amount: u64,
    pub display_pool: String,
    pub created_time: u64,
}

pub struct TransactionDetail {
    pub txid_hex: String,
    pub tx_kind: String,
    pub primary_address: Option<String>,
    pub memo: Option<String>,
    pub outputs: Vec<TransactionDetailOutput>,
}

pub struct TransactionDetailOutput {
    pub address: Option<String>,
    pub amount_zatoshi: u64,
    pub pool: String,
}

pub fn get_transaction_history(
    db_path: String,
    network: String,
    limit: Option<u32>,
    account_uuid: String,
) -> Result<Vec<TransactionInfo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let txs = wallet_sync::get_transaction_history(&db_path, network, limit, &account_uuid)?;
        Ok(txs
            .into_iter()
            .map(|t| TransactionInfo {
                txid_hex: t.txid_hex,
                mined_height: t.mined_height,
                expired_unmined: t.expired_unmined,
                account_balance_delta: t.account_balance_delta,
                fee: t.fee,
                block_time: t.block_time,
                is_transparent: t.is_transparent,
                tx_kind: t.tx_kind,
                display_amount: t.display_amount,
                display_pool: t.display_pool,
                created_time: t.created_time,
            })
            .collect())
    })
}

pub fn get_export_birthday_height(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<u64, String> {
    catch(|| {
        let _network = keys::parse_network(&network)?;
        let anchor = wallet_sync::get_export_birthday_anchor(&db_path, &account_uuid)?;
        Ok(anchor.block_height)
    })
}

pub fn get_block_time(lightwalletd_url: String, height: u64) -> Result<u64, String> {
    catch(|| fetch_block_time(&lightwalletd_url, height))
}

fn fetch_block_time(lightwalletd_url: &str, block_height: u64) -> Result<u64, String> {
    use zcash_client_backend::proto::service::BlockId;

    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
    rt.block_on(async {
        let mut client = sync_engine::open_lwd_channel(lightwalletd_url)
            .await
            .map_err(|e| e.to_string())?;
        let block = tokio::time::timeout(
            std::time::Duration::from_secs(10),
            client.get_block(BlockId {
                height: block_height,
                hash: vec![],
            }),
        )
        .await
        .map_err(|_| "get_block: timed out waiting for response".to_string())?
        .map_err(|e| format!("get_block: {e}"))?
        .into_inner();

        Ok(u64::from(block.time))
    })
}

#[frb(sync)]
pub fn get_transaction_detail(
    db_path: String,
    network: String,
    account_uuid: String,
    txid_hex: String,
    tx_kind: String,
) -> Result<TransactionDetail, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let detail = wallet_sync::get_transaction_detail(
            &db_path,
            network,
            &account_uuid,
            &txid_hex,
            &tx_kind,
        )?;
        Ok(TransactionDetail {
            txid_hex: detail.txid_hex,
            tx_kind: detail.tx_kind,
            primary_address: detail.primary_address,
            memo: detail.memo,
            outputs: detail
                .outputs
                .into_iter()
                .map(|output| TransactionDetailOutput {
                    address: output.address,
                    amount_zatoshi: output.amount_zatoshi,
                    pool: output.pool,
                })
                .collect(),
        })
    })
}

// ======================== Utility ========================

#[flutter_rust_bridge::frb(sync)]
pub fn get_blocks_dir(cache_path: String) -> String {
    wallet_sync::get_blocks_dir(&cache_path)
}

// ======================== PCZT (Hardware Wallet) ========================

/// Create a PCZT from a stored proposal for hardware wallet signing.
pub fn create_pczt_from_proposal(
    db_path: String,
    network: String,
    proposal_id: u64,
    send_flow_id: String,
) -> Result<Vec<u8>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        wallet_sync::create_pczt_from_proposal(&db_path, network, proposal_id, &send_flow_id)
    })
}

/// Release a stored proposal without executing it. Called by the Dart send
/// flow when the user cancels before `create_pczt_from_proposal` so the
/// proposal ID cannot be replayed. Idempotent.
pub fn discard_proposal(proposal_id: u64, send_flow_id: String) {
    wallet_sync::discard_proposal(proposal_id, &send_flow_id);
}

/// Add Orchard (and Sapling if needed) proofs to a PCZT locally. The output
/// is the "PCZT with proofs" half that is later combined with the signed PCZT
/// returned by the hardware wallet.
///
/// `spend_params_path` and `output_params_path` are only consulted when the
/// PCZT has a non-empty Sapling bundle (e.g. sending to a Sapling-only
/// recipient). Orchard-only sends can pass `None` for both. The caller is
/// responsible for ensuring the referenced files exist — the `proposal
/// .needsSaplingParams` flag on the propose result already tells the Dart
/// layer when it needs to download them.
pub fn add_proofs_to_pczt(
    pczt_bytes: Vec<u8>,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<Vec<u8>, String> {
    wallet_sync::add_proofs_to_pczt(
        &pczt_bytes,
        spend_params_path.as_deref(),
        output_params_path.as_deref(),
    )
}

/// Redact information from a PCZT that the hardware signer does not need
/// (witnesses, proprietary metadata). The returned bytes are what is sent
/// to the Keystone device for signing.
pub fn redact_pczt_for_signer(pczt_bytes: Vec<u8>) -> Result<Vec<u8>, String> {
    wallet_sync::redact_pczt_for_signer(&pczt_bytes)
}

/// Combine a PCZT-with-proofs and a PCZT-with-signatures, extract the final
/// transaction, store it in the wallet DB, and broadcast it to lightwalletd.
/// Returns the txid.
///
/// `spend_params_path` / `output_params_path` are required whenever the
/// combined PCZT has a non-empty Sapling bundle (e.g. the original proposal
/// had `needsSaplingParams == true`). They are used both to verify the
/// extracted transaction in-memory before broadcast and by
/// `extract_and_store_transaction_from_pczt` after broadcast. Orchard-only
/// sends can pass `None` for both. Mirrors the `add_proofs_to_pczt`
/// contract: if you needed to supply params there, you need them here too.
pub async fn extract_and_broadcast_pczt(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    pczt_with_proofs_bytes: Vec<u8>,
    pczt_with_signatures_bytes: Vec<u8>,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<ExtractAndBroadcastPcztResult, String> {
    let network = keys::parse_network(&network)?;
    let result = wallet_sync::extract_and_broadcast_pczt(
        &db_path,
        &lightwalletd_url,
        network,
        &pczt_with_proofs_bytes,
        &pczt_with_signatures_bytes,
        spend_params_path.as_deref(),
        output_params_path.as_deref(),
    )
    .await?;
    Ok(ExtractAndBroadcastPcztResult {
        txid: result.txid,
        status: result.status,
        message: result.message,
    })
}
