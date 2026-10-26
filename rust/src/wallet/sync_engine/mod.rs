use std::collections::{BTreeSet, HashSet, VecDeque};
use std::future::Future;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, RwLock};

use futures::{stream, FutureExt, StreamExt, TryStreamExt};
use nonempty::NonEmpty;
use rusqlite::{params, OptionalExtension};
use shardtree::error::{InsertionError, QueryError, ShardTreeError};
use tonic::transport::Channel;
use zcash_client_backend::data_api::{
    chain::{
        self, decrypt_cached_blocks, error::Error as ChainError, scan_cached_blocks,
        scan_decrypted_blocks, BlockDecryption,
    },
    ll::LowLevelWalletWrite,
    scanning::{ScanPriority, ScanRange},
    wallet::ConfirmationsPolicy,
    WalletCommitmentTrees, WalletRead, WalletWrite,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_readonly_with_timeout,
        open_wallet_db_with_timeout, open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock,
        WalletDatabase, READ_DB_BUSY_TIMEOUT, SYNC_DB_BUSY_TIMEOUT,
    },
    keys,
    network::WalletNetwork,
    sync, transparent_receive_cache, tree_states,
};

use {
    ::transparent::{
        address::{Script, TransparentAddress},
        bundle::{OutPoint, TxOut},
        keys::TransparentKeyScope,
    },
    zcash_client_backend::{
        proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
        wallet::WalletTransparentOutput,
    },
    zcash_keys::encoding::AddressCodec as _,
    zcash_protocol::value::Zatoshis,
    zcash_script::script,
};

mod address_history;
mod block_source;
mod claim_roots;
pub(crate) mod enhancement;
mod ephemeral_checks;
#[cfg(test)]
mod ephemeral_checks_tests;
mod error;
pub(crate) mod gift_card_claim;
pub(crate) mod ledger_discovery;
mod lwd;
pub(crate) mod mempool;
#[cfg(test)]
mod private_recovery_reorg_tests;
mod progress_work;
mod retry_progress;
pub(crate) mod scan_power;
#[cfg(test)]
pub(crate) mod test_lwd;
mod tip_cache;
pub(crate) mod transparent_details;
pub(crate) mod transparent_ledger;
#[cfg(test)]
mod transparent_recovery_tests;

use enhancement::{queue_stored_transactions, EnhancementPolicy, EnhancementSession};
pub(crate) use error::SyncError;
use error::{RecoveryStrategy, MAX_REWINDS_PER_RUN};
pub(crate) use lwd::{
    dispatch_signal::Dispatched, get_compact_block_hash, get_latest_block, next_stream_message,
    open_background_direct_lwd_channel, open_background_direct_lwd_transport,
    open_isolated_lwd_channel, open_isolated_lwd_transport, open_lwd_channel,
    open_lwd_channel_with_cancel, open_lwd_transport, open_lwd_transport_with_cancel,
    send_transaction, send_transaction_signalling, send_transaction_with_status,
    transparent_lookup::TransparentLookupGate,
};
use lwd::{
    download_blocks, download_subtree_roots, get_tree_state, get_tree_state_for_block,
    open_block_download_lwd_transport, open_isolated_lwd_transport_until,
};
use progress_work::{JobProgress, WorkModel};
pub(crate) use tip_cache::{
    get_latest_block_recorded, latest_block_for_transaction,
    latest_block_for_transaction_with_client,
};

/// What a [`SyncProgressEvent`] reports.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncEventKind {
    /// The sync is still running: preparation, download, or scan progress.
    Progress,
    /// The sync completed. The deferred inactive-account refresh and the
    /// ephemeral address checks report it again when they change wallet data.
    Completed,
    /// A post-sync follow-up (private transparent recovery, transparent
    /// details) changed wallet data after completion was reported. The sync
    /// stays complete; its stream, and the running guard, end only once
    /// every follow-up has.
    FollowupUpdated,
}

/// Additional scan work discovered after the original queue drained.
/// The cycle resets UI interpolation when the measured queue changes. It is
/// internal bookkeeping, not a user-visible repair count.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CheckingProgress {
    pub cycle: u32,
    pub percentage: f64,
    pub display_target_percentage: f64,
}

fn checking_progress(
    cycle: u32,
    total: u64,
    remaining: u64,
    target_blocks: u64,
) -> Option<CheckingProgress> {
    (cycle > 0).then(|| CheckingProgress {
        cycle,
        percentage: target_percentage_after_blocks(total, remaining, 0),
        display_target_percentage: target_percentage_after_blocks(total, remaining, target_blocks),
    })
}

fn begin_checking(cycle: &mut u32, total: u64, tip: u64, job: &JobProgress) -> SyncProgressEvent {
    *cycle += 1;
    SyncProgressEvent {
        checking: checking_progress(*cycle, total, total, 0),
        remaining_scan_blocks: Some(total),
        ..preparation_progress_event(tip, "chain_prepare", 0, 0, job.fraction(), job.id())
    }
}

/// Retry preparation carries the previous status until this queue is known.
/// Only a nonempty queue starts a new Checking measurement; an empty queue
/// keeps the current stage while final validation/enhancement finishes.
fn scan_queue_progress_event(
    cycle: &mut u32,
    main_scan_complete: bool,
    total: u64,
    tip: u64,
    pending_start: Option<u64>,
    job: &JobProgress,
) -> SyncProgressEvent {
    let mut event = if total > 0 && (*cycle > 0 || main_scan_complete) {
        begin_checking(cycle, total, tip, job)
    } else {
        SyncProgressEvent {
            checking: checking_progress(*cycle, total, total, 0),
            remaining_scan_blocks: Some(total),
            ..preparation_progress_event(tip, "chain_prepare", 0, 0, job.fraction(), job.id())
        }
    };
    event.pending_scan_start_height = pending_start;
    event
}

/// Progress event sent to caller (Dart or Swift).
#[derive(Clone, Debug)]
pub struct SyncProgressEvent {
    pub kind: SyncEventKind,
    pub checking: Option<CheckingProgress>,
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub display_target_percentage: f64,
    pub display_target_blocks: u64,
    /// All pending scan work, including lower-priority historical ranges.
    /// None until this attempt has enumerated the scan queue; Some(0) is empty.
    pub remaining_scan_blocks: Option<u64>,
    /// Inclusive start of the earliest pending range, not the current batch.
    /// None when the queue is unknown or empty (see remaining_scan_blocks).
    pub pending_scan_start_height: Option<u64>,
    pub is_syncing: bool,
    /// A scanned batch found wallet notes, or a re-reported completion stored
    /// transactions. A `FollowupUpdated` event implies a refresh on its own.
    pub has_new_tx: bool,
    /// Completed and total work units for preparation phases. A zero total
    /// means the phase has no measurable work and should be time-interpolated
    /// by the UI instead.
    pub phase_completed_units: u64,
    pub phase_total_units: u64,
    /// Current sync phase for UI display. One of:
    /// - `"active_utxo"` — refreshing the active account's transparent UTXOs
    /// - `"chain_prepare"` — resubmission, subtree, and scan-range preparation
    /// - `"download"` — downloading compact blocks from lightwalletd
    /// - `"scan"` — running `scan_cached_blocks` (CPU-intensive)
    /// - `""` — completion event or unspecified
    pub phase: String,
    /// Id of the sync job `percentage` belongs to. A job lasts until a sync
    /// completes, across retries, endpoint fallbacks and app relaunches, so a
    /// new attempt with the same id continues the same fraction. Claimed
    /// before the first event, so every event carries it.
    pub sync_job_id: String,
}

/// Blocks per scan batch at most; the byte budget decides below it. Every
/// batch pays a fixed serial cost after its scan (range and checkpoint
/// bookkeeping, tip check), so sparse history wants long batches: on a
/// 400,000-block stretch before the spam window, 10,000 instead of 2,000
/// cut the scan from 81 to 32 s (medians of three runs) and its CPU time by
/// a fifth. On an iPhone 16 Pro, 5,000 instead of 1,000 made a restore from
/// Sapling activation no faster (68.5 against 67.3 minutes, a day apart):
/// the byte budget decides the batches of the spam window, which took three
/// quarters of the time, and the blocks before it are nearly empty. With
/// 5,000 the spam-window runs held about 20 MB more memory, so mobile keeps
/// 1,000.
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const BATCH_SIZE_FOREGROUND: u32 = 10_000;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const BATCH_SIZE_FOREGROUND: u32 = 1000;
const BATCH_SIZE_BACKGROUND: u32 = 300;
/// Scan batches downloading ahead of the one being scanned, each on its own
/// request. A download is usually the bottleneck, and each request waits
/// before its first block, so more requests in flight keep the link busy
/// through those waits. On spam-window slices, four instead of two raised
/// throughput by about 40% with the mobile byte budget (7.1 to 9.7-10.3 MB/s).
/// With the desktop budget it depends on the link: on a dense slice four
/// scanned 17% slower than two over a fast link and as fast or faster over a
/// slower one. Queued batches stay encoded (`MemoryBlockSource`), so four
/// ahead holds about two more batches of wire bytes, some 60 MB on desktop.
const PREFETCH_DEPTH: usize = 4;
/// Pauses before retrying a queued batch whose download failed quickly with a
/// network error, while the scan is still busy with earlier batches. Without
/// a retry the batch is downloaded again inline when the scan reaches it, on
/// one request while nothing else downloads.
const PREFETCH_RETRY_PAUSES: [std::time::Duration; 2] = [
    std::time::Duration::from_secs(1),
    std::time::Duration::from_secs(4),
];
/// Estimated compact-block download at or above which a sync session fetches
/// its scan batches directly while Tor is on. A direct session shows the
/// server the device's IP address with the height its scan resumes from, so a
/// lower value hands over that link after shorter absences.
///
/// Desktop keeps syncing in the background: 256 MiB is about 13 minutes on
/// one Tor circuit at the 0.35 MB/s measured on mainnet, and in the October
/// 2026 chain about seven months of recent blocks, so only older restores
/// (17 GB from Sapling activation) go direct.
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const DIRECT_BLOCK_DOWNLOAD_MIN_BYTES: f64 = 256.0 * 1024.0 * 1024.0;
/// A phone syncs only while Vizor is on screen, so time on Tor is time the
/// user waits with the app open. 8 MiB is about 25 seconds at the same rate
/// (not measured on a phone) and about five days of recent blocks: a daily
/// catch-up stays on Tor, a longer absence or a restore goes direct.
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const DIRECT_BLOCK_DOWNLOAD_MIN_BYTES: f64 = 8.0 * 1024.0 * 1024.0;
const TRANSPARENT_UTXO_RECENT_EXTERNAL_LIMIT: usize = 20;
const TRANSPARENT_UTXO_SWEEP_EXTERNAL_LIMIT: usize = 20;
const TIP_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(600);
const FINAL_TIP_REFRESH_MIN_AGE: std::time::Duration = std::time::Duration::from_secs(5);
const MAX_CONCURRENT_TRANSPARENT_UTXO_STREAMS: usize = 4;
const MAX_DEFERRED_TRANSPARENT_REFRESH_ATTEMPTS: u32 = 3;

pub(crate) type ActiveSyncAccountTarget = Arc<RwLock<Option<String>>>;

fn current_active_sync_account(target: Option<&ActiveSyncAccountTarget>) -> Option<String> {
    target.map(|target| {
        target
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    })?
}

/// A preparation event. `job_percentage` is the stored fraction of the job
/// this attempt resumes, or 0 for a new job, so the display does not fall
/// back to zero while the attempt prepares.
fn preparation_progress_event(
    chain_tip_height: u64,
    phase: &str,
    phase_completed_units: u64,
    phase_total_units: u64,
    job_percentage: f64,
    sync_job_id: &str,
) -> SyncProgressEvent {
    SyncProgressEvent {
        kind: SyncEventKind::Progress,
        checking: None,
        scanned_height: 0,
        chain_tip_height,
        percentage: job_percentage,
        display_target_percentage: job_percentage,
        display_target_blocks: 0,
        remaining_scan_blocks: None,
        pending_scan_start_height: None,
        is_syncing: true,
        has_new_tx: false,
        phase_completed_units,
        phase_total_units,
        phase: phase.into(),
        sync_job_id: sync_job_id.into(),
    }
}

/// Reports that a post-sync follow-up changed wallet data after the sync
/// reported completion at `completed` (scanned height, chain tip).
pub(crate) fn followup_updated_event(completed: (u64, u64)) -> SyncProgressEvent {
    let (scanned_height, chain_tip_height) = completed;
    SyncProgressEvent {
        kind: SyncEventKind::FollowupUpdated,
        checking: None,
        scanned_height,
        chain_tip_height,
        percentage: 1.0,
        display_target_percentage: 1.0,
        display_target_blocks: 0,
        remaining_scan_blocks: Some(0),
        pending_scan_start_height: None,
        is_syncing: false,
        has_new_tx: false,
        phase_completed_units: 0,
        phase_total_units: 0,
        phase: String::new(),
        // The job ended with the completion this follows.
        sync_job_id: String::new(),
    }
}

/// Estimated compact-block bytes per scan batch (`WorkModel::batch_blocks`).
/// Up to `1 + PREFETCH_DEPTH` batches are in memory at once.
const BATCH_BYTE_BUDGET: f64 = if cfg!(any(
    target_os = "macos",
    target_os = "windows",
    target_os = "linux"
)) {
    DESKTOP_BATCH_BYTE_BUDGET
} else {
    MOBILE_BATCH_BYTE_BUDGET
};
/// The heaviest batch the block-count planner made on desktop: 2,000 blocks
/// right after the spam window.
const DESKTOP_BATCH_BYTE_BUDGET: f64 = 31_000_000.0;
/// The heaviest 100-block spam-window batch by the compiled tree sizes
/// (1,780,000..1,790,000 averages 113 KB a block). By the subtree heights
/// those batches came to about 15 MB, which leaves room for the estimate's
/// error between subtree heights. On an iPhone 16 Pro a 4 MB budget, with
/// spam-window batches a third as long, scanned 6,000 of those blocks about
/// a third slower.
const MOBILE_BATCH_BYTE_BUDGET: f64 = 11_300_000.0;
/// Fewest blocks per batch, against a broken estimate; real data never needs
/// it.
const MIN_BATCH_BLOCKS: u32 = 10;
/// Most blocks a batch takes past the compiled mainnet tree sizes, and off
/// mainnet, where no estimate says how dense they are: the desktop cap before
/// byte budgets. Blocks as dense as the 2022 spam window there would
/// otherwise fill the desktop's 10,000-block batches, five of them in memory.
const UNPLANNED_BATCH_BLOCKS: u32 = 2_000;

const MAX_WITNESS_REPAIR_PASSES_PER_RUN: u32 = 3;
const WITNESS_CHECK_POLICY_VERSION: u32 = 1;
const WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS: u64 = 10_000;
const SYNC_META_TABLE: &str = "ext_vizor_sync_meta";
const SYNC_COMPLETION_POLICY_VERSION: u32 = 1;
const SYNC_COMPLETION_POLICY_VERSION_KEY: &str = "sync_completion_policy_version";
const LAST_COMPLETED_SYNC_HEIGHT_KEY: &str = "last_completed_sync_height";
const SYNC_IN_PROGRESS_KEY: &str = "sync_in_progress";
const WITNESS_CHECK_POLICY_VERSION_KEY: &str = "witness_check_policy_version";
const WITNESS_CHECK_LAST_CLEAN_HEIGHT_KEY: &str = "witness_check_last_clean_height";
// `truncate_to_chain_state` only injects a canonical frontier when the requested
// height is below the retained checkpoint window. Start at the pruning depth
// and escalate so corrupted anchor checkpoints do not survive the repair.
const ANCHOR_ROOT_REPAIR_REWIND_DISTANCES: [u32; 3] = [100, 1000, 10_000];

/// Sync-scoped elapsed time reference. Set at sync start.
static SYNC_START: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

pub(crate) fn elapsed() -> String {
    SYNC_START
        .lock()
        .ok()
        .and_then(|g| g.map(|t| format!("{:.1}s", t.elapsed().as_secs_f64())))
        .unwrap_or_default()
}

/// The wallet backend's count of stored subtree roots found wrong, as last
/// logged. The backend counts for the whole process, so this is kept for the
/// process too: a mismatch is logged once, not again by every later sync.
static STORED_ROOT_MISMATCHES_LOGGED: AtomicU64 = AtomicU64::new(0);

/// Whether `count` includes mismatches not yet logged, recording it in
/// `logged` if so.
fn mismatches_not_yet_logged(logged: &AtomicU64, count: u64) -> bool {
    logged.fetch_max(count, Ordering::Relaxed) < count
}

/// The batch starting at `start`: its planned block count (as many as fit
/// `BATCH_BYTE_BUDGET`, at most `max_blocks`) and its end, cut at `range_end`.
fn planned_batch_end(
    model: &WorkModel,
    max_blocks: u32,
    start: BlockHeight,
    range_end: BlockHeight,
) -> Option<(u32, BlockHeight)> {
    if start >= range_end {
        return None;
    }

    let batch_size = model.batch_blocks(u64::from(u32::from(start)), max_blocks);
    let end = std::cmp::min(start + batch_size, range_end);
    Some((batch_size, end))
}

fn chain_tip_exclusive_end(current_tip_height: u64) -> BlockHeight {
    let current_tip = u32::try_from(current_tip_height).unwrap_or(u32::MAX);
    BlockHeight::from_u32(current_tip.saturating_add(1))
}

fn scannable_batch_end(
    model: &WorkModel,
    max_blocks: u32,
    start: BlockHeight,
    range_end: BlockHeight,
    current_tip_height: u64,
) -> Option<(u32, BlockHeight)> {
    let available_end = std::cmp::min(range_end, chain_tip_exclusive_end(current_tip_height));
    if start >= available_end {
        return None;
    }

    planned_batch_end(model, max_blocks, start, available_end)
}

/// The next `count` batch ranges from `start`, contiguous, inside the range
/// and below the tip.
fn prefetch_ranges(
    model: &WorkModel,
    max_blocks: u32,
    start: BlockHeight,
    range_end: BlockHeight,
    current_tip_height: u64,
    count: usize,
) -> Vec<(BlockHeight, BlockHeight)> {
    let mut ranges = Vec::with_capacity(count);
    let mut next = start;
    while ranges.len() < count {
        let Some((_, end)) =
            scannable_batch_end(model, max_blocks, next, range_end, current_tip_height)
        else {
            break;
        };
        ranges.push((next, end));
        next = end;
    }
    ranges
}

fn effective_base_batch_size(default_batch_size: u32) -> u32 {
    #[cfg(debug_assertions)]
    {
        if let Ok(raw) = std::env::var("ZCASH_E2E_SYNC_BATCH_SIZE") {
            if let Ok(parsed) = raw.parse::<u32>() {
                if parsed > 0 {
                    return parsed.min(default_batch_size);
                }
            }
        }
    }

    default_batch_size
}

#[cfg(debug_assertions)]
async fn maybe_sleep_for_e2e_sync_batch_delay() {
    let Ok(raw) = std::env::var("ZCASH_E2E_SYNC_BATCH_DELAY_MS") else {
        return;
    };
    let Ok(parsed) = raw.parse::<u64>() else {
        return;
    };
    if parsed == 0 {
        return;
    }

    tokio::time::sleep(std::time::Duration::from_millis(parsed.min(5_000))).await;
}

fn target_percentage_after_blocks(initial_total: u64, remaining: u64, blocks: u64) -> f64 {
    if initial_total == 0 {
        1.0
    } else {
        let target_remaining = remaining.saturating_sub(blocks);
        (1.0 - (target_remaining as f64 / initial_total as f64)).clamp(0.0, 1.0)
    }
}

/// Restart work-based progress before scanning ranges queued at completion.
fn reset_promoted_scan_progress(
    ranges: &[ScanRange],
    initial_total: &mut u64,
    prev_remaining: &mut u64,
) {
    let pending = pending_scan_blocks(ranges);
    *initial_total = pending;
    *prev_remaining = pending;
}

fn is_pending_scan_range(range: &ScanRange) -> bool {
    range.priority() != ScanPriority::Ignored && range.priority() != ScanPriority::Scanned
}

/// The pending range to scan next: the first, in priority order, that starts
/// at or below the loop's tip. A ChainTip range the mempool observer queued
/// past that tip waits behind history until a tip fetch reaches it. With no
/// such range, the first pending range is returned and the loop's
/// past-the-tip handling decides.
fn next_pending_scan_range(ranges: &[ScanRange], current_tip_height: u64) -> Option<&ScanRange> {
    let tip_end = chain_tip_exclusive_end(current_tip_height);
    let mut pending = ranges.iter().filter(|range| is_pending_scan_range(range));
    let first = pending.clone().next()?;
    Some(
        pending
            .find(|range| range.block_range().start < tip_end)
            .unwrap_or(first),
    )
}

fn recovery_resubmit_exclusions(
    db_path: &str,
    ranges: &[ScanRange],
) -> Result<HashSet<Vec<u8>>, SyncError> {
    let pending_ranges = ranges
        .iter()
        .filter(|range| is_pending_scan_range(range))
        .map(|range| range.block_range().clone())
        .collect::<Vec<_>>();
    crate::wallet::sync::get_unmined_txids_with_mined_output_evidence(db_path, &pending_ranges)
        .map_err(SyncError::db)
}

/// Both completion and post-batch resubmission use this handoff. Keep the
/// durable status rows on every outcome except a verified unchanged tip.
pub(crate) fn complete_verified_recovery_statuses(
    db_path: &str,
    ready: &HashSet<Vec<u8>>,
    relation: RefreshedTipRelation,
) -> Result<(), SyncError> {
    if ready.is_empty() || relation != RefreshedTipRelation::Unchanged {
        return Ok(());
    }
    with_wallet_db_write_lock("sync_engine.complete_verified_recovery_statuses", || {
        let mut conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)?;
        for txid in ready {
            crate::wallet::sync::resolve_recovered_nonmined_status(&mut conn, txid)?;
        }
        Ok::<(), String>(())
    })
    .map_err(SyncError::db)
}

/// What [`resubmit_released_transactions`] did.
#[derive(Debug)]
pub(crate) enum ReleasedResubmission {
    /// Nothing was released, resubmission is disabled, the sync is exiting,
    /// or the refreshed tip's identity could not be verified.
    Skipped,
    /// The tip was confirmed unchanged and a resubmit pass ran.
    Resubmitted,
    /// The chain advanced to this height. Nothing was broadcast: a new block
    /// may have mined the released transaction, and only scanning it can
    /// restore that mined height. The wallet tip has been promoted; the caller
    /// must resume scanning; the post-batch pass then resubmits against the scanned state.
    TipAdvanced(u64),
}

/// Enhancement can observe a conclusive non-mined status for a previously
/// mined transaction while retaining its status guard until tip validation.
/// A path that completes without a post-batch pass broadcasts it here rather
/// than leaving it for a later block that may be past its expiry. `ranges` are the current scan
/// ranges, which keep the usual rewind-recovery exclusions in force. Refresh
/// and validate the remote tip after enhancement; `tip_height` is only the
/// prior validation baseline, never the expiry filter. Refresh/validation
/// failures do not fall back to that stale height, and an advanced tip is
/// returned for scanning rather than broadcast against. Equal height without
/// a stored hash cannot rule out a reorg. Status work stays pending until tip
/// identity is verified, including refresh errors and cancellation.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn resubmit_released_transactions(
    ready: &HashSet<Vec<u8>>,
    allow_resubmit: bool,
    ranges: &[ScanRange],
    db_path: &str,
    lightwalletd_url: &str,
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    tip_height: u64,
    should_exit: impl Fn() -> bool,
) -> Result<ReleasedResubmission, SyncError> {
    if ready.is_empty() || !allow_resubmit || should_exit() {
        return Ok(ReleasedResubmission::Skipped);
    }
    let fresh_tip = unless_exiting(&should_exit, get_latest_block(client)).await;
    let Some(fresh_tip) =
        fresh_tip.and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
    else {
        return Ok(ReleasedResubmission::Skipped);
    };
    let fresh_tip = fresh_tip?;
    let tip = block_height_from_u64(fresh_tip.height, "released resubmission tip")?;
    let stored_hash = stored_hash_for_refreshed_tip(db, tip_height, fresh_tip.height)?;
    let relation = unless_exiting(
        &should_exit,
        classify_refreshed_tip_with_fallback(
            client,
            tip_height,
            stored_hash,
            fresh_tip.height,
            &fresh_tip.hash,
        ),
    )
    .await;
    let Some(relation) =
        relation.and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
    else {
        return Ok(ReleasedResubmission::Skipped);
    };
    match relation? {
        RefreshedTipRelation::ServerBehind => {
            return Err(lagging_lightwalletd_tip(tip_height, fresh_tip.height));
        }
        RefreshedTipRelation::Reorg => {
            return Err(SyncError::continuity(
                fresh_tip.height,
                "released resubmission tip proved a reorg",
            ));
        }
        RefreshedTipRelation::Advanced => {
            with_wallet_db_write_lock("sync_engine.update_chain_tip.released_resubmission", || {
                db.update_chain_tip(tip)
            })
            .map_err(|e| {
                SyncError::db(format!(
                    "released resubmission update_chain_tip({tip}): {e}"
                ))
            })?;
            return Ok(ReleasedResubmission::TipAdvanced(fresh_tip.height));
        }
        RefreshedTipRelation::UnchangedUnverified => {
            return Ok(ReleasedResubmission::Skipped);
        }
        RefreshedTipRelation::Unchanged => {}
    }
    complete_verified_recovery_statuses(db_path, ready, RefreshedTipRelation::Unchanged)?;
    // The tip's height and hash match, so the scanned state reflects every block
    // that could have mined the transaction; it supplies the expiry boundary.
    let exclusions = recovery_resubmit_exclusions(db_path, ranges)?;
    crate::wallet::sync::resubmit_pending_transactions(
        db_path,
        lightwalletd_url,
        client,
        u32::from(tip),
        &exclusions,
        should_exit,
    )
    .await;
    Ok(ReleasedResubmission::Resubmitted)
}

/// Whether a sync session downloads its scan batches over a direct
/// connection: only while Tor is desired, only when one circuit would hold the
/// session for long, and only under Private queries. The direct connection
/// opens alongside the session's Tor one, so the server can tie the two
/// together by timing; Private queries keep address and txid lookups off that
/// Tor connection. Decided once per session.
fn fetches_blocks_directly(
    tor_desired: bool,
    private_queries: bool,
    pending_download_bytes: f64,
) -> bool {
    tor_desired && private_queries && pending_download_bytes >= DIRECT_BLOCK_DOWNLOAD_MIN_BYTES
}

/// Direct batch failures in a row after which a session downloads its blocks
/// over Tor until it tries a fresh direct connection. Each failed batch is
/// downloaded again over Tor.
const DIRECT_BLOCK_FAILURES_BEFORE_TOR: u32 = 3;

/// How long a session downloads over Tor after its direct connection is
/// demoted before it opens a fresh one. Each later demotion doubles the wait,
/// up to [`DIRECT_BLOCK_RETRY_MAX`]. A connection that stops answering (three
/// queued batches timed out together on a phone restore) fails every request
/// on it, while a fresh connection to the same server works.
const DIRECT_BLOCK_RETRY_AFTER: std::time::Duration = std::time::Duration::from_secs(60);
const DIRECT_BLOCK_RETRY_MAX: std::time::Duration = std::time::Duration::from_secs(600);

/// The direct block connection of a session that may download directly: in
/// use, or demoted to Tor until a fresh connection may be tried.
#[derive(Debug)]
struct DirectBlockRoute {
    /// Direct batch failures in a row.
    failures: u32,
    /// Demotions so far, which set the wait before the next fresh connection.
    demotions: u32,
    /// When a demoted route may open a fresh connection; `None` while in use.
    retry_at: Option<std::time::Instant>,
}

impl DirectBlockRoute {
    fn new() -> Self {
        Self {
            failures: 0,
            demotions: 0,
            retry_at: None,
        }
    }

    fn in_use(&self) -> bool {
        self.retry_at.is_none()
    }

    /// Records one direct batch. Returns the wait before a fresh connection
    /// when this failure demotes the route.
    fn record(&mut self, failed: bool, now: std::time::Instant) -> Option<std::time::Duration> {
        if !failed {
            self.failures = 0;
            return None;
        }
        self.failures += 1;
        (self.failures >= DIRECT_BLOCK_FAILURES_BEFORE_TOR).then(|| self.demote(now))
    }

    /// Moves the route to Tor and returns the wait before a fresh connection.
    fn demote(&mut self, now: std::time::Instant) -> std::time::Duration {
        self.demotions += 1;
        self.failures = 0;
        let wait = DIRECT_BLOCK_RETRY_AFTER
            .saturating_mul(1 << (self.demotions - 1).min(4))
            .min(DIRECT_BLOCK_RETRY_MAX);
        self.retry_at = Some(now + wait);
        wait
    }

    fn retry_due(&self, now: std::time::Instant) -> bool {
        self.retry_at.is_some_and(|at| now >= at)
    }

    /// A fresh connection opened. Its first direct batch decides: a failure
    /// moves the route back to Tor for a longer wait.
    fn reopened(&mut self) {
        self.retry_at = None;
        self.failures = DIRECT_BLOCK_FAILURES_BEFORE_TOR - 1;
    }
}

/// How long a batch that ends far below the chain tip goes without the tip
/// check after each batch. That check is a round trip over the session's
/// route, Tor when it is on, which the loop waits for after the scan: a
/// restore runs thousands of history batches, and on an iPhone restore five
/// of those checks timed out, three after the full 20 seconds. Batches within
/// [`HISTORY_TIP_CHECK_DISTANCE`] of the tip still check after every batch,
/// so tip promotion, resubmission and the completion check near the tip are
/// unchanged. The schedule depends only on time and the batch's height, so
/// the requests still carry no wallet state.
const HISTORY_TIP_CHECK_EVERY: std::time::Duration = std::time::Duration::from_secs(60);
const HISTORY_TIP_CHECK_DISTANCE: u64 = 10_000;

/// Whether the batch ending at `batch_end` checks the chain tip after it scans.
fn post_batch_tip_check_due(
    batch_end: u64,
    tip: u64,
    since_last_check: std::time::Duration,
) -> bool {
    batch_end.saturating_add(HISTORY_TIP_CHECK_DISTANCE) >= tip
        || since_last_check >= HISTORY_TIP_CHECK_EVERY
}

/// How often a sync session logs where its time went, in debug builds only.
const SYNC_TIMING_SUMMARY_EVERY: std::time::Duration = std::time::Duration::from_secs(60);

/// The batches of a session since its last timing summary, so a log shows
/// whether a slow sync waits on downloads or on the scan: time waiting for a
/// batch's blocks counts as download, time waiting for the tip check after a
/// batch as tip checks, and time in the scan and the write as scan.
#[derive(Debug, Default)]
struct SyncTimingSummary {
    batches: u32,
    direct_batches: u32,
    blocks: u64,
    bytes: u64,
    waited: std::time::Duration,
    scanned: std::time::Duration,
    tip_waited: std::time::Duration,
}

impl SyncTimingSummary {
    fn record(
        &mut self,
        direct: bool,
        blocks: u64,
        bytes: u64,
        waited: std::time::Duration,
        scanned: std::time::Duration,
    ) {
        self.batches += 1;
        self.direct_batches += u32::from(direct);
        self.blocks += blocks;
        self.bytes += bytes;
        self.waited += waited;
        self.scanned += scanned;
    }

    /// The summary of `period`, at the scan power in effect.
    fn line(&self, period: std::time::Duration, power: scan_power::ScanPower) -> String {
        let seconds = period.as_secs_f64().max(f64::EPSILON);
        let megabytes = self.bytes as f64 / 1_000_000.0;
        format!(
            "last {:.0}s: {} batches ({} direct), {} blocks, {:.1} MB ({:.2} MB/s), \
             waited {:.1}s for downloads and {:.1}s for tip checks, scanned {:.1}s at \
             {power:?} power",
            period.as_secs_f64(),
            self.batches,
            self.direct_batches,
            self.blocks,
            megabytes,
            megabytes / seconds,
            self.waited.as_secs_f64(),
            self.tip_waited.as_secs_f64(),
            self.scanned.as_secs_f64(),
        )
    }
}

/// The connection a fresh scan batch download goes over.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum BlockRoute {
    Direct,
    Tor,
}

/// Downloads a scan batch fresh: over the direct connection when the batch may
/// use it, and over Tor when it may not, when its queued direct download
/// failed, or when the direct download fails with a network error. Also
/// returns whether the batch counts as a direct failure.
async fn download_with_direct_fallback<T, Download, DownloadFuture>(
    batch_is_direct: bool,
    queued_direct_failed: bool,
    mut download: Download,
) -> (Result<T, SyncError>, bool)
where
    Download: FnMut(BlockRoute) -> DownloadFuture,
    DownloadFuture: Future<Output = Result<T, SyncError>>,
{
    if !batch_is_direct {
        return (download(BlockRoute::Tor).await, false);
    }
    if queued_direct_failed {
        return (download(BlockRoute::Tor).await, true);
    }
    match download(BlockRoute::Direct).await {
        Err(SyncError::Network(error)) => {
            log::warn!(
                "[{}] sync: direct block download failed ({error}); downloading this batch over Tor",
                elapsed(),
            );
            (download(BlockRoute::Tor).await, true)
        }
        result => (result, false),
    }
}

/// Estimated download of the pending ranges whose batches may use the direct
/// connection, so a queue that only Tor would serve never opens it.
fn direct_download_bytes(
    work_model: &WorkModel,
    ranges: &[ScanRange],
    tip_height: u64,
    checking_cycle: u32,
    scanned_before_session: Option<BlockHeight>,
) -> f64 {
    let direct_ranges: Vec<ScanRange> = ranges
        .iter()
        .filter(|range| {
            batch_uses_direct_connection(
                checking_cycle,
                range.priority(),
                range.block_range().start,
                scanned_before_session,
            )
        })
        .cloned()
        .collect();
    work_model.pending_download_bytes(&direct_ranges, tip_height)
}

/// Whether a scan batch may use the session's direct block connection: only a
/// main-scan batch of a range every wallet with the same birthday and tip
/// scans alike. A Verify batch above the blocks scanned before this session is
/// the continuity check at the scan frontier, often merged into a full queued
/// batch; one at or below them re-scans blocks, as the witness repairs a
/// stopped session leaves do, so it stays on Tor with FoundNote and
/// OpenAdjacent ranges, which follow the wallet's notes.
fn batch_uses_direct_connection(
    checking_cycle: u32,
    priority: ScanPriority,
    start: BlockHeight,
    scanned_before_session: Option<BlockHeight>,
) -> bool {
    checking_cycle == 0
        && match priority {
            ScanPriority::ChainTip
            | ScanPriority::Historic
            | ScanPriority::LatestPoolActivation => true,
            ScanPriority::Verify => scanned_before_session.is_none_or(|height| start > height),
            _ => false,
        }
}

fn pending_scan_blocks(ranges: &[ScanRange]) -> u64 {
    ranges
        .iter()
        .filter(|r| is_pending_scan_range(r))
        .map(|r| {
            u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64
        })
        .sum()
}

/// The deepest reorg the wallet backend handles (its pruning depth).
const CATCH_UP_REORG_DEPTH: u64 = 100;

/// Whether pending work starting at `earliest_pending` scans only the blocks
/// since a sync completed at `completed_height`, give or take a reorg: a
/// catch-up. History below it, such as an account added since, is not.
fn scans_only_after_completion(
    earliest_pending: Option<u64>,
    completed_height: Option<u64>,
) -> bool {
    match (earliest_pending, completed_height) {
        (None, _) => true,
        (Some(start), Some(completed)) => start.saturating_add(CATCH_UP_REORG_DEPTH) >= completed,
        (Some(_), None) => false,
    }
}

/// Drops `job`'s catch-up flag when `ranges` reach below the sync that
/// completed at `completed_height`: an account added since, before or during
/// the attempt, brings its history to scan. Returns whether it dropped it.
fn reclassify_catch_up(
    job: &mut JobProgress,
    ranges: &[ScanRange],
    completed_height: Option<u64>,
) -> bool {
    if !job.from_completed_sync()
        || scans_only_after_completion(earliest_pending_scan_start(ranges), completed_height)
    {
        return false;
    }
    job.clear_from_completed_sync();
    true
}

fn earliest_pending_scan_start(ranges: &[ScanRange]) -> Option<u64> {
    ranges
        .iter()
        .filter(|r| is_pending_scan_range(r))
        .map(|r| u32::from(r.block_range().start) as u64)
        .min()
}

fn first_pending_scan_range(ranges: &[ScanRange]) -> Option<String> {
    ranges
        .iter()
        .find(|r| is_pending_scan_range(r))
        .map(|r| r.to_string())
}

fn block_range_len(range: &std::ops::Range<BlockHeight>) -> u64 {
    u32::from(range.end).saturating_sub(u32::from(range.start)) as u64
}

