use std::collections::{BTreeSet, HashSet, VecDeque};
use std::future::Future;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, RwLock};

use futures::{stream, StreamExt, TryStreamExt};
use nonempty::NonEmpty;
use rusqlite::{params, OptionalExtension};
use shardtree::error::{InsertionError, QueryError, ShardTreeError};
use tonic::transport::Channel;
use zcash_client_backend::data_api::{
    chain::{self, error::Error as ChainError, scan_cached_blocks},
    scanning::{ScanPriority, ScanRange},
    wallet::ConfirmationsPolicy,
    WalletCommitmentTrees, WalletRead, WalletWrite,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_with_timeout,
        open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        SYNC_DB_BUSY_TIMEOUT,
    },
    keys,
    network::WalletNetwork,
    sync, transparent_receive_cache,
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

mod block_source;
mod enhance;
mod error;
mod lwd;
pub(crate) mod mempool;

use enhance::run_enhancement;
pub(crate) use error::SyncError;
use error::{RecoveryStrategy, MAX_REWINDS_PER_RUN};
use lwd::{
    download_blocks, download_subtree_roots, get_address_utxos_stream, get_compact_block_hash,
    get_tree_state,
};
pub(crate) use lwd::{
    get_latest_block, get_taddress_txids, get_transaction, next_stream_message,
    open_background_direct_lwd_channel, open_isolated_lwd_channel, open_lwd_channel,
    send_transaction, send_transaction_with_status,
};

