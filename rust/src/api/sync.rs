use std::panic;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use zeroize::Zeroizing;

use crate::frb_generated::StreamSink;
use crate::wallet::{keys, network::WalletNetwork, secret_store, sync as wallet_sync, sync_engine};

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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
                true,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
    pub is_complete: bool,
}

pub enum WalletBalanceAvailability {
    Available,
    SummaryUnavailable,
    AccountUnavailable,
}

pub struct WalletBalance {
    pub availability: WalletBalanceAvailability,
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
    pub ironwood: u64,
    pub transparent_pending: u64,
    pub sapling_pending: u64,
    pub orchard_pending: u64,
    pub ironwood_pending: u64,
    /// Wallet-created change that has not reached the trusted confirmation depth.
    pub change_pending_confirmation: u64,
    /// Other received value awaiting confirmations or additional witness scanning.
    pub value_pending_spendability: u64,
    /// Notes at or below the ZIP-317 marginal fee, excluded from normal spendability.
    pub uneconomic_value: u64,
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

fn parse_network_and_migrate(db_path: &str, network: &str) -> Result<WalletNetwork, String> {
    let network = keys::parse_network(network)?;
    keys::ensure_db_migrated_once(db_path, network)?;
    Ok(network)
}

// ======================== Sync Functions ========================

pub fn update_chain_tip(db_path: String, network: String, height: u64) -> Result<(), String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        wallet_sync::update_chain_tip(&db_path, network, height)
    })
}

pub struct SubtreeIndices {
    pub next_sapling: u64,
    pub next_orchard: u64,
    pub next_ironwood: u64,
}

pub fn get_next_subtree_indices(
    db_path: String,
    network: String,
) -> Result<SubtreeIndices, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let (s, o, i) = wallet_sync::get_next_subtree_indices(&db_path, network)?;
        Ok(SubtreeIndices {
            next_sapling: s,
            next_orchard: o,
            next_ironwood: i,
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
    ironwood_start_index: u64,
    ironwood_roots: Vec<SubtreeRoot>,
) -> Result<(), String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
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
        let ironwood: Vec<(u64, Vec<u8>)> = ironwood_roots
            .into_iter()
            .map(|r| (r.completing_block_height, r.root_hash))
            .collect();
        wallet_sync::put_ironwood_subtree_roots(
            &db_path,
            network,
            ironwood_start_index,
            &ironwood,
        )?;
        Ok(())
    })
}

pub fn suggest_scan_ranges(db_path: String, network: String) -> Result<Vec<ScanRangeInfo>, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
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
    tree_state_ironwood_tree: String,
    limit: u64,
) -> Result<ScanResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
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
            &tree_state_ironwood_tree,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
        let p = wallet_sync::get_sync_progress(&db_path, network)?;
        Ok(SyncProgress {
            scanned_height: p.scanned_height,
            chain_tip_height: p.chain_tip_height,
            is_syncing: p.is_syncing,
            is_complete: p.is_complete,
        })
    })
}

pub fn get_balance(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<WalletBalance, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let b = wallet_sync::get_wallet_balance(&db_path, network, &account_uuid)?;
        let availability = match b.availability {
            wallet_sync::WalletBalanceAvailability::Available => {
                WalletBalanceAvailability::Available
            }
            wallet_sync::WalletBalanceAvailability::SummaryUnavailable => {
                WalletBalanceAvailability::SummaryUnavailable
            }
            wallet_sync::WalletBalanceAvailability::AccountUnavailable => {
                WalletBalanceAvailability::AccountUnavailable
            }
        };
        let spendable = b.sapling + b.orchard + b.ironwood;
        let total_spendable = b.transparent + b.sapling + b.orchard + b.ironwood;
        let pending =
            b.transparent_pending + b.sapling_pending + b.orchard_pending + b.ironwood_pending;
        Ok(WalletBalance {
            availability,
            transparent: b.transparent,
            sapling: b.sapling,
            orchard: b.orchard,
            ironwood: b.ironwood,
            transparent_pending: b.transparent_pending,
            sapling_pending: b.sapling_pending,
            orchard_pending: b.orchard_pending,
            ironwood_pending: b.ironwood_pending,
            change_pending_confirmation: b.change_pending_confirmation,
            value_pending_spendability: b.value_pending_spendability,
            uneconomic_value: b.uneconomic_value,
            spendable,
            total: total_spendable + pending,
        })
    })
}