fn describe_block_range(range: &std::ops::Range<BlockHeight>) -> String {
    format!("{}..{}", u32::from(range.start), u32::from(range.end))
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct WitnessCheckMeta {
    policy_version: Option<u32>,
    last_clean_height: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WitnessCheckRunReason {
    Forced,
    MissingMarker,
    PolicyVersionChanged { stored: u32 },
    TipBelowLastClean { last_clean_height: u64 },
    MaxCleanAgeReached { age_blocks: u64 },
    MetadataUnavailable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WitnessCheckDecision {
    Run(WitnessCheckRunReason),
    Skip {
        last_clean_height: u64,
        age_blocks: u64,
    },
}

impl WitnessCheckRunReason {
    fn description(self) -> String {
        match self {
            WitnessCheckRunReason::Forced => "forced by repair/reorg signal".into(),
            WitnessCheckRunReason::MissingMarker => "no clean marker".into(),
            WitnessCheckRunReason::PolicyVersionChanged { stored } => format!(
                "policy version changed (stored={stored}, current={WITNESS_CHECK_POLICY_VERSION})"
            ),
            WitnessCheckRunReason::TipBelowLastClean { last_clean_height } => format!(
                "tip moved below last clean height (last_clean_height={last_clean_height})"
            ),
            WitnessCheckRunReason::MaxCleanAgeReached { age_blocks } => format!(
                "clean marker is stale (age_blocks={age_blocks}, max_age_blocks={WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS})"
            ),
            WitnessCheckRunReason::MetadataUnavailable => "metadata unavailable".into(),
        }
    }
}

fn decide_witness_check(
    meta: WitnessCheckMeta,
    current_tip_height: u64,
    force_check: bool,
) -> WitnessCheckDecision {
    if force_check {
        return WitnessCheckDecision::Run(WitnessCheckRunReason::Forced);
    }

    match meta.policy_version {
        Some(WITNESS_CHECK_POLICY_VERSION) => {}
        Some(stored) => {
            return WitnessCheckDecision::Run(WitnessCheckRunReason::PolicyVersionChanged {
                stored,
            });
        }
        None => return WitnessCheckDecision::Run(WitnessCheckRunReason::MissingMarker),
    }

    let Some(last_clean_height) = meta.last_clean_height else {
        return WitnessCheckDecision::Run(WitnessCheckRunReason::MissingMarker);
    };

    if last_clean_height > current_tip_height {
        return WitnessCheckDecision::Run(WitnessCheckRunReason::TipBelowLastClean {
            last_clean_height,
        });
    }

    let age_blocks = current_tip_height - last_clean_height;
    if age_blocks >= WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS {
        return WitnessCheckDecision::Run(WitnessCheckRunReason::MaxCleanAgeReached { age_blocks });
    }

    WitnessCheckDecision::Skip {
        last_clean_height,
        age_blocks,
    }
}

fn sync_meta_table_exists(conn: &rusqlite::Connection) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(
            SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1
        )",
        params![SYNC_META_TABLE],
        |row| row.get::<_, i64>(0),
    )
    .map(|exists| exists != 0)
    .map_err(|e| format!("read sync metadata table existence: {e}"))
}

fn read_sync_meta_value(conn: &rusqlite::Connection, key: &str) -> Result<Option<String>, String> {
    conn.query_row(
        "SELECT value FROM ext_vizor_sync_meta WHERE key = ?1",
        params![key],
        |row| row.get::<_, String>(0),
    )
    .optional()
    .map_err(|e| format!("read sync metadata value {key}: {e}"))
}

fn parse_sync_meta_u32(key: &str, value: Option<String>) -> Option<u32> {
    let value = value?;
    match value.parse::<u32>() {
        Ok(parsed) => Some(parsed),
        Err(e) => {
            log::warn!("sync: ignoring invalid sync metadata value {key}={value:?}: {e}");
            None
        }
    }
}

fn parse_sync_meta_u64(key: &str, value: Option<String>) -> Option<u64> {
    let value = value?;
    match value.parse::<u64>() {
        Ok(parsed) => Some(parsed),
        Err(e) => {
            log::warn!("sync: ignoring invalid sync metadata value {key}={value:?}: {e}");
            None
        }
    }
}

fn read_witness_check_meta(db_data_path: &str) -> Result<WitnessCheckMeta, String> {
    let conn = open_readonly_conn_with_timeout(db_data_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    if !sync_meta_table_exists(&conn)? {
        return Ok(WitnessCheckMeta::default());
    }

    Ok(WitnessCheckMeta {
        policy_version: parse_sync_meta_u32(
            WITNESS_CHECK_POLICY_VERSION_KEY,
            read_sync_meta_value(&conn, WITNESS_CHECK_POLICY_VERSION_KEY)?,
        ),
        last_clean_height: parse_sync_meta_u64(
            WITNESS_CHECK_LAST_CLEAN_HEIGHT_KEY,
            read_sync_meta_value(&conn, WITNESS_CHECK_LAST_CLEAN_HEIGHT_KEY)?,
        ),
    })
}

fn read_sync_completion_meta(
    db_data_path: &str,
) -> Result<(Option<u32>, Option<u64>, Option<bool>), String> {
    let conn = open_readonly_conn_with_timeout(db_data_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    if !sync_meta_table_exists(&conn)? {
        return Ok((None, None, None));
    }

    Ok((
        parse_sync_meta_u32(
            SYNC_COMPLETION_POLICY_VERSION_KEY,
            read_sync_meta_value(&conn, SYNC_COMPLETION_POLICY_VERSION_KEY)?,
        ),
        parse_sync_meta_u64(
            LAST_COMPLETED_SYNC_HEIGHT_KEY,
            read_sync_meta_value(&conn, LAST_COMPLETED_SYNC_HEIGHT_KEY)?,
        ),
        parse_sync_meta_u32(
            SYNC_IN_PROGRESS_KEY,
            read_sync_meta_value(&conn, SYNC_IN_PROGRESS_KEY)?,
        )
        .map(|value| value != 0),
    ))
}

fn witness_check_decision(
    db_data_path: &str,
    current_tip_height: u64,
    force_check: bool,
) -> WitnessCheckDecision {
    match read_witness_check_meta(db_data_path) {
        Ok(meta) => decide_witness_check(meta, current_tip_height, force_check),
        Err(e) => {
            log::warn!(
                "[{}] sync: witness repair metadata unavailable, running check: {e}",
                elapsed(),
            );
            WitnessCheckDecision::Run(WitnessCheckRunReason::MetadataUnavailable)
        }
    }
}

fn ensure_sync_meta_table(conn: &rusqlite::Connection) -> Result<(), String> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS ext_vizor_sync_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )",
        [],
    )
    .map(|_| ())
    .map_err(|e| format!("create sync metadata table: {e}"))
}

fn mark_witness_check_clean(db_data_path: &str, current_tip_height: u64) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;

    let tx = conn
        .transaction()
        .map_err(|e| format!("begin sync metadata transaction: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            WITNESS_CHECK_POLICY_VERSION_KEY,
            WITNESS_CHECK_POLICY_VERSION.to_string()
        ],
    )
    .map_err(|e| format!("write witness check policy version: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            WITNESS_CHECK_LAST_CLEAN_HEIGHT_KEY,
            current_tip_height.to_string()
        ],
    )
    .map_err(|e| format!("write witness check clean height: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit sync metadata transaction: {e}"))
}

fn initialize_sync_completion_policy(
    db_data_path: &str,
    legacy_completed_height: Option<u64>,
) -> Result<(Option<u64>, Option<bool>), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin sync completion metadata transaction: {e}"))?;
    let inserted = tx
        .execute(
            "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO NOTHING",
            params![
                SYNC_COMPLETION_POLICY_VERSION_KEY,
                SYNC_COMPLETION_POLICY_VERSION.to_string()
            ],
        )
        .map_err(|e| format!("initialize sync completion policy version: {e}"))?;
    if inserted > 0 {
        tx.execute(
            "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, '0')
             ON CONFLICT(key) DO NOTHING",
            params![SYNC_IN_PROGRESS_KEY],
        )
        .map_err(|e| format!("initialize sync in-progress marker: {e}"))?;
        if let Some(height) = legacy_completed_height {
            tx.execute(
                "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                params![LAST_COMPLETED_SYNC_HEIGHT_KEY, height.to_string()],
            )
            .map_err(|e| format!("migrate legacy completed sync height: {e}"))?;
        }
    }
    tx.commit()
        .map_err(|e| format!("commit sync completion metadata: {e}"))?;
    read_sync_completion_meta(db_data_path).map(|(_, height, in_progress)| (height, in_progress))
}

pub(crate) fn completed_sync_height_for_status(
    db_data_path: &str,
    scanned_height: u64,
    chain_tip_height: u64,
) -> Result<Option<u64>, String> {
    let (policy_version, completed_height, in_progress) = read_sync_completion_meta(db_data_path)?;
    match policy_version {
        Some(SYNC_COMPLETION_POLICY_VERSION) => Ok((in_progress == Some(false))
            .then_some(completed_height)
            .flatten()),
        Some(other) => {
            log::warn!(
                "sync: unsupported completion policy version {other}; treating status as incomplete"
            );
            Ok(None)
        }
        None => {
            let legacy_completed_height = (chain_tip_height > 0
                && scanned_height >= chain_tip_height)
                .then_some(chain_tip_height);
            initialize_sync_completion_policy(db_data_path, legacy_completed_height).map(
                |(height, in_progress)| (in_progress == Some(false)).then_some(height).flatten(),
            )
        }
    }
}

/// Marks a sync in progress and returns its progress job: the stored one, or
/// a newly claimed one, a catch-up when the last sync stood completed.
fn mark_sync_started(db_data_path: &str) -> Result<progress_work::StoredProgressJob, String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin sync-start metadata transaction: {e}"))?;
    let from_completed_sync = parse_sync_meta_u32(
        SYNC_COMPLETION_POLICY_VERSION_KEY,
        read_sync_meta_value(&tx, SYNC_COMPLETION_POLICY_VERSION_KEY)?,
    ) == Some(SYNC_COMPLETION_POLICY_VERSION)
        && parse_sync_meta_u32(
            SYNC_IN_PROGRESS_KEY,
            read_sync_meta_value(&tx, SYNC_IN_PROGRESS_KEY)?,
        ) == Some(0)
        && parse_sync_meta_u64(
            LAST_COMPLETED_SYNC_HEIGHT_KEY,
            read_sync_meta_value(&tx, LAST_COMPLETED_SYNC_HEIGHT_KEY)?,
        )
        .is_some();
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            SYNC_COMPLETION_POLICY_VERSION_KEY,
            SYNC_COMPLETION_POLICY_VERSION.to_string()
        ],
    )
    .map_err(|e| format!("write sync-start policy version: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![SYNC_IN_PROGRESS_KEY],
    )
    .map_err(|e| format!("write sync in-progress marker: {e}"))?;
    let job = progress_work::claim_progress_job(&tx, from_completed_sync)?;
    tx.commit()
        .map_err(|e| format!("commit sync-start metadata: {e}"))?;
    Ok(job)
}

/// The stored sync job's id, last fraction and whether it is a catch-up, for
/// the status a relaunch or an unlock starts from: an unfinished job, or one
/// whose scan finished before the attempt could complete, which the next
/// attempt resumes too. A completed sync clears it.
pub(crate) fn stored_progress_job(db_data_path: &str) -> Option<(String, f64, bool)> {
    match progress_work::read_progress_job(db_data_path) {
        Ok(job) => job.map(|job| (job.id, job.fraction, job.from_completed_sync)),
        Err(e) => {
            log::warn!("sync: stored progress job unreadable: {e}");
            None
        }
    }
}

fn mark_sync_completed(db_data_path: &str, completed_tip_height: u64) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin completed sync transaction: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            SYNC_COMPLETION_POLICY_VERSION_KEY,
            SYNC_COMPLETION_POLICY_VERSION.to_string()
        ],
    )
    .map_err(|e| format!("write sync completion policy version: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![
            LAST_COMPLETED_SYNC_HEIGHT_KEY,
            completed_tip_height.to_string()
        ],
    )
    .map_err(|e| format!("write completed sync height: {e}"))?;
    tx.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, '0')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![SYNC_IN_PROGRESS_KEY],
    )
    .map_err(|e| format!("clear sync in-progress marker: {e}"))?;
    // The job is done; the next sync measures its own work from zero.
    progress_work::clear_progress_job(&tx)?;
    tx.commit()
        .map_err(|e| format!("commit completed sync transaction: {e}"))
}

fn ensure_complete_scan_state(
    db: &mut WalletDatabase,
    current_tip_height: u64,
) -> Result<(u64, u64), SyncError> {
    let ranges = db
        .suggest_scan_ranges()
        .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
    let pending_blocks = pending_scan_blocks(&ranges);
    if pending_blocks > 0 {
        let first = first_pending_scan_range(&ranges).unwrap_or_else(|| "unknown".into());
        return Err(SyncError::continuity(
            current_tip_height,
            format!(
                "sync completion blocked: {pending_blocks} pending scan blocks remain \
                 (first pending range: {first})"
            ),
        ));
    }

    let wallet_heights = sync::wallet_scan_heights(db).map_err(SyncError::db)?;
    let heights = validate_complete_scan_heights(current_tip_height, wallet_heights)?;
    let stored_tip_hash = if current_tip_height == 0 {
        None
    } else {
        let tip_height = block_height_from_u64(current_tip_height, "completion chain tip")?;
        db.get_block_hash(tip_height)
            .map_err(|e| SyncError::db(format!("get_block_hash({tip_height}): {e}")))?
    };
    validate_complete_tip_hash(current_tip_height, stored_tip_hash)?;
    Ok(heights)
}

fn validate_complete_scan_heights(
    current_tip_height: u64,
    wallet_heights: Option<(u64, u64)>,
) -> Result<(u64, u64), SyncError> {
    let Some((fully_scanned_height, db_tip_height)) = wallet_heights else {
        return if current_tip_height == 0 {
            Ok((0, 0))
        } else {
            Err(SyncError::db(format!(
                "sync completion blocked: wallet summary unavailable at tip \
                 {current_tip_height}"
            )))
        };
    };

    if db_tip_height != current_tip_height {
        let relation = if db_tip_height < current_tip_height {
            "lags"
        } else {
            "is ahead of"
        };
        return Err(SyncError::continuity(
            current_tip_height,
            format!(
                "sync completion blocked: wallet DB chain tip {db_tip_height} \
                 {relation} lightwalletd tip {current_tip_height}"
            ),
        ));
    }

    if fully_scanned_height != db_tip_height {
        return Err(SyncError::continuity(
            db_tip_height,
            format!(
                "sync completion blocked: fully scanned height {fully_scanned_height} \
                 does not match wallet DB chain tip {db_tip_height}"
            ),
        ));
    }

    Ok((fully_scanned_height, db_tip_height))
}

fn validate_complete_tip_hash(
    current_tip_height: u64,
    stored_tip_hash: Option<BlockHash>,
) -> Result<(), SyncError> {
    if current_tip_height == 0 || stored_tip_hash.is_some() {
        Ok(())
    } else {
        Err(SyncError::db(format!(
            "sync completion blocked: stored block hash is unavailable at tip \
             {current_tip_height}"
        )))
    }
}

fn queue_witness_repairs_if_needed(
    db_data_path: &str,
    db: &mut WalletDatabase,
    current_tip_height: u64,
    repair_passes_this_run: &mut u32,
    force_check: bool,
) -> Result<Option<u64>, SyncError> {
    match witness_check_decision(db_data_path, current_tip_height, force_check) {
        WitnessCheckDecision::Run(reason) => {
            log::info!(
                "[{}] sync: witness repair check running ({})",
                elapsed(),
                reason.description(),
            );
        }
        WitnessCheckDecision::Skip {
            last_clean_height,
            age_blocks,
        } => {
            log::info!(
                "[{}] sync: witness repair check skipped \
                 (last_clean_height={last_clean_height}, current_tip={current_tip_height}, \
                 age_blocks={age_blocks}, max_age_blocks={WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS})",
                elapsed(),
            );
            return Ok(None);
        }
    }

    let rescan_ranges = with_wallet_db_write_lock("sync_engine.check_witnesses", || {
        match db.check_witnesses() {
            Ok(ranges) => Ok(ranges),
            Err(error) if is_witness_position_beyond_tree(&error) => {
                let cleared = clear_unmined_note_commitment_positions(db_data_path)?;
                if cleared == 0 {
                    return Err(SyncError::db(format!("check_witnesses: {error}")));
                }

                log::warn!(
                    "[{}] sync: cleared {} stale commitment-tree position(s) from unmined notes after reorg; retrying witness check",
                    elapsed(),
                    cleared,
                );
                db.check_witnesses().map_err(|retry_error| {
                    SyncError::db(format!(
                        "check_witnesses after clearing unmined note positions: {retry_error}"
                    ))
                })
            }
            Err(error) => Err(SyncError::db(format!("check_witnesses: {error}"))),
        }
    })?;

    let Some(nonempty_ranges) = NonEmpty::from_vec(rescan_ranges) else {
        if let Err(e) = with_wallet_db_write_lock("sync_engine.mark_witness_check_clean", || {
            mark_witness_check_clean(db_data_path, current_tip_height)
        }) {
            log::warn!(
                "[{}] sync: witness repair clean marker update failed: {e}",
                elapsed(),
            );
        } else {
            log::info!(
                "[{}] sync: witness repair check found no work; marked clean at height {}",
                elapsed(),
                current_tip_height,
            );
        }
        return Ok(None);
    };

    if *repair_passes_this_run >= MAX_WITNESS_REPAIR_PASSES_PER_RUN {
        let first = describe_block_range(&nonempty_ranges.head);
        return Err(SyncError::db(format!(
            "sync completion blocked: witness repair budget exhausted \
             after {} pass(es); first remaining repair range: {first}",
            MAX_WITNESS_REPAIR_PASSES_PER_RUN,
        )));
    }

    *repair_passes_this_run += 1;
    let pass = *repair_passes_this_run;
    let range_count = 1 + nonempty_ranges.tail.len();
    let repair_blocks = nonempty_ranges.iter().map(block_range_len).sum::<u64>();
    let first = describe_block_range(&nonempty_ranges.head);

    log::warn!(
        "[{}] sync: witness repair pass {}/{} queued {} range(s), {} block(s) \
         (first={first})",
        elapsed(),
        pass,
        MAX_WITNESS_REPAIR_PASSES_PER_RUN,
        range_count,
        repair_blocks,
    );

    with_wallet_db_write_lock("sync_engine.queue_witness_repairs", || {
        db.queue_rescans(nonempty_ranges, ScanPriority::Verify)
            .map_err(|e| SyncError::db(format!("queue witness rescans: {e}")))
    })?;

    let post_ranges = db
        .suggest_scan_ranges()
        .map_err(|e| SyncError::db(format!("suggest_scan_ranges after witness repair: {e}")))?;
    let pending_blocks = pending_scan_blocks(&post_ranges);
    if pending_blocks == 0 && current_tip_height > 0 {
        return Err(SyncError::db(format!(
            "sync completion blocked: witness repair queued ranges but no pending scan \
             ranges were produced at tip {current_tip_height}"
        )));
    }

    Ok(Some(pending_blocks))
}

async fn repair_anchor_root_mismatch_if_needed(
    db_data_path: &str,
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    current_tip_height: u64,
    repair_passes_this_run: &mut u32,
) -> Result<Option<u64>, SyncError> {
    let Some((target_height, anchor_height)) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| SyncError::db(format!("get_target_and_anchor_heights: {e}")))?
    else {
        return Ok(None);
    };

    let local_sapling = db
        .with_sapling_tree_mut(|tree| tree.root_at_checkpoint_id(&anchor_height))
        .map_err(|e| SyncError::db(format!("sapling root at {anchor_height}: {e}")))?;
    let local_orchard = db
        .with_orchard_tree_mut(|tree| tree.root_at_checkpoint_id(&anchor_height))
        .map_err(|e| SyncError::db(format!("orchard root at {anchor_height}: {e}")))?;
    let ironwood_enabled = lwd::ironwood_sync_enabled(network, anchor_height);
    let local_ironwood = if ironwood_enabled {
        Some(
            db.with_ironwood_tree_mut(|tree| tree.root_at_checkpoint_id(&anchor_height))
                .map_err(|e| SyncError::db(format!("ironwood root at {anchor_height}: {e}")))?,
        )
    } else {
        None
    };

    let anchor_chain_state = get_tree_state(client, u32::from(anchor_height) as u64)
        .await?
        .to_chain_state()
        .map_err(|e| SyncError::parse(format!("parse anchor tree state: {e}")))?;
    if anchor_chain_state.block_height() != anchor_height {
        return Err(SyncError::parse(format!(
            "lightwalletd returned tree state for height {}, requested {anchor_height}",
            anchor_chain_state.block_height(),
        )));
    }

    let canonical_sapling = anchor_chain_state.final_sapling_tree().root();
    let canonical_orchard = anchor_chain_state.final_orchard_tree().root();
    let canonical_ironwood =
        ironwood_enabled.then(|| anchor_chain_state.final_ironwood_tree().root());
    let ironwood_roots_match = match (&local_ironwood, &canonical_ironwood) {
        // `with_ironwood_tree_mut` reports `None` when the backend tracks no
        // Ironwood tree; treat that like a missing root so repair kicks in.
        (Some(local), Some(canonical)) => {
            local.as_ref().and_then(|root| root.as_ref()) == Some(canonical)
        }
        (None, None) => true,
        _ => false,
    };
    if local_sapling.as_ref() == Some(&canonical_sapling)
        && local_orchard.as_ref() == Some(&canonical_orchard)
        && ironwood_roots_match
    {
        return Ok(None);
    }

    let start_idx = usize::try_from(*repair_passes_this_run).unwrap_or(usize::MAX);
    let mut last_root_conflict = None;
    for rewind_distance in ANCHOR_ROOT_REPAIR_REWIND_DISTANCES
        .iter()
        .copied()
        .skip(start_idx)
    {
        *repair_passes_this_run += 1;
        let repair_height = anchor_height.saturating_sub(rewind_distance);
        let repair_chain_state = get_tree_state(client, u32::from(repair_height) as u64)
            .await?
            .to_chain_state()
            .map_err(|e| SyncError::parse(format!("parse repair tree state: {e}")))?;
        if repair_chain_state.block_height() != repair_height {
            return Err(SyncError::parse(format!(
                "lightwalletd returned tree state for height {}, requested {repair_height}",
                repair_chain_state.block_height(),
            )));
        }

        log::warn!(
            "[{}] sync: anchor root mismatch at {anchor_height} \
             (target={}, repair_height={repair_height}, pass {}/{}); \
             local_sapling={:?}, canonical_sapling={:?}, local_orchard={:?}, \
             canonical_orchard={:?}, local_ironwood={:?}, canonical_ironwood={:?}; \
             rewinding to canonical chain state",
            elapsed(),
            u32::from(target_height),
            *repair_passes_this_run,
            ANCHOR_ROOT_REPAIR_REWIND_DISTANCES.len(),
            local_sapling,
            canonical_sapling,
            local_orchard,
            canonical_orchard,
            local_ironwood,
            canonical_ironwood,
        );

        let current_tip =
            block_height_from_u64(current_tip_height, "current lightwalletd chain tip")?;
        invalidate_transparent_checks_before_rewind(db_data_path)?;
        let attempt_result = with_wallet_db_write_lock(
            "sync_engine.truncate_to_chain_state.anchor_root_mismatch",
            || -> Result<Result<Vec<ScanRange>, String>, SyncError> {
                ledger_discovery::invalidate_for_rewind(db_data_path, db, repair_height)
                    .map_err(|e| SyncError::db(format!("invalidate transparent refresh: {e}")))?;
                match db.truncate_to_chain_state(repair_chain_state.clone()) {
                    Ok(()) => {}
                    Err(e) if is_commitment_tree_root_conflict(&e) => {
                        return Ok(Err(format!("{e}")));
                    }
                    Err(e) if is_sqlite_lock_contention(&e) => {
                        return Err(SyncError::other(format!(
                            "truncate_to_chain_state({repair_height}): SQLite lock contention: {e}"
                        )));
                    }
                    Err(e) => {
                        return Err(SyncError::db(format!(
                            "truncate_to_chain_state({repair_height}): {e}"
                        )));
                    }
                }
                db.update_chain_tip(current_tip).map_err(|e| {
                    SyncError::db(format!(
                        "update_chain_tip({current_tip_height}) after anchor root repair: {e}"
                    ))
                })?;
                db.suggest_scan_ranges()
                    .map_err(|e| {
                        SyncError::db(format!("suggest_scan_ranges after anchor root repair: {e}"))
                    })
                    .map(Ok)
            },
        )?;

        let post_rewind_ranges = match attempt_result {
            Ok(ranges) => ranges,
            Err(conflict) => {
                log::warn!(
                    "[{}] sync: anchor root repair at {repair_height} conflicted \
                     with an existing tree root; trying a deeper repair if available ({conflict})",
                    elapsed(),
                );
                last_root_conflict = Some(conflict);
                continue;
            }
        };

        let pending_blocks = pending_scan_blocks(&post_rewind_ranges);
        let first_pending =
            first_pending_scan_range(&post_rewind_ranges).unwrap_or_else(|| "none".into());
        log::info!(
            "[{}] sync: anchor root repair queued {pending_blocks} block(s) \
             (first_pending={first_pending})",
            elapsed(),
        );

        let anchor_height_u64 = u32::from(anchor_height) as u64;
        if pending_blocks == 0 && anchor_height_u64 < current_tip_height {
            return Err(SyncError::continuity(
                current_tip_height,
                format!(
                    "anchor root repair at {anchor_height} produced no pending scan \
                     ranges, but lightwalletd tip is {current_tip_height}"
                ),
            ));
        }

        return Ok(Some(pending_blocks));
    }

    Err(SyncError::db(format!(
        "sync completion blocked: anchor root repair budget exhausted \
         after {} pass(es) at anchor {anchor_height}{}",
        ANCHOR_ROOT_REPAIR_REWIND_DISTANCES.len(),
        last_root_conflict
            .as_deref()
            .map(|e| format!("; last root conflict: {e}"))
            .unwrap_or_default(),
    )))
}

fn transparent_utxo_query_network(network: WalletNetwork) -> WalletNetwork {
    #[cfg(ironwood_masquerade)]
    if network == WalletNetwork::Main {
        return WalletNetwork::Test;
    }

    network
}

fn transparent_address_for_query(
    address: &str,
    source_network: WalletNetwork,
    query_network: WalletNetwork,
) -> Result<String, String> {
    if source_network == query_network {
        return Ok(address.to_string());
    }

    TransparentAddress::decode(&source_network, address)
        .map(|address| address.encode(&query_network))
        .map_err(|e| format!("decode transparent address {address}: {e}"))
}

struct TransparentRefresh {
    addresses: Vec<String>,
    start_height: BlockHeight,
    label: String,
    account_uuid: String,
    completion: Option<TransparentRefreshCompletion>,
}

struct TransparentRefreshCompletion {
    non_external_addresses: Vec<String>,
    internal_sweep: bool,
    child_indices: Vec<u32>,
    next_sweep_offset: Option<usize>,
}

struct DownloadedTransparentRefresh {
    refresh: TransparentRefresh,
    outputs: Vec<WalletTransparentOutput<AccountUuid>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransparentRefreshOutcome {
    Completed,
    Cancelled,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransparentAccountSelection<'a> {
    All,
    Only(&'a str),
    Except(&'a str),
}

impl TransparentAccountSelection<'_> {
    fn includes(self, account_uuid: &str) -> bool {
        match self {
            Self::All => true,
            Self::Only(selected) => account_uuid == selected,
            Self::Except(selected) => account_uuid != selected,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct TransparentRefreshSummary {
    matched_accounts: usize,
    /// The transparent policy withheld the public UTXO lookup entirely.
    withheld: bool,
}

async fn refresh_utxos(
    client: &mut CompactTxStreamerClient<Channel>,
    db_data_path: &str,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    tip_height: BlockHeight,
    account_selection: TransparentAccountSelection<'_>,
    priority_account_target: Option<&ActiveSyncAccountTarget>,
    received_outputs_seen: &mut bool,
    progress: Option<&(dyn Fn(u64, u64) + Sync)>,
    should_exit: &impl Fn() -> bool,
) -> Result<TransparentRefreshSummary, SyncError> {
    let mut refreshes = Vec::new();
    let mut summary = TransparentRefreshSummary::default();
    // GetAddressUtxos discloses every refreshed address, so it is authorized
    // under the policy the sync captured. When withheld, no query height
    // advances, so a later authorized refresh still covers the gap.
    let gate = TransparentLookupGate::for_sync(
        policy.public_transparent_lookups(db)?,
        db_data_path,
        network,
    )?;
    if !gate.is_allowed() {
        log::info!(
            "[{}] sync: transparent policy withholds public UTXO refresh",
            elapsed(),
        );
        summary.withheld = true;
        return Ok(summary);
    }
    for account_id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(format!("get_account_ids: {e}")))?
    {
        if should_exit() {
            return Ok(summary);
        }
        let account_uuid = account_id.expose_uuid().to_string();
        if !account_selection.includes(&account_uuid) {
            continue;
        }
        summary.matched_accounts += 1;
        let planning_started = std::time::Instant::now();
        let first_refresh = refreshes.len();
        let safety_start_height = db
            .utxo_query_height(account_id)
            .map_err(|e| SyncError::db(format!("utxo_query_height: {e}")))?;
        let account_birthday_height = account_birthday_height(db_data_path, account_id)
            .unwrap_or_else(|e| {
                log::warn!(
                    "sync: failed to read account {} birthday for transparent UTXO sweep: {}",
                    account_uuid,
                    e
                );
                u64::from(u32::from(safety_start_height))
            });

        let is_ledger = db
            .get_account(account_id)
            .map_err(|e| SyncError::db(e.to_string()))?
            .is_some_and(|a| {
                keys::hardware_signer_kind(zcash_client_backend::data_api::Account::source(&a))
                    == Some(keys::HardwareSignerKind::Ledger)
            });
        let account_birthday_height = if is_ledger {
            0
        } else {
            account_birthday_height
        };
        let safety_start_height = if is_ledger {
            BlockHeight::from_u32(0)
        } else {
            safety_start_height
        };

        let (external_sweep_due, internal_sweep_due) = if is_ledger {
            transparent_receive_cache::ledger_sweep_due(db_data_path, network, &account_uuid)
                .unwrap_or_else(|e| {
                    log::warn!(
                        "transparent sweep schedule unavailable for account {}: {}",
                        account_uuid,
                        e
                    );
                    (true, true)
                })
        } else {
            (true, true)
        };
        let external_recent_limit = if is_ledger {
            10
        } else {
            TRANSPARENT_UTXO_RECENT_EXTERNAL_LIMIT
        };

        let query_network = transparent_utxo_query_network(network);
        let mut external_addresses = keys::get_external_transparent_receive_addresses_from_db(
            db_data_path,
            network,
            Some(&account_uuid),
        )
        .map_err(|e| SyncError::db(format!("external transparent receive addresses: {e}")))?;
        for address in &mut external_addresses {
            address.address =
                transparent_address_for_query(&address.address, network, query_network)
                    .map_err(SyncError::parse)?;
        }
        let external_batches = match transparent_receive_cache::plan_external_utxo_refresh(
            db_data_path,
            network,
            &account_uuid,
            &external_addresses,
            account_birthday_height,
            u64::from(u32::from(safety_start_height)),
            external_recent_limit,
            if external_sweep_due {
                TRANSPARENT_UTXO_SWEEP_EXTERNAL_LIMIT
            } else {
                0
            },
        ) {
            Ok(batches) => batches,
            Err(e) => {
                log::warn!(
                    "transparent receive cache: failed to plan bounded UTXO refresh for account {}; falling back to full external refresh: {}",
                    account_uuid,
                    e
                );
                vec![transparent_receive_cache::TransparentUtxoRefreshBatch {
                    addresses: external_addresses
                        .iter()
                        .filter(|address| !address.address.is_empty())
                        .map(|address| address.address.clone())
                        .collect(),
                    child_indices: Vec::new(),
                    start_height: 0,
                    next_sweep_offset: None,
                }]
            }
        };

        for (batch_index, batch) in external_batches.into_iter().enumerate() {
            if should_exit() {
                return Ok(summary);
            }
            let start_height = block_height_from_u64(
                batch.start_height,
                "transparent receive UTXO batch start height",
            )?;
            let label = if batch.next_sweep_offset.is_some() {
                format!("transparent external UTXOs sweep batch {}", batch_index + 1)
            } else {
                "transparent external UTXOs recent batch".to_string()
            };
            refreshes.push(TransparentRefresh {
                addresses: batch.addresses,
                start_height,
                label,
                account_uuid: account_uuid.clone(),
                completion: Some(TransparentRefreshCompletion {
                    non_external_addresses: Vec::new(),
                    internal_sweep: false,
                    child_indices: batch.child_indices,
                    next_sweep_offset: batch.next_sweep_offset,
                }),
            });
        }

        let external_selected = external_addresses
            .iter()
            .map(|address| address.address.as_str())
            .collect::<BTreeSet<_>>();
        let mut internal_addresses = std::collections::HashSet::new();
        let receivers = db
            .get_transparent_receivers(account_id, true, true)
            .map_err(|e| SyncError::db(format!("get_transparent_receivers: {e}")))?;
        if is_ledger {
            let internal = receivers
                .iter()
                .filter(|(_, meta)| meta.scope() == Some(TransparentKeyScope::INTERNAL))
                .map(|(addr, meta)| {
                    meta.address_index()
                        .map(|index| (index.index(), addr.encode(&query_network)))
                        .ok_or_else(|| SyncError::db("Ledger internal address has no child index"))
                })
                .collect::<Result<Vec<_>, _>>()?;
            let batches = transparent_receive_cache::plan_internal_utxo_refresh(
                db_data_path,
                network,
                &account_uuid,
                &internal,
                5,
                if internal_sweep_due { TRANSPARENT_UTXO_SWEEP_EXTERNAL_LIMIT } else { 0 },
            )
            .unwrap_or_else(|e| {
                // Like the existing external fallback, cache failure must not
                // make wallet funds inaccessible. This exceptional path retains
                // the pre-optimization complete snapshot and logs its cost.
                log::warn!("transparent receive cache: failed to plan internal refresh for account {}; falling back to full internal refresh: {}", account_uuid, e);
                vec![transparent_receive_cache::TransparentUtxoRefreshBatch {
                    addresses: internal.iter().map(|(_, address)| address.clone()).collect(),
                    child_indices: Vec::new(), start_height: 0, next_sweep_offset: None,
                }]
            });
            for batch in batches {
                refreshes.push(TransparentRefresh {
                    addresses: batch.addresses.clone(),
                    start_height: block_height_from_u64(batch.start_height, "internal UTXO start")?,
                    label: "transparent internal UTXOs".into(),
                    account_uuid: account_uuid.clone(),
                    completion: Some(TransparentRefreshCompletion {
                        non_external_addresses: batch.addresses.clone(),
                        internal_sweep: true,
                        child_indices: batch.child_indices,
                        next_sweep_offset: batch.next_sweep_offset,
                    }),
                });
            }
        }
        let non_external_addresses: Vec<String> = receivers
            .into_iter()
            .filter(|(_, metadata)| metadata.scope() != Some(TransparentKeyScope::EXTERNAL))
            .map(|(addr, metadata)| {
                let query_address = addr.encode(&query_network);
                if metadata.scope() == Some(TransparentKeyScope::INTERNAL) {
                    internal_addresses.insert(query_address.clone());
                }
                query_address
            })
            .filter(|addr| !external_selected.contains(addr.as_str()))
            .collect();

        let non_external_batches = transparent_receive_cache::plan_non_external_utxo_refresh(
            db_data_path,
            network,
            &account_uuid,
            &non_external_addresses,
            account_birthday_height,
            u64::from(u32::from(safety_start_height)),
            &internal_addresses,
            u64::from(u32::from(tip_height)),
        )
        .unwrap_or_else(|error| {
            log::warn!("non-external UTXO planning failed; querying from genesis: {error}");
            if non_external_addresses.is_empty() {
                Vec::new()
            } else {
                vec![(non_external_addresses.clone(), 0)]
            }
        });
        for (mut addresses, start) in non_external_batches {
            if is_ledger {
                addresses.retain(|address| !internal_addresses.contains(address));
            }
            if addresses.is_empty() {
                continue;
            }
            refreshes.push(TransparentRefresh {
                completion: Some(TransparentRefreshCompletion {
                    non_external_addresses: addresses.clone(),
                    internal_sweep: false,
                    child_indices: Vec::new(),
                    next_sweep_offset: None,
                }),
                addresses,
                start_height: block_height_from_u64(start, "non-external UTXO start")?,
                label: "transparent non-external UTXOs".to_string(),
                account_uuid: account_uuid.clone(),
            });
        }
        log::info!(
            "transparent refresh plan: account={} rpc_count={} addresses={} elapsed_ms={}",
            account_id.expose_uuid(),
            refreshes.len() - first_refresh,
            refreshes[first_refresh..]
                .iter()
                .map(|r| r.addresses.len())
                .sum::<usize>(),
            planning_started.elapsed().as_millis(),
        );
    }

    let total_refreshes = refreshes.len() as u64;
    if let Some(progress) = progress {
        progress(0, total_refreshes);
    }
    let mut completed_refreshes = 0u64;
    let download_client = client.clone();
    let download_gate = gate.clone();
    let outcome = process_bounded_transparent_refreshes(
        refreshes,
        move |refresh| {
            download_transparent_outputs(
                download_client.clone(),
                download_gate.clone(),
                refresh,
                should_exit,
            )
        },
        |downloaded| {
            let downloaded_count = downloaded.len() as u64;
            let received_outputs = downloaded.iter().any(|batch| !batch.outputs.is_empty());
            let completion_authorized = std::cell::Cell::new(false);
            store_then_mark_transparent_refreshes(
                downloaded,
                |downloaded| {
                    store_transparent_outputs(db, downloaded)?;
                    // Outputs already received are stored, but a group answered
                    // after a transition does not advance refresh metadata, so
                    // a later pass under the new policy re-covers it.
                    completion_authorized.set(gate.permits()?);
                    Ok(())
                },
                |downloaded| {
                    if completion_authorized.get() {
                        update_transparent_refresh_cache_metadata(
                            db_data_path,
                            network,
                            tip_height,
                            downloaded,
                        )
                    }
                },
            )?;
            *received_outputs_seen |= received_outputs;
            completed_refreshes = completed_refreshes.saturating_add(downloaded_count);
            if let Some(progress) = progress {
                progress(completed_refreshes, total_refreshes);
            }
            Ok(())
        },
        |pending| prioritize_pending_transparent_refreshes(pending, priority_account_target),
        should_exit,
    )
    .await?;
    match outcome {
        TransparentRefreshOutcome::Completed => {}
        TransparentRefreshOutcome::Cancelled => log::info!(
            "[{}] sync: exiting before transparent UTXO database update",
            elapsed(),
        ),
    }

    Ok(summary)
}

fn prioritize_pending_transparent_refreshes(
    pending: &mut VecDeque<TransparentRefresh>,
    priority_account_target: Option<&ActiveSyncAccountTarget>,
) {
    let Some(active_account_uuid) = current_active_sync_account(priority_account_target) else {
        return;
    };
    let Some(previous_position) = pending
        .iter()
        .position(|refresh| refresh.account_uuid == active_account_uuid)
    else {
        return;
    };
    // Stable sorting keeps every other account in its existing order. This is
    // evaluated only between bounded groups, so requests already in flight are
    // allowed to finish and commit normally.
    pending
        .make_contiguous()
        .sort_by_key(|refresh| refresh.account_uuid != active_account_uuid);
    if previous_position > 0 {
        log::info!(
            "[{}] sync: moved active account {} ahead of {} pending transparent refresh(es)",
            elapsed(),
            active_account_uuid,
            previous_position,
        );
    }
}

fn update_transparent_refresh_cache_metadata(
    db_data_path: &str,
    network: WalletNetwork,
    tip_height: BlockHeight,
    downloaded: &DownloadedTransparentRefresh,
) {
    if !downloaded.outputs.is_empty() {
        mark_transparent_receive_cache_dirty(db_data_path, &downloaded.refresh.account_uuid);
    }
    if let Some(completion) = downloaded.refresh.completion.as_ref() {
        if !completion.non_external_addresses.is_empty() {
            let result = if completion.internal_sweep {
                transparent_receive_cache::mark_non_external_utxo_refresh_complete_with_sweep(
                    db_data_path,
                    network,
                    &downloaded.refresh.account_uuid,
                    &completion.non_external_addresses,
                    u64::from(u32::from(tip_height)) + 1,
                    completion.next_sweep_offset,
                )
            } else {
                transparent_receive_cache::mark_non_external_utxo_refresh_complete(
                    db_data_path,
                    network,
                    &downloaded.refresh.account_uuid,
                    &completion.non_external_addresses,
                    u64::from(u32::from(tip_height)) + 1,
                )
            };
            if let Err(error) = result {
                log::warn!("failed to mark non-external UTXO lookup complete: {error}");
            }
        }
        if !completion.internal_sweep {
            if let Err(e) = transparent_receive_cache::mark_utxo_refresh_batch_complete(
                db_data_path,
                network,
                &downloaded.refresh.account_uuid,
                &completion.child_indices,
                u64::from(u32::from(tip_height)) + 1,
                completion.next_sweep_offset,
            ) {
                log::warn!(
                    "transparent receive cache: failed to mark UTXO batch complete for \
                 account {}: {}",
                    downloaded.refresh.account_uuid,
                    e,
                );
            }
        }
    }
}

fn mark_transparent_receive_cache_dirty(db_data_path: &str, account_uuid: &str) {
    if let Err(e) = transparent_receive_cache::mark_account_dirty(db_data_path, account_uuid) {
        log::warn!(
            "transparent receive cache: failed to mark account {} dirty: {}",
            account_uuid,
            e
        );
    }
}

fn account_birthday_height(db_path: &str, account_id: AccountUuid) -> Result<u64, SyncError> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))
        .map_err(|e| SyncError::db(format!("open DB for account birthday: {e}")))?;
    let birthday: i64 = conn
        .query_row(
            "SELECT birthday_height FROM accounts WHERE uuid = ?1",
            params![account_id.expose_uuid().as_bytes().as_slice()],
            |row| row.get(0),
        )
        .map_err(|e| SyncError::db(format!("account birthday query: {e}")))?;
    u64::try_from(birthday)
        .map_err(|_| SyncError::parse(format!("invalid account birthday height: {birthday}")))
}

fn block_height_from_u64(height: u64, label: &str) -> Result<BlockHeight, SyncError> {
    let height = u32::try_from(height)
        .map_err(|_| SyncError::parse(format!("{label} exceeded u32: {height}")))?;
    Ok(BlockHeight::from_u32(height))
}

async fn process_bounded_transparent_refreshes<R, D, E, Download, DownloadFuture, Persist, Exit>(
    refreshes: Vec<R>,
    download: Download,
    mut persist: Persist,
    mut prioritize_pending: impl FnMut(&mut VecDeque<R>),
    should_exit: &Exit,
) -> Result<TransparentRefreshOutcome, E>
where
    Download: Fn(R) -> DownloadFuture,
    DownloadFuture: Future<Output = Result<Option<D>, E>>,
    Persist: FnMut(Vec<D>) -> Result<(), E>,
    Exit: Fn() -> bool,
{
    let mut refreshes = VecDeque::from(refreshes);
    loop {
        if should_exit() {
            return Ok(TransparentRefreshOutcome::Cancelled);
        }

        prioritize_pending(&mut refreshes);
        let group = (0..MAX_CONCURRENT_TRANSPARENT_UTXO_STREAMS)
            .filter_map(|_| refreshes.pop_front())
            .collect::<Vec<_>>();
        if group.is_empty() {
            return Ok(TransparentRefreshOutcome::Completed);
        }

        let downloaded_result = download_transparent_refresh_group(group, &download).await;
        // Cancellation and mode handoff win if they race a network error.
        // No database or cache mutation is allowed after either signal.
        if should_exit() {
            return Ok(TransparentRefreshOutcome::Cancelled);
        }
        let downloaded = downloaded_result?;
        let Some(downloaded) = downloaded.into_iter().collect::<Option<Vec<_>>>() else {
            return Ok(TransparentRefreshOutcome::Cancelled);
        };

        persist(downloaded)?;
    }
}

async fn download_transparent_refresh_group<R, D, E, Download, DownloadFuture>(
    refreshes: Vec<R>,
    download: &Download,
) -> Result<Vec<Option<D>>, E>
where
    Download: Fn(R) -> DownloadFuture,
    DownloadFuture: Future<Output = Result<Option<D>, E>>,
{
    let mut downloaded = stream::iter(refreshes.into_iter().enumerate())
        .map(|(position, refresh)| {
            let future = download(refresh);
            async move { future.await.map(|downloaded| (position, downloaded)) }
        })
        .buffer_unordered(MAX_CONCURRENT_TRANSPARENT_UTXO_STREAMS)
        .try_collect::<Vec<_>>()
        .await?;
    downloaded.sort_unstable_by_key(|(position, _)| *position);
    Ok(downloaded
        .into_iter()
        .map(|(_, downloaded)| downloaded)
        .collect())
}

fn store_then_mark_transparent_refreshes<T, E>(
    downloaded: Vec<T>,
    store: impl FnOnce(&[T]) -> Result<(), E>,
    mut mark_cache_metadata: impl FnMut(&T),
) -> Result<(), E> {
    store(&downloaded)?;
    for item in &downloaded {
        mark_cache_metadata(item);
    }
    Ok(())
}

fn store_transparent_outputs(
    db: &mut WalletDatabase,
    downloaded: &[DownloadedTransparentRefresh],
) -> Result<(), SyncError> {
    if downloaded.iter().all(|batch| batch.outputs.is_empty()) {
        return Ok(());
    }

    with_wallet_db_write_lock("sync_engine.put_received_transparent_utxos", || {
        db.transactionally(|tx_db| -> Result<(), SqliteClientError> {
            for batch in downloaded {
                for output in &batch.outputs {
                    tx_db.put_received_transparent_utxo(output)?;
                    // The UTXO RPC does not provide full transaction data. Fetch it
                    // once through enhancement so the backend registers spend
                    // detection (and recognizes coinbase outputs) before we rely
                    // on incremental lookups. Queue insertion shares this commit.
                    // The backend skips transactions whose raw bytes are already
                    // stored; avoid decoding those bytes on every UTXO refresh.
                    tx_db.queue_tx_retrieval(std::iter::once(*output.outpoint().txid()), None)?;
                }
            }
            Ok(())
        })
        .map_err(|e| SyncError::db(format!("put_received_transparent_utxos: {e}")))
    })
}

async fn download_transparent_outputs(
    mut client: CompactTxStreamerClient<Channel>,
    gate: TransparentLookupGate,
    mut refresh: TransparentRefresh,
    should_exit: &impl Fn() -> bool,
) -> Result<Option<DownloadedTransparentRefresh>, SyncError> {
    if should_exit() {
        return Ok(None);
    }
    if refresh.addresses.is_empty() {
        return Ok(Some(DownloadedTransparentRefresh {
            refresh,
            outputs: Vec::new(),
        }));
    }

    let started = std::time::Instant::now();
    let address_count = refresh.addresses.len();
    log::info!(
        "[{}] sync: refreshing {} for account {} from height {} ({} addresses)",
        elapsed(),
        refresh.label,
        refresh.account_uuid,
        u32::from(refresh.start_height),
        refresh.addresses.len(),
    );

    let addresses = std::mem::take(&mut refresh.addresses);
    let stream = tokio::select! {
        biased;
        _ = watch_for_exit(should_exit) => {
            log::info!(
                "[{}] sync: exiting during {} transparent UTXO stream start",
                elapsed(),
                refresh.label,
            );
            return Ok(None);
        }
        result = gate.address_utxos(
            &mut client,
            addresses,
            refresh.start_height,
        ) => result?,
    };
    // Withheld: nothing was sent, and the group is not committed.
    let Some(mut stream) = stream else {
        log::info!(
            "[{}] sync: transparent policy withholds {}",
            elapsed(),
            refresh.label,
        );
        return Ok(None);
    };

    let mut outputs = Vec::new();
    let mut response_bytes = 0usize;
    loop {
        let reply = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => {
                log::info!(
                    "[{}] sync: exiting during {} transparent UTXO refresh",
                    elapsed(),
                    refresh.label,
                );
                return Ok(None);
            }
            result = next_stream_message(&mut stream, "get_address_utxos_stream") => result?,
        };
        let Some(reply) = reply else {
            break;
        };
        response_bytes += prost::Message::encoded_len(&reply);
        let txid: [u8; 32] = reply
            .txid
            .try_into()
            .map_err(|_| SyncError::parse("transparent UTXO txid was not 32 bytes"))?;
        let index = u32::try_from(reply.index).map_err(|_| {
            SyncError::parse(format!("invalid transparent UTXO index: {}", reply.index))
        })?;
        let height = u32::try_from(reply.height).map_err(|_| {
            SyncError::parse(format!("invalid transparent UTXO height: {}", reply.height))
        })?;
        let value = Zatoshis::from_nonnegative_i64(reply.value_zat).map_err(|_| {
            SyncError::parse(format!(
                "invalid transparent UTXO value: {}",
                reply.value_zat
            ))
        })?;

        outputs.push(
            WalletTransparentOutput::from_parts(
                OutPoint::new(txid, index),
                TxOut::new(value, Script(script::Code(reply.script))),
                Some(BlockHeight::from_u32(height)),
                None,
                None,
                None,
            )
            .ok_or_else(|| {
                SyncError::parse("transparent UTXO script did not decode to a wallet address")
            })?,
        );
    }