/// Progress event sent to caller (Dart or Swift).
#[derive(Clone, Debug)]
pub struct SyncProgressEvent {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub display_target_percentage: f64,
    pub display_target_blocks: u64,
    pub is_syncing: bool,
    pub is_complete: bool,
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
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const BATCH_SIZE_FOREGROUND: u32 = 2000;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const BATCH_SIZE_FOREGROUND: u32 = 1000;
const BATCH_SIZE_BACKGROUND: u32 = 300;
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

fn preparation_progress_event(
    chain_tip_height: u64,
    phase: &str,
    phase_completed_units: u64,
    phase_total_units: u64,
) -> SyncProgressEvent {
    SyncProgressEvent {
        scanned_height: 0,
        chain_tip_height,
        percentage: 0.0,
        display_target_percentage: 0.0,
        display_target_blocks: 0,
        is_syncing: true,
        is_complete: false,
        has_new_tx: false,
        phase_completed_units,
        phase_total_units,
        phase: phase.into(),
    }
}

/// Sandblasting attack range (Zcash mainnet). Blocks in this range
/// contain a very large number of outputs from a sustained spam
/// attack, making `scan_cached_blocks` significantly more expensive
/// per block. We reduce the batch size to `BATCH_SIZE_SANDBLASTING`
/// while the next batch falls inside this window to avoid excessive
/// memory pressure and potential timeouts. Batches are clamped at both
/// boundaries so a long historical range does not inherit the reduced
/// size before reaching the window or keep it after leaving the window.
///
/// Matches `zcash-android-wallet-sdk`'s `SANDBLASTING_RANGE` in
/// `CompactBlockProcessor.kt:1171-1181`.
const SANDBLASTING_START: u32 = 1_710_000;
const SANDBLASTING_END: u32 = 2_050_000;
const BATCH_SIZE_SANDBLASTING: u32 = 100;

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
// Witness repair is finalization work after the main scan drains. Cap its
// starting display percentage so a long repair pass is visible instead of
// looking pinned at 99%, while still avoiding a misleading deep rewind signal.
const TAIL_REPAIR_MAX_START_PERCENTAGE: f64 = 0.95;
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

fn planned_batch_end(
    base_batch_size: u32,
    start: BlockHeight,
    range_end: BlockHeight,
) -> Option<(u32, BlockHeight)> {
    if start >= range_end {
        return None;
    }

    let start_u32 = u32::from(start);
    let (batch_size, phase_end) = if start_u32 < SANDBLASTING_START {
        (
            base_batch_size,
            std::cmp::min(range_end, BlockHeight::from_u32(SANDBLASTING_START)),
        )
    } else if start_u32 < SANDBLASTING_END {
        (
            BATCH_SIZE_SANDBLASTING,
            std::cmp::min(range_end, BlockHeight::from_u32(SANDBLASTING_END)),
        )
    } else {
        (base_batch_size, range_end)
    };

    let end = std::cmp::min(start + batch_size, phase_end);
    Some((batch_size, end))
}

fn chain_tip_exclusive_end(current_tip_height: u64) -> BlockHeight {
    let current_tip = u32::try_from(current_tip_height).unwrap_or(u32::MAX);
    BlockHeight::from_u32(current_tip.saturating_add(1))
}

fn scannable_batch_end(
    base_batch_size: u32,
    start: BlockHeight,
    range_end: BlockHeight,
    current_tip_height: u64,
) -> Option<(u32, BlockHeight)> {
    let available_end = std::cmp::min(range_end, chain_tip_exclusive_end(current_tip_height));
    if start >= available_end {
        return None;
    }

    planned_batch_end(base_batch_size, start, available_end)
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

fn chain_window_percentage(window_start_height: u64, tip_height: u64, scanned_height: u64) -> f64 {
    if tip_height <= window_start_height {
        return 1.0;
    }
    let scanned = scanned_height.saturating_sub(window_start_height);
    let total = tip_height - window_start_height;
    (scanned as f64 / total as f64).clamp(0.0, 1.0)
}

fn tail_repair_percentage(base_percentage: f64, total_blocks: u64, remaining_blocks: u64) -> f64 {
    if total_blocks == 0 {
        return 1.0;
    }
    let completed = total_blocks.saturating_sub(remaining_blocks);
    let repair_fraction = completed as f64 / total_blocks as f64;
    let base = base_percentage.clamp(0.0, TAIL_REPAIR_MAX_START_PERCENTAGE);
    (base + ((1.0 - base) * repair_fraction)).clamp(0.0, 1.0)
}

fn chain_window_frontier_height(ranges: &[ScanRange], fallback_height: u64) -> u64 {
    earliest_pending_scan_start(ranges).unwrap_or(fallback_height)
}

fn chain_window_target_height_after_batch(
    ranges: &[ScanRange],
    batch_start: BlockHeight,
    batch_end: BlockHeight,
    fallback_height: u64,
) -> u64 {
    let frontier = chain_window_frontier_height(ranges, fallback_height);
    if frontier == u32::from(batch_start) as u64 {
        u32::from(batch_end) as u64
    } else {
        frontier
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum ProgressDisplayMode {
    Work,
    ChainWindow {
        window_start_height: u64,
    },
    TailRepair {
        base_percentage: f64,
        total_blocks: u64,
    },
}

impl ProgressDisplayMode {
    fn percentage(
        self,
        initial_total: u64,
        remaining_blocks: u64,
        scanned_height: u64,
        tip_height: u64,
    ) -> f64 {
        match self {
            ProgressDisplayMode::Work => {
                if initial_total == 0 {
                    1.0
                } else {
                    (1.0 - (remaining_blocks as f64 / initial_total as f64)).clamp(0.0, 1.0)
                }
            }
            ProgressDisplayMode::ChainWindow {
                window_start_height,
            } => chain_window_percentage(window_start_height, tip_height, scanned_height),
            ProgressDisplayMode::TailRepair {
                base_percentage,
                total_blocks,
            } => tail_repair_percentage(base_percentage, total_blocks, remaining_blocks),
        }
    }

    fn target_percentage_after_blocks(
        self,
        initial_total: u64,
        remaining_blocks: u64,
        scanned_height: u64,
        tip_height: u64,
        blocks: u64,
    ) -> f64 {
        match self {
            ProgressDisplayMode::Work => {
                target_percentage_after_blocks(initial_total, remaining_blocks, blocks)
            }
            ProgressDisplayMode::ChainWindow {
                window_start_height,
            } => chain_window_percentage(
                window_start_height,
                tip_height,
                scanned_height.saturating_add(blocks),
            ),
            ProgressDisplayMode::TailRepair {
                base_percentage,
                total_blocks,
            } => {
                let target_remaining = remaining_blocks.saturating_sub(blocks);
                tail_repair_percentage(base_percentage, total_blocks, target_remaining)
            }
        }
    }

    fn extend_work(&mut self, new_total: u64) {
        if let ProgressDisplayMode::TailRepair { total_blocks, .. } = self {
            *total_blocks = (*total_blocks).max(new_total);
        }
    }

    fn batch_start_height(self, ranges: &[ScanRange], batch_start: BlockHeight) -> u64 {
        match self {
            ProgressDisplayMode::ChainWindow { .. } => {
                chain_window_frontier_height(ranges, u32::from(batch_start) as u64)
            }
            ProgressDisplayMode::Work | ProgressDisplayMode::TailRepair { .. } => {
                u32::from(batch_start) as u64
            }
        }
    }

    fn batch_end_height(
        self,
        post_ranges: &[ScanRange],
        batch_end: BlockHeight,
        tip_height: u64,
    ) -> u64 {
        match self {
            ProgressDisplayMode::ChainWindow { .. } => {
                chain_window_frontier_height(post_ranges, tip_height)
            }
            ProgressDisplayMode::Work | ProgressDisplayMode::TailRepair { .. } => {
                u32::from(batch_end) as u64
            }
        }
    }

    fn batch_target_percentage(
        self,
        initial_total: u64,
        remaining_blocks: u64,
        ranges: &[ScanRange],
        batch_start: BlockHeight,
        batch_end: BlockHeight,
        tip_height: u64,
    ) -> f64 {
        match self {
            ProgressDisplayMode::ChainWindow {
                window_start_height,
            } => chain_window_percentage(
                window_start_height,
                tip_height,
                chain_window_target_height_after_batch(
                    ranges,
                    batch_start,
                    batch_end,
                    u32::from(batch_start) as u64,
                ),
            ),
            ProgressDisplayMode::Work | ProgressDisplayMode::TailRepair { .. } => self
                .target_percentage_after_blocks(
                    initial_total,
                    remaining_blocks,
                    u32::from(batch_start) as u64,
                    tip_height,
                    u32::from(batch_end).saturating_sub(u32::from(batch_start)) as u64,
                ),
        }
    }
}

fn is_pending_scan_range(range: &ScanRange) -> bool {
    range.priority() != ScanPriority::Ignored && range.priority() != ScanPriority::Scanned
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

fn pending_scan_blocks(ranges: &[ScanRange]) -> u64 {
    ranges
        .iter()
        .filter(|r| is_pending_scan_range(r))
        .map(|r| {
            u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64
        })
        .sum()
}

fn first_pending_scan_range(ranges: &[ScanRange]) -> Option<String> {
    ranges
        .iter()
        .find(|r| is_pending_scan_range(r))
        .map(|r| r.to_string())
}

fn earliest_pending_scan_start(ranges: &[ScanRange]) -> Option<u64> {
    ranges
        .iter()
        .filter(|r| is_pending_scan_range(r))
        .map(|r| u32::from(r.block_range().start) as u64)
        .min()
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

fn mark_sync_started(db_data_path: &str) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin sync-start metadata transaction: {e}"))?;
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
    tx.commit()
        .map_err(|e| format!("commit sync-start metadata: {e}"))
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
        let attempt_result = with_wallet_db_write_lock(
            "sync_engine.truncate_to_chain_state.anchor_root_mismatch",
            || -> Result<Result<Vec<ScanRange>, String>, SyncError> {
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
}

async fn refresh_utxos(
    client: &mut CompactTxStreamerClient<Channel>,
    db_data_path: &str,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    tip_height: BlockHeight,
    account_selection: TransparentAccountSelection<'_>,
    priority_account_target: Option<&ActiveSyncAccountTarget>,
    received_outputs_seen: &mut bool,
    progress: Option<&(dyn Fn(u64, u64) + Sync)>,
    should_exit: &impl Fn() -> bool,
) -> Result<TransparentRefreshSummary, SyncError> {
    let mut refreshes = Vec::new();
    let mut summary = TransparentRefreshSummary::default();
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
            TRANSPARENT_UTXO_RECENT_EXTERNAL_LIMIT,
            TRANSPARENT_UTXO_SWEEP_EXTERNAL_LIMIT,
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
                    start_height: u64::from(u32::from(safety_start_height)),
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
                    child_indices: batch.child_indices,
                    next_sweep_offset: batch.next_sweep_offset,
                }),
            });
        }

        let external_selected = external_addresses
            .iter()
            .map(|address| address.address.as_str())
            .collect::<BTreeSet<_>>();
        let non_external_addresses: Vec<String> = db
            .get_transparent_receivers(account_id, true, true)
            .map_err(|e| SyncError::db(format!("get_transparent_receivers: {e}")))?
            .into_iter()
            .filter(|(_, metadata)| metadata.scope() != Some(TransparentKeyScope::EXTERNAL))
            .map(|(addr, _)| addr.encode(&query_network))
            .filter(|addr| !external_selected.contains(addr.as_str()))
            .collect();

        if !non_external_addresses.is_empty() {
            refreshes.push(TransparentRefresh {
                addresses: non_external_addresses,
                start_height: safety_start_height,
                label: "transparent non-external UTXOs".to_string(),
                account_uuid,
                completion: None,
            });
        }
    }

    let total_refreshes = refreshes.len() as u64;
    if let Some(progress) = progress {
        progress(0, total_refreshes);
    }
    let mut completed_refreshes = 0u64;
    let download_client = client.clone();
    let outcome = process_bounded_transparent_refreshes(
        refreshes,
        move |refresh| download_transparent_outputs(download_client.clone(), refresh, should_exit),
        |downloaded| {
            let downloaded_count = downloaded.len() as u64;
            let received_outputs = downloaded.iter().any(|batch| !batch.outputs.is_empty());
            store_then_mark_transparent_refreshes(
                downloaded,
                |downloaded| store_transparent_outputs(db, downloaded),
                |downloaded| {
                    update_transparent_refresh_cache_metadata(
                        db_data_path,
                        network,
                        tip_height,
                        downloaded,
                    )
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
    if outcome == TransparentRefreshOutcome::Cancelled {
        log::info!(
            "[{}] sync: exiting before transparent UTXO database update",
            elapsed(),
        );
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
                }
            }
            Ok(())
        })
        .map_err(|e| SyncError::db(format!("put_received_transparent_utxos: {e}")))
    })
}