// ======================== Rewind ========================

pub fn rewind_to_height(db_path: String, network: String, height: u64) -> Result<u64, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
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

pub struct IronwoodMigrationResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
    pub fee_zatoshi: u64,
    pub migrated_zatoshi: u64,
}

pub struct KeystoneMigrationMessage {
    pub id: String,
    pub redacted_pczt: Vec<u8>,
}

pub struct KeystoneMigrationSigningRequest {
    pub request_id: String,
    pub messages: Vec<KeystoneMigrationMessage>,
    pub signing_batch_limit: u32,
}

/// One signed message in the compact "signatures-only" Keystone response: the
/// produced spend-authorization signatures for request message `id`. Replaces
/// the prior full-signed-PCZT payload. Dart builds this from the decoded
/// `KeystoneSigResult` and feeds it into the migration completion calls.
pub struct KeystoneSignedMigrationMessage {
    pub id: String,
    pub sigs: Vec<crate::api::keystone::KeystoneActionSig>,
}

pub struct KeystoneMigrationProofStatus {
    pub ready_count: u32,
    pub total_count: u32,
    pub is_ready: bool,
    pub is_failed: bool,
    pub message: Option<String>,
}

pub struct MigrationScheduledBroadcast {
    pub txid_hex: String,
    pub value_zatoshi: u64,
    pub scheduled_at_ms: i64,
    pub schedule_start_height: Option<u32>,
    pub scheduled_height: u32,
    pub status: String,
}

pub struct MigrationScheduledTransfer {
    pub part_index: u32,
    pub value_zatoshi: u64,
    pub block_offset: u32,
}

pub struct MigrationOutboxItem {
    /// Stable Swift outbox item identifier. This is the finalized txid.
    pub item_id: String,
    pub part_index: u32,
    pub txid_hex: String,
    pub raw_transaction: Vec<u8>,
    pub anchor_boundary_height: u32,
    pub scheduled_height: u32,
    pub schedule_start_height: u32,
    pub expiry_height: u32,
}

pub struct MigrationOutboxBatch {
    pub run_id: String,
    pub timing_mean_blocks: u32,
    pub timing_max_blocks: u32,
    pub next_proof_height: Option<u32>,
    pub items: Vec<MigrationOutboxItem>,
}

pub struct MigrationOutboxScheduleUpdate {
    pub item_id: String,
    pub scheduled_height: u32,
    pub schedule_start_height: u32,
}

pub enum MigrationPartState {
    Preparing,
    Scheduled,
    Migrating,
    Confirming,
    Completed,
    NeedsInput,
}

pub struct MigrationPartStatus {
    pub part_index: u32,
    pub schedule_order: Option<u32>,
    pub value_zatoshi: u64,
    pub state: MigrationPartState,
    pub txid_hex: Option<String>,
    pub schedule_start_height: Option<u32>,
    pub scheduled_height: Option<u32>,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
}