    log::info!(
        "transparent refresh: account={} batch={:?} addresses={} rpc_count=1 outputs={} response_bytes={} elapsed_ms={}",
        refresh.account_uuid, refresh.label,
        address_count, outputs.len(), response_bytes, started.elapsed().as_millis(),
    );
    Ok(Some(DownloadedTransparentRefresh { refresh, outputs }))
}

pub(crate) async fn watch_for_exit(should_exit: &impl Fn() -> bool) {
    while !should_exit() {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
}

/// `request`'s output, or `None` once cancellation or a mode handoff wins. A
/// request still waiting on a slow server would otherwise hold the session
/// until its own deadline.
async fn unless_exiting<T>(
    should_exit: &impl Fn() -> bool,
    request: impl Future<Output = T>,
) -> Option<T> {
    tokio::select! {
        biased;
        _ = watch_for_exit(should_exit) => None,
        output = request => Some(output),
    }
}

fn needs_completion_enhancement_pass(enhancement_after_scan: bool) -> bool {
    !enhancement_after_scan
}

/// Discard a completed tip RPC result when cancellation or a mode handoff won
/// the race. Callers must apply this before interpreting the result or mutating
/// the wallet DB.
fn tip_rpc_result_unless_exiting<T>(
    result: Result<T, SyncError>,
    should_exit: bool,
) -> Option<Result<T, SyncError>> {
    (!should_exit).then_some(result)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum RefreshedTipRelation {
    Unchanged,
    UnchangedUnverified,
    Advanced,
    Reorg,
    ServerBehind,
}

fn classify_refreshed_tip(
    current_height: u64,
    stored_hash: Option<BlockHash>,
    fresh_height: u64,
    fresh_hash: &[u8],
) -> Result<RefreshedTipRelation, SyncError> {
    // A lower response is never authoritative enough to prove a reorg. The
    // server may be a lagging replica that is still serving an orphaned fork,
    // so even a hash mismatch at its tip must not trigger a wallet rewind.
    if fresh_height < current_height {
        return Ok(RefreshedTipRelation::ServerBehind);
    }

    // `BlockID.hash` is optional in the lightwalletd protocol. Preserve
    // height-only compatibility when the server omits it, but reject a
    // non-empty malformed value instead of silently treating it as absent.
    let fresh_hash = if fresh_hash.is_empty() {
        None
    } else {
        Some(BlockHash::try_from_slice(fresh_hash).ok_or_else(|| {
            SyncError::net(format!(
                "get_latest_block returned a {}-byte hash at height {fresh_height}",
                fresh_hash.len(),
            ))
        })?)
    };

    if fresh_height > current_height {
        return Ok(RefreshedTipRelation::Advanced);
    }

    if stored_hash.is_some() && fresh_hash.is_none() {
        return Err(SyncError::net(format!(
            "a block hash is required to validate the stored tip at height {fresh_height}"
        )));
    }

    Ok(match (stored_hash, fresh_hash) {
        (Some(stored_hash), Some(fresh_hash)) if stored_hash != fresh_hash => {
            RefreshedTipRelation::Reorg
        }
        (None, _) if current_height > 0 => RefreshedTipRelation::UnchangedUnverified,
        _ => RefreshedTipRelation::Unchanged,
    })
}

async fn classify_refreshed_tip_with_fallback(
    client: &mut CompactTxStreamerClient<Channel>,
    current_height: u64,
    stored_hash: Option<BlockHash>,
    fresh_height: u64,
    fresh_hash: &[u8],
) -> Result<RefreshedTipRelation, SyncError> {
    if tip_hash_fallback_required(current_height, stored_hash, fresh_height, fresh_hash) {
        let compact_block_hash = get_compact_block_hash(client, fresh_height).await?;
        classify_refreshed_tip(
            current_height,
            stored_hash,
            fresh_height,
            &compact_block_hash.0,
        )
    } else {
        classify_refreshed_tip(current_height, stored_hash, fresh_height, fresh_hash)
    }
}

fn tip_hash_fallback_required(
    current_height: u64,
    stored_hash: Option<BlockHash>,
    fresh_height: u64,
    fresh_hash: &[u8],
) -> bool {
    fresh_height == current_height && stored_hash.is_some() && fresh_hash.is_empty()
}

fn stored_hash_for_refreshed_tip(
    db: &WalletDatabase,
    current_height: u64,
    fresh_height: u64,
) -> Result<Option<BlockHash>, SyncError> {
    if fresh_height != current_height {
        return Ok(None);
    }

    let fresh_height = block_height_from_u64(fresh_height, "refreshed lightwalletd chain tip")?;
    db.get_block_hash(fresh_height)
        .map_err(|e| SyncError::db(format!("get_block_hash({fresh_height}): {e}")))
}

fn lagging_lightwalletd_tip(current_height: u64, fresh_height: u64) -> SyncError {
    SyncError::net(format!(
        "lightwalletd tip {fresh_height} is behind wallet DB tip {current_height} \
         without evidence of a reorg"
    ))
}

fn should_refresh_tip_before_completion(
    validation_required: bool,
    validation_age: std::time::Duration,
) -> bool {
    validation_required || validation_age >= FINAL_TIP_REFRESH_MIN_AGE
}

fn invalidate_transparent_checks_before_rewind(db_data_path: &str) -> Result<(), SyncError> {
    transparent_receive_cache::invalidate_utxo_checks(db_data_path)
        .map_err(|error| SyncError::db(format!("invalidate UTXO checks before rewind: {error}")))
}

/// A successful reorg rewind permits one new private recovery allowance at
/// the replacement tip. Endpoint lag and failed rewinds must not call this.
/// Holds, service-requested waits and content-failure counters are unchanged.
fn reset_private_recovery_after_reorg(db_data_path: &str, tip: u64) {
    enhancement::content_failures::after_reorg(db_data_path, tip);
    transparent_ledger::clear_recovery_tip(db_data_path);
}

fn truncate_wallet_to_height(
    db_data_path: &str,
    db: &mut WalletDatabase,
    requested_height: BlockHeight,
    fresh_tip_height: BlockHeight,
    operation: &'static str,
) -> Result<BlockHeight, SyncError> {
    invalidate_transparent_checks_before_rewind(db_data_path)?;
    with_wallet_db_write_lock(operation, || {
        truncate_wallet_with(db_data_path, requested_height, fresh_tip_height, |height| {
            ledger_discovery::truncate(db_data_path, db, height)
        })
    })
}

fn truncate_wallet_with(
    db_data_path: &str,
    requested_height: BlockHeight,
    fresh_tip_height: BlockHeight,
    mut truncate: impl FnMut(BlockHeight) -> Result<BlockHeight, SqliteClientError>,
) -> Result<BlockHeight, SyncError> {
    let actual_height = match truncate(requested_height) {
        Ok(height) => validate_reorg_rewind_height(height, fresh_tip_height),
        Err(SqliteClientError::RequestedRewindInvalid {
            safe_rewind_height: Some(safe_height),
            ..
        }) => {
            // Validate before calling `truncate_to_height` again. A checkpoint
            // at or above the divergent server tip cannot repair continuity,
            // and must not trigger a fallback DB mutation.
            validate_reorg_rewind_height(safe_height, fresh_tip_height)?;
            log::warn!(
                "[{}] sync: rewind target {requested_height} is not safely \
                 representable; retrying at reported safe height {safe_height}",
                elapsed(),
            );
            let actual_height = truncate(safe_height).map_err(|e| {
                if is_sqlite_lock_contention(&e) {
                    SyncError::other(format!(
                        "truncate_to_height({safe_height}): SQLite lock contention: {e}"
                    ))
                } else {
                    SyncError::db(format!("truncate_to_height({safe_height}): {e}"))
                }
            })?;
            validate_reorg_rewind_height(actual_height, fresh_tip_height)
        }
        Err(SqliteClientError::RequestedRewindInvalid {
            safe_rewind_height: None,
            ..
        }) => Err(SyncError::db(format!(
            "truncate_to_height({requested_height}): no safe rewind height"
        ))),
        Err(e) if is_sqlite_lock_contention(&e) => Err(SyncError::other(format!(
            "truncate_to_height({requested_height}): SQLite lock contention: {e}"
        ))),
        Err(e) => Err(SyncError::db(format!(
            "truncate_to_height({requested_height}): {e}"
        ))),
    }?;
    reset_private_recovery_after_reorg(db_data_path, u64::from(u32::from(fresh_tip_height)));
    Ok(actual_height)
}

fn validate_reorg_rewind_height(
    rewind_height: BlockHeight,
    fresh_tip_height: BlockHeight,
) -> Result<BlockHeight, SyncError> {
    if rewind_height < fresh_tip_height {
        Ok(rewind_height)
    } else {
        Err(SyncError::db(format!(
            "confirmed reorg could not rewind below tip {fresh_tip_height}; \
             candidate height was {rewind_height}"
        )))
    }
}

fn confirmed_reorg_rewind_target(fresh_tip_height: BlockHeight) -> Result<BlockHeight, SyncError> {
    u32::from(fresh_tip_height)
        .checked_sub(1)
        .map(BlockHeight::from_u32)
        .ok_or_else(|| SyncError::net("confirmed reorg cannot rewind below genesis"))
}

fn rewind_for_confirmed_tip_reorg(
    db_data_path: &str,
    db: &mut WalletDatabase,
    fresh_tip_height: u64,
) -> Result<(BlockHeight, Vec<ScanRange>, u64), SyncError> {
    let fresh_height = block_height_from_u64(fresh_tip_height, "reorg lightwalletd chain tip")?;
    let requested_height = confirmed_reorg_rewind_target(fresh_height)?;
    let actual_height = truncate_wallet_to_height(
        db_data_path,
        db,
        requested_height,
        fresh_height,
        "sync_engine.truncate_to_height.tip_reorg",
    )?;
    let ranges = with_wallet_db_write_lock(
        "sync_engine.update_chain_tip.tip_reorg",
        || -> Result<Vec<ScanRange>, SyncError> {
            db.update_chain_tip(fresh_height).map_err(|e| {
                SyncError::db(format!(
                    "update_chain_tip({fresh_height}) after confirmed reorg: {e}"
                ))
            })?;
            db.suggest_scan_ranges().map_err(|e| {
                SyncError::db(format!("suggest_scan_ranges after confirmed reorg: {e}"))
            })
        },
    )?;
    let pending_blocks = pending_scan_blocks(&ranges);

    if pending_blocks == 0 {
        return Err(SyncError::continuity(
            fresh_tip_height,
            format!(
                "confirmed reorg rewind to {actual_height} produced no pending \
                 scan ranges"
            ),
        ));
    }

    Ok((actual_height, ranges, pending_blocks))
}

type ScanBatch = (block_source::MemoryBlockSource, chain::ChainState);

async fn join_scan_batch_inputs<BlockSourceT, ChainStateT, BlockFuture, StateFuture>(
    blocks: BlockFuture,
    chain_state: StateFuture,
) -> Result<(BlockSourceT, ChainStateT), SyncError>
where
    BlockFuture: Future<Output = Result<BlockSourceT, SyncError>>,
    StateFuture: Future<Output = Result<ChainStateT, SyncError>>,
{
    tokio::try_join!(blocks, chain_state)
}

/// Downloads one compact-block batch and its preceding chain state in
/// parallel. If independently served responses do not form one sequence, the
/// tree state is fetched again by the first block's exact predecessor hash.
async fn download_scan_batch(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
    network: WalletNetwork,
) -> Result<ScanBatch, SyncError> {
    let mut tree_state_client = client.clone();
    let local_state = local_batch_start_state(network, start)?;
    let uses_compiled_checkpoint =
        local_state.is_some() && !should_use_empty_chain_state(&network, start)?;
    let tree_state = async move {
        match local_state {
            Some(state) => Ok(state),
            None => get_tree_state(&mut tree_state_client, u64::from(u32::from(start - 1)))
                .await?
                .to_chain_state()
                .map_err(|e| SyncError::parse(format!("parse tree state: {e}"))),
        }
    };

    let (block_source, from_state) =
        join_scan_batch_inputs(download_blocks(client, start, end, network), tree_state).await?;
    if block_source.starts_after(&from_state) {
        return Ok((block_source, from_state));
    }
    if uses_compiled_checkpoint {
        // A forked or non-mainnet server behind a `main` endpoint, or a bad
        // table entry. The hash-pinned lookup below reveals only the
        // checkpoint's bucket, and keeps the wallet syncing.
        log::error!(
            "sync: compiled tree state at {} does not precede the served block {start}; \
             fetching the served predecessor's state",
            u32::from(start - 1)
        );
    }

    let predecessor_hash = match block_source
        .first_block_prev_hash()
        .filter(|hash| !hash.is_empty())
    {
        Some(hash) => hash,
        None => {
            let BlockHash(hash) =
                get_compact_block_hash(client, u64::from(u32::from(start - 1))).await?;
            hash.to_vec()
        }
    };
    let pinned_state = get_tree_state_for_block(client, predecessor_hash)
        .await?
        .to_chain_state()
        .map_err(|e| SyncError::parse(format!("parse hash-pinned tree state: {e}")))?;

    Ok((block_source, pinned_state))
}

fn validate_scan_batch(
    block_source: &block_source::MemoryBlockSource,
    from_state: &chain::ChainState,
    start: BlockHeight,
    end: BlockHeight,
) -> Result<(), SyncError> {
    if !block_source.contains_exact_range(u32::from(start), u32::from(end)) {
        return Err(SyncError::other(format!(
            "downloaded compact blocks do not exactly cover {}..{}",
            u32::from(start),
            u32::from(end),
        )));
    }

    let frontier_height = u32::from(start)
        .checked_sub(1)
        .ok_or_else(|| SyncError::other("scan range starts before a usable frontier"))?;
    if u32::from(from_state.block_height()) != frontier_height {
        return Err(SyncError::other(format!(
            "downloaded tree state height {} does not match scan frontier {frontier_height}",
            u32::from(from_state.block_height()),
        )));
    }
    if !block_source.starts_after(from_state) {
        return Err(inconsistent_scan_batch_error(start));
    }

    Ok(())
}

fn inconsistent_scan_batch_error(start: BlockHeight) -> SyncError {
    SyncError::net(format!(
        "lightwalletd returned an inconsistent compact block/tree-state tuple while scanning from {}",
        u32::from(start),
    ))
}

struct Prefetch<T> {
    handle: Option<tokio::task::JoinHandle<Result<T, SyncError>>>,
    /// The task's result, once `finished` has taken it from `handle`.
    done: Option<Result<Result<T, SyncError>, tokio::task::JoinError>>,
    start: BlockHeight,
    end: BlockHeight,
}

impl<T> Prefetch<T>
where
    T: Send + 'static,
{
    fn spawn(
        start: BlockHeight,
        end: BlockHeight,
        future: impl Future<Output = Result<T, SyncError>> + Send + 'static,
    ) -> Self {
        Self {
            handle: Some(tokio::spawn(future)),
            done: None,
            start,
            end,
        }
    }

    /// The downloaded tuple, if its download has finished, without waiting
    /// for it. The result stays here for the iteration that scans it.
    fn finished(&mut self) -> Option<&T> {
        if self.done.is_none() {
            let handle = self.handle.as_mut()?;
            if !handle.is_finished() {
                return None;
            }
            self.done = Some(handle.now_or_never()?);
            self.handle = None;
        }
        self.done.as_ref()?.as_ref().ok()?.as_ref().ok()
    }
}

impl<T> Drop for Prefetch<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            handle.abort();
        }
    }
}

/// Runs `attempt` for queued batch `start..=last`, again after each of
/// [`PREFETCH_RETRY_PAUSES`] while it fails with a network error sooner than
/// any lightwalletd timeout, such as a stream reset or a refused connection.
/// A slower failure is a timeout, which a retry would repeat, so it is
/// returned at once: a server that stopped answering reaches the inline
/// download, the sync retry and the endpoint fallback as soon as without this.
/// The task running this future is aborted with its [`Prefetch`], so a pause
/// ends with the queue.
async fn retry_quick_prefetch_failures<T, Attempt, AttemptFuture>(
    start: BlockHeight,
    last: BlockHeight,
    mut attempt: Attempt,
) -> Result<T, SyncError>
where
    Attempt: FnMut() -> AttemptFuture,
    AttemptFuture: Future<Output = Result<T, SyncError>>,
{
    let mut retries = 0;
    loop {
        let started = tokio::time::Instant::now();
        let result = attempt().await;
        let quick = started.elapsed() < lwd::SHORTEST_LIGHTWALLETD_TIMEOUT;
        match result {
            Err(SyncError::Network(message)) if quick && retries < PREFETCH_RETRY_PAUSES.len() => {
                let pause = PREFETCH_RETRY_PAUSES[retries];
                retries += 1;
                log::warn!(
                    "[{}] sync: prefetch {}-{} failed ({message}); retrying in background",
                    elapsed(),
                    u32::from(start),
                    u32::from(last),
                );
                tokio::time::sleep(pause).await;
            }
            result => return result,
        }
    }
}

/// Trial decryption of the queued batch `start..end`, started ahead of its scan.
struct NextDecryption<D = BlockDecryption<<WalletDatabase as WalletRead>::AccountId>> {
    start: BlockHeight,
    end: BlockHeight,
    decryption: D,
}

/// `next` while the queued batch it decrypts is still first in `queue`. A tip
/// batch scanned between history batches leaves the queue as it was, and
/// dropping a decryption already running would not stop its work, only
/// repeat it when the scan returns. Ranges that changed under the queue
/// cleared it, and the decryption with it.
fn decryption_still_next<D, T>(
    next: Option<NextDecryption<D>>,
    queue: &VecDeque<Prefetch<T>>,
) -> Option<NextDecryption<D>> {
    next.filter(|next| {
        queue
            .front()
            .is_some_and(|queued| queued.start == next.start && queued.end == next.end)
    })
}

/// Starts trial decryption of the queued batch that follows `end`, if its
/// download has finished. Its work queues behind the current batch's on the
/// rayon pool, so it overlaps the current batch's `put_blocks`. A failure here
/// is left for that batch's own scan to report.
fn start_next_decryption(
    network: &WalletNetwork,
    db: &WalletDatabase,
    prefetch: &mut VecDeque<Prefetch<ScanBatch>>,
    end: BlockHeight,
) -> Option<NextDecryption> {
    let next = prefetch.front_mut().filter(|next| next.start == end)?;
    let (start, end) = (next.start, next.end);
    let (block_source, _) = next.finished()?;
    let blocks = u32::from(end).saturating_sub(u32::from(start)) as usize;
    match decrypt_cached_blocks(network, block_source, db, start, blocks) {
        Ok(decryption) => Some(NextDecryption {
            start,
            end,
            decryption,
        }),
        Err(error) => {
            log::debug!(
                "[{}] sync: could not start decrypting {}-{} ahead: {error}",
                elapsed(),
                u32::from(start),
                u32::from(end).saturating_sub(1),
            );
            None
        }
    }
}

/// The queued tuple for batch `start..end`, if it is next. A batch that
/// overlaps the queue any other way means the ranges changed under it, so
/// the queue is dropped. A batch clear of it, such as a tip batch between
/// history batches, leaves it for when the scan returns. Rewinds clear the
/// queue where they happen.
fn take_queued_batch<T>(
    queue: &mut VecDeque<Prefetch<T>>,
    start: BlockHeight,
    end: BlockHeight,
) -> Option<Prefetch<T>> {
    if queue
        .front()
        .is_some_and(|queued| queued.start == start && queued.end == end)
    {
        return queue.pop_front();
    }
    if queue
        .iter()
        .any(|queued| queued.start < end && start < queued.end)
    {
        queue.clear();
    }
    None
}

/// The end of the queued tuple that starts at `start` and runs past `end`,
/// when every block it adds is still pending. A chain tip that moves while
/// the tip ranges scan puts a short Verify range at the scan frontier, inside
/// the tuple queued next; scanning that tuple whole keeps the queue and the
/// blocks it already downloaded.
fn queued_batch_extension<T>(
    queue: &VecDeque<Prefetch<T>>,
    start: BlockHeight,
    end: BlockHeight,
    ranges: &[ScanRange],
) -> Option<BlockHeight> {
    let queued = queue.front()?;
    if queued.start != start || queued.end <= end {
        return None;
    }
    let mut next = end;
    while next < queued.end {
        next = ranges
            .iter()
            .find(|range| {
                is_pending_scan_range(range)
                    && range.block_range().start <= next
                    && next < range.block_range().end
            })?
            .block_range()
            .end;
    }
    Some(queued.end)
}

/// Where to queue more tuples after batch `..end` of a range ending at
/// `range_end`: after the queue when it continues this batch, else right
/// after this batch. A batch that cut in ahead of the queue keeps it only
/// while it is the last of its range (one new block's tip range, say), so
/// a longer range that cuts in still downloads ahead.
fn prefetch_continues_from<T>(
    queue: &mut VecDeque<Prefetch<T>>,
    end: BlockHeight,
    range_end: BlockHeight,
) -> Option<BlockHeight> {
    match (queue.front(), queue.back()) {
        (None, _) => Some(end),
        (Some(front), Some(back)) if front.start == end => Some(back.end),
        _ if end < range_end => {
            queue.clear();
            Some(end)
        }
        _ => None,
    }
}

/// The post-batch chain tip, fetched while the batch scans so the round trip
/// overlaps CPU work instead of waiting after it. Dropping it aborts the
/// request.
struct TipPrefetch {
    handle: Option<
        tokio::task::JoinHandle<Result<zcash_client_backend::proto::service::BlockId, SyncError>>,
    >,
    /// When the request was sent. The tip it returns is as old as this, not
    /// as old as the moment it is read after the scan.
    requested_at: std::time::Instant,
}

impl TipPrefetch {
    fn spawn(
        mut client: CompactTxStreamerClient<Channel>,
        lightwalletd_url: &str,
        network: WalletNetwork,
    ) -> Self {
        let lightwalletd_url = lightwalletd_url.to_owned();
        Self {
            handle: Some(tokio::spawn(async move {
                get_latest_block_recorded(&mut client, &lightwalletd_url, network).await
            })),
            requested_at: std::time::Instant::now(),
        }
    }

    /// The tip, or `None` when cancellation or a mode handoff won.
    async fn resolve(
        mut self,
        should_exit: &impl Fn() -> bool,
    ) -> Option<Result<zcash_client_backend::proto::service::BlockId, SyncError>> {
        let handle = self.handle.as_mut()?;
        let result = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => return None,
            result = handle => result,
        };
        self.handle = None;
        Some(result.unwrap_or_else(|error| {
            Err(SyncError::other(format!(
                "post-batch tip fetch task failed: {error}"
            )))
        }))
    }
}

impl Drop for TipPrefetch {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            handle.abort();
        }
    }
}