async fn download_transparent_outputs(
    mut client: CompactTxStreamerClient<Channel>,
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

    log::info!(
        "[{}] sync: refreshing {} for account {} from height {} ({} addresses)",
        elapsed(),
        refresh.label,
        refresh.account_uuid,
        u32::from(refresh.start_height),
        refresh.addresses.len(),
    );

    let addresses = std::mem::take(&mut refresh.addresses);
    let mut stream = tokio::select! {
        biased;
        _ = watch_for_exit(should_exit) => {
            log::info!(
                "[{}] sync: exiting during {} transparent UTXO stream start",
                elapsed(),
                refresh.label,
            );
            return Ok(None);
        }
        result = get_address_utxos_stream(
            &mut client,
            addresses,
            refresh.start_height,
        ) => result?,
    };

    let mut outputs = Vec::new();
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

    Ok(Some(DownloadedTransparentRefresh { refresh, outputs }))
}

async fn watch_for_exit(should_exit: &impl Fn() -> bool) {
    while !should_exit() {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
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
enum RefreshedTipRelation {
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

fn truncate_wallet_to_height(
    db: &mut WalletDatabase,
    requested_height: BlockHeight,
    fresh_tip_height: BlockHeight,
    operation: &'static str,
) -> Result<BlockHeight, SyncError> {
    with_wallet_db_write_lock(operation, || {
        truncate_wallet_with(requested_height, fresh_tip_height, |height| {
            db.truncate_to_height(height)
        })
    })
}

fn truncate_wallet_with(
    requested_height: BlockHeight,
    fresh_tip_height: BlockHeight,
    mut truncate: impl FnMut(BlockHeight) -> Result<BlockHeight, SqliteClientError>,
) -> Result<BlockHeight, SyncError> {
    match truncate(requested_height) {
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
    }
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
    db: &mut WalletDatabase,
    fresh_tip_height: u64,
) -> Result<(BlockHeight, Vec<ScanRange>, u64), SyncError> {
    let fresh_height = block_height_from_u64(fresh_tip_height, "reorg lightwalletd chain tip")?;
    let requested_height = confirmed_reorg_rewind_target(fresh_height)?;
    let actual_height = truncate_wallet_to_height(
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
/// parallel. The requests are independent, and cloned tonic clients share the
/// underlying HTTP/2 connection.
async fn download_scan_batch(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
    network: WalletNetwork,
) -> Result<ScanBatch, SyncError> {
    let mut tree_state_client = client.clone();
    let use_empty_state = should_use_empty_chain_state(&network, start)?;
    let tree_state = async move {
        if use_empty_state {
            Ok(chain::ChainState::empty(start - 1, BlockHash([0u8; 32])))
        } else {
            let state =
                get_tree_state(&mut tree_state_client, u64::from(u32::from(start - 1))).await?;
            state
                .to_chain_state()
                .map_err(|e| SyncError::parse(format!("parse tree state: {e}")))
        }
    };

    join_scan_batch_inputs(download_blocks(client, start, end, network), tree_state).await
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

    Ok(())
}

struct Prefetch<T> {
    handle: Option<tokio::task::JoinHandle<Result<T, SyncError>>>,
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
            start,
            end,
        }
    }
}

impl<T> Drop for Prefetch<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            handle.abort();
        }
    }
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
            let result = tokio::select! {
                biased;
                _ = watch_for_exit(should_exit) => return Ok(None),
                result = prefetch.handle.as_mut().expect("prefetch handle present") => result,
            };
            if should_exit() {
                return Ok(None);
            }
            let _completed_handle = prefetch.handle.take().expect("prefetch handle present");
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
    *SYNC_START.lock().unwrap() = Some(std::time::Instant::now());

    for attempt in 0..=MAX_RETRIES {
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
                if cancel.load(Ordering::Relaxed)
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

        match run_sync_impl(
            db_data_path,
            lightwalletd_url,
            network,
            cancel.clone(),
            running_mode,
            desired_mode,
            active_account_target.as_ref(),
            allow_resubmit,
            &progress_fn,
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
) -> Result<(), SyncError> {
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
    with_wallet_db_write_lock("sync_engine.mark_sync_started", || {
        mark_sync_started(db_data_path)
    })
    .map_err(SyncError::db)?;

    // 1. Connect gRPC (plain TLS via tonic + webpki roots).
    let mut client = open_lwd_channel(lightwalletd_url).await?;

    // Open DB once — reused for the entire sync
    let mut db =
        with_wallet_db_write_lock("sync_engine.open_db", || open_db(db_data_path, network))?;
    // The main-phase rewind budget also covers a reorg detected by the
    // initial tip response, before the scan queue has been created.
    let mut main_rewinds_this_run: u32 = 0;
    let should_exit =
        || cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode;

    // 2. Get the chain tip. Reconcile it with the DB before treating it as
    // authoritative: `WalletDb::update_chain_tip` deliberately ignores a
    // height below the maximum scanned block, so assigning the server height
    // first could later report completion above a lagging endpoint.
    let tip_result = get_latest_block(&mut client).await;
    let Some(tip_result) = tip_rpc_result_unless_exiting(tip_result, should_exit()) else {
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
        let relation = classify_refreshed_tip_with_fallback(
            &mut client,
            db_tip,
            stored_hash,
            tip.height,
            &tip.hash,
        )
        .await;
        let Some(relation) = tip_rpc_result_unless_exiting(relation, should_exit()) else {
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
                rewind_for_confirmed_tip_reorg(&mut db, tip.height)?;
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

    // Retained send-lock expiry requires a usable target height.
    crate::wallet::sync::recover_orphaned_send_locks(db_data_path, network)
        .map_err(SyncError::db)?;

    if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
        log::info!(
            "[{}] sync: cancel/mode observed before transparent UTXO refresh, skipping",
            elapsed(),
        );
        return Ok(());
    }

    let active_utxo_progress = |completed, total| {
        progress_fn(preparation_progress_event(
            current_tip_height,
            "active_utxo",
            completed,
            total,
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
            tip_height,
            TransparentAccountSelection::Only(active_account_uuid),
            None,
            &mut critical_received_outputs,
            Some(&active_utxo_progress),
            &should_exit,
        )
        .await?;
        if active_summary.matched_accounts == 0 {
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
    download_subtree_roots(&mut client, &mut db, db_data_path, network, tip_height).await?;

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
    // after the tip update, before `initial_total` is measured — demotes both
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
    let initial_window_start_height =
        earliest_pending_scan_start(&initial_ranges).unwrap_or(current_tip_height);
    let mut queued_ranges = Some(initial_ranges);
    let mut prev_remaining = initial_total;
    let mut progress_display_mode = ProgressDisplayMode::Work;
    let mut last_progress_percentage: f64 = 0.0;
    log::info!("[{}] sync: {} blocks to scan", elapsed(), initial_total);

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

    // Prefetched scan batch from the previous iteration.
    // When the scan loop processes a range that spans multiple batches,
    // we start the next block-and-frontier tuple before scanning the current
    // batch. This overlaps network I/O with CPU work on multithread runtimes
    // and with later async stages on the iOS current-thread runtime, matching
    // the SDK's `.buffer(1)` pipelining pattern in
    // `CompactBlockProcessor.kt:1666`.
    //
    // `None` on the first iteration and whenever the previous batch
    // was the last in its range (so there's nothing to prefetch until
    // `suggest_scan_ranges` runs again).
    let mut prefetch: Option<Prefetch<ScanBatch>> = None;

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
        if last_periodic_tip_refresh_attempt.elapsed() >= TIP_REFRESH_INTERVAL {
            last_periodic_tip_refresh_attempt = std::time::Instant::now();
            let fresh_tip_result = get_latest_block(&mut client).await;
            let Some(fresh_tip_result) =
                tip_rpc_result_unless_exiting(fresh_tip_result, should_exit())
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
                    let relation = classify_refreshed_tip_with_fallback(
                        &mut client,
                        current_tip_height,
                        stored_hash,
                        fresh_tip.height,
                        &fresh_tip.hash,
                    )
                    .await;
                    let Some(relation) = tip_rpc_result_unless_exiting(relation, should_exit())
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
                            prefetch = None;
                            let (actual_height, repair_ranges, pending_blocks) =
                                rewind_for_confirmed_tip_reorg(&mut db, fresh_tip.height)?;
                            log::warn!(
                                "[{}] sync: periodic tip proved a reorg; rewound to {} \
                                 and queued {} block(s) toward tip {}",
                                elapsed(),
                                actual_height,
                                pending_blocks,
                                fresh_tip.height,
                            );
                            current_tip_height = fresh_tip.height;
                            initial_total = pending_blocks;
                            prev_remaining = pending_blocks;
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

        let range = match ranges.iter().find(|r| is_pending_scan_range(r)) {
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
                    let fresh_tip_result = get_latest_block(&mut client).await;
                    let Some(fresh_tip_result) =
                        tip_rpc_result_unless_exiting(fresh_tip_result, should_exit())
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
                    let relation = classify_refreshed_tip_with_fallback(
                        &mut client,
                        current_tip_height,
                        stored_hash,
                        fresh_tip.height,
                        &fresh_tip.hash,
                    )
                    .await;
                    let Some(relation) = tip_rpc_result_unless_exiting(relation, should_exit())
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
                            prefetch = None;
                            let (actual_height, repair_ranges, repair_pending_blocks) =
                                rewind_for_confirmed_tip_reorg(&mut db, fresh_tip.height)?;
                            log::warn!(
                                "[{}] sync: final tip proved a reorg; rewound to {} \
                                 and queued {} block(s) toward tip {}",
                                elapsed(),
                                actual_height,
                                repair_pending_blocks,
                                fresh_tip.height,
                            );
                            current_tip_height = fresh_tip.height;
                            initial_total = repair_pending_blocks;
                            prev_remaining = repair_pending_blocks;
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
                    progress_display_mode = ProgressDisplayMode::TailRepair {
                        base_percentage: last_progress_percentage
                            .min(TAIL_REPAIR_MAX_START_PERCENTAGE),
                        total_blocks: repair_pending_blocks,
                    };
                    prefetch = None;
                    continue;
                } else if let Some(repair_pending_blocks) = repair_anchor_root_mismatch_if_needed(
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
                    let repair_ranges = db.suggest_scan_ranges().map_err(|e| {
                        SyncError::db(format!("suggest_scan_ranges after anchor repair: {e}"))
                    })?;
                    let first_pending = earliest_pending_scan_start(&repair_ranges)
                        .unwrap_or(initial_window_start_height);
                    progress_display_mode = ProgressDisplayMode::ChainWindow {
                        window_start_height: initial_window_start_height.min(first_pending),
                    };
                    prefetch = None;
                    continue;
                } else {
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
        // Adaptive batch size: shrink to BATCH_SIZE_SANDBLASTING
        // while the next batch is inside the known Zcash mainnet
        // sandblasting attack window. These blocks contain an
        // order of magnitude more outputs than normal blocks,
        // making scan_cached_blocks much slower per block and
        // using more memory. Matches the SDK's
        // `SANDBLASTING_RANGE` check.
        let Some((batch_size, end)) =
            scannable_batch_end(base_batch_size, start, range_end, current_tip_height)
        else {
            log::info!(
                "[{}] sync: pending range {} starts after current tip {}, waiting for tip advance",
                elapsed(),
                describe_block_range(range.block_range()),
                current_tip_height,
            );
            break;
        };
        let batch_blocks = u32::from(end).saturating_sub(u32::from(start)) as u64;
        let display_scanned_height = progress_display_mode.batch_start_height(&ranges, start);
        let current_pct = progress_display_mode.percentage(
            initial_total,
            prev_remaining,
            display_scanned_height,
            current_tip_height,
        );
        let display_target_percentage = progress_display_mode.batch_target_percentage(
            initial_total,
            prev_remaining,
            &ranges,
            start,
            end,
            current_tip_height,
        );
        last_progress_percentage = current_pct.clamp(0.0, 1.0);
        progress_fn(SyncProgressEvent {
            scanned_height: u32::from(start) as u64,
            chain_tip_height: current_tip_height,
            percentage: last_progress_percentage,
            display_target_percentage,
            display_target_blocks: batch_blocks,
            is_syncing: true,
            is_complete: false,
            has_new_tx: false,
            phase_completed_units: 0,
            phase_total_units: 0,
            phase: "download".into(),
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

        // Download blocks and their preceding frontier together, or consume a
        // matching tuple that the previous iteration prefetched.
        let batch =
            resolve_prefetched_or_download(prefetch.take(), start, end, &should_exit, || {
                download_scan_batch(&mut client, start, end - 1, network)
            })
            .await?;
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

        let incoming_orchard_checkpoint_heights =
            migration_anchor_retention_required.then(|| block_source.orchard_checkpoint_heights());

        // Start the next tuple before scanning this batch. Dropping `prefetch`
        // on any early return, error, or reorg aborts its network task.
        if end < range_end && !should_exit() {
            let prefetch_start = end;
            if let Some((_, prefetch_end)) = scannable_batch_end(
                base_batch_size,
                prefetch_start,
                range_end,
                current_tip_height,
            ) {
                let mut prefetch_client = client.clone();
                prefetch = Some(Prefetch::spawn(prefetch_start, prefetch_end, async move {
                    download_scan_batch(
                        &mut prefetch_client,
                        prefetch_start,
                        prefetch_end - 1,
                        network,
                    )
                    .await
                }));
            } else {
                log::debug!(
                    "[{}] sync: skipping prefetch from {} past current tip {}",
                    elapsed(),
                    u32::from(prefetch_start),
                    current_tip_height,
                );
            }
        }

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
        let scan_result = with_wallet_db_write_lock("sync_engine.retain_and_scan_blocks", || {
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
            scan_cached_blocks(
                &network,
                &block_source,
                &mut db,
                start,
                &from_state,
                batch_blocks as usize,
            )
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
        });

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
                    let actual_rewind_height = with_wallet_db_write_lock(
                        "sync_engine.truncate_to_height",
                        || -> Result<BlockHeight, SyncError> {
                            match db.truncate_to_height(target) {
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
                                    db.truncate_to_height(safe).map_err(|e| {
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
                        initial_total = post_rewind_pending;
                        prev_remaining = post_rewind_pending;
                        let rewind_start = earliest_pending_scan_start(&post_rewind_ranges)
                            .unwrap_or(actual_rewind_height_u64);
                        progress_display_mode = ProgressDisplayMode::ChainWindow {
                            window_start_height: initial_window_start_height.min(rewind_start),
                        };
                    }
                    prefetch = None;
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

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after scan", elapsed());
            return Ok(());
        }

        // Truncation can temporarily clear a transaction's mined height while
        // retaining note positions that prove compact scanning found it mined.
        // Exclude those transactions from recovery resubmission while scanning
        // can still restore their mined heights.
        let post_scan_ranges = db
            .suggest_scan_ranges()
            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
        let resubmit_exclusions = recovery_resubmit_exclusions(db_data_path, &post_scan_ranges)?;

        // Enhancement
        run_enhancement(&mut client, &mut db, db_data_path, network).await?;

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
        // `run_enhancement` (which can spend a second or two on a
        // transparent-address scan), bail before opening a single
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
        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!(
                "[{}] sync: cancel/mode observed before post-batch resubmit, exiting",
                elapsed(),
            );
            return Ok(());
        }
        let fresh_tip_result = get_latest_block(&mut client).await;
        let Some(fresh_tip_result) = tip_rpc_result_unless_exiting(fresh_tip_result, should_exit())
        else {
            log::info!("[{}] sync: exiting after post-batch tip fetch", elapsed());
            return Ok(());
        };
        match fresh_tip_result {
            Ok(fresh_tip) => {
                let fresh_tip_height =
                    block_height_from_u64(fresh_tip.height, "post-batch lightwalletd chain tip")?;

                let stored_hash =
                    stored_hash_for_refreshed_tip(&db, current_tip_height, fresh_tip.height)?;
                let relation = classify_refreshed_tip_with_fallback(
                    &mut client,
                    current_tip_height,
                    stored_hash,
                    fresh_tip.height,
                    &fresh_tip.hash,
                )
                .await;
                let Some(relation) = tip_rpc_result_unless_exiting(relation, should_exit()) else {
                    log::info!(
                        "[{}] sync: exiting after post-batch tip validation",
                        elapsed()
                    );
                    return Ok(());
                };
                let relation = relation?;
                match relation {
                    RefreshedTipRelation::Unchanged => {
                        last_completion_tip_validation = std::time::Instant::now();
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
                        prefetch = None;
                        let (actual_height, repair_ranges, pending_blocks) =
                            rewind_for_confirmed_tip_reorg(&mut db, fresh_tip.height)?;
                        log::warn!(
                            "[{}] sync: post-batch tip proved a reorg; rewound to {} \
                                 and queued {} block(s) toward tip {}",
                            elapsed(),
                            actual_height,
                            pending_blocks,
                            fresh_tip.height,
                        );
                        current_tip_height = fresh_tip.height;
                        initial_total = pending_blocks;
                        prev_remaining = pending_blocks;
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
        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
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
        let remaining: u64 = post_ranges
            .iter()
            .filter(|r| is_pending_scan_range(r))
            .map(|r| {
                u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start))
                    as u64
            })
            .sum();
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
            progress_display_mode.extend_work(new_total);
        }
        prev_remaining = remaining;
        let display_scanned_height =
            progress_display_mode.batch_end_height(&post_ranges, end, current_tip_height);
        let pct = progress_display_mode.percentage(
            initial_total,
            remaining,
            display_scanned_height,
            current_tip_height,
        );
        let next_display_range = post_ranges
            .iter()
            .find(|r| is_pending_scan_range(r))
            .and_then(|r| {
                let next_start = r.block_range().start;
                planned_batch_end(base_batch_size, next_start, r.block_range().end)
                    .map(|(_, next_end)| (next_start, next_end))
            });
        let next_display_target_blocks = next_display_range
            .map(|(next_start, next_end)| {
                u32::from(next_end).saturating_sub(u32::from(next_start)) as u64
            })
            .unwrap_or(0);
        let display_target_percentage = if let Some((next_start, next_end)) = next_display_range {
            progress_display_mode.batch_target_percentage(
                initial_total,
                remaining,
                &post_ranges,
                next_start,
                next_end,
                current_tip_height,
            )
        } else {
            progress_display_mode.percentage(
                initial_total,
                remaining,
                current_tip_height,
                current_tip_height,
            )
        };
        let progress = SyncProgressEvent {
            scanned_height: u32::from(end) as u64,
            chain_tip_height: current_tip_height,
            percentage: pct.clamp(0.0, 1.0),
            display_target_percentage,
            display_target_blocks: next_display_target_blocks,
            is_syncing: true,
            is_complete: false,
            has_new_tx,
            phase_completed_units: 0,
            phase_total_units: 0,
            phase: "scan".into(),
        };
        last_progress_percentage = progress.percentage;
        log::info!(
            "[{}] sync: {:.1}% (remaining={}/{}, scanned={})",
            elapsed(),
            progress.percentage * 100.0,
            remaining,
            initial_total,
            initial_total - remaining
        );
        progress_fn(progress);
        #[cfg(debug_assertions)]
        maybe_sleep_for_e2e_sync_batch_delay().await;
    }

    let (final_scanned_height, final_tip_height) =
        ensure_complete_scan_state(&mut db, current_tip_height)?;
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
    match transparent_receive_cache::refresh_all_from_wallet_db(
        db_data_path,
        network,
        Some(final_scanned_height),
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
    with_wallet_db_write_lock("sync_engine.mark_sync_completed", || {
        mark_sync_completed(db_data_path, final_tip_height)
    })
    .map_err(SyncError::db)?;
    // Final progress
    let final_progress = SyncProgressEvent {
        scanned_height: final_scanned_height,
        chain_tip_height: final_tip_height,
        percentage: 1.0,
        display_target_percentage: 1.0,
        display_target_blocks: 0,
        is_syncing: false,
        is_complete: true,
        has_new_tx: false,
        phase_completed_units: 0,
        phase_total_units: 0,
        phase: String::new(),
    };
    progress_fn(final_progress);

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
            if let Err(error) = run_enhancement(&mut client, &mut db, db_data_path, network).await {
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
                is_syncing: false,
                is_complete: true,
                has_new_tx: true,
                phase_completed_units: 0,
                phase_total_units: 0,
                phase: String::new(),
            });
        }
    }

    Ok(())
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

    fn assert_pct(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() < 0.000_001,
            "expected {expected}, got {actual}"
        );
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
    fn work_progress_matches_remaining_block_ratio() {
        let mode = ProgressDisplayMode::Work;

        assert_pct(mode.percentage(1_000, 300, 0, 0), 0.7);
        assert_pct(
            mode.target_percentage_after_blocks(1_000, 300, 0, 0, 100),
            0.8,
        );
    }

    #[test]
    fn chain_window_progress_uses_session_window_not_absolute_height() {
        let mode = ProgressDisplayMode::ChainWindow {
            window_start_height: 1_000,
        };

        assert_pct(mode.percentage(0, 0, 1_700, 2_000), 0.7);
        assert_pct(
            mode.target_percentage_after_blocks(0, 0, 1_700, 2_000, 100),
            0.8,
        );
    }

    #[test]
    fn chain_window_progress_waits_for_earliest_pending_range() {
        let mode = ProgressDisplayMode::ChainWindow {
            window_start_height: 1_000,
        };
        let high_range_start = BlockHeight::from_u32(1_900);
        let high_range_end = BlockHeight::from_u32(2_000);
        let ranges = vec![
            ScanRange::from_parts(high_range_start..high_range_end, ScanPriority::Verify),
            ScanRange::from_parts(
                BlockHeight::from_u32(1_700)..BlockHeight::from_u32(1_800),
                ScanPriority::Verify,
            ),
        ];

        let display_height = mode.batch_start_height(&ranges, high_range_start);
        assert_eq!(display_height, 1_700);
        assert_pct(mode.percentage(0, 0, display_height, 2_000), 0.7);
        assert_pct(
            mode.batch_target_percentage(0, 0, &ranges, high_range_start, high_range_end, 2_000),
            0.7,
        );

        let post_ranges = vec![ScanRange::from_parts(
            BlockHeight::from_u32(1_700)..BlockHeight::from_u32(1_800),
            ScanPriority::Verify,
        )];
        let display_height_after = mode.batch_end_height(&post_ranges, high_range_end, 2_000);
        assert_eq!(display_height_after, 1_700);
        assert_pct(mode.percentage(0, 0, display_height_after, 2_000), 0.7);
    }

    #[test]
    fn tail_repair_progress_starts_near_completion_and_advances_by_repair_work() {
        let mode = ProgressDisplayMode::TailRepair {
            base_percentage: 0.99,
            total_blocks: 100,
        };

        assert_pct(mode.percentage(100, 100, 50, 1_000), 0.95);
        assert_pct(
            mode.target_percentage_after_blocks(100, 100, 50, 1_000, 50),
            0.975,
        );
        assert_pct(mode.percentage(100, 0, 50, 1_000), 1.0);
    }

    #[test]
    fn tail_repair_progress_does_not_jump_forward_when_sync_was_not_near_done() {
        let mode = ProgressDisplayMode::TailRepair {
            base_percentage: 0.8,
            total_blocks: 100,
        };

        assert_pct(mode.percentage(100, 100, 50, 1_000), 0.8);
        assert_pct(
            mode.target_percentage_after_blocks(100, 100, 50, 1_000, 50),
            0.9,
        );
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

    #[test]
    fn scannable_batch_end_clamps_to_current_tip() {
        assert_eq!(
            scannable_batch_end(
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
                2_000,
                BlockHeight::from_u32(122),
                BlockHeight::from_u32(131),
                121,
            ),
            None,
        );
    }

    #[test]
    fn planned_batch_end_uses_base_size_before_sandblasting() {
        assert_eq!(
            planned_batch_end(
                1_000,
                BlockHeight::from_u32(419_200),
                BlockHeight::from_u32(3_500_000),
            ),
            Some((1_000, BlockHeight::from_u32(420_200))),
        );
    }

    #[test]
    fn planned_batch_end_stops_at_sandblasting_boundaries() {
        assert_eq!(
            planned_batch_end(
                1_000,
                BlockHeight::from_u32(SANDBLASTING_START - 500),
                BlockHeight::from_u32(3_500_000),
            ),
            Some((1_000, BlockHeight::from_u32(SANDBLASTING_START))),
        );
        assert_eq!(
            planned_batch_end(
                1_000,
                BlockHeight::from_u32(SANDBLASTING_START),
                BlockHeight::from_u32(3_500_000),
            ),
            Some((
                BATCH_SIZE_SANDBLASTING,
                BlockHeight::from_u32(SANDBLASTING_START + BATCH_SIZE_SANDBLASTING),
            )),
        );
        assert_eq!(
            planned_batch_end(
                1_000,
                BlockHeight::from_u32(SANDBLASTING_END - 50),
                BlockHeight::from_u32(3_500_000),
            ),
            Some((
                BATCH_SIZE_SANDBLASTING,
                BlockHeight::from_u32(SANDBLASTING_END),
            )),
        );
        assert_eq!(
            planned_batch_end(
                1_000,
                BlockHeight::from_u32(SANDBLASTING_END),
                BlockHeight::from_u32(3_500_000),
            ),
            Some((1_000, BlockHeight::from_u32(SANDBLASTING_END + 1_000))),
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
        let actual = truncate_wallet_with(requested, BlockHeight::from_u32(100), |height| {
            rewind_calls.push(height);
            Ok(height)
        })
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

        let result = truncate_wallet_with(requested, fresh_tip, |height| {
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

        let result = truncate_wallet_with(requested, fresh_tip, |height| {
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