pub struct MigrationStatus {
    pub phase: String,
    pub active_run_id: Option<String>,
    pub target_values_zatoshi: Vec<u64>,
    pub prepared_note_count: u32,
    /// Minimum confirmation depth across the active denomination split
    /// frontier, including parallel split roots.
    pub denomination_confirmation_count: u32,
    pub denomination_confirmation_target: u32,
    /// Denomination split transactions that have reached the wallet's trusted
    /// confirmation depth, rather than transactions that are merely mined.
    pub denomination_split_completed_count: u32,
    /// Total denomination split transactions planned for this migration run.
    pub denomination_split_total_count: u32,
    pub pending_tx_count: u32,
    pub broadcasted_tx_count: u32,
    pub confirmed_tx_count: u32,
    pub total_count: u32,
    pub signed_child_pczt_count: u32,
    pub pending_split_stage_count: u32,
    pub message: Option<String>,
    pub can_abandon: bool,
    pub signing_batch_limit: u32,
    pub schedule_mean_delay_blocks: u32,
    pub schedule_max_delay_blocks: u32,
    pub max_prepared_notes_per_run: u32,
    pub next_action_height: Option<u32>,
    pub estimated_completion_height: Option<u32>,
    pub next_action_part_index: Option<u32>,
    pub scheduled_broadcasts: Vec<MigrationScheduledBroadcast>,
    pub parts: Vec<MigrationPartStatus>,
}

pub struct OrchardMigrationPrivatePlan {
    pub target_values_zatoshi: Vec<u64>,
    pub total_input_zatoshi: u64,
    pub total_migratable_zatoshi: u64,
    pub orchard_change_zatoshi: Option<u64>,
    pub denomination_split_fee_zatoshi: u64,
    pub migration_fee_zatoshi: u64,
    pub estimated_total_fee_zatoshi: u64,
    pub planned_batch_count: u32,
    pub denomination_split_stage_count: u32,
    pub signing_batch_limit: u32,
    pub schedule_mean_delay_blocks: u32,
    pub schedule_max_delay_blocks: u32,
    pub max_prepared_notes_per_run: u32,
    pub scheduled_transfers: Vec<MigrationScheduledTransfer>,
}