/// The post-batch tip and when it was requested, or `None` when cancellation
/// or a mode handoff won. A tip proved unchanged counts as validated when it
/// was requested, so the final tip check before completion stays as strict as
/// a fetch made here. The prefetch was requested before this batch's status
/// lookups, so it cannot validate a status they released: that batch fetches
/// the tip again, as the completion path does for its own releases.
async fn post_batch_tip(
    prefetch: Option<TipPrefetch>,
    validates_released_statuses: bool,
    client: &mut CompactTxStreamerClient<Channel>,
    lightwalletd_url: &str,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> (
    std::time::Instant,
    Option<Result<zcash_client_backend::proto::service::BlockId, SyncError>>,
) {
    match prefetch.filter(|_| !validates_released_statuses) {
        Some(prefetch) => {
            let requested_at = prefetch.requested_at;
            (requested_at, prefetch.resolve(should_exit).await)
        }
        None => (
            std::time::Instant::now(),
            unless_exiting(
                should_exit,
                get_latest_block_recorded(client, lightwalletd_url, network),
            )
            .await,
        ),
    }
}

/// Whether a pending range that starts past the loop's tip should trigger one
/// tip refresh instead of ending the attempt. The mempool observer writes new
/// tips to the wallet DB while the loop scans, so the next ChainTip range can
/// start past the tip this loop last fetched. One refresh per range start: a
/// server still behind it ends the attempt as before, without spinning.
fn refresh_tip_for_queued_range(range_start: u32, refreshed_for: &mut Option<u32>) -> bool {
    if *refreshed_for == Some(range_start) {
        return false;
    }
    *refreshed_for = Some(range_start);
    true
}

async fn resolve_prefetched_or_download<T, Download, DownloadFuture>(
    prefetch: Option<Prefetch<T>>,
    start: BlockHeight,
    end: BlockHeight,
    should_exit: &impl Fn() -> bool,
    download_fresh: Download,
) -> Result<Option<T>, SyncError>
where
    Download: FnOnce() -> DownloadFuture,
    DownloadFuture: Future<Output = Result<T, SyncError>>,
{
    if should_exit() {
        return Ok(None);
    }

    if let Some(mut prefetch) = prefetch {
        if prefetch.start == start && prefetch.end == end {
            // Keep the handle inside `Prefetch` while suspended. If the sync
            // future is dropped here, `Prefetch::drop` still aborts the task.
            let result = match prefetch.done.take() {
                Some(result) => result,
                None => tokio::select! {
                    biased;
                    _ = watch_for_exit(should_exit) => return Ok(None),
                    result = prefetch.handle.as_mut().expect("prefetch handle present") => result,
                },
            };
            if should_exit() {
                return Ok(None);
            }
            let _completed_handle = prefetch.handle.take();
            match result {
                Ok(Ok(batch)) => return Ok(Some(batch)),
                Ok(Err(error)) => log::warn!(
                    "[{}] sync: prefetched batch {}-{} failed ({error}); downloading fresh",
                    elapsed(),
                    u32::from(start),
                    u32::from(end).saturating_sub(1),
                ),
                Err(error) => log::warn!(
                    "[{}] sync: prefetched batch {}-{} task failed ({error}); downloading fresh",
                    elapsed(),
                    u32::from(start),
                    u32::from(end).saturating_sub(1),
                ),
            }
        } else {
            // A reorg or priority change invalidated the speculative range.
            // Dropping the owner aborts the now-unusable network task.
            drop(prefetch);
        }
    }

    if should_exit() {
        return Ok(None);
    }
    let fresh_download = download_fresh();
    tokio::pin!(fresh_download);
    let result = tokio::select! {
        biased;
        _ = watch_for_exit(should_exit) => return Ok(None),
        result = &mut fresh_download => result,
    };
    // Cancellation and mode handoff win over a simultaneous network failure:
    // callers asked the sync session to stop, so no retry should be scheduled.
    if should_exit() {
        return Ok(None);
    }
    result.map(Some)
}

// ==================== Main sync ====================

/// Run the full sync loop with automatic retry on failure.
/// Retries up to 3 times with exponential backoff (2s, 4s, 8s).
/// Progress is the sync job's fraction, which includes work completed by
/// earlier attempts; the Checking stage carries across attempts in this call.
/// This is the unified entry point called by both Dart (FRB) and Swift (C FFI).
pub async fn run_sync_inner(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    running_mode: u8,
    desired_mode: &AtomicU8,
    active_account_target: Option<ActiveSyncAccountTarget>,
    allow_resubmit: bool,
    progress_fn: impl Fn(SyncProgressEvent) + Send + Sync,
) -> Result<(), String> {
    const MAX_RETRIES: u32 = 3;
    let mut last_err = String::new();
    let progress = std::sync::Mutex::new(retry_progress::RetryProgress::default());
    *SYNC_START.lock().unwrap() = Some(std::time::Instant::now());

    for attempt in 0..=MAX_RETRIES {
        // A queued FRB start may clear the per-run cancel flag after exit began.
        if crate::wallet::sync::proposal_locks::is_shutting_down() {
            return Ok(());
        }
        // Account deletion removes its companions best-effort; one it left
        // behind is deleted here, in every build, so none outlives its account.
        if attempt == 0 {
            if let Err(error) = transparent_ledger::pir::remove_orphan_companions(db_data_path) {
                log::warn!(
                    "[{}] sync: could not delete orphan transparent PIR companions: {error}",
                    elapsed()
                );
            }
            // A public wallet keeps no private ledger facts. This finishes a
            // forget that failed when the policy was lowered, or one a build
            // without it never did; with nothing to forget it only reads.
            if let Err(error) = transparent_ledger::forget_private_ledger(db_data_path, network) {
                log::warn!(
                    "[{}] sync: could not forget private ledger facts: {error}",
                    elapsed()
                );
            }
        }
        if attempt > 0 {
            let delay_secs = 1u64 << attempt; // 2, 4, 8
            log::warn!(
                "[{}] sync: retry {}/{} in {}s (error: {})",
                elapsed(),
                attempt,
                MAX_RETRIES,
                delay_secs,
                last_err
            );
            for _ in 0..delay_secs {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                if crate::wallet::sync::proposal_locks::is_shutting_down()
                    || cancel.load(Ordering::Relaxed)
                    || desired_mode.load(Ordering::SeqCst) != running_mode
                {
                    log::warn!(
                        "[{}] sync: cancelled/mode changed during retry wait (pending error: {})",
                        elapsed(),
                        last_err
                    );
                    return Ok(());
                }
            }
        }

        let (checking_cycle, main_scan_complete) = {
            let progress = progress.lock().unwrap();
            (progress.checking_cycle(), progress.main_scan_complete())
        };
        let report_progress = |event| {
            let event = progress.lock().unwrap().report(event);
            progress_fn(event);
        };

        match run_sync_impl(
            db_data_path,
            lightwalletd_url,
            network,
            cancel.clone(),
            running_mode,
            desired_mode,
            active_account_target.as_ref(),
            allow_resubmit,
            &report_progress,
            checking_cycle,
            main_scan_complete,
            attempt > 0,
        )
        .await
        {
            Ok(()) => return Ok(()),
            Err(sync_err) => {
                // Inspect the typed error's recovery strategy before
                // flattening to a `String` at the public boundary. Fatal
                // variants (`Db`, `Parse`) bail out immediately with no
                // retry — repeatedly hammering a DB corruption or a
                // deserialization bug doesn't fix it and just costs time.
                // Transient variants (`Network`, `Other`) fall through to
                // the existing exponential-backoff retry path.
                //
                // A `Rewind` strategy reaching this layer means the inline
                // reorg-recovery inside `run_sync_impl` exhausted its
                // phase budget (commit 1.4). Treat it as a retry-worthy
                // transient: the next attempt gets a fresh rewind budget,
                // which is often enough to get past a multi-level reorg
                // that couldn't be cleared in one run.
                let strategy = sync_err.recovery_strategy();
                let err_string = sync_err.to_string();
                match strategy {
                    RecoveryStrategy::Fatal => {
                        log::error!(
                            "[{}] sync: fatal error, not retrying: {err_string}",
                            elapsed(),
                        );
                        return Err(err_string);
                    }
                    RecoveryStrategy::RetryWithBackoff | RecoveryStrategy::Rewind { .. } => {
                        last_err = err_string;
                        if attempt == MAX_RETRIES {
                            log::error!(
                                "[{}] sync: all {} retries exhausted",
                                elapsed(),
                                MAX_RETRIES,
                            );
                        }
                    }
                }
            }
        }
    }

    Err(last_err)
}

/// Runs the bounded shielded scan needed by one payment-link claim wallet.
///
/// Claim wallets are short-lived, single-account databases. They deliberately
/// skip transparent refresh, transaction enhancement, migration preparation,
/// and main-wallet completion metadata. Each caller owns its database, so this
/// path does not take the main wallet's process-global sync guard or write lock.
pub async fn run_payment_link_claim_sync(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    allow_resubmit: bool,
) -> Result<(), String> {
    let started = std::time::Instant::now();
    const MAX_RETRIES: u32 = 3;
    let mut last_error = String::new();

    for attempt in 0..=MAX_RETRIES {
        if cancel.load(Ordering::Relaxed) {
            return Err("Gift Card scan cancelled".to_string());
        }
        if attempt > 0 {
            let delay_secs = 1u64 << attempt;
            for _ in 0..delay_secs {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                if cancel.load(Ordering::Relaxed) {
                    return Err("Gift Card scan cancelled".to_string());
                }
            }
        }

        match run_payment_link_claim_sync_once(
            db_data_path,
            lightwalletd_url,
            network,
            cancel.clone(),
            allow_resubmit,
        )
        .await
        {
            Ok(()) if cancel.load(Ordering::Relaxed) => {
                return Err("Gift Card scan cancelled".to_string())
            }
            Ok(()) => {
                log::info!(
                    "PaymentLinkClaim: scan ready elapsed_ms={}",
                    started.elapsed().as_millis()
                );
                return Ok(());
            }
            Err(error) => {
                let strategy = error.recovery_strategy();
                last_error = error.to_string();
                if matches!(strategy, RecoveryStrategy::Fatal) {
                    return Err(last_error);
                }
            }
        }
    }

    Err(last_error)
}

// Account removal retains blocks, so update_chain_tip can recreate work before
// the remaining accounts' birthdays. Normalize immediately before every range
// selection, including after tip refreshes, rewinds, and scan-generated hints.
fn payment_link_scan_ranges(
    db: &WalletDatabase,
    db_data_path: &str,
) -> Result<Vec<ScanRange>, SyncError> {
    keys::prune_orphaned_scan_ranges(db_data_path)
        .map_err(|error| SyncError::db(format!("payment-link prune scan ranges: {error}")))?;
    db.suggest_scan_ranges()
        .map_err(|error| SyncError::db(format!("payment-link suggest_scan_ranges: {error}")))
}

async fn run_payment_link_claim_sync_once(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    allow_resubmit: bool,
) -> Result<(), SyncError> {
    let should_exit = || cancel.load(Ordering::Relaxed);
    let mut client = open_lwd_channel(lightwalletd_url).await?;
    let mut db = open_db(db_data_path, network)?;
    let initial_tip = get_latest_block(&mut client).await?;
    let mut current_tip_height = initial_tip.height;
    if let Some((_, db_tip_height)) = sync::wallet_scan_heights(&mut db).map_err(SyncError::db)? {
        let stored_hash = stored_hash_for_refreshed_tip(&db, db_tip_height, initial_tip.height)?;
        match classify_refreshed_tip_with_fallback(
            &mut client,
            db_tip_height,
            stored_hash,
            initial_tip.height,
            &initial_tip.hash,
        )
        .await?
        {
            RefreshedTipRelation::ServerBehind => {
                return Err(lagging_lightwalletd_tip(db_tip_height, initial_tip.height));
            }
            RefreshedTipRelation::Reorg => {
                rewind_for_confirmed_tip_reorg(db_data_path, &mut db, initial_tip.height)?;
            }
            RefreshedTipRelation::Advanced
            | RefreshedTipRelation::Unchanged
            | RefreshedTipRelation::UnchangedUnverified => {}
        }
    }
    let tip_height = block_height_from_u64(current_tip_height, "payment-link chain tip")?;
    db.update_chain_tip(tip_height)
        .map_err(|error| SyncError::db(format!("payment-link update_chain_tip: {error}")))?;
    crate::wallet::sync::recover_orphaned_send_locks(db_data_path, network)
        .map_err(|error| SyncError::db(format!("payment-link recover send locks: {error}")))?;

    claim_roots::prepare_roots(&mut client, &mut db, db_data_path, network, tip_height).await?;

    // Claim ranges start at a card's funding height, long after the spam
    // window, so the compiled tree sizes are enough to size their batches.
    let batch_model = WorkModel::compiled(network);
    let mut rewind_attempts = 0u32;
    loop {
        if should_exit() {
            return Ok(());
        }

        let ranges = payment_link_scan_ranges(&db, db_data_path)?;
        let next_range = ranges
            .iter()
            .find(|range| is_pending_scan_range(range))
            .cloned();

        let Some(range) = next_range else {
            let fresh_tip = get_latest_block(&mut client).await?;
            let stored_hash =
                stored_hash_for_refreshed_tip(&db, current_tip_height, fresh_tip.height)?;
            match classify_refreshed_tip_with_fallback(
                &mut client,
                current_tip_height,
                stored_hash,
                fresh_tip.height,
                &fresh_tip.hash,
            )
            .await?
            {
                RefreshedTipRelation::Advanced => {
                    current_tip_height = fresh_tip.height;
                    let height =
                        block_height_from_u64(current_tip_height, "payment-link refreshed tip")?;
                    db.update_chain_tip(height).map_err(|error| {
                        SyncError::db(format!("payment-link update_chain_tip({height}): {error}"))
                    })?;
                    continue;
                }
                RefreshedTipRelation::Reorg => {
                    if rewind_attempts >= MAX_REWINDS_PER_RUN {
                        return Err(SyncError::continuity(
                            fresh_tip.height,
                            "payment-link tip reorg rewind budget exhausted",
                        ));
                    }
                    rewind_attempts += 1;
                    let fresh_height =
                        block_height_from_u64(fresh_tip.height, "payment-link reorg tip")?;
                    let requested = confirmed_reorg_rewind_target(fresh_height)?;
                    invalidate_transparent_checks_before_rewind(db_data_path)?;
                    truncate_wallet_with(db_data_path, requested, fresh_height, |height| {
                        ledger_discovery::truncate(db_data_path, &mut db, height)
                    })?;
                    db.update_chain_tip(fresh_height).map_err(|error| {
                        SyncError::db(format!("payment-link update tip after reorg: {error}"))
                    })?;
                    current_tip_height = fresh_tip.height;
                    continue;
                }
                RefreshedTipRelation::ServerBehind => {
                    return Err(lagging_lightwalletd_tip(
                        current_tip_height,
                        fresh_tip.height,
                    ));
                }
                RefreshedTipRelation::Unchanged | RefreshedTipRelation::UnchangedUnverified => {
                    ensure_complete_scan_state(&mut db, current_tip_height)?;
                    if allow_resubmit {
                        let exclusions =
                            crate::wallet::sync::payment_link_resubmit_exclusions(db_data_path)
                                .map_err(SyncError::db)?;
                        let _ = crate::wallet::sync::resubmit_pending_transactions(
                            db_data_path,
                            lightwalletd_url,
                            &mut client,
                            u32::try_from(current_tip_height).unwrap_or(u32::MAX),
                            &exclusions,
                            &should_exit,
                        )
                        .await;
                    }
                    return Ok(());
                }
            }
        };

        let start = range.block_range().start;
        let range_end = range.block_range().end;
        let Some((_, end)) = scannable_batch_end(
            &batch_model,
            BATCH_SIZE_FOREGROUND,
            start,
            range_end,
            current_tip_height,
        ) else {
            return Err(SyncError::continuity(
                current_tip_height,
                "payment-link pending scan range starts after the observed tip",
            ));
        };
        let batch_blocks = u32::from(end).saturating_sub(u32::from(start)) as u64;

        let (block_source, from_state) =
            download_scan_batch(&mut client, start, end - 1, network).await?;
        validate_scan_batch(&block_source, &from_state, start, end)?;
        if should_exit() {
            return Ok(());
        }

        let scan_result = scan_cached_blocks(
            &network,
            &block_source,
            &mut db,
            start,
            &from_state,
            batch_blocks as usize,
        );
        match scan_result {
            Ok(_) => {}
            Err(error) => {
                let sync_error = match error {
                    ChainError::Scan(scan_error) if scan_error.is_continuity_error() => {
                        SyncError::continuity(
                            u32::from(scan_error.at_height()) as u64,
                            scan_error.to_string(),
                        )
                    }
                    ChainError::Wallet(SqliteClientError::BlockConflict(at)) => {
                        SyncError::continuity(u32::from(at) as u64, "payment-link block conflict")
                    }
                    ChainError::Wallet(SqliteClientError::NonSequentialBlocks) => {
                        inconsistent_scan_batch_error(start)
                    }
                    ChainError::Wallet(wallet_error)
                        if is_commitment_tree_root_conflict(&wallet_error) =>
                    {
                        SyncError::continuity(
                            u32::from(start) as u64,
                            format!("payment-link commitment tree root conflict: {wallet_error}"),
                        )
                    }
                    ChainError::Wallet(wallet_error) => {
                        SyncError::db(format!("payment-link scan wallet: {wallet_error}"))
                    }
                    other => SyncError::other(format!("payment-link scan: {other}")),
                };
                if !sync_error.is_continuity() || rewind_attempts >= MAX_REWINDS_PER_RUN {
                    return Err(sync_error);
                }
                let attempt = rewind_attempts;
                rewind_attempts += 1;
                let requested_height = sync_error
                    .rewind_target_for_attempt(attempt)
                    .unwrap_or_else(|| u32::from(start).saturating_sub(10) as u64);
                let requested =
                    block_height_from_u64(requested_height, "payment-link scan rewind target")?;
                let fresh_tip =
                    block_height_from_u64(current_tip_height, "payment-link scan rewind tip")?;
                invalidate_transparent_checks_before_rewind(db_data_path)?;
                truncate_wallet_with(db_data_path, requested, fresh_tip, |height| {
                    ledger_discovery::truncate(db_data_path, &mut db, height)
                })?;
            }
        }
    }
}

/// Inner sync implementation. Called by run_sync_inner (with retry wrapper).
async fn run_sync_impl(
    db_data_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    running_mode: u8,
    desired_mode: &AtomicU8,
    active_account_target: Option<&ActiveSyncAccountTarget>,
    allow_resubmit: bool,
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
    mut checking_cycle: u32,
    main_scan_complete: bool,
    fresh_circuit: bool,
) -> Result<(), SyncError> {
    if crate::wallet::sync::proposal_locks::is_shutting_down() {
        return Ok(());
    }
    let active_account_uuid = current_active_sync_account(active_account_target);
    let mut migration_anchor_retention_required =
        crate::wallet::sync::migration_anchor_retention_required(db_data_path, network)
            .map_err(SyncError::db)?;
    let default_batch_size = if running_mode == 2 {
        BATCH_SIZE_BACKGROUND
    } else {
        BATCH_SIZE_FOREGROUND
    };
    let base_batch_size = effective_base_batch_size(default_batch_size);
    log::info!(
        "[{}] sync: starting (mode={}, base_batch={}, migration_anchor_retention={})",
        elapsed(),
        running_mode,
        base_batch_size,
        migration_anchor_retention_required,
    );

    // Persist the active session before any new sync work begins. A crash or
    // mode handoff cannot leave the previous completed tip looking like the
    // current run completed successfully.
    //
    // The progress job is the one an earlier attempt or session left, even
    // one whose scan finished before it could complete, or a new one claimed
    // now. Preparation reports its stored fraction; the job is measured, and
    // rarely replaced, once pending work is known below.
    let stored_progress_job = with_wallet_db_write_lock("sync_engine.mark_sync_started", || {
        mark_sync_started(db_data_path)
    })
    .map_err(SyncError::db)?;
    let preparation_job_id = stored_progress_job.id.clone();
    let preparation_job_percentage = stored_progress_job.fraction;

    // Declared before the channel open so a stopped session leaves the Tor wait.
    let should_exit = || {
        crate::wallet::sync::proposal_locks::is_shutting_down()
            || cancel.load(Ordering::Relaxed)
            || desired_mode.load(Ordering::SeqCst) != running_mode
    };

    // 1. Connect gRPC (plain TLS via tonic + webpki roots). The lanes' public
    // transparent lookups go over the same transport with a dispatch signal,
    // so a policy transition waits only for them to be sent.
    // A session that opens `client` while Tor is off holds a direct route that
    // a later Tor enable cancels; it must not add a direct block connection.
    let tor_route = crate::network_privacy::is_tor_desired();
    // A retry takes a fresh Tor circuit, so a bad exit does not fail every
    // attempt on the client's shared one.
    let transport = if fresh_circuit {
        open_isolated_lwd_transport_until(lightwalletd_url, should_exit).await?
    } else {
        open_lwd_transport_with_cancel(lightwalletd_url, should_exit).await?
    };
    let mut client = CompactTxStreamerClient::new(transport.clone());
    let _lookup_transport =
        lwd::transparent_lookup::register_sync_transport(db_data_path, transport);

    // Open DB once — reused for the entire sync
    let mut db =
        with_wallet_db_write_lock("sync_engine.open_db", || open_db(db_data_path, network))?;
    let mut enhancement = EnhancementSession::new(network, db_data_path);
    // The main-phase rewind budget also covers a reorg detected by the
    // initial tip response, before the scan queue has been created.
    let mut main_rewinds_this_run: u32 = 0;

    // 2. Get the chain tip. Reconcile it with the DB before treating it as
    // authoritative: `WalletDb::update_chain_tip` deliberately ignores a
    // height below the maximum scanned block, so assigning the server height
    // first could later report completion above a lagging endpoint.
    let tip_result = unless_exiting(
        &should_exit,
        get_latest_block_recorded(&mut client, lightwalletd_url, network),
    )
    .await;
    let Some(tip_result) =
        tip_result.and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
    else {
        log::info!("[{}] sync: exiting after initial tip fetch", elapsed());
        return Ok(());
    };
    let tip = tip_result?;
    let initial_tip_observed_at = std::time::Instant::now();

    let tip_height = block_height_from_u64(tip.height, "lightwalletd chain tip")?;
    let db_tip_height = sync::wallet_scan_heights(&mut db)
        .map_err(SyncError::db)?
        .map(|(_, db_tip)| db_tip);
    let initial_tip_relation = if let Some(db_tip) = db_tip_height {
        let stored_hash = stored_hash_for_refreshed_tip(&db, db_tip, tip.height)?;
        let relation = unless_exiting(
            &should_exit,
            classify_refreshed_tip_with_fallback(
                &mut client,
                db_tip,
                stored_hash,
                tip.height,
                &tip.hash,
            ),
        )
        .await;
        let Some(relation) =
            relation.and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
        else {
            log::info!("[{}] sync: exiting after initial tip validation", elapsed());
            return Ok(());
        };
        Some((db_tip, relation?))
    } else {
        None
    };
    let initial_tip_identity_verified = matches!(
        initial_tip_relation,
        Some((_, RefreshedTipRelation::Unchanged))
    );

    match initial_tip_relation {
        Some((db_tip_height, RefreshedTipRelation::ServerBehind)) => {
            return Err(lagging_lightwalletd_tip(db_tip_height, tip.height));
        }
        Some((_, RefreshedTipRelation::Reorg)) => {
            if main_rewinds_this_run >= MAX_REWINDS_PER_RUN {
                return Err(SyncError::continuity(
                    tip.height,
                    "initial tip reorg rewind budget exhausted",
                ));
            }
            main_rewinds_this_run += 1;
            let (actual_height, _, pending_blocks) =
                rewind_for_confirmed_tip_reorg(db_data_path, &mut db, tip.height)?;
            log::warn!(
                "[{}] sync: initial tip proved a reorg; rewound to {} and \
                 queued {} block(s) toward tip {}",
                elapsed(),
                actual_height,
                pending_blocks,
                tip.height,
            );
        }
        Some((_, RefreshedTipRelation::Unchanged))
        | Some((_, RefreshedTipRelation::UnchangedUnverified))
        | Some((_, RefreshedTipRelation::Advanced))
        | None => {
            with_wallet_db_write_lock("sync_engine.update_chain_tip.initial", || {
                db.update_chain_tip(tip_height).map_err(|e| {
                    if is_sqlite_lock_contention(&e) {
                        SyncError::other(format!(
                            "update_chain_tip: transient SQLite lock contention: {e}"
                        ))
                    } else {
                        SyncError::db(format!("update_chain_tip: {e}"))
                    }
                })
            })?;
        }
    }

    let mut current_tip_height: u64 = tip.height;
    log::info!("[{}] sync: chain tip = {}", elapsed(), current_tip_height);
    // A new block lets work that failed on content count, and be asked, again.
    enhancement::content_failures::at_tip(db_data_path, current_tip_height);

    // Retained send-lock expiry requires a usable target height.
    crate::wallet::sync::recover_orphaned_send_locks(db_data_path, network)
        .map_err(SyncError::db)?;

    if should_exit() {
        log::info!(
            "[{}] sync: cancel/mode observed before transparent UTXO refresh, skipping",
            elapsed(),
        );
        return Ok(());
    }

    // Recovery runs after import, under the existing sync lifetime. Once both
    // scopes complete it performs no further address-history requests.
    ledger_discovery::run(
        &mut client,
        &mut db,
        db_data_path,
        network,
        enhancement.policy(),
        tip_height,
        &should_exit,
    )
    .await?;
    if should_exit() {
        return Ok(());
    }

    let active_utxo_progress = |completed, total| {
        progress_fn(preparation_progress_event(
            current_tip_height,
            "active_utxo",
            completed,
            total,
            preparation_job_percentage,
            &preparation_job_id,
        ));
    };
    let defer_inactive_transparent_refresh = if let Some(active_account_uuid) =
        active_account_uuid.as_deref()
    {
        log::info!(
            "[{}] sync: refreshing active-account transparent UTXOs before chain scan ({})",
            elapsed(),
            active_account_uuid,
        );
        let mut critical_received_outputs = false;
        let active_summary = refresh_utxos(
            &mut client,
            db_data_path,
            &mut db,
            network,
            enhancement.policy(),
            tip_height,
            TransparentAccountSelection::Only(active_account_uuid),
            None,
            &mut critical_received_outputs,
            Some(&active_utxo_progress),
            &should_exit,
        )
        .await?;
        if active_summary.matched_accounts == 0 && !active_summary.withheld {
            log::warn!(
                "[{}] sync: active account {} was absent from the wallet DB; refreshing all transparent UTXOs before chain scan",
                elapsed(),
                active_account_uuid,
            );
            refresh_utxos(
                &mut client,
                db_data_path,
                &mut db,
                network,
                enhancement.policy(),
                tip_height,
                TransparentAccountSelection::All,
                None,
                &mut critical_received_outputs,
                Some(&active_utxo_progress),
                &should_exit,
            )
            .await?;
            false
        } else {
            true
        }
    } else {
        let mut critical_received_outputs = false;
        refresh_utxos(
            &mut client,
            db_data_path,
            &mut db,
            network,
            enhancement.policy(),
            tip_height,
            TransparentAccountSelection::All,
            None,
            &mut critical_received_outputs,
            None,
            &should_exit,
        )
        .await?;
        false
    };

    if should_exit() {
        log::info!(
            "[{}] sync: cancel/mode observed after transparent UTXO refresh",
            elapsed(),
        );
        return Ok(());
    }

    if running_mode == 1 {
        progress_fn(preparation_progress_event(
            current_tip_height,
            "chain_prepare",
            0,
            0,
            preparation_job_percentage,
            &preparation_job_id,
        ));
    }

    // 2.5. Resubmit eligible unmined wallet txs now that we know the
    // current tip. Matches the first of the three
    // resubmit call sites in zcash-android-wallet-sdk's
    // `processNewBlocks` (line 551). Best-effort: failures are
    // logged inside the helper and must not abort the sync.
    //
    // We reuse the same `client` instead of opening a fresh channel.
    //
    // Pre-flight cancel/mode check: `update_chain_tip` and
    // `open_lwd_channel` can take a couple of seconds under a
    // slow connection, which is long enough for the user to hit
    // stop. Skip the whole pass in that case instead of sending
    // one more round of broadcasts after the UI asked us to quit.
    if !allow_resubmit {
        log::info!("[{}] sync: startup resubmit disabled", elapsed());
    } else if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode
    {
        log::info!(
            "[{}] sync: cancel/mode observed before startup resubmit, skipping",
            elapsed(),
        );
    } else {
        let startup_ranges = db
            .suggest_scan_ranges()
            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
        let startup_resubmit_exclusions =
            recovery_resubmit_exclusions(db_data_path, &startup_ranges)?;
        let _ = crate::wallet::sync::resubmit_pending_transactions(
            db_data_path,
            lightwalletd_url,
            &mut client,
            u32::from(tip_height),
            &startup_resubmit_exclusions,
            || {
                cancel.load(Ordering::Relaxed)
                    || desired_mode.load(Ordering::SeqCst) != running_mode
            },
        )
        .await;
    }

    // 3. Download subtree roots (incremental)
    let Some(subtree_roots) = unless_exiting(
        &should_exit,
        download_subtree_roots(&mut client, &mut db, network, tip_height),
    )
    .await
    else {
        log::info!("[{}] sync: exiting during subtree root download", elapsed());
        return Ok(());
    };
    subtree_roots?;

    if migration_anchor_retention_required {
        with_wallet_db_write_lock(
            "sync_engine.reconcile_migration_anchor_checkpoints.initial",
            || {
                crate::wallet::sync::retain_prepared_note_anchor_checkpoints_after_scan(
                    db_data_path,
                    network,
                    &mut db,
                )
            },
        )
        .map_err(|error| {
            SyncError::other(format!(
                "reconcile migration anchor checkpoints before scan: {error}"
            ))
        })?;
    }

    // Rescue pass (VZR-89): demote orphaned scan ranges left below the surviving
    // accounts' birthday by a pre-fix account deletion, so a wallet bricked by
    // that bug heals automatically (just update + re-sync, no reinstall) and a
    // freshly-deleted old import doesn't pin progress / block completion.
    //
    // This MUST run AFTER `update_chain_tip` above, not before it: that call
    // anchors new Verify/Historic ranges at `max_scanned + 1` (read from the
    // `blocks` table) WITHOUT clamping to the wallet birthday
    // (zcash_client_sqlite scanning.rs::update_chain_tip / block_height_extrema).
    // If a deleted, only-partially-synced old-birthday account left scanned
    // blocks BELOW the surviving birthday, `max_scanned` sits below it and
    // `update_chain_tip` re-creates sub-birthday pending work. Pruning here —
    // after the tip update, before pending work is measured — demotes both
    // the original orphan and any such re-created range, so the orphaned history
    // is never scanned. No-op for healthy wallets; best-effort (a failure must
    // not block sync).
    match crate::wallet::keys::prune_orphaned_scan_ranges(db_data_path) {
        Ok(demoted) if demoted > 0 => log::info!(
            "[{}] sync: pruned {demoted} orphaned scan range(s) below the wallet birthday",
            elapsed(),
        ),
        Ok(_) => {}
        Err(e) => log::warn!(
            "[{}] sync: failed to prune orphaned scan ranges (continuing): {e}",
            elapsed(),
        ),
    }

    // 4. Calculate initial scan target (before any scanning)
    let initial_ranges = db
        .suggest_scan_ranges()
        .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
    let mut initial_total = pending_scan_blocks(&initial_ranges);
    // Batches are counted at the platform's foreground cap even in
    // background mode, so a mode switch does not move the fraction. The model
    // also sizes the batches, and without the subtree heights its 10,000-block
    // averages miss where dense spam starts and stops, so a failed read ends
    // the attempt like any other DB read.
    let work_model = WorkModel::load(db_data_path, network, BATCH_SIZE_FOREGROUND)
        .map_err(|e| SyncError::db(format!("subtree heights: {e}")))?;
    // Main-scan batches only (`batch_uses_direct_connection`). Checking-stage
    // batches, ranges that follow the wallet's notes, and every request that
    // carries an address, txid or transaction stay on `client`.
    let scanned_before_session = db
        .block_max_scanned()
        .map_err(|e| SyncError::db(format!("block_max_scanned: {e}")))?
        .map(|block| block.block_height());
    let pending_download_bytes = direct_download_bytes(
        &work_model,
        &initial_ranges,
        current_tip_height,
        checking_cycle,
        scanned_before_session,
    );
    let opens_direct = checking_cycle == 0
        && !main_scan_complete
        && lwd::block_download_can_go_direct(lightwalletd_url)
        && fetches_blocks_directly(
            tor_route && crate::network_privacy::is_tor_desired(),
            enhancement.policy().is_private(),
            pending_download_bytes,
        );
    let mut direct_route = opens_direct.then(DirectBlockRoute::new);
    let mut block_client = if opens_direct {
        let opened = tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => {
                log::info!("[{}] sync: exiting while opening the direct block connection", elapsed());
                return Ok(());
            }
            opened = open_block_download_lwd_transport(lightwalletd_url) => opened,
        };
        match opened {
            Ok(transport) => {
                log::info!(
                    "[{}] sync: downloading about {} MB of compact blocks directly; other requests stay on Tor",
                    elapsed(),
                    (pending_download_bytes / 1_000_000.0).round(),
                );
                CompactTxStreamerClient::new(transport)
            }
            // A network that blocks the server but not Tor keeps the
            // download on Tor rather than failing every attempt.
            Err(error) => {
                let wait = direct_route
                    .as_mut()
                    .map(|route| route.demote(std::time::Instant::now()))
                    .unwrap_or_default();
                log::warn!(
                    "[{}] sync: direct block download unavailable ({error}); downloading over Tor, retrying in {}s",
                    elapsed(),
                    wait.as_secs(),
                );
                client.clone()
            }
        }
    } else {
        client.clone()
    };
    let (mut job, job_start) = JobProgress::start(
        stored_progress_job,
        work_model.pending_work(&initial_ranges, current_tip_height),
        work_model.reference_batch_work(),
    );
    // A job claimed after a completed sync is a catch-up only while it scans
    // the blocks since; checked again whenever the loop reads new ranges.
    let catch_up_completed_height = if job.from_completed_sync() {
        read_sync_completion_meta(db_data_path)
            .ok()
            .and_then(|(_, height, _)| height)
    } else {
        None
    };
    reclassify_catch_up(&mut job, &initial_ranges, catch_up_completed_height);
    job.persist_if_due(db_data_path, true);
    progress_fn(scan_queue_progress_event(
        &mut checking_cycle,
        main_scan_complete,
        initial_total,
        current_tip_height,
        earliest_pending_scan_start(&initial_ranges),
        &job,
    ));
    let mut queued_ranges = Some(initial_ranges);
    let mut voting_scan_end = None;
    let mut prev_remaining = initial_total;
    // Set when a queued range starts past the loop's tip (see
    // `refresh_tip_for_queued_range`).
    let mut force_tip_refresh = false;
    let mut queued_tip_refreshed_for: Option<u32> = None;
    // Logged when a batch scans at a different power level than the last.
    let mut last_scan_power = None;
    let mut timing = SyncTimingSummary::default();
    let mut timing_since = std::time::Instant::now();
    let mut last_post_batch_tip_check = std::time::Instant::now();
    log::info!(
        "[{}] sync: {} blocks to scan; progress job {} {:?} at {:.1}% ({:.0} of {:.0} work units left)",
        elapsed(),
        initial_total,
        job.id(),
        job_start,
        job.fraction() * 100.0,
        job.remaining(),
        job.total(),
    );

    // Reorg-triggered rewinds are split between the verify and main scan
    // phases. The main budget was initialized before tip reconciliation;
    // this verify budget is independent so a flapping verify range cannot
    // consume the main scan's recovery allowance.
    let mut verify_rewinds_this_run: u32 = 0;
    let mut witness_repair_passes_this_run: u32 = 0;
    let mut anchor_root_repair_passes_this_run: u32 = 0;
    let mut force_witness_check_this_run = false;

    // Phase-transition markers used only for logging. Progress through the
    // scan queue is implicitly ordered by `ScanPriority::Verify` >
    // everything else, so an explicit state machine isn't needed — we just
    // log when we first see a verify range and when we first see a
    // non-verify range so diagnosis of a reorg-heavy sync is easier.
    let mut verify_phase_announced = false;
    let mut main_phase_announced = false;

    // If the scan loop has been running longer than this without
    // refreshing the chain tip from lightwalletd, we re-fetch
    // the tip and call `update_chain_tip` so that
    // `suggest_scan_ranges` incorporates any new blocks that
    // appeared while the wallet was catching up.
    //
    // Matches zcash-android-wallet-sdk's
    // `SYNCHRONIZATION_RESTART_TIMEOUT = 10.minutes`
    // (CompactBlockProcessor.kt:1197). We don't restart the
    // whole sync like the SDK does — just refreshing the tip is
    // enough because our `suggest_scan_ranges` call at the top
    // of each loop iteration already reflects the new tip once
    // `update_chain_tip` has written it to the DB.
    let mut last_completion_tip_validation = initial_tip_observed_at;
    let mut completion_tip_validation_required = !initial_tip_identity_verified;
    let mut last_periodic_tip_refresh_attempt = initial_tip_observed_at;

    // Scan batches downloading ahead of the current one, in order.
    // When the scan loop processes a range that spans multiple batches,
    // we keep up to `PREFETCH_DEPTH` block-and-frontier tuples in flight
    // before scanning the current batch. App syncs run on a multi-thread
    // runtime on every platform (`bounded_runtime`), so the downloads overlap
    // the scan; migration preparation's current-thread runtime overlaps only
    // later async stages. The Android SDK pipelines one batch (`.buffer(1)`,
    // `CompactBlockProcessor.kt:1666`) and the Swift SDK two
    // (`DownloadAction`); this downloads four.
    //
    // Empty on the first iteration, after a rewind, and once the last
    // batch of a range is consumed (there's nothing to prefetch until
    // `suggest_scan_ranges` runs again). A one-batch tip range that cuts
    // in leaves it for the history batches it holds
    // (`take_queued_batch`).
    let mut prefetch: VecDeque<Prefetch<ScanBatch>> = VecDeque::new();
    // Trial decryption of the next queued batch, started before this batch is
    // written so that it runs while `put_blocks` does. Keyed by the batch's
    // range; `scan_decrypted_blocks` decrypts again unless it covers exactly
    // the blocks scanned, with the current viewing keys.
    let mut next_decryption: Option<NextDecryption> = None;

    // Retry enhancement work left by an interrupted/older sync before scanning.
    // Best-effort: a failed public payload stays durable and the session holds
    // it back until its retry time; a local failure here is logged, and the
    // checkpoints after scanning report it.
    match enhancement
        .run_payload_recovery(&mut db, &mut client, None, &should_exit)
        .await
    {
        Ok(true) => {
            log::info!("[{}] sync: exiting during enhancement", elapsed());
            return Ok(());
        }
        Ok(false) => {}
        Err(error) => log::warn!(
            "[{}] sync: startup enhancement failed; it will retry after scanning: {}",
            elapsed(),
            error,
        ),
    }
    let mut enhancement_after_scan = false;

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

        // Periodic tip refresh: if we've been scanning for longer
        // than TIP_REFRESH_INTERVAL, re-fetch the chain tip so
        // new blocks that arrived during a long catch-up are
        // picked up by the next suggest_scan_ranges() call.
        // Transport errors are logged and skipped so scanning can continue
        // against the last validated tip. A lower, non-divergent response is
        // returned as a transient error to avoid repeatedly requesting an
        // empty range from a lagging replica.
        if force_tip_refresh || last_periodic_tip_refresh_attempt.elapsed() >= TIP_REFRESH_INTERVAL
        {
            force_tip_refresh = false;
            last_periodic_tip_refresh_attempt = std::time::Instant::now();
            let fresh_tip_result = unless_exiting(
                &should_exit,
                get_latest_block_recorded(&mut client, lightwalletd_url, network),
            )
            .await;
            let Some(fresh_tip_result) = fresh_tip_result
                .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
            else {
                log::info!("[{}] sync: exiting after periodic tip fetch", elapsed());
                return Ok(());
            };
            match fresh_tip_result {
                Ok(fresh_tip) => {
                    let fresh_tip_height =
                        block_height_from_u64(fresh_tip.height, "periodic lightwalletd chain tip")?;

                    let stored_hash =
                        stored_hash_for_refreshed_tip(&db, current_tip_height, fresh_tip.height)?;
                    let relation = unless_exiting(
                        &should_exit,
                        classify_refreshed_tip_with_fallback(
                            &mut client,
                            current_tip_height,
                            stored_hash,
                            fresh_tip.height,
                            &fresh_tip.hash,
                        ),
                    )
                    .await;
                    let Some(relation) = relation
                        .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
                    else {
                        log::info!(
                            "[{}] sync: exiting after periodic tip validation",
                            elapsed()
                        );
                        return Ok(());
                    };
                    let relation = relation?;
                    match relation {
                        RefreshedTipRelation::Unchanged => {
                            last_completion_tip_validation = std::time::Instant::now();
                            completion_tip_validation_required = false;
                        }
                        RefreshedTipRelation::UnchangedUnverified => {
                            completion_tip_validation_required = true;
                        }
                        RefreshedTipRelation::Advanced => {
                            if let Err(e) = with_wallet_db_write_lock(
                                "sync_engine.update_chain_tip.periodic",
                                || db.update_chain_tip(fresh_tip_height),
                            ) {
                                completion_tip_validation_required = true;
                                log::warn!(
                                    "[{}] sync: periodic tip refresh update_chain_tip \
                                     failed: {e}",
                                    elapsed(),
                                );
                            } else {
                                log::info!(
                                    "[{}] sync: periodic tip refresh {} → {}",
                                    elapsed(),
                                    current_tip_height,
                                    fresh_tip.height,
                                );
                                current_tip_height = fresh_tip.height;
                                enhancement::content_failures::at_tip(
                                    db_data_path,
                                    current_tip_height,
                                );
                                completion_tip_validation_required = true;
                            }
                        }
                        RefreshedTipRelation::ServerBehind => {
                            return Err(lagging_lightwalletd_tip(
                                current_tip_height,
                                fresh_tip.height,
                            ));
                        }
                        RefreshedTipRelation::Reorg => {
                            if main_rewinds_this_run >= MAX_REWINDS_PER_RUN {
                                return Err(SyncError::continuity(
                                    fresh_tip.height,
                                    "periodic tip reorg rewind budget exhausted",
                                ));
                            }
                            main_rewinds_this_run += 1;
                            prefetch.clear();
                            let (actual_height, repair_ranges, pending_blocks) =
                                rewind_for_confirmed_tip_reorg(
                                    db_data_path,
                                    &mut db,
                                    fresh_tip.height,
                                )?;
                            log::warn!(
                                "[{}] sync: periodic tip proved a reorg; rewound to {} \
                                 and queued {} block(s) toward tip {}",
                                elapsed(),
                                actual_height,
                                pending_blocks,
                                fresh_tip.height,
                            );
                            current_tip_height = fresh_tip.height;
                            enhancement::content_failures::at_tip(db_data_path, current_tip_height);
                            initial_total = pending_blocks;
                            prev_remaining = pending_blocks;
                            if checking_cycle > 0 && pending_blocks > 0 {
                                progress_fn(begin_checking(
                                    &mut checking_cycle,
                                    pending_blocks,
                                    current_tip_height,
                                    &job,
                                ));
                            }
                            queued_ranges = Some(repair_ranges);
                            completion_tip_validation_required = true;
                            continue;
                        }
                    }
                }
                Err(e) => {
                    completion_tip_validation_required = true;
                    log::warn!(
                        "[{}] sync: periodic tip refresh get_latest_block failed: {e}",
                        elapsed(),
                    );
                }
            }
        }

        let ranges = if let Some(ranges) = queued_ranges.take() {
            ranges
        } else {
            db.suggest_scan_ranges()
                .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?
        };

        let range = match next_pending_scan_range(&ranges, current_tip_height) {
            Some(r) => r.clone(),
            None => {
                // A long catch-up can outlive the tip captured at startup.
                // Refresh once when the queue drains, but reuse a successful
                // validation that is less than five seconds old. Any failed
                // periodic or post-batch refresh forces this check regardless
                // of age. If the tip advanced, queue its ranges before running
                // completion repair checks.
                if should_refresh_tip_before_completion(
                    completion_tip_validation_required,
                    last_completion_tip_validation.elapsed(),
                ) {
                    let fresh_tip_result = unless_exiting(
                        &should_exit,
                        get_latest_block_recorded(&mut client, lightwalletd_url, network),
                    )
                    .await;
                    let Some(fresh_tip_result) = fresh_tip_result
                        .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
                    else {
                        log::info!("[{}] sync: exiting after final tip fetch", elapsed());
                        return Ok(());
                    };
                    let fresh_tip = fresh_tip_result?;
                    last_periodic_tip_refresh_attempt = std::time::Instant::now();
                    let fresh_tip_height =
                        block_height_from_u64(fresh_tip.height, "final lightwalletd chain tip")?;

                    let stored_hash =
                        stored_hash_for_refreshed_tip(&db, current_tip_height, fresh_tip.height)?;
                    let relation = unless_exiting(
                        &should_exit,
                        classify_refreshed_tip_with_fallback(
                            &mut client,
                            current_tip_height,
                            stored_hash,
                            fresh_tip.height,
                            &fresh_tip.hash,
                        ),
                    )
                    .await;
                    let Some(relation) = relation
                        .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
                    else {
                        log::info!("[{}] sync: exiting after final tip validation", elapsed());
                        return Ok(());
                    };
                    let relation = relation?;

                    match relation {
                        RefreshedTipRelation::Unchanged => {
                            last_completion_tip_validation = std::time::Instant::now();
                            completion_tip_validation_required = false;
                        }
                        RefreshedTipRelation::UnchangedUnverified => {
                            completion_tip_validation_required = true;
                        }
                        RefreshedTipRelation::Advanced => {
                            with_wallet_db_write_lock(
                                "sync_engine.update_chain_tip.queue_drain",
                                || db.update_chain_tip(fresh_tip_height),
                            )
                            .map_err(|e| {
                                SyncError::db(format!(
                                    "queue-drain update_chain_tip({fresh_tip_height}): {e}"
                                ))
                            })?;
                            current_tip_height = fresh_tip.height;
                            enhancement::content_failures::at_tip(db_data_path, current_tip_height);
                            let promoted_ranges = db.suggest_scan_ranges().map_err(|e| {
                                SyncError::db(format!(
                                    "suggest_scan_ranges after final tip advance: {e}"
                                ))
                            })?;
                            reset_promoted_scan_progress(
                                &promoted_ranges,
                                &mut initial_total,
                                &mut prev_remaining,
                            );
                            if initial_total > 0 {
                                progress_fn(begin_checking(
                                    &mut checking_cycle,
                                    initial_total,
                                    current_tip_height,
                                    &job,
                                ));
                            }
                            queued_ranges = Some(promoted_ranges);

                            completion_tip_validation_required = true;
                            continue;
                        }
                        RefreshedTipRelation::ServerBehind => {
                            return Err(lagging_lightwalletd_tip(
                                current_tip_height,
                                fresh_tip.height,
                            ));
                        }
                        RefreshedTipRelation::Reorg => {
                            if main_rewinds_this_run >= MAX_REWINDS_PER_RUN {
                                return Err(SyncError::continuity(
                                    fresh_tip.height,
                                    "queue-drain reorg rewind budget exhausted",
                                ));
                            }
                            main_rewinds_this_run += 1;
                            prefetch.clear();
                            let (actual_height, repair_ranges, repair_pending_blocks) =
                                rewind_for_confirmed_tip_reorg(
                                    db_data_path,
                                    &mut db,
                                    fresh_tip.height,
                                )?;
                            log::warn!(
                                "[{}] sync: final tip proved a reorg; rewound to {} \
                                 and queued {} block(s) toward tip {}",
                                elapsed(),
                                actual_height,
                                repair_pending_blocks,
                                fresh_tip.height,
                            );
                            current_tip_height = fresh_tip.height;
                            enhancement::content_failures::at_tip(db_data_path, current_tip_height);
                            initial_total = repair_pending_blocks;
                            prev_remaining = repair_pending_blocks;
                            progress_fn(begin_checking(
                                &mut checking_cycle,
                                repair_pending_blocks,
                                current_tip_height,
                                &job,
                            ));
                            queued_ranges = Some(repair_ranges);
                            completion_tip_validation_required = true;
                            continue;
                        }
                    }
                }

                if let Some(repair_pending_blocks) = queue_witness_repairs_if_needed(
                    db_data_path,
                    &mut db,
                    current_tip_height,
                    &mut witness_repair_passes_this_run,
                    force_witness_check_this_run,
                )? {
                    force_witness_check_this_run = true;
                    initial_total = repair_pending_blocks;
                    prev_remaining = repair_pending_blocks;
                    if repair_pending_blocks > 0 {
                        progress_fn(begin_checking(
                            &mut checking_cycle,
                            repair_pending_blocks,
                            current_tip_height,
                            &job,
                        ));
                    }
                    prefetch.clear();
                    continue;
                } else if let Some(repair_pending_blocks) = repair_anchor_root_mismatch_if_needed(
                    db_data_path,
                    &mut client,
                    &mut db,
                    network,
                    current_tip_height,
                    &mut anchor_root_repair_passes_this_run,
                )
                .await?
                {
                    force_witness_check_this_run = true;
                    initial_total = repair_pending_blocks;
                    prev_remaining = repair_pending_blocks;
                    if repair_pending_blocks > 0 {
                        progress_fn(begin_checking(
                            &mut checking_cycle,
                            repair_pending_blocks,
                            current_tip_height,
                            &job,
                        ));
                    }
                    prefetch.clear();
                    continue;
                } else {
                    // A previous attempt may have scanned its final batch before
                    // cancellation or an enhancement failure. Drain its durable
                    // requests even when no further blocks need scanning.
                    if enhancement
                        .run_checkpoint(&mut db, &mut client, None, &should_exit)
                        .await?
                        || should_exit()
                    {
                        return Ok(());
                    }
                    let released = enhancement.take_ready_resubmission();
                    // This path completes without a post-batch pass, so a
                    // transaction released by a final status observation is
                    // broadcast now against the validated tip. If the chain
                    // advanced, scan first: a new block may have mined it.
                    let ranges = if !released.is_empty() {
                        db.suggest_scan_ranges()
                            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?
                    } else {
                        Vec::new()
                    };
                    let outcome = resubmit_released_transactions(
                        &released,
                        allow_resubmit,
                        &ranges,
                        db_data_path,
                        lightwalletd_url,
                        &mut client,
                        &mut db,
                        current_tip_height,
                        || {
                            cancel.load(Ordering::Relaxed)
                                || desired_mode.load(Ordering::SeqCst) != running_mode
                        },
                    )
                    .await?;
                    if let ReleasedResubmission::TipAdvanced(fresh_height) = outcome {
                        current_tip_height = fresh_height;
                        enhancement::content_failures::at_tip(db_data_path, current_tip_height);
                        let promoted_ranges = db.suggest_scan_ranges().map_err(|e| {
                            SyncError::db(format!("suggest_scan_ranges after tip promotion: {e}"))
                        })?;
                        reset_promoted_scan_progress(
                            &promoted_ranges,
                            &mut initial_total,
                            &mut prev_remaining,
                        );
                        if initial_total > 0 {
                            progress_fn(begin_checking(
                                &mut checking_cycle,
                                initial_total,
                                current_tip_height,
                                &job,
                            ));
                        }
                        queued_ranges = Some(promoted_ranges);
                        completion_tip_validation_required = true;
                        continue;
                    }

                    enhancement_after_scan = true;
                    ensure_complete_scan_state(&mut db, current_tip_height)?;
                    break;
                }
            }
        };

        // Phase bookkeeping. `ScanPriority::Verify` ranges are
        // librustzcash's "please re-check these blocks to confirm their
        // chain linkage" signal, and always sort ahead of ChainTip /
        // Historic / etc. via `suggest_scan_ranges` (ORDER BY priority
        // DESC), so seeing a non-Verify range means the verify phase has
        // drained. The announcement booleans keep this purely for logs;
        // the rewind counters below are what actually matter.
        let is_verify_phase = range.priority() == ScanPriority::Verify;
        if is_verify_phase && !verify_phase_announced {
            log::info!("[{}] sync: entering verify phase", elapsed());
            verify_phase_announced = true;
        } else if !is_verify_phase && !main_phase_announced {
            if verify_phase_announced {
                log::info!(
                    "[{}] sync: verify phase complete, entering main scan",
                    elapsed()
                );
            } else {
                log::info!(
                    "[{}] sync: entering main scan phase (no verify work)",
                    elapsed()
                );
            }
            main_phase_announced = true;
        }

        let start = range.block_range().start;
        let range_end = range.block_range().end;
        let frontier_height = u32::from(start)
            .checked_sub(1)
            .ok_or_else(|| SyncError::other("scan range starts before a usable frontier"))?;
        // Batch size: as many blocks as fit `BATCH_BYTE_BUDGET` of
        // estimated compact-block bytes (compiled tree sizes and subtree
        // completion heights), up to `base_batch_size`, so dense
        // spam-window blocks get short batches without naming their heights.
        let Some((batch_size, end)) = scannable_batch_end(
            &work_model,
            base_batch_size,
            start,
            range_end,
            current_tip_height,
        ) else {
            if refresh_tip_for_queued_range(u32::from(start), &mut queued_tip_refreshed_for) {
                log::info!(
                    "[{}] sync: pending range {} starts after current tip {}; refreshing the tip",
                    elapsed(),
                    describe_block_range(range.block_range()),
                    current_tip_height,
                );
                force_tip_refresh = true;
                continue;
            }
            log::info!(
                "[{}] sync: pending range {} starts after current tip {}, waiting for tip advance",
                elapsed(),
                describe_block_range(range.block_range()),
                current_tip_height,
            );
            break;
        };
        let (batch_size, end) = match queued_batch_extension(&prefetch, start, end, &ranges) {
            Some(queued_end) => (u32::from(queued_end) - u32::from(start), queued_end),
            None => (batch_size, end),
        };
        let batch_blocks = u32::from(end).saturating_sub(u32::from(start)) as u64;
        // Ranges can change between batches (a rewind, a repair, a new
        // account); any added work raises the job total here.
        job.observe(work_model.pending_work(&ranges, current_tip_height));
        if reclassify_catch_up(&mut job, &ranges, catch_up_completed_height) {
            job.persist_if_due(db_data_path, true);
        }
        let batch_work =
            work_model.range_work(u64::from(u32::from(start)), u64::from(u32::from(end)));
        let (current_pct, display_target_percentage) =
            (job.fraction(), job.fraction_after(batch_work));
        progress_fn(SyncProgressEvent {
            scanned_height: u32::from(start) as u64,
            chain_tip_height: current_tip_height,
            percentage: current_pct,
            display_target_percentage,
            display_target_blocks: batch_blocks,
            remaining_scan_blocks: Some(pending_scan_blocks(&ranges)),
            pending_scan_start_height: earliest_pending_scan_start(&ranges),
            is_syncing: true,
            kind: SyncEventKind::Progress,
            checking: checking_progress(
                checking_cycle,
                initial_total,
                prev_remaining,
                batch_blocks,
            ),
            has_new_tx: false,
            phase_completed_units: 0,
            phase_total_units: 0,
            phase: "download".into(),
            sync_job_id: job.id().to_string(),
        });
        log::info!(
            "[{}] sync: scanning {}-{} (priority {:?}{}, batch={})",
            elapsed(),
            u32::from(start),
            u32::from(end) - 1,
            range.priority(),
            if is_verify_phase {
                ", verify phase"
            } else {
                ""
            },
            batch_size,
        );

        // A demoted direct route opens a fresh connection once its wait is
        // over and a batch that downloads directly comes up. The queue then
        // holds batches fetched over Tor, so it starts again from this batch.
        if let Some(route) = direct_route.as_mut().filter(|route| {
            route.retry_due(std::time::Instant::now())
                && batch_uses_direct_connection(
                    checking_cycle,
                    range.priority(),
                    start,
                    scanned_before_session,
                )
        }) {
            let opened = tokio::select! {
                biased;
                _ = watch_for_exit(&should_exit) => {
                    log::info!("[{}] sync: exiting while reopening the direct block connection", elapsed());
                    return Ok(());
                }
                opened = open_block_download_lwd_transport(lightwalletd_url) => opened,
            };
            match opened {
                Ok(transport) => {
                    log::info!("[{}] sync: reopened the direct block connection", elapsed());
                    block_client = CompactTxStreamerClient::new(transport);
                    route.reopened();
                    prefetch.clear();
                }
                Err(error) => {
                    let wait = route.demote(std::time::Instant::now());
                    log::warn!(
                        "[{}] sync: direct block download still unavailable ({error}); retrying in {}s",
                        elapsed(),
                        wait.as_secs(),
                    );
                }
            }
        }

        // Download blocks and their preceding frontier together, or consume a
        // matching tuple that an earlier iteration prefetched.
        let queued = take_queued_batch(&mut prefetch, start, end);
        let batch_is_direct = direct_route.as_ref().is_some_and(DirectBlockRoute::in_use)
            && batch_uses_direct_connection(
                checking_cycle,
                range.priority(),
                start,
                scanned_before_session,
            );
        // A queued batch reaches the fresh download only when it failed.
        let queued_direct_failed = batch_is_direct && queued.is_some();
        let mut direct_failed = false;
        let download_started = std::time::Instant::now();
        let batch = resolve_prefetched_or_download(queued, start, end, &should_exit, || {
            let (block_client, client, direct_failed) =
                (&block_client, &client, &mut direct_failed);
            async move {
                let (result, failed) =
                    download_with_direct_fallback(batch_is_direct, queued_direct_failed, |route| {
                        let mut route_client = match route {
                            BlockRoute::Direct => block_client.clone(),
                            BlockRoute::Tor => client.clone(),
                        };
                        async move {
                            download_scan_batch(&mut route_client, start, end - 1, network).await
                        }
                    })
                    .await;
                *direct_failed = failed;
                result
            }
        })
        .await?;
        // A network that lets the connection open but breaks its streams
        // fails every batch; a passing blip should not move a restore to Tor.
        if let Some(wait) = direct_route
            .as_mut()
            .filter(|_| batch_is_direct)
            .and_then(|route| route.record(direct_failed, std::time::Instant::now()))
        {
            log::warn!(
                "[{}] sync: direct block downloads failed {DIRECT_BLOCK_FAILURES_BEFORE_TOR} times in a row; downloading over Tor, retrying a fresh connection in {}s",
                elapsed(),
                wait.as_secs(),
            );
            block_client = client.clone();
            prefetch.clear();
        }
        let Some((block_source, from_state)) = batch else {
            log::info!("[{}] sync: exiting after download", elapsed());
            return Ok(());
        };
        if should_exit() {
            log::info!("[{}] sync: exiting after download", elapsed());
            return Ok(());
        }

        // Validate the tuple before projecting checkpoints or scheduling work
        // derived from it. Neither half is useful without the other.
        validate_scan_batch(&block_source, &from_state, start, end)?;

        let batch_waited = download_started.elapsed();
        let batch_bytes = block_source.encoded_bytes() as u64;
        let incoming_orchard_checkpoint_heights =
            migration_anchor_retention_required.then(|| block_source.orchard_checkpoint_heights());

        // Start the next tuples before scanning this batch. Dropping `prefetch`
        // on any early return, error, or reorg aborts their network tasks.
        if let Some(next_start) = (!should_exit())
            .then(|| prefetch_continues_from(&mut prefetch, end, range_end))
            .flatten()
        {
            let planned = prefetch_ranges(
                &work_model,
                base_batch_size,
                next_start,
                range_end,
                current_tip_height,
                PREFETCH_DEPTH.saturating_sub(prefetch.len()),
            );
            for &(prefetch_start, prefetch_end) in &planned {
                let prefetch_client = if batch_uses_direct_connection(
                    checking_cycle,
                    range.priority(),
                    prefetch_start,
                    scanned_before_session,
                ) {
                    block_client.clone()
                } else {
                    client.clone()
                };
                prefetch.push_back(Prefetch::spawn(
                    prefetch_start,
                    prefetch_end,
                    retry_quick_prefetch_failures(prefetch_start, prefetch_end - 1, move || {
                        let mut client = prefetch_client.clone();
                        async move {
                            download_scan_batch(
                                &mut client,
                                prefetch_start,
                                prefetch_end - 1,
                                network,
                            )
                            .await
                        }
                    }),
                ));
            }
            let next_start = planned.last().map_or(next_start, |r| r.1);
            if prefetch.len() < PREFETCH_DEPTH && next_start < range_end {
                log::debug!(
                    "[{}] sync: skipping prefetch from {} past current tip {}",
                    elapsed(),
                    u32::from(next_start),
                    current_tip_height,
                );
            }
        }
        let tip_check_due = post_batch_tip_check_due(
            u64::from(u32::from(end)),
            current_tip_height,
            last_post_batch_tip_check.elapsed(),
        );
        if tip_check_due {
            last_post_batch_tip_check = std::time::Instant::now();
        }
        let tip_prefetch = (tip_check_due && !should_exit())
            .then(|| TipPrefetch::spawn(client.clone(), lightwalletd_url, network));

        // Scan from memory. There are three reorg-adjacent signals from
        // librustzcash that all need to land on `SyncError::Continuity`
        // so the rewind recovery below fires:
        //
        //   - `ChainError::Scan(ScanError::PrevHashMismatch)` / `Scan(
        //     ScanError::BlockHeightDiscontinuity)` — the compact blocks
        //     we just downloaded don't chain to what we scanned last
        //     time. Detected via `is_continuity_error()`.
        //
        //   - `ChainError::Wallet(SqliteClientError::BlockConflict(h))` —
        //     `put_blocks` found an existing row for block `h` with a
        //     different hash. Per librustzcash: "indicates that a
        //     required rewind was not performed". Semantically identical
        //     to a continuity error and equally recoverable via
        //     `truncate_to_height`, so it gets the same treatment.
        //
        // Any other `ChainError::Wallet(e)` is a real DB failure and
        // becomes `SyncError::Db` (Fatal). Everything else (non-scan,
        // non-wallet — e.g. block-source errors, unrecognised scan
        // variants) becomes `SyncError::Other` (retry-with-backoff).
        let scan_started = std::time::Instant::now();
        let scan_result = with_wallet_db_write_lock("sync_engine.retain_and_scan_blocks", || {
            // Persist before scanning advances scan_queue: cancellation or a crash
            // after the scan must not lose this account's recovery work.
            queue_stored_transactions(db_data_path, &block_source)?;
            if let Some(incoming_checkpoint_heights) = &incoming_orchard_checkpoint_heights {
                let retained =
                    crate::wallet::sync::retain_migration_anchor_checkpoints_before_scan(
                        db_data_path,
                        network,
                        &mut db,
                        frontier_height,
                        u32::from(end),
                        incoming_checkpoint_heights,
                    )
                    .map_err(|error| {
                        SyncError::other(format!(
                            "retain migration anchor checkpoints before scan: {error}"
                        ))
                    })?;
                if retained > 0 {
                    log::info!(
                        "[{}] sync: ensured {retained} migration anchor checkpoint(s) retained",
                        elapsed(),
                    );
                }
            }
            // One notification per contiguous scan range, not per batch.
            if voting_scan_end != Some(start) {
                crate::wallet::voting::snapshot_changes::record(
                    db_data_path,
                    u32::from(start) as u64,
                );
            }
            voting_scan_end = Some(end);
            let power = scan_power::current();
            if last_scan_power != Some(power) {
                log::info!("[{}] sync: scanning at {power:?} power", elapsed());
                last_scan_power = Some(power);
            }
            // The next batch's decryption starts inside the same call, so it
            // runs at this batch's scan power too.
            scan_power::install(power, || {
                // The decryption started while the previous batch was written, if
                // it is this batch's.
                match next_decryption.take_if(|next| next.start == start && next.end == end) {
                    Some(next) => Ok(next.decryption),
                    None => decrypt_cached_blocks(
                        &network,
                        &block_source,
                        &db,
                        start,
                        batch_blocks as usize,
                    ),
                }
                .and_then(|decryption| {
                    // This batch's decryption was queued first, so the next
                    // batch's runs after it, while this batch is written. One
                    // already running for the queued batch is kept.
                    next_decryption = decryption_still_next(next_decryption.take(), &prefetch)
                        .or_else(|| start_next_decryption(&network, &db, &mut prefetch, end));
                    scan_decrypted_blocks(
                        &network,
                        &block_source,
                        &mut db,
                        start,
                        &from_state,
                        batch_blocks as usize,
                        decryption,
                    )
                })
            })
            .map_err(|e| match e {
                ChainError::Scan(scan_err) if scan_err.is_continuity_error() => {
                    let at_height = u32::from(scan_err.at_height()) as u64;
                    SyncError::continuity(at_height, scan_err.to_string())
                }
                ChainError::Wallet(SqliteClientError::BlockConflict(at)) => {
                    let at_height = u32::from(at) as u64;
                    SyncError::continuity(
                        at_height,
                        format!("BlockConflict at {at_height}: wallet rewind required"),
                    )
                }
                ChainError::Wallet(SqliteClientError::NonSequentialBlocks) => {
                    inconsistent_scan_batch_error(start)
                }
                ChainError::Wallet(wallet_err) if is_commitment_tree_root_conflict(&wallet_err) => {
                    let at_height = u32::from(start) as u64;
                    SyncError::continuity(
                        at_height,
                        format!(
                            "commitment tree root conflict while scanning from {at_height}: {wallet_err}"
                        ),
                    )
                }
                ChainError::Wallet(wallet_err) => {
                    // Transient SQLite lock contention (e.g. another wallet
                    // connection holds a write lock) must retry, not bail out.
                    // Everything else is treated as genuine DB failure and
                    // goes Fatal via the per-category retry policy.
                    if is_sqlite_lock_contention(&wallet_err) {
                        SyncError::other(format!("scan: SQLite lock contention: {wallet_err}"))
                    } else {
                        SyncError::db(format!("scan wallet: {wallet_err}"))
                    }
                }
                other => SyncError::other(format!("scan: {other}")),
            })
            .map(|summary| {
                // A snapshot can be registered while a contiguous range is
                // already scanning. Notify actual note changes as well, before
                // releasing the wallet write lock, so that registration cannot
                // miss a later mutation in that range.
                if summary.received_orchard_note_count() > 0
                    || summary.spent_orchard_note_count() > 0
                {
                    crate::wallet::voting::snapshot_changes::record(db_data_path, u32::from(start) as u64);
                }
                summary
            })
        });

        // A stored subtree root that disagrees with the scanned note commitments
        // fails nothing: the backend counts it and builds every shard from then
        // on, for the rest of the process.
        let stored_root_mismatches =
            zcash_client_backend::data_api::ll::wallet::stored_root_mismatches();
        if mismatches_not_yet_logged(&STORED_ROOT_MISMATCHES_LOGGED, stored_root_mismatches) {
            log::warn!(
                "[{}] sync: {stored_root_mismatches} downloaded subtree root(s) in this process \
                 disagreed with the scanned note commitments; shards are built in full from now on",
                elapsed(),
            );
        }

        // Handle the scan result. On a reorg we rewind the wallet to
        // `at_height - REWIND_DISTANCE` (bounded by `truncate_to_height`'s
        // nearest checkpoint) and restart the scan loop. librustzcash's
        // `suggest_scan_ranges` produces a fresh range list after the
        // truncate, so a `continue` is enough — no manual bookkeeping.
        //
        // Rewind budget is phase-scoped: verify-phase rewinds and
        // main-phase rewinds each have their own cap of
        // `MAX_REWINDS_PER_RUN`. A verify range that keeps flapping won't
        // exhaust the budget the main scan needs to handle an unrelated
        // later reorg.
        timing.record(
            batch_is_direct,
            u64::from(u32::from(end) - u32::from(start)),
            batch_bytes,
            batch_waited,
            scan_started.elapsed(),
        );
        if timing_since.elapsed() >= SYNC_TIMING_SUMMARY_EVERY {
            if cfg!(debug_assertions) {
                log::info!(
                    "[{}] sync: {}",
                    elapsed(),
                    timing.line(timing_since.elapsed(), scan_power::current())
                );
            }
            timing = SyncTimingSummary::default();
            timing_since = std::time::Instant::now();
        }
        let scan_summary = match scan_result {
            Ok(s) => s,
            Err(sync_err) => match sync_err.recovery_strategy() {
                RecoveryStrategy::Rewind { to_height } => {
                    let (phase_name, current_rewinds) = if is_verify_phase {
                        ("verify", &mut verify_rewinds_this_run)
                    } else {
                        ("main", &mut main_rewinds_this_run)
                    };
                    if *current_rewinds >= MAX_REWINDS_PER_RUN {
                        log::error!(
                            "[{}] sync: {phase_name} rewind budget exhausted \
                             ({}/{}); propagating error",
                            elapsed(),
                            *current_rewinds,
                            MAX_REWINDS_PER_RUN,
                        );
                        return Err(sync_err);
                    }
                    let rewind_attempt_index = *current_rewinds;
                    let rewind_distance =
                        sync_err.rewind_distance_for_attempt(rewind_attempt_index);
                    let requested_rewind_height = sync_err
                        .rewind_target_for_attempt(rewind_attempt_index)
                        .unwrap_or(to_height);
                    *current_rewinds += 1;
                    // `truncate_to_height` does NOT silently clamp to the
                    // nearest checkpoint. If the requested height is below
                    // the earliest available checkpoint it returns
                    // `SqliteClientError::RequestedRewindInvalid` with
                    // `safe_rewind_height: Option<BlockHeight>`. When
                    // `safe_rewind_height` is `Some(h)` the library is
                    // telling us the deepest checkpoint it can land on;
                    // retry at that height so a reorg near genesis (or
                    // right after a birthday-bounded import) still
                    // recovers. When it's `None` there is genuinely
                    // nowhere safe to rewind to, and we surface the
                    // failure as fatal.
                    let target =
                        block_height_from_u64(requested_rewind_height, "scan rewind target")?;
                    invalidate_transparent_checks_before_rewind(db_data_path)?;
                    let actual_rewind_height = with_wallet_db_write_lock(
                        "sync_engine.truncate_to_height",
                        || -> Result<BlockHeight, SyncError> {
                            match ledger_discovery::truncate(db_data_path, &mut db, target) {
                                Ok(h) => Ok(h),
                                Err(SqliteClientError::RequestedRewindInvalid {
                                    safe_rewind_height: Some(safe),
                                    requested_height,
                                }) => {
                                    log::warn!(
                                        "[{}] sync: {phase_name} rewind target {requested_height} \
                                         below earliest checkpoint; retrying at safe_rewind_height={safe}",
                                        elapsed(),
                                    );
                                    ledger_discovery::truncate(db_data_path, &mut db, safe).map_err(|e| {
                                        if is_sqlite_lock_contention(&e) {
                                            SyncError::other(format!(
                                                "truncate_to_height({safe}) retry: SQLite lock contention: {e}"
                                            ))
                                        } else {
                                            SyncError::db(format!(
                                                "truncate_to_height({safe}) retry after RequestedRewindInvalid: {e}"
                                            ))
                                        }
                                    })
                                }
                                Err(SqliteClientError::RequestedRewindInvalid {
                                    safe_rewind_height: None,
                                    requested_height,
                                }) => {
                                    log::error!(
                                        "[{}] sync: {phase_name} rewind to {requested_height} \
                                         rejected and no safe_rewind_height is available; \
                                         cannot recover from this reorg in-place",
                                        elapsed(),
                                    );
                                    Err(SyncError::db(format!(
                                        "truncate_to_height({requested_height}): no safe rewind height"
                                    )))
                                }
                                Err(e) if is_sqlite_lock_contention(&e) => {
                                    // Transient lock contention on the rewind. The
                                    // outer retry wrapper will re-invoke run_sync_impl
                                    // after a backoff, which re-detects the continuity
                                    // error and triggers the rewind again. If the
                                    // lock has cleared by then, the retry succeeds.
                                    Err(SyncError::other(format!(
                                        "truncate_to_height({requested_rewind_height}): SQLite lock contention: {e}"
                                    )))
                                }
                                Err(e) => Err(SyncError::db(format!(
                                    "truncate_to_height({requested_rewind_height}): {e}"
                                ))),
                            }
                        },
                    )?;
                    let current_tip = block_height_from_u64(
                        current_tip_height,
                        "current lightwalletd chain tip",
                    )?;
                    reset_private_recovery_after_reorg(db_data_path, current_tip_height);
                    let post_rewind_ranges = with_wallet_db_write_lock(
                        "sync_engine.update_chain_tip.after_rewind",
                        || -> Result<Vec<ScanRange>, SyncError> {
                            db.update_chain_tip(current_tip).map_err(|e| {
                                SyncError::db(format!(
                                    "update_chain_tip({current_tip_height}) after rewind: {e}"
                                ))
                            })?;
                            db.suggest_scan_ranges().map_err(|e| {
                                SyncError::db(format!("suggest_scan_ranges after rewind: {e}"))
                            })
                        },
                    )?;
                    let post_rewind_pending = pending_scan_blocks(&post_rewind_ranges);
                    let first_pending = first_pending_scan_range(&post_rewind_ranges)
                        .unwrap_or_else(|| "none".into());
                    let summary = sync::wallet_scan_heights(&mut db).map_err(SyncError::db)?;
                    let actual_rewind_height_u64 = u32::from(actual_rewind_height) as u64;
                    log::info!(
                        "[{}] sync: {phase_name} rewound to {actual_rewind_height} \
                         after reorg (requested={requested_rewind_height}, \
                         distance={rewind_distance}, attempt {}/{}); \
                         post_rewind_pending={post_rewind_pending}, first_pending={first_pending}, \
                         summary={summary:?}; restarting scan loop",
                        elapsed(),
                        *current_rewinds,
                        MAX_REWINDS_PER_RUN,
                    );
                    force_witness_check_this_run = true;
                    if actual_rewind_height_u64 < current_tip_height && post_rewind_pending == 0 {
                        return Err(SyncError::continuity(
                            current_tip_height,
                            format!(
                                "post-rewind scan queue empty after rewinding to \
                                 {actual_rewind_height_u64}, but lightwalletd tip is \
                                 {current_tip_height}"
                            ),
                        ));
                    }
                    if post_rewind_pending > 0 {
                        // Rewound blocks count as added job work, measured at
                        // the next batch.
                        initial_total = post_rewind_pending;
                        prev_remaining = post_rewind_pending;
                        if checking_cycle > 0 && post_rewind_pending > 0 {
                            progress_fn(begin_checking(
                                &mut checking_cycle,
                                post_rewind_pending,
                                current_tip_height,
                                &job,
                            ));
                        }
                    }
                    prefetch.clear();
                    continue;
                }
                RecoveryStrategy::RetryWithBackoff | RecoveryStrategy::Fatal => {
                    return Err(sync_err);
                }
            },
        };

        if migration_anchor_retention_required {
            let retained = with_wallet_db_write_lock(
                "sync_engine.retain_migration_anchor_checkpoints",
                || {
                    crate::wallet::sync::retain_prepared_note_anchor_checkpoints_after_scan(
                        db_data_path,
                        network,
                        &mut db,
                    )
                },
            )
            .map_err(|error| {
                SyncError::other(format!(
                    "retain migration anchor checkpoints after scan: {error}"
                ))
            })?;
            if retained > 0 {
                log::info!(
                    "[{}] sync: retained {retained} migration anchor checkpoint(s)",
                    elapsed(),
                );
            }
            // Re-check so a run that finished, was abandoned, or released its
            // last reference mid-sync stops paying for pre-scan inspection and
            // post-scan reconciliation. A sync without a migration never enters
            // either path.
            let still_required =
                crate::wallet::sync::migration_anchor_retention_required(db_data_path, network)
                    .map_err(SyncError::db)?;
            if !still_required {
                migration_anchor_retention_required = false;
                log::info!(
                    "[{}] sync: migration anchor retention released (base_batch={})",
                    elapsed(),
                    base_batch_size,
                );
            }
        }

        if should_exit() {
            log::info!("[{}] sync: exiting after scan", elapsed());
            return Ok(());
        }

        // Truncation can temporarily clear a transaction's mined height while
        // retaining note positions that prove compact scanning found it mined.
        // Exclude those transactions from recovery resubmission while scanning
        // can still restore their mined heights. Only a batch that checks the
        // tip resubmits, so the others skip the lookup.
        let resubmit_exclusions = if tip_check_due {
            let post_scan_ranges = db
                .suggest_scan_ranges()
                .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
            recovery_resubmit_exclusions(db_data_path, &post_scan_ranges)?
        } else {
            HashSet::new()
        };

        // Status and transparent history run before the routed payload snapshot,
        // so transactions discovered by history are enhanced in this checkpoint.
        // Status lookups run only on a batch that checks the tip, so a status
        // recovered here is completed by this batch's check, made after them.
        if enhancement
            .run_batch_checkpoint(
                &mut db,
                &mut client,
                &block_source,
                tip_check_due,
                &should_exit,
            )
            .await?
        {
            log::info!("[{}] sync: exiting during enhancement", elapsed());
            return Ok(());
        }
        enhancement_after_scan = true;
        // A history batch between tip checks skips its own; the schedule never
        // depends on what the wallet holds.
        let check_tip = tip_check_due;
        let ready = enhancement.take_ready_resubmission();

        // Post-batch tip reconciliation and auto-resubmit. The resubmit calls
        // match zcash-android-wallet-sdk's lines 593/701 call sites (end of a
        // verify batch / end of a regular batch).
        //
        // We deliberately re-fetch the chain tip via
        // `get_latest_block` before each pass instead of reusing
        // `tip.height` captured once at the top of `run_sync_impl`.
        // `get_resubmittable_txs` decides "still inside expiry
        // window" with `expiry_height > current_height`; using the
        // stale top-of-sync tip meant a long catch-up session
        // (several thousand blocks) could keep rebroadcasting txs
        // whose expiry had already passed against the real chain
        // tip. Refreshing here is one extra unary gRPC per batch,
        // which is cheap compared to the batch download itself and
        // closes the "resubmit expired tx forever" regression
        // caught by Codex 2nd-round review finding 2.
        //
        // Pre-flight guard matches the one at the startup resubmit
        // call site — if cancel or mode-change landed during
        // `run_checkpoint` (which can spend a second or two on a transparent-
        // address scan), bail before opening a single
        // new `send_transaction` RPC. The helper also consults the
        // same closure between candidates and before each retry so
        // a cancel arriving mid-pass stops initiating further
        // broadcasts.
        //
        // Best-effort: helper swallows per-tx failures, we ignore
        // the return value, and if the tip refresh itself fails we
        // log and skip the pass rather than falling back to the
        // stale height (the whole point of the refresh is to avoid
        // rebroadcasting against a stale expiry window).
        if should_exit() {
            log::info!(
                "[{}] sync: cancel/mode observed before post-batch resubmit, exiting",
                elapsed(),
            );
            return Ok(());
        }
        if check_tip {
            // The prefetch started before the scan and is usually complete by
            // now; a released status is completed only below, with resubmission.
            let tip_check_started = std::time::Instant::now();
            let (tip_requested_at, fresh_tip_result) = post_batch_tip(
                tip_prefetch,
                allow_resubmit && !ready.is_empty(),
                &mut client,
                lightwalletd_url,
                network,
                &should_exit,
            )
            .await;
            timing.tip_waited += tip_check_started.elapsed();
            let Some(fresh_tip_result) = fresh_tip_result
                .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
            else {
                log::info!("[{}] sync: exiting after post-batch tip fetch", elapsed());
                return Ok(());
            };
            match fresh_tip_result {
                Ok(fresh_tip) => {
                    let fresh_tip_height = block_height_from_u64(
                        fresh_tip.height,
                        "post-batch lightwalletd chain tip",
                    )?;

                    let stored_hash =
                        stored_hash_for_refreshed_tip(&db, current_tip_height, fresh_tip.height)?;
                    let relation = unless_exiting(
                        &should_exit,
                        classify_refreshed_tip_with_fallback(
                            &mut client,
                            current_tip_height,
                            stored_hash,
                            fresh_tip.height,
                            &fresh_tip.hash,
                        ),
                    )
                    .await;
                    let Some(relation) = relation
                        .and_then(|result| tip_rpc_result_unless_exiting(result, should_exit()))
                    else {
                        log::info!(
                            "[{}] sync: exiting after post-batch tip validation",
                            elapsed()
                        );
                        return Ok(());
                    };
                    let relation = relation?;
                    match relation {
                        RefreshedTipRelation::Unchanged => {
                            last_completion_tip_validation = tip_requested_at;
                            completion_tip_validation_required = false;
                            last_periodic_tip_refresh_attempt = std::time::Instant::now();
                        }
                        RefreshedTipRelation::UnchangedUnverified => {
                            completion_tip_validation_required = true;
                            last_periodic_tip_refresh_attempt = std::time::Instant::now();
                        }
                        RefreshedTipRelation::Advanced => {
                            match with_wallet_db_write_lock(
                                "sync_engine.update_chain_tip.post_batch",
                                || db.update_chain_tip(fresh_tip_height),
                            ) {
                                Ok(_) => {
                                    current_tip_height = fresh_tip.height;
                                    enhancement::content_failures::at_tip(
                                        db_data_path,
                                        current_tip_height,
                                    );
                                    completion_tip_validation_required = true;
                                    last_periodic_tip_refresh_attempt = std::time::Instant::now();
                                }
                                Err(e) => {
                                    completion_tip_validation_required = true;
                                    log::warn!(
                                        "[{}] sync: post-batch update_chain_tip({}) \
                                             failed, keeping tip at {current_tip_height}: {e}",
                                        elapsed(),
                                        fresh_tip.height,
                                    );
                                }
                            }
                        }
                        RefreshedTipRelation::ServerBehind => {
                            return Err(lagging_lightwalletd_tip(
                                current_tip_height,
                                fresh_tip.height,
                            ));
                        }
                        RefreshedTipRelation::Reorg => {
                            if main_rewinds_this_run >= MAX_REWINDS_PER_RUN {
                                return Err(SyncError::continuity(
                                    fresh_tip.height,
                                    "post-batch tip reorg rewind budget exhausted",
                                ));
                            }
                            main_rewinds_this_run += 1;
                            prefetch.clear();
                            let (actual_height, repair_ranges, pending_blocks) =
                                rewind_for_confirmed_tip_reorg(
                                    db_data_path,
                                    &mut db,
                                    fresh_tip.height,
                                )?;
                            log::warn!(
                                "[{}] sync: post-batch tip proved a reorg; rewound to {} \
                                     and queued {} block(s) toward tip {}",
                                elapsed(),
                                actual_height,
                                pending_blocks,
                                fresh_tip.height,
                            );
                            current_tip_height = fresh_tip.height;
                            enhancement::content_failures::at_tip(db_data_path, current_tip_height);
                            initial_total = pending_blocks;
                            prev_remaining = pending_blocks;
                            if checking_cycle > 0 && pending_blocks > 0 {
                                progress_fn(begin_checking(
                                    &mut checking_cycle,
                                    pending_blocks,
                                    current_tip_height,
                                    &job,
                                ));
                            }
                            queued_ranges = Some(repair_ranges);
                            completion_tip_validation_required = true;
                            last_periodic_tip_refresh_attempt = std::time::Instant::now();
                            continue;
                        }
                    }

                    // Use the just-observed network height for the expiry
                    // filter. The authoritative progress tip was promoted
                    // above only when its DB update succeeded; lower or
                    // divergent responses cannot reach this broadcast path.
                    if allow_resubmit {
                        complete_verified_recovery_statuses(db_data_path, &ready, relation)?;
                        let _ = crate::wallet::sync::resubmit_pending_transactions(
                            db_data_path,
                            lightwalletd_url,
                            &mut client,
                            u32::from(fresh_tip_height),
                            &resubmit_exclusions,
                            || {
                                cancel.load(Ordering::Relaxed)
                                    || desired_mode.load(Ordering::SeqCst) != running_mode
                            },
                        )
                        .await;
                    }
                }
                Err(e) => {
                    completion_tip_validation_required = true;
                    log::warn!(
                        "[{}] sync: post-batch tip refresh failed; skipping \
                         tip promotion and resubmit pass: {e}",
                        elapsed(),
                    );
                }
            }
        }
        if should_exit() {
            log::info!("[{}] sync: exiting after post-batch pass", elapsed());
            return Ok(());
        }

        // Report progress
        let has_new_tx = scan_summary.received_sapling_note_count() > 0
            || scan_summary.spent_sapling_note_count() > 0
            || scan_summary.received_orchard_note_count() > 0
            || scan_summary.spent_orchard_note_count() > 0;
        let post_ranges = db
            .suggest_scan_ranges()
            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
        let remaining = pending_scan_blocks(&post_ranges);
        // Adjust initial_total if new ranges appeared (e.g. new account added mid-sync).
        // Use scanned + remaining as the true total, so progress never goes backward.
        let scanned_so_far = initial_total.saturating_sub(prev_remaining);
        let new_total = scanned_so_far + remaining;
        if new_total > initial_total {
            log::info!(
                "[{}] sync: new scan ranges detected, adjusted total {} -> {}",
                elapsed(),
                initial_total,
                new_total
            );
            initial_total = new_total;
            if checking_cycle > 0 {
                // The denominator changed. Let Checking show its recalculated
                // fraction instead of holding the previous UI progress floor.
                checking_cycle += 1;
            }
        }
        job.observe_after_batch(
            batch_work,
            work_model.pending_work(&post_ranges, current_tip_height),
        );
        prev_remaining = remaining;
        let next_display_range = next_pending_scan_range(&post_ranges, current_tip_height)
            .and_then(|r| {
                let next_start = r.block_range().start;
                planned_batch_end(
                    &work_model,
                    base_batch_size,
                    next_start,
                    r.block_range().end,
                )
                .map(|(_, next_end)| (next_start, next_end))
            });
        let (next_display_target_blocks, next_work) = next_display_range
            .map(|(next_start, next_end)| {
                (
                    u32::from(next_end).saturating_sub(u32::from(next_start)) as u64,
                    work_model.range_work(
                        u64::from(u32::from(next_start)),
                        u64::from(u32::from(next_end)),
                    ),
                )
            })
            .unwrap_or((0, 0.0));
        let (pct, display_target_percentage) = (job.fraction(), job.fraction_after(next_work));
        let progress = SyncProgressEvent {
            scanned_height: u32::from(end) as u64,
            chain_tip_height: current_tip_height,
            percentage: pct,
            display_target_percentage,
            display_target_blocks: next_display_target_blocks,
            remaining_scan_blocks: Some(remaining),
            pending_scan_start_height: earliest_pending_scan_start(&post_ranges),
            is_syncing: true,
            kind: SyncEventKind::Progress,
            checking: checking_progress(
                checking_cycle,
                initial_total,
                remaining,
                next_display_target_blocks,
            ),
            has_new_tx,
            phase_completed_units: 0,
            phase_total_units: 0,
            phase: "scan".into(),
            sync_job_id: job.id().to_string(),
        };
        // Save the batch that finishes the scan at once, so a process killed
        // before the sync completes leaves a finished job for the next
        // attempt. Work the Checking stage finds afterwards raises the total
        // and is saved like other new work: a process killed in that stage
        // resumes at the lower fraction, as a main scan.
        job.persist_if_due(db_data_path, job.remaining() <= 0.0);
        log::info!(
            "[{}] sync: {:.1}% (work remaining={:.0}/{:.0}, blocks remaining={})",
            elapsed(),
            progress.percentage * 100.0,
            job.remaining(),
            job.total(),
            remaining,
        );
        progress_fn(progress);
        #[cfg(debug_assertions)]
        maybe_sleep_for_e2e_sync_batch_delay().await;
    }

    // A mode change can expose ordinary transaction-ID enhancement requests
    // while the compact scan queue is already empty. Always service both
    // queues once at completion so disabling private recovery takes effect
    // without waiting for another block to arrive.
    if needs_completion_enhancement_pass(enhancement_after_scan) {
        if enhancement
            .run_checkpoint(&mut db, &mut client, None, &should_exit)
            .await?
            || should_exit()
        {
            log::info!(
                "[{}] sync: exiting during completion enhancement",
                elapsed()
            );
            return Ok(());
        }
    }

    let (final_scanned_height, final_tip_height) =
        ensure_complete_scan_state(&mut db, current_tip_height)?;
    for id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(e.to_string()))?
    {
        if !ledger_discovery::is_ready(db_data_path, network, id).map_err(SyncError::db)? {
            return Err(SyncError::other(
                "Ledger recovery was invalidated during sync; retrying",
            ));
        }
    }
    // Reconcile migration chain state only after the scan queue is fully
    // drained, then update generic wallet locks for denomination outputs that
    // became visible in this run. This is intentionally repeated after every
    // completed sync because a later block may mine an output that was
    // unresolved in an earlier run.
    crate::wallet::sync::reconcile_wallet_locks_after_sync(db_data_path, network)
        .map_err(SyncError::db)?;
    if migration_anchor_retention_required {
        with_wallet_db_write_lock(
            "sync_engine.retain_migration_anchor_checkpoints.final",
            || {
                crate::wallet::sync::retain_prepared_note_anchor_checkpoints_after_scan(
                    db_data_path,
                    network,
                    &mut db,
                )
            },
        )
        .map_err(|error| {
            SyncError::other(format!(
                "retain migration anchor checkpoints after sync: {error}"
            ))
        })?;
    }
    log::info!(
        "[{}] sync: completed (fully_scanned={}, chain_tip={})",
        elapsed(),
        final_scanned_height,
        final_tip_height,
    );
    refresh_transparent_receive_cache(db_data_path, network, final_scanned_height);
    with_wallet_db_write_lock("sync_engine.mark_sync_completed", || {
        mark_sync_completed(db_data_path, final_tip_height)
    })
    .map_err(SyncError::db)?;
    job.complete();
    // Final progress
    let final_progress = SyncProgressEvent {
        scanned_height: final_scanned_height,
        chain_tip_height: final_tip_height,
        percentage: 1.0,
        display_target_percentage: 1.0,
        display_target_blocks: 0,
        remaining_scan_blocks: Some(0),
        pending_scan_start_height: None,
        is_syncing: false,
        kind: SyncEventKind::Completed,
        checking: None,
        has_new_tx: false,
        phase_completed_units: 0,
        phase_total_units: 0,
        phase: String::new(),
        sync_job_id: job.id().to_string(),
    };
    progress_fn(final_progress);

    // Private transparent recovery runs once completion is reported, so
    // waiting for a lagging publication never delays the sync's own result.
    // Background preparation syncs skip it; see [`transparent_followup`].
    if !should_exit() {
        let first = current_active_sync_account(active_account_target)
            .and_then(|uuid| keys::parse_account_uuid(&uuid).ok());
        transparent_followup(
            running_mode,
            &mut db,
            db_data_path,
            network,
            enhancement.policy(),
            &transparent_ledger::TransparentPirSource::new(db_data_path, network),
            first,
            &should_exit,
            progress_fn,
            (final_scanned_height, final_tip_height),
        )
        .await;
    }

    // Loop 4, transparent txid enhancement, only fills in detail views. It
    // runs once completion is reported, under the same cancellation, and
    // never fails the sync. Background preparation syncs skip it.
    if !should_exit() && running_mode != 2 {
        transparent_details::transparent_details_followup(
            &mut db,
            db_data_path,
            network,
            enhancement.policy(),
            &client,
            &should_exit,
            progress_fn,
            (final_scanned_height, final_tip_height),
        )
        .await;
    }

    // Transparent receivers belonging to inactive accounts do not affect the
    // account-scoped balance shown for this completed foreground sync. Keep
    // the active account on the correctness-critical path, then refresh all
    // remaining accounts after reporting chain-sync completion. The FRB
    // stream stays open until this bounded follow-up finishes, so lock/reset
    // cancellation and the global running guard still own its lifetime.
    if defer_inactive_transparent_refresh && !should_exit() {
        let active_account_uuid = active_account_uuid
            .as_deref()
            .expect("deferred refresh has active account");
        log::info!(
            "[{}] sync: starting deferred inactive-account transparent UTXO refresh",
            elapsed(),
        );
        let mut deferred_attempt = 1;
        let mut deferred_received_outputs = false;
        let deferred_result = loop {
            let result = refresh_utxos(
                &mut client,
                db_data_path,
                &mut db,
                network,
                enhancement.policy(),
                BlockHeight::from_u32(final_tip_height as u32),
                TransparentAccountSelection::Except(active_account_uuid),
                active_account_target,
                &mut deferred_received_outputs,
                None,
                &should_exit,
            )
            .await;
            match result {
                Ok(summary) => break Ok(summary),
                Err(error)
                    if deferred_attempt < MAX_DEFERRED_TRANSPARENT_REFRESH_ATTEMPTS
                        && !should_exit() =>
                {
                    let delay_secs = 1u64 << deferred_attempt;
                    log::warn!(
                        "[{}] sync: deferred transparent UTXO refresh attempt {}/{} failed; retrying in {}s: {}",
                        elapsed(),
                        deferred_attempt,
                        MAX_DEFERRED_TRANSPARENT_REFRESH_ATTEMPTS,
                        delay_secs,
                        error,
                    );
                    let retry_delay =
                        tokio::time::sleep(std::time::Duration::from_secs(delay_secs));
                    tokio::pin!(retry_delay);
                    tokio::select! {
                        biased;
                        _ = watch_for_exit(&should_exit) => break Err(error),
                        _ = &mut retry_delay => {}
                    }
                    deferred_attempt += 1;
                }
                Err(error) => break Err(error),
            }
        };
        match &deferred_result {
            Ok(summary) => {
                log::info!(
                    "[{}] sync: deferred transparent UTXO refresh finished (accounts={}, received_outputs={})",
                    elapsed(),
                    summary.matched_accounts,
                    deferred_received_outputs,
                );
            }
            Err(error) => log::warn!(
                "[{}] sync: deferred inactive-account transparent UTXO refresh failed after {} attempt(s); it will retry on a later sync: {}",
                elapsed(),
                deferred_attempt,
                error,
            ),
        }
        if deferred_received_outputs && !should_exit() {
            if let Err(error) = enhancement
                .run_checkpoint(&mut db, &mut client, None, &should_exit)
                .await
            {
                log::warn!(
                    "[{}] sync: deferred transparent transaction enhancement failed; it will retry on a later sync: {}",
                    elapsed(),
                    error,
                );
            }
            // The user may have switched accounts while the deferred pass was
            // running. Re-emit completion even after a terminal partial
            // failure so Dart refreshes whichever account is active now from
            // every output that was committed by an earlier successful group.
            progress_fn(SyncProgressEvent {
                scanned_height: final_scanned_height,
                chain_tip_height: final_tip_height,
                percentage: 1.0,
                display_target_percentage: 1.0,
                display_target_blocks: 0,
                remaining_scan_blocks: Some(0),
                pending_scan_start_height: None,
                is_syncing: false,
                kind: SyncEventKind::Completed,
                checking: None,
                has_new_tx: true,
                phase_completed_units: 0,
                phase_total_units: 0,
                phase: String::new(),
                sync_job_id: job.id().to_string(),
            });
        }
    }

    if !should_exit() {
        let mut changed = false;
        // Each check sends an ephemeral address, so it is authorized under
        // the transparent policy this sync captured.
        if let Err(error) = ephemeral_checks::run(
            lightwalletd_url,
            &mut db,
            db_data_path,
            network,
            enhancement.policy(),
            BlockHeight::from_u32(final_tip_height as u32),
            &mut changed,
            &should_exit,
        )
        .await
        {
            log::warn!(
                "[{}] sync: ephemeral address check failed; it will retry on a later sync: {}",
                elapsed(),
                error,
            );
        }
        // Refresh even after a failure that followed stored transactions.
        if changed && !should_exit() {
            progress_fn(SyncProgressEvent {
                scanned_height: final_scanned_height,
                chain_tip_height: final_tip_height,
                percentage: 1.0,
                display_target_percentage: 1.0,
                display_target_blocks: 0,
                remaining_scan_blocks: Some(0),
                pending_scan_start_height: None,
                is_syncing: false,
                kind: SyncEventKind::Completed,
                checking: None,
                has_new_tx: true,
                phase_completed_units: 0,
                phase_total_units: 0,
                phase: String::new(),
                sync_job_id: job.id().to_string(),
            });
        }
    }

    Ok(())
}