fn to_wallet_migration_schedule(
    schedule: Vec<MigrationScheduledTransfer>,
) -> Vec<wallet_sync::MigrationScheduleEntry> {
    schedule
        .into_iter()
        .map(|entry| wallet_sync::MigrationScheduleEntry {
            part_index: Some(entry.part_index),
            value_zatoshi: entry.value_zatoshi,
            block_offset: entry.block_offset,
        })
        .collect()
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
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
    mnemonic_bytes: Vec<u8>,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<ExecuteProposalResult, String> {
    catch(|| {
        let mnemonic_bytes = Zeroizing::new(mnemonic_bytes);
        let seed = keys::mnemonic_bytes_to_seed(mnemonic_bytes.as_slice())?;
        drop(mnemonic_bytes);

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::execute_proposal(
            &db_path,
            &lightwalletd_url,
            proposal_id,
            &send_flow_id,
            seed,
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

/// macOS-only software send path that keeps encrypted mnemonic payloads out of
/// Dart memory. Rust reads and decrypts the stored mnemonic, derives the seed,
/// and zeroizes intermediate material.
pub fn execute_proposal_with_macos_stored_mnemonic(
    db_path: String,
    lightwalletd_url: String,
    proposal_id: u64,
    send_flow_id: String,
    password: String,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<ExecuteProposalResult, String> {
    catch(|| {
        let password = Zeroizing::new(password.into_bytes());
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::execute_proposal_with_seed_loader(
            &db_path,
            &lightwalletd_url,
            proposal_id,
            &send_flow_id,
            move |network, account_id| {
                secret_store::seed_from_macos_stored_mnemonic(
                    network,
                    &account_id.expose_uuid().to_string(),
                    password,
                )
            },
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

pub fn migrate_orchard_to_ironwood(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    mnemonic_bytes: Vec<u8>,
    password: String,
    salt_base64: String,
    approved_schedule: Vec<MigrationScheduledTransfer>,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let mnemonic_bytes = Zeroizing::new(mnemonic_bytes);
        let password = Zeroizing::new(password.into_bytes());
        let network = parse_network_and_migrate(&db_path, &network)?;
        let seed = keys::mnemonic_bytes_to_seed(mnemonic_bytes.as_slice())?;
        drop(mnemonic_bytes);

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::migrate_orchard_to_ironwood(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            seed,
            password,
            &salt_base64,
            to_wallet_migration_schedule(approved_schedule),
        ))?;
        Ok(IronwoodMigrationResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            migrated_zatoshi: r.migrated_zatoshi,
        })
    })
}

pub fn retire_unbroadcast_orchard_migration(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    expected_run_id: String,
) -> Result<(), String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(wallet_sync::retire_unbroadcast_orchard_migration(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            &expected_run_id,
        ))
    })
}

pub fn get_orchard_migration_status(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<MigrationStatus, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let balance = wallet_sync::get_wallet_balance(&db_path, network, &account_uuid)?;
        let status = wallet_sync::migration_status(
            &db_path,
            network,
            &account_uuid,
            balance.orchard,
            balance.orchard_pending,
            balance.ironwood,
            balance.ironwood_pending,
        )?;
        Ok(MigrationStatus {
            phase: status.phase,
            active_run_id: status.active_run_id,
            target_values_zatoshi: status.target_values_zatoshi,
            prepared_note_count: status.prepared_note_count,
            denomination_confirmation_count: status.denomination_confirmation_count,
            denomination_confirmation_target: status.denomination_confirmation_target,
            denomination_split_completed_count: status.denomination_split_completed_count,
            denomination_split_total_count: status.denomination_split_total_count,
            pending_tx_count: status.pending_tx_count,
            broadcasted_tx_count: status.broadcasted_tx_count,
            confirmed_tx_count: status.confirmed_tx_count,
            total_count: status.total_count,
            signed_child_pczt_count: status.signed_child_pczt_count,
            pending_split_stage_count: status.pending_split_stage_count,
            message: status.message,
            can_abandon: status.can_abandon,
            signing_batch_limit: status.signing_batch_limit,
            schedule_mean_delay_blocks: status.schedule_mean_delay_blocks,
            schedule_max_delay_blocks: status.schedule_max_delay_blocks,
            max_prepared_notes_per_run: status.max_prepared_notes_per_run,
            next_action_height: status.next_action_height,
            estimated_completion_height: status.estimated_completion_height,
            next_action_part_index: status.next_action_part_index,
            scheduled_broadcasts: status
                .scheduled_broadcasts
                .into_iter()
                .map(|broadcast| MigrationScheduledBroadcast {
                    txid_hex: broadcast.txid_hex,
                    value_zatoshi: broadcast.value_zatoshi,
                    scheduled_at_ms: broadcast.scheduled_at_ms,
                    schedule_start_height: broadcast.schedule_start_height,
                    scheduled_height: broadcast.scheduled_height,
                    status: broadcast.status,
                })
                .collect(),
            parts: status
                .parts
                .into_iter()
                .map(|part| MigrationPartStatus {
                    part_index: part.part_index,
                    schedule_order: part.schedule_order,
                    value_zatoshi: part.value_zatoshi,
                    state: match part.state {
                        wallet_sync::MigrationPartState::Preparing => MigrationPartState::Preparing,
                        wallet_sync::MigrationPartState::Scheduled => MigrationPartState::Scheduled,
                        wallet_sync::MigrationPartState::Migrating => MigrationPartState::Migrating,
                        wallet_sync::MigrationPartState::Confirming => {
                            MigrationPartState::Confirming
                        }
                        wallet_sync::MigrationPartState::Completed => MigrationPartState::Completed,
                        wallet_sync::MigrationPartState::NeedsInput => {
                            MigrationPartState::NeedsInput
                        }
                    },
                    txid_hex: part.txid_hex,
                    schedule_start_height: part.schedule_start_height,
                    scheduled_height: part.scheduled_height,
                    confirmation_count: part.confirmation_count,
                    confirmation_target: part.confirmation_target,
                })
                .collect(),
        })
    })
}

pub fn get_orchard_migration_private_plan(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<Option<OrchardMigrationPrivatePlan>, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        wallet_sync::get_orchard_migration_private_plan(&db_path, network, &account_uuid).map(
            |plan| {
                plan.map(|plan| OrchardMigrationPrivatePlan {
                    target_values_zatoshi: plan.target_values_zatoshi,
                    total_input_zatoshi: plan.total_input_zatoshi,
                    total_migratable_zatoshi: plan.total_migratable_zatoshi,
                    orchard_change_zatoshi: plan.orchard_change_zatoshi,
                    denomination_split_fee_zatoshi: plan.denomination_split_fee_zatoshi,
                    migration_fee_zatoshi: plan.migration_fee_zatoshi,
                    estimated_total_fee_zatoshi: plan.estimated_total_fee_zatoshi,
                    planned_batch_count: plan.planned_batch_count,
                    denomination_split_stage_count: plan.denomination_split_stage_count,
                    signing_batch_limit: plan.signing_batch_limit,
                    schedule_mean_delay_blocks: plan.schedule_mean_delay_blocks,
                    schedule_max_delay_blocks: plan.schedule_max_delay_blocks,
                    max_prepared_notes_per_run: plan.max_prepared_notes_per_run,
                    scheduled_transfers: plan
                        .scheduled_transfers
                        .into_iter()
                        .map(|entry| MigrationScheduledTransfer {
                            part_index: entry.part_index.unwrap_or(0),
                            value_zatoshi: entry.value_zatoshi,
                            block_offset: entry.block_offset,
                        })
                        .collect(),
                })
            },
        )
    })
}

/// Foreground-only migration preparation for the Swift-owned outbox.
/// Denomination stages may advance, and every currently provable signed child
/// is materialized, but scheduled child transactions are never broadcast here.
pub fn prepare_orchard_migration_outbox(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    password: String,
    salt_base64: String,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let result = rt.block_on(wallet_sync::IronwoodMigrationResult::prepare_outbox(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            password.as_slice(),
            &salt_base64,
        ))?;
        Ok(IronwoodMigrationResult {
            txids: result.txids,
            status: result.status,
            broadcasted_count: result.broadcasted_count,
            total_count: result.total_count,
            message: result.message,
            fee_zatoshi: result.fee_zatoshi,
            migrated_zatoshi: result.migrated_zatoshi,
        })
    })
}

pub fn export_orchard_migration_outbox(
    db_path: String,
    network: String,
    account_uuid: String,
    password: String,
    salt_base64: String,
) -> Result<Option<MigrationOutboxBatch>, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        wallet_sync::IronwoodMigrationResult::export_outbox(
            &db_path,
            network,
            &account_uuid,
            password.as_slice(),
            &salt_base64,
        )
        .map(|batch| {
            batch.map(|batch| MigrationOutboxBatch {
                run_id: batch.run_id,
                timing_mean_blocks: batch.timing_mean_blocks,
                timing_max_blocks: batch.timing_max_blocks,
                next_proof_height: batch.next_proof_height,
                items: batch
                    .items
                    .into_iter()
                    .map(|item| MigrationOutboxItem {
                        item_id: item.item_id,
                        part_index: item.part_index,
                        txid_hex: item.txid_hex,
                        raw_transaction: item.raw_tx,
                        anchor_boundary_height: item.anchor_boundary_height,
                        scheduled_height: item.scheduled_height,
                        schedule_start_height: item.schedule_start_height,
                        expiry_height: item.expiry_height,
                    })
                    .collect(),
            })
        })
    })
}