/// Runs private transparent recovery once a sync has completed and reported
/// completion at `completed` (scanned height, chain tip), then refreshes the
/// transparent receive cache and reports a
/// [`SyncEventKind::FollowupUpdated`] event so the UI re-reads the balances,
/// shielding state and receive address the run may have changed.
///
/// Recovery can record receipts at addresses the receive cache lists as
/// unused, so the cache is marked dirty before the run and only a refresh
/// after it marks an account clean again. A run that exits, or a refresh that
/// fails, leaves the cache dirty: reads fall back to the wallet DB until the
/// next sync refreshes it.
///
/// Recovery keeps its own progress in the library and never fails the sync:
/// errors and outcomes are only logged. With private queries off, the policy
/// captures `Public`, so the run returns before any read, and the cache and
/// UI are left alone; nothing is reported either when the run exited.
///
/// A background preparation sync (`running_mode` 2) skips the run entirely:
/// it holds the global sync guard, so a foreground sync requested meanwhile
/// waits behind it, and recovery runs on the next foreground sync instead.
#[allow(clippy::too_many_arguments)]
async fn transparent_followup<S: transparent_ledger::RecoverySource>(
    running_mode: u8,
    db: &mut WalletDatabase,
    db_data_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    source: &S,
    first: Option<AccountUuid>,
    should_exit: &(dyn Fn() -> bool + Sync),
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
    completed: (u64, u64),
) {
    if !runs_transparent_followup(running_mode) {
        return;
    }
    let Some(schedule) = transparent_ledger::recovery_schedule(db_data_path, completed.1) else {
        return;
    };
    let private = policy.transparent_mode()
        != zcash_client_backend::data_api::transparent_ledger::TransparentLedgerMode::Public;
    if private {
        if let Err(e) = transparent_receive_cache::mark_all_dirty(db_data_path) {
            log::warn!(
                "[{}] sync: could not mark the transparent receive cache dirty: {}",
                elapsed(),
                e
            );
        }
    }
    match transparent_ledger::run(
        db,
        db_data_path,
        network,
        policy,
        source,
        first,
        schedule,
        std::time::Instant::now,
        should_exit,
    )
    .await
    {
        // Nothing was recorded; a durable `Public` policy found after marking
        // the cache dirty still restores it below.
        Ok(transparent_ledger::RunOutcome::NotEnabled) => {
            if private {
                refresh_transparent_receive_cache(db_data_path, network, completed.0);
            }
            return;
        }
        // A cancelled run does not use up the block: the cancellation is the
        // app's own, and the next sync at this tip runs again.
        Ok(transparent_ledger::RunOutcome::Exited) => {
            log::info!(
                "[{}] sync: exiting during private transparent recovery",
                elapsed()
            );
            return;
        }
        Ok(outcome) => {
            transparent_ledger::recovery_ran(db_data_path, completed.1);
            log::info!(
                "[{}] sync: private transparent recovery: {:?}",
                elapsed(),
                outcome
            )
        }
        // Commits applied before the failure stay durable.
        Err(error) => {
            transparent_ledger::recovery_ran(db_data_path, completed.1);
            log::warn!(
                "[{}] sync: private transparent recovery failed: {}",
                elapsed(),
                error
            )
        }
    }
    refresh_transparent_receive_cache(db_data_path, network, completed.0);
    progress_fn(followup_updated_event(completed));
}