#[allow(clippy::too_many_arguments)]
pub fn reconcile_orchard_migration_outbox_receipt(
    db_path: String,
    network: String,
    account_uuid: String,
    run_id: String,
    txid_hex: String,
    outcome: String,
    remote_height: u32,
    response_message: Option<String>,
    schedule_updates: Vec<MigrationOutboxScheduleUpdate>,
    accepted_raw_transaction: Option<Vec<u8>>,
) -> Result<(), String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let schedule_updates = schedule_updates
            .into_iter()
            .map(|update| {
                (
                    update.item_id,
                    update.scheduled_height,
                    update.schedule_start_height,
                )
            })
            .collect();
        wallet_sync::IronwoodMigrationResult::reconcile_outbox_receipt(
            &db_path,
            network,
            &account_uuid,
            &run_id,
            &txid_hex,
            &outcome,
            remote_height,
            response_message.as_deref(),
            schedule_updates,
            accepted_raw_transaction,
        )
    })
}

pub fn broadcast_due_orchard_migration_transactions(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    password: String,
    salt_base64: String,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::broadcast_due_orchard_migration_transactions(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            password,
            &salt_base64,
        ))?;
        Ok(IronwoodMigrationResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            migrated_zatoshi: r.migrated_zatoshi,
        })
    })
}

pub fn broadcast_one_due_orchard_migration_transaction(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    password: String,
    salt_base64: String,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(
            wallet_sync::broadcast_one_due_orchard_migration_transaction(
                &db_path,
                &lightwalletd_url,
                network,
                &account_uuid,
                password,
                &salt_base64,
            ),
        )?;
        Ok(IronwoodMigrationResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            migrated_zatoshi: r.migrated_zatoshi,
        })
    })
}

pub fn prepare_orchard_migration_denominations_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<KeystoneMigrationSigningRequest, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let request = wallet_sync::prepare_orchard_migration_denominations_pczt(
            &db_path,
            network,
            &account_uuid,
        )?;
        Ok(KeystoneMigrationSigningRequest {
            request_id: request.request_id,
            signing_batch_limit: request.signing_batch_limit,
            messages: request
                .messages
                .into_iter()
                .map(|message| KeystoneMigrationMessage {
                    id: message.id,
                    redacted_pczt: message.redacted_pczt,
                })
                .collect(),
        })
    })
}

/// Convert the FRB-boundary signed messages (compact action signatures with
/// `Vec<u8>` sigs) into the wallet-layer form (`[u8; 64]` sigs), validating each
/// signature is exactly 64 bytes. Shared by all three migration completion FRB
/// wrappers so the conversion (and its length check) stays in one place.
fn to_wallet_signed_messages(
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
) -> Result<Vec<wallet_sync::KeystoneSignedMigrationMessage>, String> {
    signed_messages
        .into_iter()
        .map(|message| {
            let sigs = message
                .sigs
                .into_iter()
                .map(|action| {
                    let sig: [u8; 64] = action.sig.as_slice().try_into().map_err(|_| {
                        format!(
                            "Keystone signature for {} must be 64 bytes, got {}",
                            message.id,
                            action.sig.len()
                        )
                    })?;
                    let value_pool = match action.pool {
                        0 => orchard::ValuePool::Orchard,
                        1 => orchard::ValuePool::Ironwood,
                        other => {
                            return Err(format!(
                                "Keystone signature for {} has unsupported pool {other}",
                                message.id
                            ));
                        }
                    };
                    let action_index = usize::try_from(action.action_index).map_err(|_| {
                        format!(
                            "Keystone signature action index {} exceeds usize",
                            action.action_index
                        )
                    })?;
                    Ok(pczt::roles::signer::SpendAuthSignature::from_parts(
                        value_pool,
                        action_index,
                        sig,
                    ))
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok(wallet_sync::KeystoneSignedMigrationMessage {
                id: message.id,
                sigs,
            })
        })
        .collect()
}

pub async fn complete_orchard_migration_denominations_pczt(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    request_id: String,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    password: String,
    salt_base64: String,
    approved_schedule: Vec<MigrationScheduledTransfer>,
) -> Result<IronwoodMigrationResult, String> {
    let network = parse_network_and_migrate(&db_path, &network)?;
    let password = Zeroizing::new(password.into_bytes());
    let signed_messages = to_wallet_signed_messages(signed_messages)?;
    let r = wallet_sync::complete_orchard_migration_denominations_pczt(
        &db_path,
        &lightwalletd_url,
        network,
        &account_uuid,
        &request_id,
        signed_messages,
        password.as_slice(),
        &salt_base64,
        to_wallet_migration_schedule(approved_schedule),
    )
    .await?;
    Ok(IronwoodMigrationResult {
        txids: r.txids,
        status: r.status,
        broadcasted_count: r.broadcasted_count,
        total_count: r.total_count,
        message: r.message,
        fee_zatoshi: r.fee_zatoshi,
        migrated_zatoshi: r.migrated_zatoshi,
    })
}

pub fn prepare_orchard_migration_single_qr_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<KeystoneMigrationSigningRequest, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let request = wallet_sync::prepare_orchard_migration_single_qr_pczt(
            &db_path,
            network,
            &account_uuid,
        )?;
        Ok(KeystoneMigrationSigningRequest {
            request_id: request.request_id,
            signing_batch_limit: request.signing_batch_limit,
            messages: request
                .messages
                .into_iter()
                .map(|message| KeystoneMigrationMessage {
                    id: message.id,
                    redacted_pczt: message.redacted_pczt,
                })
                .collect(),
        })
    })
}

pub async fn complete_orchard_migration_single_qr_pczt(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    request_id: String,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    password: String,
    salt_base64: String,
) -> Result<IronwoodMigrationResult, String> {
    let network = parse_network_and_migrate(&db_path, &network)?;
    let password = Zeroizing::new(password.into_bytes());
    let signed_messages = to_wallet_signed_messages(signed_messages)?;
    let r = wallet_sync::complete_orchard_migration_single_qr_pczt(
        &db_path,
        &lightwalletd_url,
        network,
        &account_uuid,
        &request_id,
        signed_messages,
        password.as_slice(),
        &salt_base64,
    )
    .await?;
    Ok(IronwoodMigrationResult {
        txids: r.txids,
        status: r.status,
        broadcasted_count: r.broadcasted_count,
        total_count: r.total_count,
        message: r.message,
        fee_zatoshi: r.fee_zatoshi,
        migrated_zatoshi: r.migrated_zatoshi,
    })
}

pub fn prepare_orchard_migration_batch_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<KeystoneMigrationSigningRequest, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let request =
            wallet_sync::prepare_orchard_migration_batch_pczt(&db_path, network, &account_uuid)?;
        Ok(KeystoneMigrationSigningRequest {
            request_id: request.request_id,
            signing_batch_limit: request.signing_batch_limit,
            messages: request
                .messages
                .into_iter()
                .map(|message| KeystoneMigrationMessage {
                    id: message.id,
                    redacted_pczt: message.redacted_pczt,
                })
                .collect(),
        })
    })
}

pub fn keystone_migration_proof_status(
    request_id: String,
) -> Result<KeystoneMigrationProofStatus, String> {
    catch(|| {
        let status = wallet_sync::keystone_migration_proof_status(&request_id)?;
        Ok(KeystoneMigrationProofStatus {
            ready_count: status.ready_count,
            total_count: status.total_count,
            is_ready: status.is_ready,
            is_failed: status.is_failed,
            message: status.message,
        })
    })
}

pub fn discard_keystone_migration_request(request_id: String) -> Result<(), String> {
    catch(|| wallet_sync::discard_keystone_migration_request(&request_id))
}

pub fn discard_all_keystone_migration_requests() -> Result<(), String> {
    catch(wallet_sync::discard_all_keystone_migration_requests)
}