/// Rewrites every account's transparent receive cache from the wallet DB as
/// of `scanned_height`, so the receive screen never offers an address the
/// wallet has seen funds at. Failures are logged; a later sync retries.
fn refresh_transparent_receive_cache(
    db_data_path: &str,
    network: WalletNetwork,
    scanned_height: u64,
) {
    match transparent_receive_cache::refresh_all_from_wallet_db(
        db_data_path,
        network,
        Some(scanned_height),
    ) {
        Ok(refreshed) => log::info!(
            "[{}] sync: refreshed transparent receive cache ({} accounts)",
            elapsed(),
            refreshed
        ),
        Err(e) => log::warn!(
            "[{}] sync: transparent receive cache refresh failed: {}",
            elapsed(),
            e
        ),
    }
}

/// Whether a sync running in `running_mode` runs private transparent
/// recovery after completing: foreground syncs do, background preparation
/// syncs (mode 2) never do.
pub(crate) fn runs_transparent_followup(running_mode: u8) -> bool {
    running_mode != 2
}

// ==================== Helpers ====================

fn open_db(path: &str, network: WalletNetwork) -> Result<WalletDatabase, SyncError> {
    open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("DB open: {e}")))
}

/// Returns `true` when `err` wraps a transient SQLite lock-contention
/// primary code (`SQLITE_BUSY` or `SQLITE_LOCKED`). These are not
/// corruption — they fire when another connection currently holds a
/// write lock on the wallet DB. The wallet opens separate connections
/// for balance queries, the send flow, and the sync loop itself, so
/// this condition is reachable in normal operation and must be
/// classified as transient (retry-with-backoff) rather than fatal.
///
/// Extended codes (`SQLITE_BUSY_RECOVERY`, `SQLITE_BUSY_SNAPSHOT`,
/// `SQLITE_BUSY_TIMEOUT`, `SQLITE_LOCKED_SHAREDCACHE`,
/// `SQLITE_LOCKED_VTAB`) are all rolled up into the two primary codes
/// by `rusqlite`, so matching on `ErrorCode::DatabaseBusy` /
/// `DatabaseLocked` catches all of them.
fn is_sqlite_lock_contention(err: &SqliteClientError) -> bool {
    if let SqliteClientError::DbError(rusqlite::Error::SqliteFailure(inner, _)) = err {
        matches!(
            inner.code,
            rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked,
        )
    } else {
        false
    }
}

fn is_commitment_tree_root_conflict(err: &SqliteClientError) -> bool {
    matches!(
        err,
        SqliteClientError::CommitmentTree(ShardTreeError::Insert(InsertionError::Conflict(_)))
    )
}

fn is_witness_position_beyond_tree(err: &SqliteClientError) -> bool {
    matches!(
        err,
        SqliteClientError::CommitmentTree(ShardTreeError::Query(QueryError::NotContained(_)))
    )
}

fn clear_unmined_note_commitment_positions(db_data_path: &str) -> Result<usize, SyncError> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("open DB to repair unmined note positions: {e}")))?;
    let tx = conn
        .transaction()
        .map_err(|e| SyncError::db(format!("begin unmined note position repair: {e}")))?;
    let mut cleared = 0;

    for table in [
        "sapling_received_notes",
        "orchard_received_notes",
        "ironwood_received_notes",
    ] {
        let exists = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
                [table],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|e| SyncError::db(format!("inspect {table} before position repair: {e}")))?;
        if !exists {
            continue;
        }

        cleared += tx
            .execute(
                &format!(
                    "UPDATE {table} AS rn
                     SET commitment_tree_position = NULL
                     WHERE commitment_tree_position IS NOT NULL
                     AND EXISTS (
                         SELECT 1 FROM transactions AS tx
                         WHERE tx.id_tx = rn.transaction_id
                         AND tx.mined_height IS NULL
                     )"
                ),
                [],
            )
            .map_err(|e| SyncError::db(format!("repair unmined positions in {table}: {e}")))?;
    }

    tx.commit()
        .map_err(|e| SyncError::db(format!("commit unmined note position repair: {e}")))?;
    Ok(cleared)
}

/// The chain state preceding a scan batch that starts at `start`, when it is
/// known without asking lightwalletd: empty at Sapling activation, or a
/// compiled mainnet checkpoint (see [`tree_states`]). Account birthdays are
/// rounded to the checkpoint grid, so a restored account's first batch gets one
/// whenever its bucket is in the table.
fn local_batch_start_state(
    network: WalletNetwork,
    start: BlockHeight,
) -> Result<Option<chain::ChainState>, SyncError> {
    if should_use_empty_chain_state(&network, start)? {
        return Ok(Some(chain::ChainState::empty(
            start - 1,
            BlockHash([0u8; 32]),
        )));
    }
    Ok(tree_states::mainnet_chain_state(
        network,
        u64::from(u32::from(start - 1)),
    ))
}

fn should_use_empty_chain_state(
    network: &WalletNetwork,
    start: BlockHeight,
) -> Result<bool, SyncError> {
    let sapling_activation_height = network
        .activation_height(NetworkUpgrade::Sapling)
        .ok_or_else(|| SyncError::parse("Sapling activation height is unavailable"))?;
    Ok(start <= sapling_activation_height)
}