pub fn complete_orchard_migration_batch_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
    request_id: String,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    password: String,
    salt_base64: String,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        let signed_messages = to_wallet_signed_messages(signed_messages)?;
        let r = wallet_sync::complete_orchard_migration_batch_pczt(
            &db_path,
            network,
            &account_uuid,
            &request_id,
            signed_messages,
            password.as_slice(),
            &salt_base64,
        )?;
        Ok(IronwoodMigrationResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            migrated_zatoshi: r.migrated_zatoshi,
        })
    })
}

pub fn migrate_orchard_to_ironwood_with_macos_stored_mnemonic(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    password: String,
    salt_base64: String,
    approved_schedule: Vec<MigrationScheduledTransfer>,
) -> Result<IronwoodMigrationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password_bytes = password.into_bytes();
        let seed = secret_store::seed_from_macos_stored_mnemonic(
            network,
            &account_uuid,
            Zeroizing::new(password_bytes.clone()),
        )?;

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::migrate_orchard_to_ironwood(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            seed,
            Zeroizing::new(password_bytes),
            &salt_base64,
            to_wallet_migration_schedule(approved_schedule),
        ))?;
        Ok(IronwoodMigrationResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            migrated_zatoshi: r.migrated_zatoshi,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
        let r = wallet_sync::get_shield_transparent_status(&db_path, network, &account_uuid)?;
        Ok(ShieldTransparentStatus {
            can_shield: r.can_shield,
            fee_zatoshi: r.fee_zatoshi,
            shielded_zatoshi: r.shielded_zatoshi,
            reason: r.reason,
        })
    })
}

/// Create an Ironwood transparent-shielding PCZT for hardware accounts.
pub fn create_shield_transparent_pczt(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<ShieldTransparentPcztResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
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
/// Software-account only.
pub fn shield_transparent_balance(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    mnemonic_bytes: Vec<u8>,
) -> Result<ShieldTransparentResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let mnemonic_bytes = Zeroizing::new(mnemonic_bytes);
        let seed = keys::mnemonic_bytes_to_seed(mnemonic_bytes.as_slice())?;
        drop(mnemonic_bytes);

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::shield_transparent_balance(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            seed,
        ))?;
        Ok(ShieldTransparentResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
            fee_zatoshi: r.fee_zatoshi,
            shielded_zatoshi: r.shielded_zatoshi,
        })
    })
}

/// macOS-only software transparent shielding path that keeps encrypted mnemonic
/// payloads out of Dart memory. Rust reads and decrypts the stored mnemonic,
/// derives the seed, and zeroizes intermediate material.
pub fn shield_transparent_balance_with_macos_stored_mnemonic(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    password: String,
) -> Result<ShieldTransparentResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let password = Zeroizing::new(password.into_bytes());
        let seed = secret_store::seed_from_macos_stored_mnemonic(network, &account_uuid, password)?;

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let r = rt.block_on(wallet_sync::shield_transparent_balance(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            seed,
        ))?;
        Ok(ShieldTransparentResult {
            txids: r.txids,
            status: r.status,
            broadcasted_count: r.broadcasted_count,
            total_count: r.total_count,
            message: r.message,
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
    address_request: String,
) -> Result<String, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let address_request = wallet_sync::parse_address_request_kind(&address_request)?;
        wallet_sync::get_next_available_address(&db_path, network, &account_uuid, address_request)
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
    pub source_address: Option<String>,
    pub source_pool: Option<String>,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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

pub fn get_previous_transaction_count_for_address(
    db_path: String,
    network: String,
    account_uuid: String,
    address: String,
) -> Result<u32, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        wallet_sync::get_previous_transaction_count_for_address(
            &db_path,
            network,
            &account_uuid,
            &address,
        )
    })
}

pub fn get_export_birthday_height(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<u64, String> {
    catch(|| {
        let _network = parse_network_and_migrate(&db_path, &network)?;
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
            source_address: detail.source_address,
            source_pool: detail.source_pool,
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
        let network = parse_network_and_migrate(&db_path, &network)?;
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
    let network = parse_network_and_migrate(&db_path, &network)?;
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