// ==================== Tests ====================
//
// Error-taxonomy tests live alongside their types in `error.rs`. Tests here
// cover the small orchestration helpers that remain in this module.

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    use std::sync::atomic::AtomicUsize;
    use std::sync::Mutex;
    use std::time::Duration;
    use tokio::sync::{Barrier, Notify, Semaphore};
    use zcash_client_backend::proto::compact_formats::CompactBlock;

    /// The 2022-23 spam window (`zcash-android-wallet-sdk`'s
    /// `SANDBLASTING_RANGE`), where the mobile byte budget comes from.
    const SANDBLASTING_START: u32 = 1_710_000;
    const SANDBLASTING_END: u32 = 2_050_000;

    #[test]
    fn only_a_large_download_over_tor_fetches_blocks_directly() {
        assert!(!fetches_blocks_directly(false, true, f64::MAX));
        assert!(!fetches_blocks_directly(
            true,
            true,
            DIRECT_BLOCK_DOWNLOAD_MIN_BYTES - 1.0
        ));
        assert!(fetches_blocks_directly(
            true,
            true,
            DIRECT_BLOCK_DOWNLOAD_MIN_BYTES
        ));
    }

    #[test]
    fn only_main_scan_ranges_every_wallet_scans_alike_use_the_direct_connection() {
        let h = BlockHeight::from_u32;
        let scanned = Some(h(3_438_142));
        for priority in [
            ScanPriority::ChainTip,
            ScanPriority::Historic,
            ScanPriority::LatestPoolActivation,
        ] {
            assert!(
                batch_uses_direct_connection(0, priority, h(3_000_000), scanned),
                "{priority:?}"
            );
            assert!(
                !batch_uses_direct_connection(1, priority, h(3_000_000), scanned),
                "{priority:?}"
            );
        }
        // The continuity check at the scan frontier, and any Verify range of a
        // wallet that has scanned nothing yet.
        assert!(batch_uses_direct_connection(
            0,
            ScanPriority::Verify,
            h(3_438_143),
            scanned
        ));
        assert!(batch_uses_direct_connection(
            0,
            ScanPriority::Verify,
            h(3_000_000),
            None
        ));
        // Witness repairs a stopped session left behind come back as Verify
        // ranges over blocks already scanned, before the Checking stage starts.
        assert!(!batch_uses_direct_connection(
            0,
            ScanPriority::Verify,
            h(3_438_142),
            scanned
        ));
        assert!(!batch_uses_direct_connection(
            0,
            ScanPriority::Verify,
            h(3_100_000),
            scanned
        ));
        for priority in [ScanPriority::FoundNote, ScanPriority::OpenAdjacent] {
            assert!(
                !batch_uses_direct_connection(0, priority, h(3_438_143), None),
                "{priority:?}"
            );
        }
    }

    #[test]
    fn only_failures_in_a_row_move_a_session_to_tor() {
        let now = std::time::Instant::now();
        let runs = |outcomes: &[bool]| {
            let mut route = DirectBlockRoute::new();
            outcomes
                .iter()
                .map(|&failed| route.record(failed, now).is_some())
                .collect::<Vec<_>>()
        };
        // A success between failures keeps the direct connection.
        assert_eq!(
            runs(&[true, true, false, true, true]),
            [false, false, false, false, false]
        );
        assert_eq!(runs(&[true, true, true]), [false, false, true]);
    }

    #[test]
    fn the_timing_summary_splits_download_waits_from_scan_time() {
        let mut timing = SyncTimingSummary::default();
        let second = std::time::Duration::from_secs(1);
        timing.record(true, 100, 11_000_000, 3 * second, second);
        timing.record(false, 1000, 4_000_000, second, 2 * second);
        timing.tip_waited += 5 * second;
        assert_eq!(
            timing.line(
                std::time::Duration::from_secs(60),
                scan_power::ScanPower::Efficient
            ),
            "last 60s: 2 batches (1 direct), 1100 blocks, 15.0 MB (0.25 MB/s), \
             waited 4.0s for downloads and 5.0s for tip checks, scanned 3.0s at \
             Efficient power"
        );
    }

    #[test]
    fn history_batches_far_below_the_tip_check_it_once_a_minute() {
        let tip = 3_500_000;
        let second = std::time::Duration::from_secs(1);
        // Far below the tip: only once the interval has passed.
        assert!(!post_batch_tip_check_due(2_000_000, tip, second));
        assert!(post_batch_tip_check_due(
            2_000_000,
            tip,
            HISTORY_TIP_CHECK_EVERY
        ));
        // Near the tip: after every batch.
        assert!(post_batch_tip_check_due(
            tip - HISTORY_TIP_CHECK_DISTANCE,
            tip,
            second
        ));
        assert!(post_batch_tip_check_due(tip, tip, second));
        assert!(!post_batch_tip_check_due(
            tip - HISTORY_TIP_CHECK_DISTANCE - 1,
            tip,
            second
        ));
    }

    #[test]
    fn a_demoted_direct_route_retries_a_fresh_connection_after_a_wait() {
        let start = std::time::Instant::now();
        let mut route = DirectBlockRoute::new();
        let wait = (0..DIRECT_BLOCK_FAILURES_BEFORE_TOR)
            .find_map(|_| route.record(true, start))
            .expect("three failures demote the route");
        assert_eq!(wait, DIRECT_BLOCK_RETRY_AFTER);
        assert!(!route.in_use());
        assert!(!route.retry_due(start + wait - std::time::Duration::from_secs(1)));
        assert!(route.retry_due(start + wait));

        route.reopened();
        assert!(route.in_use());
        assert!(route.record(false, start + wait).is_none());
        assert!(route.in_use());
    }

    #[test]
    fn a_reopened_direct_route_that_fails_at_once_waits_longer() {
        let start = std::time::Instant::now();
        let mut route = DirectBlockRoute::new();
        let first = (0..DIRECT_BLOCK_FAILURES_BEFORE_TOR)
            .find_map(|_| route.record(true, start))
            .expect("three failures demote the route");
        route.reopened();
        let second = route
            .record(true, start + first)
            .expect("the reopened connection's first failure demotes it");
        assert_eq!(second, DIRECT_BLOCK_RETRY_AFTER * 2);

        // A connection that will not open keeps doubling the wait, up to the cap.
        let waits: Vec<_> = (0..5).map(|_| route.demote(start).as_secs()).collect();
        assert_eq!(waits, [240, 480, 600, 600, 600]);
    }

    async fn download_routes(
        batch_is_direct: bool,
        queued_direct_failed: bool,
        direct: Result<&'static str, SyncError>,
    ) -> (Result<&'static str, SyncError>, bool, Vec<BlockRoute>) {
        let mut routes = Vec::new();
        let mut direct = Some(direct);
        let (result, failed) =
            download_with_direct_fallback(batch_is_direct, queued_direct_failed, |route| {
                routes.push(route);
                let result = match route {
                    BlockRoute::Direct => direct.take().expect("one direct download"),
                    BlockRoute::Tor => Ok("tor"),
                };
                async move { result }
            })
            .await;
        (result, failed, routes)
    }

    #[tokio::test]
    async fn a_batch_off_the_direct_connection_downloads_over_tor() {
        let (result, failed, routes) = download_routes(false, false, Ok("direct")).await;
        assert_eq!(result.ok(), Some("tor"));
        assert!(!failed);
        assert_eq!(routes, [BlockRoute::Tor]);
    }

    #[tokio::test]
    async fn a_direct_batch_that_downloads_is_not_a_failure() {
        let (result, failed, routes) = download_routes(true, false, Ok("direct")).await;
        assert_eq!(result.ok(), Some("direct"));
        assert!(!failed);
        assert_eq!(routes, [BlockRoute::Direct]);
    }

    #[tokio::test]
    async fn a_direct_network_failure_downloads_the_batch_over_tor() {
        let (result, failed, routes) =
            download_routes(true, false, Err(SyncError::net("stream reset"))).await;
        assert_eq!(result.ok(), Some("tor"));
        assert!(failed);
        assert_eq!(routes, [BlockRoute::Direct, BlockRoute::Tor]);
    }

    #[tokio::test]
    async fn a_failed_queued_direct_batch_downloads_over_tor_only() {
        let (result, failed, routes) = download_routes(true, true, Ok("direct")).await;
        assert_eq!(result.ok(), Some("tor"));
        assert!(failed);
        assert_eq!(routes, [BlockRoute::Tor]);
    }

    #[tokio::test]
    async fn a_direct_error_other_than_the_network_ends_the_batch() {
        let (result, failed, routes) =
            download_routes(true, false, Err(SyncError::other("unexpected reply"))).await;
        assert!(result.is_err_and(|error| !matches!(error, SyncError::Network(_))));
        assert!(!failed);
        assert_eq!(routes, [BlockRoute::Direct]);
    }

    #[test]
    fn only_ranges_the_direct_connection_serves_count_toward_opening_it() {
        let model = WorkModel::compiled(WalletNetwork::Main);
        let range = |priority| {
            ScanRange::from_parts(
                BlockHeight::from_u32(SANDBLASTING_START)..BlockHeight::from_u32(SANDBLASTING_END),
                priority,
            )
        };
        let tip = u64::from(SANDBLASTING_END);
        let scanned = Some(BlockHeight::from_u32(SANDBLASTING_END));

        // Notes found in the spam window, and repairs of it, stay on Tor.
        for priority in [ScanPriority::FoundNote, ScanPriority::Verify] {
            assert_eq!(
                direct_download_bytes(&model, &[range(priority)], tip, 0, scanned),
                0.0,
                "{priority:?}"
            );
        }
        let historic =
            direct_download_bytes(&model, &[range(ScanPriority::Historic)], tip, 0, scanned);
        assert!(fetches_blocks_directly(true, true, historic));
        assert_eq!(
            direct_download_bytes(&model, &[range(ScanPriority::Historic)], tip, 1, scanned),
            0.0
        );
    }

    #[test]
    fn public_queries_keep_every_block_download_on_tor() {
        // Without Private queries the session's Tor connection carries address
        // and txid lookups, which a concurrent direct session would tie to the
        // device's IP address.
        assert!(!fetches_blocks_directly(true, false, f64::MAX));
    }

    #[test]
    fn a_full_restore_over_tor_fetches_blocks_directly() {
        let model = WorkModel::compiled(WalletNetwork::Main);
        let restore = [ScanRange::from_parts(
            BlockHeight::from_u32(SANDBLASTING_START)..BlockHeight::from_u32(SANDBLASTING_END),
            ScanPriority::Historic,
        )];
        let bytes = model.pending_download_bytes(&restore, u64::from(SANDBLASTING_END));
        assert!(fetches_blocks_directly(true, true, bytes));
    }

    #[test]
    fn a_stored_root_mismatch_is_logged_once_per_process() {
        let logged = AtomicU64::new(0);
        assert!(!mismatches_not_yet_logged(&logged, 0));
        assert!(mismatches_not_yet_logged(&logged, 1));
        // A later sync in the same process reads the same count.
        assert!(!mismatches_not_yet_logged(&logged, 1));
        assert!(mismatches_not_yet_logged(&logged, 3));
        assert!(!mismatches_not_yet_logged(&logged, 2));
    }

    #[tokio::test(start_paused = true)]
    async fn a_quick_prefetch_failure_is_retried_in_the_background() {
        let attempts = AtomicUsize::new(0);
        let started = tokio::time::Instant::now();
        let result = retry_quick_prefetch_failures(block_height(10), block_height(19), || {
            let attempt = attempts.fetch_add(1, Ordering::SeqCst);
            async move {
                if attempt == 0 {
                    Err(SyncError::Network("stream reset".into()))
                } else {
                    Ok(7u8)
                }
            }
        })
        .await;
        assert!(matches!(result, Ok(7)));
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
        assert_eq!(started.elapsed(), PREFETCH_RETRY_PAUSES[0]);
    }

    #[tokio::test(start_paused = true)]
    async fn a_prefetch_keeps_failing_after_its_retries() {
        let attempts = AtomicUsize::new(0);
        let started = tokio::time::Instant::now();
        let result = retry_quick_prefetch_failures(block_height(10), block_height(19), || {
            attempts.fetch_add(1, Ordering::SeqCst);
            async { Err::<u8, _>(SyncError::Network("stream reset".into())) }
        })
        .await;
        assert!(matches!(result, Err(SyncError::Network(_))));
        assert_eq!(attempts.load(Ordering::SeqCst), 3);
        assert_eq!(
            started.elapsed(),
            PREFETCH_RETRY_PAUSES[0] + PREFETCH_RETRY_PAUSES[1]
        );
    }

    #[tokio::test(start_paused = true)]
    async fn a_prefetch_that_timed_out_is_not_retried() {
        let attempts = AtomicUsize::new(0);
        let result = retry_quick_prefetch_failures(block_height(10), block_height(19), || {
            attempts.fetch_add(1, Ordering::SeqCst);
            async {
                tokio::time::sleep(lwd::SHORTEST_LIGHTWALLETD_TIMEOUT).await;
                Err::<u8, _>(SyncError::Network("timed out".into()))
            }
        })
        .await;
        assert!(matches!(result, Err(SyncError::Network(_))));
        assert_eq!(attempts.load(Ordering::SeqCst), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn a_prefetch_that_failed_for_another_reason_is_not_retried() {
        let attempts = AtomicUsize::new(0);
        let result = retry_quick_prefetch_failures(block_height(10), block_height(19), || {
            attempts.fetch_add(1, Ordering::SeqCst);
            async { Err::<u8, _>(SyncError::Parse("bad compact block".into())) }
        })
        .await;
        assert!(matches!(result, Err(SyncError::Parse(_))));
        assert_eq!(attempts.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn checking_reports_only_additional_work_and_its_next_batch() {
        assert!(checking_progress(0, 1000, 750, 100).is_none());
        let mut cycle = 0;
        let (job, _) = JobProgress::start(progress_work::StoredProgressJob::unmeasured(), 0.0, 0.0);
        let start = begin_checking(&mut cycle, 1000, 2000, &job);
        // Checking events keep the job, so the display does not restart.
        assert_eq!(start.sync_job_id, job.id());
        assert_eq!(start.kind, SyncEventKind::Progress);
        assert_eq!(start.phase, "chain_prepare");
        assert!(start.is_syncing);
        assert_eq!(start.checking.unwrap().percentage, 0.0);
        assert_eq!(start.remaining_scan_blocks, Some(1000));
        let batch = checking_progress(cycle, 1000, 750, 100).unwrap();
        assert_eq!(batch.percentage, 0.25);
        assert_eq!(batch.display_target_percentage, 0.35);
        assert_eq!(
            checking_progress(cycle, 1000, 0, 0).unwrap().percentage,
            1.0
        );
        let new_work = begin_checking(&mut cycle, 200, 2000, &job)
            .checking
            .unwrap();
        assert_eq!(new_work.cycle, 2);
        assert_eq!(new_work.percentage, 0.0);
    }

    #[test]
    fn a_range_past_the_tip_refreshes_the_tip_once_per_start() {
        let mut refreshed_for = None;
        // The observer queued blocks past the loop's tip: refresh once.
        assert!(refresh_tip_for_queued_range(3_513_789, &mut refreshed_for));
        // Still past it after the refresh (a lagging server): end as before.
        assert!(!refresh_tip_for_queued_range(3_513_789, &mut refreshed_for));
        // A later block queues a new range: refresh again.
        assert!(refresh_tip_for_queued_range(3_513_790, &mut refreshed_for));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_tip_prefetch_returns_the_tip_requested_before_it_is_read() {
        let lwd = test_lwd::CapturingLwd::start_with(Vec::new(), 3_516_998, |_| {}).await;
        let before = std::time::Instant::now();
        let prefetch = TipPrefetch::spawn(lwd.client.clone(), &lwd.url, WalletNetwork::Main);
        let requested_at = prefetch.requested_at;
        let tip = prefetch.resolve(&|| false).await.unwrap().unwrap();

        assert_eq!(tip.height, 3_516_998);
        assert_eq!(lwd.count("/GetLatestBlock"), 1);
        assert!(before <= requested_at && requested_at <= std::time::Instant::now());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_tip_prefetch_yields_to_an_exit_while_the_server_holds_it() {
        let lwd = test_lwd::CapturingLwd::start_with(Vec::new(), 3_516_998, |_| {}).await;
        let _held = lwd.hold_responses("/GetLatestBlock");
        let prefetch = TipPrefetch::spawn(lwd.client.clone(), &lwd.url, WalletNetwork::Main);

        let resolved =
            tokio::time::timeout(Duration::from_secs(5), prefetch.resolve(&|| true)).await;

        assert!(matches!(resolved, Ok(None)));
    }

    /// A prefetched tip whose request the server has received, then the
    /// moment this batch's status lookups finished.
    async fn prefetch_then_status_lookups(
        lwd: &test_lwd::CapturingLwd,
    ) -> (TipPrefetch, std::time::Instant) {
        let prefetch = TipPrefetch::spawn(lwd.client.clone(), &lwd.url, WalletNetwork::Main);
        tokio::time::timeout(Duration::from_secs(5), async {
            while lwd.count("/GetLatestBlock") == 0 {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .unwrap();
        (prefetch, std::time::Instant::now())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_batch_without_released_statuses_uses_its_tip_prefetch() {
        let lwd = test_lwd::CapturingLwd::start_with(Vec::new(), 3_516_998, |_| {}).await;
        let (prefetch, _) = prefetch_then_status_lookups(&lwd).await;
        let prefetch_requested_at = prefetch.requested_at;
        let mut client = lwd.client.clone();

        let (requested_at, tip) = post_batch_tip(
            Some(prefetch),
            false,
            &mut client,
            &lwd.url,
            WalletNetwork::Main,
            &|| false,
        )
        .await;

        assert_eq!(tip.unwrap().unwrap().height, 3_516_998);
        assert_eq!(requested_at, prefetch_requested_at);
        assert_eq!(lwd.count("/GetLatestBlock"), 1);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_released_status_is_checked_against_a_tip_requested_after_its_lookup() {
        let lwd = test_lwd::CapturingLwd::start_with(Vec::new(), 3_516_998, |_| {}).await;
        let (prefetch, lookups_done) = prefetch_then_status_lookups(&lwd).await;
        let mut client = lwd.client.clone();

        let (requested_at, tip) = post_batch_tip(
            Some(prefetch),
            true,
            &mut client,
            &lwd.url,
            WalletNetwork::Main,
            &|| false,
        )
        .await;

        assert_eq!(tip.unwrap().unwrap().height, 3_516_998);
        assert!(requested_at >= lookups_done);
        assert_eq!(lwd.count("/GetLatestBlock"), 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_tip_request_yields_to_an_exit_that_arrives_while_the_server_holds_it() {
        let lwd = test_lwd::CapturingLwd::start_with(Vec::new(), 3_516_998, |_| {}).await;
        let _held = lwd.hold_responses("/GetLatestBlock");
        let mut client = lwd.client.clone();
        let exit = Arc::new(AtomicBool::new(false));
        let flip = exit.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(200)).await;
            flip.store(true, Ordering::SeqCst);
        });

        let started = std::time::Instant::now();
        let resolved = tokio::time::timeout(
            Duration::from_secs(5),
            unless_exiting(
                &|| exit.load(Ordering::SeqCst),
                get_latest_block(&mut client),
            ),
        )
        .await;

        assert!(matches!(resolved, Ok(None)));
        assert!(started.elapsed() < Duration::from_secs(2));
        assert_eq!(lwd.count("/GetLatestBlock"), 1);
    }

    #[test]
    fn a_chain_tip_range_past_the_tip_waits_behind_history() {
        // The observer wrote 3,516,998 while the loop's tip is 3,516,997.
        let ranges = vec![
            ScanRange::from_parts(
                block_height(3_516_998)..block_height(3_516_999),
                ScanPriority::ChainTip,
            ),
            ScanRange::from_parts(
                block_height(1_800_000)..block_height(1_900_000),
                ScanPriority::Scanned,
            ),
            ScanRange::from_parts(
                block_height(1_900_000)..block_height(2_000_000),
                ScanPriority::Historic,
            ),
        ];
        let next = next_pending_scan_range(&ranges, 3_516_997).unwrap();
        assert_eq!(next.priority(), ScanPriority::Historic);
        assert_eq!(u32::from(next.block_range().start), 1_900_000);

        // Once a tip fetch reaches it, the ChainTip range goes first again.
        let next = next_pending_scan_range(&ranges, 3_516_998).unwrap();
        assert_eq!(next.priority(), ScanPriority::ChainTip);

        // With only that range left, it is returned for the tip refresh.
        let next = next_pending_scan_range(&ranges[..2], 3_516_997).unwrap();
        assert_eq!(next.priority(), ScanPriority::ChainTip);
        assert!(next_pending_scan_range(&ranges[1..2], 3_516_997).is_none());
    }

    #[test]
    fn payment_link_scan_ranges_skip_idle_history_and_preserve_older_observers() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("observer.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Main;
        let register = |birthday| {
            let phrase = keys::generate_mnemonic();
            let seed = keys::mnemonic_to_seed(&phrase).unwrap();
            let address = keys::derive_gift_address(network, &seed, 0).unwrap();
            keys::register_gift_card_observer(path, network, phrase.as_bytes(), &address, birthday)
                .unwrap()
        };
        let first = register(2_000_000);
        let mut db = open_db(path, network).unwrap();
        db.update_chain_tip(block_height(2_000_100)).unwrap();
        // Model persisted scan metadata without a network or production wallet.
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute_batch(
            "INSERT INTO blocks (height, hash, time, sapling_tree)
             VALUES (2000100, zeroblob(32), 0, X'000000');
             DELETE FROM scan_queue;
             INSERT INTO scan_queue (block_range_start, block_range_end, priority)
             VALUES (2000000, 2000101, 10);",
        )
        .unwrap();
        drop(conn);
        drop(db);
        crate::wallet::gift_card_tracking::remove(path, network, &first).unwrap();
        let db = open_db(path, network).unwrap();
        assert!(db.get_account_ids().unwrap().is_empty());
        drop(db);
        assert!(std::path::Path::new(path).exists());

        register(2_400_000);
        let mut db = open_db(path, network).unwrap();
        // Both the initial tip and a later refreshed tip recreate idle work.
        for tip in [2_500_000, 2_500_010] {
            db.update_chain_tip(block_height(tip)).unwrap();
            assert!(db.suggest_scan_ranges().unwrap().iter().any(
                |r| is_pending_scan_range(r) && r.block_range().start < block_height(2_400_000)
            ));
            let ranges = payment_link_scan_ranges(&db, path).unwrap();
            let pending: Vec<_> = ranges.iter().filter(|r| is_pending_scan_range(r)).collect();
            assert!(!pending.is_empty());
            assert!(pending
                .iter()
                .all(|r| r.block_range().start >= block_height(2_400_000)));
            assert!(pending
                .iter()
                .any(|r| r.block_range().contains(&block_height(2_400_000))));
            assert!(pending
                .iter()
                .any(|r| r.block_range().contains(&block_height(tip))));
        }
        drop(db);
        // A recovered older card must still get its birthday-to-tip history.
        register(2_200_000);
        let mut db = open_db(path, network).unwrap();
        db.update_chain_tip(block_height(2_500_020)).unwrap();
        let ranges = payment_link_scan_ranges(&db, path).unwrap();
        assert!(ranges
            .iter()
            .filter(|r| is_pending_scan_range(r))
            .all(|r| r.block_range().start >= block_height(2_200_000)));
        assert!(ranges.iter().any(
            |r| is_pending_scan_range(r) && r.block_range().contains(&block_height(2_200_000))
        ));
        assert_eq!(db.get_account_ids().unwrap().len(), 2);
    }

    struct DropSignal {
        dropped: Arc<AtomicBool>,
    }

    impl Drop for DropSignal {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    fn block_height(height: u32) -> BlockHeight {
        BlockHeight::from_u32(height)
    }

    #[test]
    fn no_scan_run_requires_a_completion_enhancement_pass() {
        assert!(needs_completion_enhancement_pass(false));
        assert!(!needs_completion_enhancement_pass(true));
    }

    fn block_source(heights: &[u64]) -> block_source::MemoryBlockSource {
        block_source::MemoryBlockSource::new(
            heights
                .iter()
                .map(|height| CompactBlock {
                    height: *height,
                    ..Default::default()
                })
                .collect(),
        )
    }

    async fn wait_for_drop(dropped: &AtomicBool) {
        tokio::time::timeout(Duration::from_secs(1), async {
            while !dropped.load(Ordering::SeqCst) {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("prefetch task was not dropped");
    }

    #[tokio::test]
    async fn transparent_refreshes_limit_concurrency_to_four() {
        let active = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let commit_count = Arc::new(AtomicUsize::new(0));

        let download_active = active.clone();
        let download_peak = peak.clone();
        let persist_count = commit_count.clone();
        let outcome = process_bounded_transparent_refreshes(
            (0..12).collect(),
            move |refresh| {
                let active = download_active.clone();
                let peak = download_peak.clone();
                async move {
                    let concurrent = active.fetch_add(1, Ordering::SeqCst) + 1;
                    peak.fetch_max(concurrent, Ordering::SeqCst);
                    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                    active.fetch_sub(1, Ordering::SeqCst);
                    Ok::<_, &'static str>(Some(refresh))
                }
            },
            move |group| {
                assert!(group.len() <= MAX_CONCURRENT_TRANSPARENT_UTXO_STREAMS);
                persist_count.fetch_add(1, Ordering::SeqCst);
                Ok(())
            },
            |_| {},
            &|| false,
        )
        .await
        .unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Completed);
        assert_eq!(peak.load(Ordering::SeqCst), 4);
        assert_eq!(active.load(Ordering::SeqCst), 0);
        assert_eq!(commit_count.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn transparent_refresh_downloads_actually_overlap() {
        let barrier = Arc::new(tokio::sync::Barrier::new(4));
        let started = Arc::new(AtomicUsize::new(0));

        let download_barrier = barrier.clone();
        let download_started = started.clone();
        let refresh = process_bounded_transparent_refreshes(
            (0..4).collect(),
            move |refresh| {
                let barrier = download_barrier.clone();
                let started = download_started.clone();
                async move {
                    started.fetch_add(1, Ordering::SeqCst);
                    barrier.wait().await;
                    Ok::<_, &'static str>(Some(refresh))
                }
            },
            |_| Ok(()),
            |_| {},
            &|| false,
        );
        let outcome = tokio::time::timeout(std::time::Duration::from_secs(1), refresh)
            .await
            .expect("four downloads did not overlap")
            .unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Completed);
        assert_eq!(started.load(Ordering::SeqCst), 4);
    }

    #[tokio::test]
    async fn transparent_refresh_cancellation_wins_over_racing_error() {
        let cancelled = Arc::new(AtomicBool::new(false));
        let commits = Arc::new(AtomicUsize::new(0));
        let download_cancelled = cancelled.clone();
        let persist_commits = commits.clone();
        let exit_cancelled = cancelled.clone();
        let should_exit = move || exit_cancelled.load(Ordering::SeqCst);

        let outcome = process_bounded_transparent_refreshes(
            vec![0],
            move |_| {
                let cancelled = download_cancelled.clone();
                async move {
                    cancelled.store(true, Ordering::SeqCst);
                    Err::<Option<usize>, _>("network error")
                }
            },
            move |_| {
                persist_commits.fetch_add(1, Ordering::SeqCst);
                Ok(())
            },
            |_| {},
            &should_exit,
        )
        .await
        .unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Cancelled);
        assert_eq!(commits.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn failed_transparent_stream_prevents_group_commit() {
        let commits = Arc::new(AtomicUsize::new(0));
        let persist_commits = commits.clone();
        let result = process_bounded_transparent_refreshes(
            (0..4).collect(),
            |refresh| async move {
                if refresh == 2 {
                    Err("stream failed")
                } else {
                    tokio::task::yield_now().await;
                    Ok(Some(refresh))
                }
            },
            move |_| {
                persist_commits.fetch_add(1, Ordering::SeqCst);
                Ok(())
            },
            |_| {},
            &|| false,
        )
        .await;

        assert_eq!(result, Err("stream failed"));
        assert_eq!(commits.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn cancelled_transparent_stream_prevents_group_commit() {
        let commits = Arc::new(AtomicUsize::new(0));
        let persist_commits = commits.clone();
        let outcome = process_bounded_transparent_refreshes(
            (0..4).collect(),
            |refresh| async move { Ok::<_, &'static str>((refresh != 2).then_some(refresh)) },
            move |_| {
                persist_commits.fetch_add(1, Ordering::SeqCst);
                Ok(())
            },
            |_| {},
            &|| false,
        )
        .await
        .unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Cancelled);
        assert_eq!(commits.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn transparent_refresh_groups_restore_request_order_before_commit() {
        let commits = Arc::new(Mutex::new(Vec::new()));
        let persist_commits = commits.clone();
        let outcome = process_bounded_transparent_refreshes(
            (0..6).collect(),
            |refresh| async move {
                let delay = 5 * (4 - (refresh % 4));
                tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                Ok::<_, &'static str>(Some(refresh))
            },
            move |group| {
                persist_commits.lock().unwrap().push(group);
                Ok(())
            },
            |_| {},
            &|| false,
        )
        .await
        .unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Completed);
        assert_eq!(*commits.lock().unwrap(), vec![vec![0, 1, 2, 3], vec![4, 5]]);
    }

    #[tokio::test]
    async fn transparent_refresh_reprioritizes_only_pending_groups() {
        let priority = Arc::new(AtomicUsize::new(usize::MAX));
        let commits = Arc::new(Mutex::new(Vec::new()));
        let first_group_started = Arc::new(Barrier::new(5));
        let release_first_group = Arc::new(Semaphore::new(0));

        let run_priority = priority.clone();
        let run_commits = commits.clone();
        let run_started = first_group_started.clone();
        let run_release = release_first_group.clone();
        let run = tokio::spawn(async move {
            process_bounded_transparent_refreshes(
                (0..6).collect(),
                move |refresh| {
                    let started = run_started.clone();
                    let release = run_release.clone();
                    async move {
                        if refresh < 4 {
                            started.wait().await;
                            release.acquire().await.unwrap().forget();
                        }
                        Ok::<_, &'static str>(Some(refresh))
                    }
                },
                move |group| {
                    run_commits.lock().unwrap().push(group);
                    Ok(())
                },
                move |pending| {
                    let priority = run_priority.load(Ordering::SeqCst);
                    pending
                        .make_contiguous()
                        .sort_by_key(|refresh| *refresh != priority);
                },
                &|| false,
            )
            .await
        });

        first_group_started.wait().await;
        priority.store(5, Ordering::SeqCst);
        release_first_group.add_permits(4);
        let outcome = run.await.unwrap().unwrap();

        assert_eq!(outcome, TransparentRefreshOutcome::Completed);
        assert_eq!(*commits.lock().unwrap(), vec![vec![0, 1, 2, 3], vec![5, 4]]);
    }

    #[test]
    fn transparent_refresh_priority_moves_every_active_batch_stably() {
        let refresh = |account_uuid: &str, label: &str| TransparentRefresh {
            addresses: Vec::new(),
            start_height: block_height(1),
            label: label.to_string(),
            account_uuid: account_uuid.to_string(),
            completion: None,
        };
        let mut pending = VecDeque::from(vec![
            refresh("active", "active recent"),
            refresh("other", "other recent"),
            refresh("active", "active sweep"),
            refresh("other", "other sweep"),
        ]);
        let target = Arc::new(RwLock::new(Some("active".to_string())));

        prioritize_pending_transparent_refreshes(&mut pending, Some(&target));

        assert_eq!(
            pending
                .iter()
                .map(|refresh| refresh.label.as_str())
                .collect::<Vec<_>>(),
            [
                "active recent",
                "active sweep",
                "other recent",
                "other sweep",
            ],
        );
    }

    #[test]
    fn transparent_cache_metadata_is_marked_only_after_commit() {
        let events = RefCell::new(Vec::new());
        store_then_mark_transparent_refreshes(
            vec![1, 2],
            |_| {
                events.borrow_mut().push("commit".to_string());
                Ok::<_, &'static str>(())
            },
            |refresh| events.borrow_mut().push(format!("mark {refresh}")),
        )
        .unwrap();

        assert_eq!(events.into_inner(), ["commit", "mark 1", "mark 2"]);
    }

    #[test]
    fn transparent_account_selection_prioritizes_one_account() {
        let selected = "active";
        assert!(TransparentAccountSelection::All.includes(selected));
        assert!(TransparentAccountSelection::Only(selected).includes(selected));
        assert!(!TransparentAccountSelection::Only(selected).includes("inactive"));
        assert!(!TransparentAccountSelection::Except(selected).includes(selected));
        assert!(TransparentAccountSelection::Except(selected).includes("inactive"));
    }

    #[test]
    fn failed_transparent_commit_does_not_advance_cache_metadata() {
        let marked = Cell::new(0);
        let result = store_then_mark_transparent_refreshes(
            vec![1, 2],
            |_| Err("commit failed"),
            |_| marked.set(marked.get() + 1),
        );

        assert_eq!(result, Err("commit failed"));
        assert_eq!(marked.get(), 0);
    }

    #[tokio::test]
    async fn scan_batch_inputs_start_concurrently() {
        let barrier = Arc::new(Barrier::new(3));
        let block_barrier = barrier.clone();
        let state_barrier = barrier.clone();
        let joined = tokio::spawn(join_scan_batch_inputs(
            async move {
                block_barrier.wait().await;
                Ok::<_, SyncError>("blocks")
            },
            async move {
                state_barrier.wait().await;
                Ok::<_, SyncError>("frontier")
            },
        ));

        tokio::time::timeout(Duration::from_secs(1), barrier.wait())
            .await
            .expect("block and frontier futures were not both polled");
        assert_eq!(
            joined.await.expect("join task").expect("joined inputs"),
            ("blocks", "frontier"),
        );
    }

    #[tokio::test]
    async fn scan_batch_input_failure_drops_the_sibling_request() {
        let barrier = Arc::new(Barrier::new(2));
        let block_barrier = barrier.clone();
        let state_barrier = barrier.clone();
        let dropped = Arc::new(AtomicBool::new(false));
        let block_dropped = dropped.clone();

        let result = join_scan_batch_inputs(
            async move {
                let _drop_signal = DropSignal {
                    dropped: block_dropped,
                };
                block_barrier.wait().await;
                std::future::pending::<Result<u8, SyncError>>().await
            },
            async move {
                state_barrier.wait().await;
                Err::<u8, _>(SyncError::net("frontier failed"))
            },
        )
        .await;

        assert!(matches!(result, Err(SyncError::Network(_))));
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn a_tip_batch_between_history_batches_keeps_the_prefetch_queue() {
        let queued = |start, end| {
            Prefetch::spawn(block_height(start), block_height(end), async {
                Ok::<_, SyncError>(0u8)
            })
        };
        let ranges = |queue: &VecDeque<Prefetch<u8>>| {
            queue
                .iter()
                .map(|p| (u32::from(p.start), u32::from(p.end)))
                .collect::<Vec<_>>()
        };
        let mut queue = VecDeque::from([queued(100, 200), queued(200, 300)]);

        // A new block's tip batch cuts in: the history tuples wait for it.
        let h = block_height;
        assert!(take_queued_batch(&mut queue, h(5_000), h(5_001)).is_none());
        assert_eq!(ranges(&queue), [(100, 200), (200, 300)]);
        assert_eq!(
            prefetch_continues_from(&mut queue, h(5_001), h(5_001)),
            None
        );
        assert_eq!(ranges(&queue), [(100, 200), (200, 300)]);

        // The scan returns to history and tops the queue up after its end.
        let next = take_queued_batch(&mut queue, h(100), h(200)).expect("queued batch");
        assert_eq!((u32::from(next.start), u32::from(next.end)), (100, 200));
        assert_eq!(
            prefetch_continues_from(&mut queue, h(200), h(1_000)),
            Some(h(300))
        );

        // A longer range that cuts in downloads ahead instead.
        assert!(take_queued_batch(&mut queue, h(5_000), h(5_100)).is_none());
        assert_eq!(
            prefetch_continues_from(&mut queue, h(5_100), h(6_000)),
            Some(h(5_100))
        );
        assert!(queue.is_empty());

        // A batch that overlaps the queue but is not next means the ranges
        // changed under it.
        let mut queue = VecDeque::from([queued(100, 200), queued(200, 300)]);
        assert!(take_queued_batch(&mut queue, h(100), h(150)).is_none());
        assert!(queue.is_empty());
        let mut queue = VecDeque::from([queued(100, 200), queued(200, 300)]);
        assert!(take_queued_batch(&mut queue, h(250), h(260)).is_none());
        assert!(queue.is_empty());
        assert_eq!(
            prefetch_continues_from(&mut queue, h(260), h(1_000)),
            Some(h(260))
        );
    }

    #[tokio::test]
    async fn a_tip_batch_keeps_the_decryption_started_for_the_queued_batch() {
        let h = block_height;
        let queued =
            |start, end| Prefetch::spawn(h(start), h(end), async { Ok::<_, SyncError>(0u8) });
        let started = |start, end| {
            Some(NextDecryption {
                start: h(start),
                end: h(end),
                decryption: (),
            })
        };
        let mut queue = VecDeque::from([queued(100, 200), queued(200, 300)]);

        // Scanning 0..100 started decrypting 100..200. A new block's tip
        // batch cuts in and leaves the queue: the decryption waits with it.
        assert!(take_queued_batch(&mut queue, h(5_000), h(5_001)).is_none());
        let kept = decryption_still_next(started(100, 200), &queue);
        assert_eq!(kept.map(|next| u32::from(next.start)), Some(100));

        // Not the queued batch's range: not kept.
        assert!(decryption_still_next(started(100, 150), &queue).is_none());

        // The scan returns and takes the queued batch; the next decryption
        // is for whatever is first now.
        assert!(take_queued_batch(&mut queue, h(100), h(200)).is_some());
        assert!(decryption_still_next(started(100, 200), &queue).is_none());

        // Ranges that changed under the queue clear it, and the decryption.
        assert!(take_queued_batch(&mut queue, h(250), h(260)).is_none());
        assert!(queue.is_empty());
        assert!(decryption_still_next(started(200, 300), &queue).is_none());
    }

    #[tokio::test]
    async fn a_verify_range_inside_the_next_queued_batch_scans_it_whole() {
        let h = block_height;
        let queued =
            |start, end| Prefetch::spawn(h(start), h(end), async { Ok::<_, SyncError>(0u8) });
        let range = |start, end, priority| ScanRange::from_parts(h(start)..h(end), priority);
        let queue = VecDeque::from([queued(100, 200), queued(200, 300)]);

        // A new block put a Verify range at the frontier, inside the queued
        // batch: scan the queued batch whole.
        let split = [
            range(100, 110, ScanPriority::Verify),
            range(110, 500, ScanPriority::ChainTip),
        ];
        assert_eq!(
            queued_batch_extension(&queue, h(100), h(110), &split),
            Some(h(200))
        );

        // Blocks no longer pending are not scanned again.
        let scanned = [
            range(100, 110, ScanPriority::Verify),
            range(110, 150, ScanPriority::Scanned),
            range(150, 500, ScanPriority::ChainTip),
        ];
        assert_eq!(
            queued_batch_extension(&queue, h(100), h(110), &scanned),
            None
        );

        // Only a longer queued batch starting at the batch extends it.
        assert_eq!(queued_batch_extension(&queue, h(100), h(200), &split), None);
        assert_eq!(queued_batch_extension(&queue, h(110), h(150), &split), None);
        assert_eq!(
            queued_batch_extension(&VecDeque::<Prefetch<u8>>::new(), h(100), h(110), &split),
            None
        );
    }

    #[tokio::test]
    async fn scan_batch_prefetch_success_and_failure_choose_the_right_source() {
        let start = block_height(10);
        let end = block_height(13);
        let keep_running = || false;
        let fresh_calls = AtomicUsize::new(0);

        let prefetched = Prefetch::spawn(start, end, async { Ok::<_, SyncError>(7) });
        let value =
            resolve_prefetched_or_download(Some(prefetched), start, end, &keep_running, || {
                fresh_calls.fetch_add(1, Ordering::SeqCst);
                async { Ok(9) }
            })
            .await
            .expect("successful prefetch")
            .expect("sync remains active");
        assert_eq!(value, 7);
        assert_eq!(fresh_calls.load(Ordering::SeqCst), 0);

        let failed = Prefetch::spawn(start, end, async {
            Err::<u8, _>(SyncError::net("prefetch failed"))
        });
        let value = resolve_prefetched_or_download(Some(failed), start, end, &keep_running, || {
            fresh_calls.fetch_add(1, Ordering::SeqCst);
            async { Ok(9) }
        })
        .await
        .expect("fresh fallback")
        .expect("sync remains active");
        assert_eq!(value, 9);
        assert_eq!(fresh_calls.load(Ordering::SeqCst), 1);
    }

    /// A tuple read early to start its decryption is the one its batch then
    /// scans; a failed one still falls back to a fresh download.
    #[tokio::test]
    async fn a_finished_prefetch_read_early_is_still_used_for_its_batch() {
        let start = block_height(10);
        let end = block_height(13);
        let keep_running = || false;
        let fresh_calls = AtomicUsize::new(0);

        let mut prefetched = Prefetch::spawn(start, end, async { Ok::<_, SyncError>(7) });
        while !prefetched.handle.as_ref().is_some_and(|h| h.is_finished()) {
            tokio::task::yield_now().await;
        }
        assert_eq!(prefetched.finished(), Some(&7));
        assert_eq!(prefetched.finished(), Some(&7));
        let value =
            resolve_prefetched_or_download(Some(prefetched), start, end, &keep_running, || {
                fresh_calls.fetch_add(1, Ordering::SeqCst);
                async { Ok(9) }
            })
            .await
            .expect("finished prefetch")
            .expect("sync remains active");
        assert_eq!(value, 7);
        assert_eq!(fresh_calls.load(Ordering::SeqCst), 0);

        let mut failed = Prefetch::spawn(start, end, async {
            Err::<u8, _>(SyncError::net("prefetch failed"))
        });
        while !failed.handle.as_ref().is_some_and(|h| h.is_finished()) {
            tokio::task::yield_now().await;
        }
        assert_eq!(failed.finished(), None);
        let value = resolve_prefetched_or_download(Some(failed), start, end, &keep_running, || {
            fresh_calls.fetch_add(1, Ordering::SeqCst);
            async { Ok(9) }
        })
        .await
        .expect("fresh fallback")
        .expect("sync remains active");
        assert_eq!(value, 9);
        assert_eq!(fresh_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn mismatched_scan_batch_prefetch_is_aborted_before_fallback() {
        let started = Arc::new(Notify::new());
        let task_started = started.clone();
        let dropped = Arc::new(AtomicBool::new(false));
        let task_dropped = dropped.clone();
        let stale = Prefetch::spawn(block_height(10), block_height(13), async move {
            let _drop_signal = DropSignal {
                dropped: task_dropped,
            };
            task_started.notify_one();
            std::future::pending::<Result<u8, SyncError>>().await
        });
        tokio::time::timeout(Duration::from_secs(1), started.notified())
            .await
            .expect("stale prefetch started");

        let keep_running = || false;
        let value = resolve_prefetched_or_download(
            Some(stale),
            block_height(20),
            block_height(23),
            &keep_running,
            || async { Ok(42) },
        )
        .await
        .expect("fallback succeeds")
        .expect("sync remains active");

        assert_eq!(value, 42);
        wait_for_drop(&dropped).await;
    }

    #[tokio::test]
    async fn dropping_a_scan_batch_wait_aborts_its_prefetch_task() {
        let started = Arc::new(Notify::new());
        let task_started = started.clone();
        let dropped = Arc::new(AtomicBool::new(false));
        let task_dropped = dropped.clone();
        let prefetch = Prefetch::spawn(block_height(10), block_height(13), async move {
            let _drop_signal = DropSignal {
                dropped: task_dropped,
            };
            task_started.notify_one();
            std::future::pending::<Result<u8, SyncError>>().await
        });
        tokio::time::timeout(Duration::from_secs(1), started.notified())
            .await
            .expect("prefetch started");

        let resolver = tokio::spawn(async move {
            let keep_running = || false;
            resolve_prefetched_or_download(
                Some(prefetch),
                block_height(10),
                block_height(13),
                &keep_running,
                || async { Ok(9) },
            )
            .await
        });
        tokio::task::yield_now().await;
        resolver.abort();
        let _ = resolver.await;

        wait_for_drop(&dropped).await;
    }

    #[tokio::test]
    async fn scan_batch_cancellation_interrupts_pending_network_work() {
        let exit = Arc::new(AtomicBool::new(false));
        let started = Arc::new(Notify::new());
        let task_started = started.clone();
        let dropped = Arc::new(AtomicBool::new(false));
        let task_dropped = dropped.clone();
        let prefetch = Prefetch::spawn(block_height(10), block_height(13), async move {
            let _drop_signal = DropSignal {
                dropped: task_dropped,
            };
            task_started.notify_one();
            std::future::pending::<Result<u8, SyncError>>().await
        });
        tokio::time::timeout(Duration::from_secs(1), started.notified())
            .await
            .expect("prefetch started");

        let resolver_exit = exit.clone();
        let resolver = tokio::spawn(async move {
            let should_exit = || resolver_exit.load(Ordering::SeqCst);
            resolve_prefetched_or_download(
                Some(prefetch),
                block_height(10),
                block_height(13),
                &should_exit,
                || async { Ok(9) },
            )
            .await
        });
        tokio::task::yield_now().await;
        exit.store(true, Ordering::SeqCst);
        assert!(tokio::time::timeout(Duration::from_secs(1), resolver)
            .await
            .expect("prefetch cancellation timed out")
            .expect("resolver task")
            .expect("cancellation is not an error")
            .is_none());
        wait_for_drop(&dropped).await;

        exit.store(false, Ordering::SeqCst);
        let fresh_started = Arc::new(Notify::new());
        let task_started = fresh_started.clone();
        let fresh_dropped = Arc::new(AtomicBool::new(false));
        let task_dropped = fresh_dropped.clone();
        let resolver_exit = exit.clone();
        let resolver = tokio::spawn(async move {
            let should_exit = || resolver_exit.load(Ordering::SeqCst);
            resolve_prefetched_or_download(
                None::<Prefetch<u8>>,
                block_height(10),
                block_height(13),
                &should_exit,
                || async move {
                    let _drop_signal = DropSignal {
                        dropped: task_dropped,
                    };
                    task_started.notify_one();
                    std::future::pending::<Result<u8, SyncError>>().await
                },
            )
            .await
        });
        tokio::time::timeout(Duration::from_secs(1), fresh_started.notified())
            .await
            .expect("fresh download started");
        exit.store(true, Ordering::SeqCst);
        assert!(tokio::time::timeout(Duration::from_secs(1), resolver)
            .await
            .expect("fresh cancellation timed out")
            .expect("resolver task")
            .expect("cancellation is not an error")
            .is_none());
        wait_for_drop(&fresh_dropped).await;
    }

    #[tokio::test]
    async fn scan_batch_cancellation_wins_over_prefetch_and_fallback_errors() {
        let exit = Arc::new(AtomicBool::new(false));
        let release = Arc::new(Notify::new());
        let task_release = release.clone();
        let task_exit = exit.clone();
        let prefetch = Prefetch::spawn(block_height(10), block_height(13), async move {
            task_release.notified().await;
            task_exit.store(true, Ordering::SeqCst);
            Err::<u8, _>(SyncError::net("prefetch failed during cancellation"))
        });
        let resolver_exit = exit.clone();
        let fresh_calls = Arc::new(AtomicUsize::new(0));
        let resolver_fresh_calls = fresh_calls.clone();
        let resolver = tokio::spawn(async move {
            let should_exit = || resolver_exit.load(Ordering::SeqCst);
            resolve_prefetched_or_download(
                Some(prefetch),
                block_height(10),
                block_height(13),
                &should_exit,
                || {
                    resolver_fresh_calls.fetch_add(1, Ordering::SeqCst);
                    async { Err(SyncError::net("fresh fallback should not run")) }
                },
            )
            .await
        });
        tokio::task::yield_now().await;
        release.notify_one();

        assert!(resolver
            .await
            .expect("resolver task")
            .expect("cancellation is not an error")
            .is_none());
        assert_eq!(fresh_calls.load(Ordering::SeqCst), 0);

        exit.store(false, Ordering::SeqCst);
        let fresh_exit = exit.clone();
        let should_exit = || exit.load(Ordering::SeqCst);
        let result = resolve_prefetched_or_download(
            None::<Prefetch<u8>>,
            block_height(10),
            block_height(13),
            &should_exit,
            || async move {
                fresh_exit.store(true, Ordering::SeqCst);
                Err(SyncError::net("fresh download failed during cancellation"))
            },
        )
        .await;
        assert!(result.expect("cancellation is not an error").is_none());
    }

    #[test]
    fn scan_batch_range_and_frontier_must_match() {
        let start = block_height(10);
        let end = block_height(13);
        let exact_blocks = block_source(&[10, 11, 12]);
        let exact_frontier = chain::ChainState::empty(block_height(9), BlockHash([0u8; 32]));
        assert!(validate_scan_batch(&exact_blocks, &exact_frontier, start, end).is_ok());

        for (name, blocks, frontier, error_fragment) in [
            (
                "short blocks",
                block_source(&[10, 11]),
                chain::ChainState::empty(block_height(9), BlockHash([0u8; 32])),
                "compact blocks",
            ),
            (
                "out-of-order blocks",
                block_source(&[10, 12, 11]),
                chain::ChainState::empty(block_height(9), BlockHash([0u8; 32])),
                "compact blocks",
            ),
            (
                "wrong frontier",
                block_source(&[10, 11, 12]),
                chain::ChainState::empty(block_height(8), BlockHash([0u8; 32])),
                "tree state height",
            ),
        ] {
            let error = validate_scan_batch(&blocks, &frontier, start, end).expect_err(name);
            assert!(
                error.to_string().contains(error_fragment),
                "{name}: {error}"
            );
        }
    }

    #[test]
    fn inconsistent_scan_batches_are_retryable_network_failures() {
        let error = inconsistent_scan_batch_error(block_height(10));

        assert!(matches!(error, SyncError::Network(_)));
        assert_eq!(
            error.recovery_strategy(),
            RecoveryStrategy::RetryWithBackoff,
        );
        assert!(error.to_string().starts_with("network:"));
    }

    #[test]
    fn promoted_scan_work_starts_incomplete_and_advances_across_batches() {
        let ranges = [ScanRange::from_parts(
            block_height(1_000)..block_height(1_300),
            ScanPriority::Historic,
        )];
        let (mut total, mut remaining) = (0, 0);
        reset_promoted_scan_progress(&ranges, &mut total, &mut remaining);
        assert_eq!(target_percentage_after_blocks(total, remaining, 0), 0.0);
        for batch in 1..=3 {
            let target = target_percentage_after_blocks(total, remaining, 100);
            remaining -= 100;
            let actual = target_percentage_after_blocks(total, remaining, 0);
            assert_eq!(target, actual);
            assert!((actual - batch as f64 / 3.0).abs() < 1e-9);
        }
        reset_promoted_scan_progress(&[], &mut total, &mut remaining);
        assert_eq!(target_percentage_after_blocks(total, remaining, 0), 1.0);
    }

    #[test]
    fn preparation_progress_does_not_claim_an_empty_scan_queue() {
        let event = preparation_progress_event(2_000, "chain_prepare", 0, 0, 0.0, "");
        assert_eq!(event.remaining_scan_blocks, None);
        assert_eq!(event.pending_scan_start_height, None);
    }

    #[test]
    fn pending_scan_work_includes_ranges_beyond_a_two_block_batch() {
        let ranges = vec![
            ScanRange::from_parts(
                block_height(1_999)..block_height(2_001),
                ScanPriority::Verify,
            ),
            ScanRange::from_parts(
                block_height(1_700)..block_height(1_800),
                ScanPriority::Historic,
            ),
            ScanRange::from_parts(
                block_height(1_800)..block_height(1_900),
                ScanPriority::Scanned,
            ),
        ];
        assert_eq!(pending_scan_blocks(&ranges), 102);
        assert_eq!(earliest_pending_scan_start(&ranges), Some(1_700));
        assert_eq!(pending_scan_blocks(&[]), 0);
        assert_eq!(earliest_pending_scan_start(&[]), None);
    }

    #[test]
    fn empty_chain_state_uses_network_activation_height() {
        assert!(
            should_use_empty_chain_state(&WalletNetwork::Main, BlockHeight::from_u32(419_200))
                .unwrap()
        );
        assert!(!should_use_empty_chain_state(
            &WalletNetwork::Main,
            BlockHeight::from_u32(419_201)
        )
        .unwrap());

        assert!(
            should_use_empty_chain_state(&WalletNetwork::Regtest, BlockHeight::from_u32(1))
                .unwrap()
        );
        assert!(
            !should_use_empty_chain_state(&WalletNetwork::Regtest, BlockHeight::from_u32(141))
                .unwrap()
        );
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn first_batch_of_a_rounded_mainnet_birthday_needs_no_tree_state_request() {
        use zcash_client_backend::proto::compact_formats::{ChainMetadata, CompactBlock};

        let start = BlockHeight::from_u32(2_340_001);
        let state = local_batch_start_state(WalletNetwork::Main, start)
            .unwrap()
            .expect("compiled checkpoint below a rounded birthday");
        assert_eq!(state.block_height(), BlockHeight::from_u32(2_340_000));

        // A served block that continues the checkpoint passes the same
        // continuity check `download_scan_batch` applies.
        let mut block = CompactBlock {
            height: 2_340_001,
            prev_hash: state.block_hash().0.to_vec(),
            chain_metadata: Some(ChainMetadata {
                sapling_commitment_tree_size: state.final_sapling_tree().tree_size() as u32,
                orchard_commitment_tree_size: state.final_orchard_tree().tree_size() as u32,
                ironwood_commitment_tree_size: state.final_ironwood_tree().tree_size() as u32,
            }),
            ..Default::default()
        };
        assert!(block_source::MemoryBlockSource::new(vec![block.clone()]).starts_after(&state));
        // A block from another chain fails it, so the batch falls back to the
        // hash-pinned lookup of the served predecessor.
        block.prev_hash = vec![7u8; 32];
        assert!(!block_source::MemoryBlockSource::new(vec![block]).starts_after(&state));

        // Batches that don't start right after a checkpoint, and other
        // networks, still fetch the state.
        assert!(
            local_batch_start_state(WalletNetwork::Main, BlockHeight::from_u32(2_340_002))
                .unwrap()
                .is_none()
        );
        for network in [WalletNetwork::Test, WalletNetwork::Regtest] {
            assert!(local_batch_start_state(network, start).unwrap().is_none());
        }
        assert!(
            local_batch_start_state(WalletNetwork::Main, BlockHeight::from_u32(419_200))
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn scannable_batch_end_clamps_to_current_tip() {
        assert_eq!(
            scannable_batch_end(
                &WorkModel::compiled(WalletNetwork::Test),
                2_000,
                BlockHeight::from_u32(121),
                BlockHeight::from_u32(131),
                121,
            ),
            Some((2_000, BlockHeight::from_u32(122))),
        );
    }

    #[test]
    fn scannable_batch_end_skips_ranges_past_current_tip() {
        assert_eq!(
            scannable_batch_end(
                &WorkModel::compiled(WalletNetwork::Test),
                2_000,
                BlockHeight::from_u32(122),
                BlockHeight::from_u32(131),
                121,
            ),
            None,
        );
    }

    #[test]
    fn prefetch_ranges_stop_at_the_range_end_and_the_tip() {
        let h = BlockHeight::from_u32;
        let test = WorkModel::compiled(WalletNetwork::Test);
        assert_eq!(
            prefetch_ranges(&test, 1_000, h(1_000), h(10_000), 20_000, 2),
            vec![(h(1_000), h(2_000)), (h(2_000), h(3_000))],
        );
        // The last batch of a range is short and nothing follows it.
        assert_eq!(
            prefetch_ranges(&test, 1_000, h(8_500), h(10_000), 20_000, 2),
            vec![(h(8_500), h(9_500)), (h(9_500), h(10_000))],
        );
        assert_eq!(
            prefetch_ranges(&test, 1_000, h(10_000), h(10_000), 20_000, 2),
            vec![]
        );
        // Blocks past the tip are not requested.
        assert_eq!(
            prefetch_ranges(&test, 1_000, h(1_000), h(10_000), 1_499, 2),
            vec![(h(1_000), h(1_500))],
        );
        assert_eq!(
            prefetch_ranges(&test, 1_000, h(1_000), h(10_000), 20_000, 0),
            vec![]
        );
    }

    /// Queued batches must match the batches the loop then plans, or every
    /// prefetch is thrown away.
    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn prefetch_ranges_match_the_planned_batches() {
        let h = BlockHeight::from_u32;
        let main = WorkModel::compiled(WalletNetwork::Main);
        let (_, first_end) = planned_batch_end(&main, 1_000, h(1_780_001), h(1_800_000)).unwrap();
        let (_, second_end) = planned_batch_end(&main, 1_000, first_end, h(1_800_000)).unwrap();
        assert!(first_end < h(1_781_001), "spam-window batches are short");
        assert_eq!(
            prefetch_ranges(&main, 1_000, h(1_780_001), h(1_800_000), 3_000_000, 2),
            vec![(h(1_780_001), first_end), (first_end, second_end)],
        );
    }

    #[test]
    fn planned_batch_end_uses_the_block_cap_where_blocks_are_sparse() {
        let h = BlockHeight::from_u32;
        let main = WorkModel::compiled(WalletNetwork::Main);
        assert_eq!(
            planned_batch_end(&main, 1_000, h(419_200), h(3_500_000)),
            Some((1_000, h(420_200))),
        );
        // Past the compiled table.
        let sizes = crate::wallet::tree_states::mainnet_tree_sizes(WalletNetwork::Main);
        let past = u32::try_from(sizes.last().unwrap().0).unwrap() + 100_000;
        assert_eq!(
            planned_batch_end(&main, 1_000, h(past), h(past + 5_000)),
            Some((1_000, h(past + 1_000))),
        );
        // No compiled data off mainnet, even at spam-window heights.
        assert_eq!(
            planned_batch_end(
                &WorkModel::compiled(WalletNetwork::Test),
                1_000,
                h(1_780_001),
                h(3_500_000),
            ),
            Some((1_000, h(1_781_001))),
        );
    }

    #[test]
    fn unplanned_blocks_take_at_most_the_unplanned_cap() {
        let h = BlockHeight::from_u32;
        let main = WorkModel::compiled(WalletNetwork::Main);
        let sizes = crate::wallet::tree_states::mainnet_tree_sizes(WalletNetwork::Main);
        let plan_end = u32::try_from(sizes.last().unwrap().0).unwrap() + 1;
        let unplanned = UNPLANNED_BATCH_BLOCKS;

        // Sparse blocks the compiled sizes cover take the desktop cap.
        assert_eq!(
            planned_batch_end(&main, 10_000, h(419_200), h(3_500_000)),
            Some((10_000, h(429_200))),
        );
        // Past the compiled table, at most the unplanned cap.
        let past = plan_end + 100_000;
        assert_eq!(
            planned_batch_end(&main, 10_000, h(past), h(past + 50_000)),
            Some((unplanned, h(past + unplanned))),
        );
        // A batch that starts before the end of the table takes the rest of
        // it and at most the unplanned cap past it.
        let start = plan_end - 500;
        assert_eq!(
            planned_batch_end(&main, 10_000, h(start), h(start + 50_000)),
            Some((500 + unplanned, h(plan_end + unplanned))),
        );
        // Off mainnet, at most the unplanned cap; smaller caps stay.
        let test = WorkModel::compiled(WalletNetwork::Test);
        assert_eq!(
            planned_batch_end(&test, 10_000, h(1_000), h(50_000)),
            Some((unplanned, h(1_000 + unplanned))),
        );
        assert_eq!(
            planned_batch_end(&test, 300, h(1_000), h(50_000)),
            Some((300, h(1_300))),
        );
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn planned_batch_end_fits_the_byte_budget() {
        let h = BlockHeight::from_u32;
        let main = WorkModel::compiled(WalletNetwork::Main);
        let start = 1_780_001;
        let (blocks, end) = planned_batch_end(&main, 1_000, h(start), h(3_500_000)).unwrap();
        assert!(blocks < 1_000);
        assert_eq!(end, h(start + blocks));
        let bytes = |n: u32| main.plan_bytes(u64::from(start), u64::from(start + n));
        assert!(bytes(blocks) <= BATCH_BYTE_BUDGET);
        assert!(bytes(blocks + 1) > BATCH_BYTE_BUDGET);

        // A batch is not cut where the spam window starts.
        let (_, end) =
            planned_batch_end(&main, 1_000, h(SANDBLASTING_START - 500), h(3_500_000)).unwrap();
        assert!(end > h(SANDBLASTING_START));
    }

    /// The budgets follow from the compiled tree sizes at fixed heights, so a
    /// longer table does not move them.
    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn batch_byte_budget_matches_its_derivation() {
        let main = WorkModel::compiled(WalletNetwork::Main);
        // The 2,000-block batch right after the window.
        let desktop = main.download_bytes(2_050_001, 2_052_001);
        // 100 blocks of the densest compiled step in the window.
        let sizes = crate::wallet::tree_states::mainnet_tree_sizes(WalletNetwork::Main);
        let mobile = sizes
            .windows(2)
            .filter(|pair| {
                pair[0].0 >= u64::from(SANDBLASTING_START)
                    && pair[1].0 <= u64::from(SANDBLASTING_END)
            })
            .map(|pair| {
                let (from, to) = (pair[0].0 + 1, pair[1].0 + 1);
                main.download_bytes(from, to) / (to - from) as f64
            })
            .fold(0.0, f64::max)
            * 100.0;
        for (budget, derived) in [
            (DESKTOP_BATCH_BYTE_BUDGET, desktop),
            (MOBILE_BATCH_BYTE_BUDGET, mobile),
        ] {
            assert!(
                (budget / derived - 1.0).abs() < 0.01,
                "budget {budget} vs derived {derived}",
            );
        }
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn plan_end_bounds_the_estimate() {
        let h = BlockHeight::from_u32;
        for network in [WalletNetwork::Test, WalletNetwork::Regtest] {
            let model = WorkModel::compiled(network);
            assert_eq!(model.plan_bytes(1_780_001, 1_790_001), 0.0);
            assert_eq!(
                planned_batch_end(&model, 1_000, h(1_780_001), h(3_500_000)),
                Some((1_000, h(1_781_001))),
            );
        }
        let main = WorkModel::compiled(WalletNetwork::Main);
        let sizes = crate::wallet::tree_states::mainnet_tree_sizes(WalletNetwork::Main);
        let plan_end = sizes.last().unwrap().0 + 1;
        // Bytes stop at the last checkpoint instead of extrapolating.
        assert_eq!(
            main.plan_bytes(plan_end - 1, plan_end + 100_000),
            main.plan_bytes(plan_end - 1, plan_end),
        );
        // A batch starting just before it is not cut there.
        let start = u32::try_from(plan_end - 10).unwrap();
        assert_eq!(
            planned_batch_end(&main, 1_000, h(start), h(start + 5_000)),
            Some((1_000, h(start + 1_000))),
        );
    }

    #[test]
    fn debug_cap_limits_every_batch() {
        let h = BlockHeight::from_u32;
        let main = WorkModel::compiled(WalletNetwork::Main);
        assert_eq!(
            planned_batch_end(&main, 5, h(1_780_001), h(2_000_000)),
            Some((5, h(1_780_006))),
        );
    }

    #[test]
    fn witness_check_runs_without_a_clean_marker() {
        assert_eq!(
            decide_witness_check(WitnessCheckMeta::default(), 3_364_776, false),
            WitnessCheckDecision::Run(WitnessCheckRunReason::MissingMarker),
        );
    }

    #[test]
    fn witness_check_skips_when_recent_clean_marker_matches_policy() {
        let meta = WitnessCheckMeta {
            policy_version: Some(WITNESS_CHECK_POLICY_VERSION),
            last_clean_height: Some(3_364_774),
        };

        assert_eq!(
            decide_witness_check(meta, 3_364_776, false),
            WitnessCheckDecision::Skip {
                last_clean_height: 3_364_774,
                age_blocks: 2,
            },
        );
    }

    #[test]
    fn witness_check_runs_when_forced_or_marker_is_stale() {
        let meta = WitnessCheckMeta {
            policy_version: Some(WITNESS_CHECK_POLICY_VERSION),
            last_clean_height: Some(1_000),
        };

        assert_eq!(
            decide_witness_check(meta, 1_001, true),
            WitnessCheckDecision::Run(WitnessCheckRunReason::Forced),
        );
        assert_eq!(
            decide_witness_check(meta, 1_000 + WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS, false),
            WitnessCheckDecision::Run(WitnessCheckRunReason::MaxCleanAgeReached {
                age_blocks: WITNESS_CHECK_MAX_CLEAN_AGE_BLOCKS,
            }),
        );
    }

    #[test]
    fn witness_check_runs_when_policy_changes_or_tip_rewinds() {
        assert_eq!(
            decide_witness_check(
                WitnessCheckMeta {
                    policy_version: Some(WITNESS_CHECK_POLICY_VERSION + 1),
                    last_clean_height: Some(3_364_774),
                },
                3_364_776,
                false,
            ),
            WitnessCheckDecision::Run(WitnessCheckRunReason::PolicyVersionChanged {
                stored: WITNESS_CHECK_POLICY_VERSION + 1,
            }),
        );
        assert_eq!(
            decide_witness_check(
                WitnessCheckMeta {
                    policy_version: Some(WITNESS_CHECK_POLICY_VERSION),
                    last_clean_height: Some(3_364_776),
                },
                3_364_775,
                false,
            ),
            WitnessCheckDecision::Run(WitnessCheckRunReason::TipBelowLastClean {
                last_clean_height: 3_364_776,
            }),
        );
    }

    #[test]
    fn witness_check_clean_marker_round_trips_through_sync_meta_table() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();

        mark_witness_check_clean(db_path, 3_364_776).unwrap();

        assert_eq!(
            read_witness_check_meta(db_path).unwrap(),
            WitnessCheckMeta {
                policy_version: Some(WITNESS_CHECK_POLICY_VERSION),
                last_clean_height: Some(3_364_776),
            },
        );
    }

    #[test]
    fn completed_sync_marker_round_trips_and_advances() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();

        assert_eq!(
            read_sync_completion_meta(db_path).unwrap(),
            (None, None, None)
        );
        mark_sync_completed(db_path, 3_364_776).unwrap();
        assert_eq!(
            read_sync_completion_meta(db_path).unwrap(),
            (
                Some(SYNC_COMPLETION_POLICY_VERSION),
                Some(3_364_776),
                Some(false)
            ),
        );
        mark_sync_started(db_path).unwrap();
        assert_eq!(
            completed_sync_height_for_status(db_path, 3_364_776, 3_364_776).unwrap(),
            None,
        );
        mark_sync_completed(db_path, 3_364_777).unwrap();
        assert_eq!(
            read_sync_completion_meta(db_path).unwrap(),
            (
                Some(SYNC_COMPLETION_POLICY_VERSION),
                Some(3_364_777),
                Some(false)
            ),
        );
    }

    #[test]
    fn only_work_since_the_completed_sync_is_a_catch_up() {
        let completed = Some(3_000_000);
        // The blocks since, or a reorg the backend handles below them.
        assert!(scans_only_after_completion(Some(3_000_001), completed));
        assert!(scans_only_after_completion(Some(2_999_990), completed));
        assert!(scans_only_after_completion(Some(2_999_900), completed));
        assert!(scans_only_after_completion(None, completed));
        // History below them: an account added since, from its birthday.
        assert!(!scans_only_after_completion(Some(2_999_899), completed));
        assert!(!scans_only_after_completion(Some(2_500_000), completed));
        assert!(!scans_only_after_completion(Some(3_000_001), None));
    }

    #[test]
    fn a_catch_up_that_meets_account_history_is_one_no_longer() {
        let h = BlockHeight::from_u32;
        let claimed = progress_work::StoredProgressJob {
            from_completed_sync: true,
            ..progress_work::StoredProgressJob::unmeasured()
        };
        let (mut job, _) = JobProgress::start(claimed, 10.0, 1.0);
        let completed = Some(3_000_000);
        let tip = ScanRange::from_parts(h(3_000_001)..h(3_000_005), ScanPriority::ChainTip);
        assert!(!reclassify_catch_up(&mut job, &[tip.clone()], completed));
        assert!(job.from_completed_sync());

        // An account added during the attempt queues its history.
        let history = ScanRange::from_parts(h(2_500_000)..h(3_000_001), ScanPriority::Historic);
        assert!(reclassify_catch_up(
            &mut job,
            &[history, tip.clone()],
            completed
        ));
        assert!(!job.from_completed_sync());
        assert!(!reclassify_catch_up(&mut job, &[tip], completed));
    }

    #[test]
    fn sync_starts_share_one_progress_job_until_completion() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let path = file.path().to_str().unwrap();
        let first = mark_sync_started(path).unwrap();
        assert!(
            !first.from_completed_sync,
            "the first sync is not a catch-up"
        );
        assert_eq!(mark_sync_started(path).unwrap().id, first.id);
        assert_eq!(
            stored_progress_job(path),
            Some((first.id.clone(), 0.0, false))
        );

        // The scan finished, but the attempt stopped before completing: the
        // status still names the job the next attempt resumes.
        let finished = progress_work::StoredProgressJob {
            total_work: 500.0,
            fraction: 1.0,
            ..first.clone()
        };
        progress_work::write_progress_job(path, &finished).unwrap();
        assert_eq!(
            stored_progress_job(path),
            Some((first.id.clone(), 1.0, false))
        );
        assert_eq!(mark_sync_started(path).unwrap(), finished);

        mark_sync_completed(path, 100).unwrap();
        assert_eq!(stored_progress_job(path), None);

        // The next sync starts from a completed one: a catch-up, which the
        // status reports until it completes.
        let catch_up = mark_sync_started(path).unwrap();
        assert_ne!(catch_up.id, first.id);
        assert!(catch_up.from_completed_sync);
        assert_eq!(
            stored_progress_job(path),
            Some((catch_up.id.clone(), 0.0, true))
        );
        assert_eq!(mark_sync_started(path).unwrap(), catch_up);
        mark_sync_completed(path, 101).unwrap();
        assert_eq!(stored_progress_job(path), None);
        assert_ne!(mark_sync_started(path).unwrap().id, first.id);
    }

    #[test]
    fn completion_policy_migrates_legacy_tip_only_once() {
        let legacy_file = tempfile::NamedTempFile::new().unwrap();
        let legacy_path = legacy_file.path().to_str().unwrap();
        assert_eq!(
            completed_sync_height_for_status(legacy_path, 100, 100).unwrap(),
            Some(100),
        );
        assert_eq!(
            read_sync_completion_meta(legacy_path).unwrap(),
            (Some(SYNC_COMPLETION_POLICY_VERSION), Some(100), Some(false)),
        );

        let active_sync_file = tempfile::NamedTempFile::new().unwrap();
        let active_sync_path = active_sync_file.path().to_str().unwrap();
        mark_sync_completed(active_sync_path, 100).unwrap();
        mark_sync_started(active_sync_path).unwrap();
        assert_eq!(
            completed_sync_height_for_status(active_sync_path, 100, 100).unwrap(),
            None,
        );
        assert_eq!(
            read_sync_completion_meta(active_sync_path).unwrap(),
            (Some(SYNC_COMPLETION_POLICY_VERSION), Some(100), Some(true)),
        );
    }

    #[test]
    fn completion_requires_one_exact_height_across_network_db_and_scanner() {
        assert_eq!(
            validate_complete_scan_heights(100, Some((100, 100))).unwrap(),
            (100, 100),
        );
        assert_eq!(validate_complete_scan_heights(0, None).unwrap(), (0, 0));

        for (label, current_tip, wallet_heights) in [
            ("missing summary", 100, None),
            ("DB behind network", 100, Some((99, 99))),
            ("DB ahead of network", 100, Some((101, 101))),
            ("scanner behind DB", 100, Some((99, 100))),
            ("scanner ahead of DB", 100, Some((101, 100))),
        ] {
            assert!(
                validate_complete_scan_heights(current_tip, wallet_heights).is_err(),
                "{label} should block completion",
            );
        }
    }

    #[test]
    fn completion_requires_the_scanned_tip_hash() {
        assert!(validate_complete_tip_hash(0, None).is_ok());
        assert!(validate_complete_tip_hash(100, Some(BlockHash([0x11; 32]))).is_ok());
        assert!(matches!(
            validate_complete_tip_hash(100, None),
            Err(SyncError::Db(_)),
        ));
    }

    #[test]
    fn tip_hash_fallback_is_used_only_when_identity_proof_is_needed() {
        let stored_hash = Some(BlockHash([0x11; 32]));

        assert!(tip_hash_fallback_required(100, stored_hash, 100, &[]));
        assert!(!tip_hash_fallback_required(100, stored_hash, 99, &[]));
        assert!(!tip_hash_fallback_required(100, stored_hash, 101, &[]));
        assert!(!tip_hash_fallback_required(100, None, 100, &[]));
        assert!(!tip_hash_fallback_required(
            100,
            stored_hash,
            100,
            &[0x11; 32],
        ));
    }

    #[test]
    fn failed_refresh_forces_queue_drain_validation_inside_the_grace_period() {
        assert!(should_refresh_tip_before_completion(
            true,
            std::time::Duration::ZERO,
        ));
        assert!(!should_refresh_tip_before_completion(
            false,
            FINAL_TIP_REFRESH_MIN_AGE - std::time::Duration::from_millis(1),
        ));
        assert!(should_refresh_tip_before_completion(
            false,
            FINAL_TIP_REFRESH_MIN_AGE,
        ));
    }

    #[test]
    fn partial_catch_up_validates_target_identity_before_completion() {
        let target_hash = BlockHash([0x22; 32]);

        // The target is ahead of the scanned DB, so its hash is not stored yet.
        // This is valid catch-up work, but it cannot count as identity proof.
        let initial_relation = classify_refreshed_tip(90, None, 100, &target_hash.0).unwrap();
        assert_eq!(initial_relation, RefreshedTipRelation::Advanced);
        let mut validation_required = initial_relation != RefreshedTipRelation::Unchanged;
        assert!(should_refresh_tip_before_completion(
            validation_required,
            std::time::Duration::ZERO,
        ));

        // A refresh during partial scanning still cannot compare the target
        // identity. The sync remains live and preserves the final check.
        let partial_relation = classify_refreshed_tip(100, None, 100, &target_hash.0).unwrap();
        assert_eq!(partial_relation, RefreshedTipRelation::UnchangedUnverified,);
        validation_required = partial_relation != RefreshedTipRelation::Unchanged;
        assert!(should_refresh_tip_before_completion(
            validation_required,
            std::time::Duration::ZERO,
        ));
        assert!(validate_complete_tip_hash(100, None).is_err());

        // Once scanning stores the target block, the queue-drain refresh can
        // prove identity and the exact-height completion checks can pass.
        let final_relation =
            classify_refreshed_tip(100, Some(target_hash), 100, &target_hash.0).unwrap();
        assert_eq!(final_relation, RefreshedTipRelation::Unchanged);
        validation_required = final_relation != RefreshedTipRelation::Unchanged;
        assert!(!should_refresh_tip_before_completion(
            validation_required,
            std::time::Duration::ZERO,
        ));
        assert_eq!(
            validate_complete_scan_heights(100, Some((100, 100))).unwrap(),
            (100, 100),
        );
        validate_complete_tip_hash(100, Some(target_hash)).unwrap();
    }

    #[test]
    fn same_height_fork_requires_rewind_rescan_and_identity_revalidation() {
        let old_tip_hash = BlockHash([0x11; 32]);
        let fork_tip_hash = BlockHash([0x22; 32]);

        let fork_relation =
            classify_refreshed_tip(100, Some(old_tip_hash), 100, &fork_tip_hash.0).unwrap();
        assert_eq!(fork_relation, RefreshedTipRelation::Reorg);
        let mut validation_required = true;
        assert!(should_refresh_tip_before_completion(
            validation_required,
            std::time::Duration::ZERO,
        ));

        let requested = confirmed_reorg_rewind_target(BlockHeight::from_u32(100)).unwrap();
        let mut rewind_calls = Vec::new();
        let actual = truncate_wallet_with(
            "same-height-fork-rewind",
            requested,
            BlockHeight::from_u32(100),
            |height| {
                rewind_calls.push(height);
                Ok(height)
            },
        )
        .unwrap();
        assert_eq!(actual, BlockHeight::from_u32(99));
        assert_eq!(rewind_calls, vec![BlockHeight::from_u32(99)]);
        assert!(validate_complete_scan_heights(100, Some((99, 100))).is_err());

        // Rescanning the replacement block stores the fork identity. A fresh
        // same-height observation can then authorize completion.
        let final_relation =
            classify_refreshed_tip(100, Some(fork_tip_hash), 100, &fork_tip_hash.0).unwrap();
        validation_required = final_relation != RefreshedTipRelation::Unchanged;
        assert!(!should_refresh_tip_before_completion(
            validation_required,
            std::time::Duration::ZERO,
        ));
        assert_eq!(
            validate_complete_scan_heights(100, Some((100, 100))).unwrap(),
            (100, 100),
        );
        validate_complete_tip_hash(100, Some(fork_tip_hash)).unwrap();
    }

    #[test]
    fn lower_server_is_rejected_without_a_database_action_even_when_its_hash_diverges() {
        let stored_hash = BlockHash([0x11; 32]);

        for fresh_hash in [vec![], vec![0x11; 32], vec![0x22; 32], vec![0x33; 31]] {
            let relation = classify_refreshed_tip(100, Some(stored_hash), 99, &fresh_hash).unwrap();

            assert_eq!(relation, RefreshedTipRelation::ServerBehind);
            let mut database_mutations = 0;
            let result = match relation {
                RefreshedTipRelation::ServerBehind => Err(lagging_lightwalletd_tip(100, 99)),
                RefreshedTipRelation::Advanced | RefreshedTipRelation::Reorg => {
                    database_mutations += 1;
                    Ok(())
                }
                RefreshedTipRelation::Unchanged | RefreshedTipRelation::UnchangedUnverified => {
                    Ok(())
                }
            };

            assert!(matches!(result, Err(SyncError::Network(_))));
            assert_eq!(database_mutations, 0);
        }
    }

    #[tokio::test]
    async fn cancellation_during_latest_tip_rpc_wins_over_error_and_mutation() {
        let cancel = AtomicBool::new(false);
        let desired_mode = AtomicU8::new(1);
        let should_exit =
            || cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != 1;

        let rpc_result = async {
            tokio::task::yield_now().await;
            cancel.store(true, Ordering::Relaxed);
            Err::<(), _>(SyncError::net("get_latest_block failed"))
        }
        .await;
        let outcome = tip_rpc_result_unless_exiting(rpc_result, should_exit());

        let mut database_mutations = 0;
        if let Some(result) = outcome {
            result.unwrap();
            database_mutations += 1;
        }
        assert_eq!(database_mutations, 0);
    }

    #[tokio::test]
    async fn mode_change_during_tip_hash_fallback_wins_over_error_and_mutation() {
        let cancel = AtomicBool::new(false);
        let desired_mode = AtomicU8::new(1);
        let should_exit =
            || cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != 1;

        let rpc_result = async {
            tokio::task::yield_now().await;
            desired_mode.store(2, Ordering::SeqCst);
            Err::<RefreshedTipRelation, _>(SyncError::net("get_block failed"))
        }
        .await;
        let outcome = tip_rpc_result_unless_exiting(rpc_result, should_exit());

        let mut database_mutations = 0;
        if let Some(result) = outcome {
            result.unwrap();
            database_mutations += 1;
        }
        assert_eq!(database_mutations, 0);
    }

    #[test]
    fn unusable_safe_rewind_is_rejected_before_the_fallback_mutation() {
        let requested = BlockHeight::from_u32(98);
        let fresh_tip = BlockHeight::from_u32(100);
        let unsafe_checkpoint = BlockHeight::from_u32(100);
        let mut calls = Vec::new();

        let result = truncate_wallet_with("unsafe-reorg-rewind", requested, fresh_tip, |height| {
            calls.push(height);
            Err(SqliteClientError::RequestedRewindInvalid {
                safe_rewind_height: Some(unsafe_checkpoint),
                requested_height: height,
            })
        });

        assert!(matches!(result, Err(SyncError::Db(_))));
        assert_eq!(calls, vec![requested]);
    }

    #[test]
    fn confirmed_reorg_target_is_checked_before_any_database_call() {
        assert!(matches!(
            confirmed_reorg_rewind_target(BlockHeight::from_u32(0)),
            Err(SyncError::Network(_)),
        ));
        assert_eq!(
            confirmed_reorg_rewind_target(BlockHeight::from_u32(1)).unwrap(),
            BlockHeight::from_u32(0),
        );
        assert_eq!(
            confirmed_reorg_rewind_target(BlockHeight::from_u32(100)).unwrap(),
            BlockHeight::from_u32(99),
        );
    }

    #[test]
    fn usable_safe_rewind_is_validated_before_and_after_the_retry() {
        let requested = BlockHeight::from_u32(98);
        let fresh_tip = BlockHeight::from_u32(100);
        let safe_checkpoint = BlockHeight::from_u32(99);
        let mut calls = Vec::new();

        let result = truncate_wallet_with("safe-reorg-rewind", requested, fresh_tip, |height| {
            calls.push(height);
            if calls.len() == 1 {
                Err(SqliteClientError::RequestedRewindInvalid {
                    safe_rewind_height: Some(safe_checkpoint),
                    requested_height: height,
                })
            } else {
                Ok(height)
            }
        });

        assert_eq!(result.unwrap(), safe_checkpoint);
        assert_eq!(calls, vec![requested, safe_checkpoint]);
    }

    #[test]
    fn refreshed_tip_classifies_height_and_hash_changes() {
        let stored_hash = BlockHash([0x11; 32]);

        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 101, &[]).unwrap(),
            RefreshedTipRelation::Advanced,
        );
        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 99, &[]).unwrap(),
            RefreshedTipRelation::ServerBehind,
        );
        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 99, &[0x11; 32]).unwrap(),
            RefreshedTipRelation::ServerBehind,
        );
        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 99, &[0x22; 32]).unwrap(),
            RefreshedTipRelation::ServerBehind,
        );
        assert_eq!(
            classify_refreshed_tip(100, None, 99, &[0x22; 32]).unwrap(),
            RefreshedTipRelation::ServerBehind,
        );
        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 100, &[0x11; 32]).unwrap(),
            RefreshedTipRelation::Unchanged,
        );
        assert_eq!(
            classify_refreshed_tip(100, Some(stored_hash), 100, &[0x22; 32]).unwrap(),
            RefreshedTipRelation::Reorg,
        );
        assert!(classify_refreshed_tip(100, Some(stored_hash), 100, &[]).is_err());
        assert_eq!(
            classify_refreshed_tip(100, None, 100, &[]).unwrap(),
            RefreshedTipRelation::UnchangedUnverified,
        );
        assert_eq!(
            classify_refreshed_tip(100, None, 100, &[0x11; 32]).unwrap(),
            RefreshedTipRelation::UnchangedUnverified,
        );
        assert_eq!(
            classify_refreshed_tip(0, None, 0, &[]).unwrap(),
            RefreshedTipRelation::Unchanged,
        );
    }

    #[test]
    fn refreshed_tip_rejects_a_nonempty_malformed_hash() {
        assert!(
            classify_refreshed_tip(100, Some(BlockHash([0x11; 32])), 100, &[0x11; 31]).is_err()
        );
        assert!(classify_refreshed_tip(100, None, 101, &[0x11; 31]).is_err());
    }

    #[test]
    fn sqlite_lock_contention_is_recognised() {
        use rusqlite::ffi;

        // DatabaseBusy → transient
        let busy = SqliteClientError::DbError(rusqlite::Error::SqliteFailure(
            ffi::Error::new(ffi::SQLITE_BUSY),
            Some("database is locked".into()),
        ));
        assert!(is_sqlite_lock_contention(&busy));

        // DatabaseLocked → transient
        let locked = SqliteClientError::DbError(rusqlite::Error::SqliteFailure(
            ffi::Error::new(ffi::SQLITE_LOCKED),
            Some("database table is locked".into()),
        ));
        assert!(is_sqlite_lock_contention(&locked));

        // SQLITE_CORRUPT → NOT transient (genuine DB failure)
        let corrupt = SqliteClientError::DbError(rusqlite::Error::SqliteFailure(
            ffi::Error::new(ffi::SQLITE_CORRUPT),
            None,
        ));
        assert!(!is_sqlite_lock_contention(&corrupt));

        // SQLITE_IOERR → NOT transient under our policy (could be
        // transient in principle but not covered by this helper). Kept
        // as-is so a future expansion to include IOERR_* codes is a
        // deliberate change.
        let ioerr = SqliteClientError::DbError(rusqlite::Error::SqliteFailure(
            ffi::Error::new(ffi::SQLITE_IOERR),
            None,
        ));
        assert!(!is_sqlite_lock_contention(&ioerr));

        // A non-DbError wallet variant is trivially not lock contention.
        let block_conflict = SqliteClientError::BlockConflict(
            zcash_protocol::consensus::BlockHeight::from_u32(2_500_000),
        );
        assert!(!is_sqlite_lock_contention(&block_conflict));
    }

    #[test]
    fn commitment_tree_root_conflict_is_recognised() {
        use incrementalmerkletree::{Address, Level};

        let conflict = SqliteClientError::CommitmentTree(ShardTreeError::Insert(
            InsertionError::Conflict(Address::from_parts(Level::new(7), 391_096)),
        ));
        assert!(is_commitment_tree_root_conflict(&conflict));

        let out_of_range =
            SqliteClientError::CommitmentTree(ShardTreeError::Insert(InsertionError::OutOfRange(
                incrementalmerkletree::Position::from(0),
                incrementalmerkletree::Position::from(1)..incrementalmerkletree::Position::from(2),
            )));
        assert!(!is_commitment_tree_root_conflict(&out_of_range));

        let block_conflict = SqliteClientError::BlockConflict(
            zcash_protocol::consensus::BlockHeight::from_u32(2_500_000),
        );
        assert!(!is_commitment_tree_root_conflict(&block_conflict));
    }

    #[test]
    fn witness_position_beyond_tree_is_recognised() {
        use incrementalmerkletree::{Address, Level};

        let not_contained = SqliteClientError::CommitmentTree(ShardTreeError::Query(
            QueryError::NotContained(Address::from_parts(Level::new(0), 0)),
        ));
        assert!(is_witness_position_beyond_tree(&not_contained));

        let incomplete = SqliteClientError::CommitmentTree(ShardTreeError::Query(
            QueryError::TreeIncomplete(vec![]),
        ));
        assert!(!is_witness_position_beyond_tree(&incomplete));
    }

    #[test]
    fn unmined_note_position_repair_preserves_mined_notes() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                mined_height INTEGER
             );
             CREATE TABLE sapling_received_notes (
                id INTEGER PRIMARY KEY,
                transaction_id INTEGER NOT NULL,
                commitment_tree_position INTEGER
             );
             CREATE TABLE ironwood_received_notes (
                id INTEGER PRIMARY KEY,
                transaction_id INTEGER NOT NULL,
                commitment_tree_position INTEGER
             );
             INSERT INTO transactions (id_tx, mined_height) VALUES (1, NULL), (2, 500);
             INSERT INTO sapling_received_notes
                (id, transaction_id, commitment_tree_position)
                VALUES (1, 1, 3), (2, 2, 4);
             INSERT INTO ironwood_received_notes
                (id, transaction_id, commitment_tree_position)
                VALUES (1, 1, 0), (2, 2, 1);",
        )
        .unwrap();
        drop(conn);

        assert_eq!(clear_unmined_note_commitment_positions(db_path).unwrap(), 2);

        let conn = rusqlite::Connection::open(db_path).unwrap();
        let sapling_positions = conn
            .prepare("SELECT commitment_tree_position FROM sapling_received_notes ORDER BY id")
            .unwrap()
            .query_map([], |row| row.get::<_, Option<u64>>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        let ironwood_positions = conn
            .prepare("SELECT commitment_tree_position FROM ironwood_received_notes ORDER BY id")
            .unwrap()
            .query_map([], |row| row.get::<_, Option<u64>>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert_eq!(sapling_positions, vec![None, Some(4)]);
        assert_eq!(ironwood_positions, vec![None, Some(1)]);
        assert_eq!(clear_unmined_note_commitment_positions(db_path).unwrap(), 0);
    }
}

pub(crate) fn enhance_recovery_status(
    path: &str,
    network: WalletNetwork,
) -> Result<crate::api::sync::EnhanceRecoveryStatus, String> {
    let mut db = open_wallet_db_readonly_with_timeout(path, network, READ_DB_BUSY_TIMEOUT)?;
    EnhancementPolicy::current(network).configure_db(&mut db);
    recovery_status_for(&db, path, enhancement::phase(path))
}

/// Counts recovery work in a database already configured with the current
/// enhancement policy.
///
/// Work that failed on content, got a reply, or was created by a reply at the
/// current chain tip is left out: it waits for the next block (see
/// [`enhancement::content_failures`]), so whether a recovery-only restart
/// happens never depends on what a reply said. Expired transparent-service
/// waits are reported separately: their public schedule permits only the
/// accounts whose waits expired to retry at the same tip.
fn recovery_status_for(
    db: &WalletDatabase,
    db_path: &str,
    service_state: String,
) -> Result<crate::api::sync::EnhanceRecoveryStatus, String> {
    use enhancement::content_failures;
    use zcash_client_backend::data_api::enhance_pir::EnhancePirRead;
    use zcash_client_backend::data_api::enhance_pir::TransactionEnhancementWork;
    use zcash_client_backend::data_api::status::{TransactionStatusRead, TransactionStatusWork};
    // `run_requests` defers private status failures for the session while the
    // obligation stays durable. Without counting it here, a wallet with no
    // payload work would never schedule the retry once Status PIR recovers.
    let status = db
        .transaction_status_work()
        .map_err(|e| e.to_string())?
        .into_iter()
        .filter(|work| matches!(work, TransactionStatusWork::Private(_)))
        .filter(|work| content_failures::may_ask_status(db_path, &work.txid()))
        .count();
    let work = zakura_pir_client::enhance::wallet::PreparedWork::new(
        db.transaction_enhancement_work()
            .map_err(|e| e.to_string())?
            .into_iter()
            .filter_map(|work| match work {
                TransactionEnhancementWork::Private(work)
                    if content_failures::may_ask(db_path, &work) =>
                {
                    Some(work)
                }
                TransactionEnhancementWork::Private(_) | TransactionEnhancementWork::Public(_) => {
                    None
                }
            }),
    );
    Ok(crate::api::sync::EnhanceRecoveryStatus {
        queries: work.query_count() as u32,
        rediscovery: work.rediscover.len() as u32,
        suspended: work.suspended as u32,
        status: status as u32,
        transparent_retry_due: transparent_ledger::service_retry_due(db_path),
        service_state,
    })
}

#[cfg(test)]
mod birthday_rpc_tests;
