use std::collections::{BTreeSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use nonempty::NonEmpty;
use rusqlite::{params, OptionalExtension};
use shardtree::error::{InsertionError, ShardTreeError};
use tonic::transport::Channel;
use zcash_client_backend::{
    data_api::{
        chain::{self, error::Error as ChainError, scan_cached_blocks},
        scanning::{ScanPriority, ScanRange},
        wallet::ConfirmationsPolicy,
        TransactionDataRequest, WalletCommitmentTrees, WalletRead, WalletWrite,
    },
    proto::service,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_sync_wallet_db_with_timeout,
        open_wallet_raw_conn_with_timeout, spawn_wallet_wal_checkpoint, with_wallet_db_write_lock,
        WalletDatabase, SYNC_DB_BUSY_TIMEOUT,
    },
    keys,
    network::WalletNetwork,
    transparent_receive_cache,
};

use {
    ::transparent::{
        address::Script,
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
use lwd::{download_blocks, download_subtree_roots, get_tree_state};
pub(crate) use lwd::{
    get_latest_block, get_taddress_txids, next_stream_message, open_lwd_channel, send_transaction,
    send_transaction_with_status,
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
    /// Current sync phase for UI display. One of:
    /// - `"download"` — downloading compact blocks from lightwalletd
    /// - `"scan"` — running `scan_cached_blocks` (CPU-intensive)
    /// - `"enhance"` — fetching full transaction data
    /// - `""` — completion event or unspecified
    pub phase: String,
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const BATCH_SIZE_FOREGROUND: u32 = 2000;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const BATCH_SIZE_FOREGROUND: u32 = 1000;
const BATCH_SIZE_BACKGROUND: u32 = 300;

// Desktop uses one look-ahead batch. Mobile sync can run on a current-thread
// Tokio runtime (notably the iOS background FFI), where a spawned network task
// cannot make progress while scan_cached_blocks is executing synchronously;
// defaulting prefetch off avoids extra RPC and memory pressure there.
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const PREFETCH_DEPTH_FOREGROUND: usize = 1;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const PREFETCH_DEPTH_FOREGROUND: usize = 0;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const PREFETCH_DEPTH_BACKGROUND: usize = 1;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const PREFETCH_DEPTH_BACKGROUND: usize = 0;

/// The resident-memory estimate applies a conservative multiplier to the
/// encoded compact-block size to account for decoded vectors and allocations.
const PREFETCH_DECODED_MEMORY_FACTOR: u64 = 3;
const PREFETCH_WIRE_FLOOR_BYTES_PER_BLOCK: u64 = 5 * 1024;
const PREFETCH_SANDBLASTING_WIRE_BYTES_PER_BLOCK: u64 = 90 * 1024;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const PREFETCH_RESIDENT_BUDGET: u64 = 128 * 1024 * 1024;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const PREFETCH_RESIDENT_BUDGET: u64 = 32 * 1024 * 1024;
const TIP_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);
const STATUS_POLL_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);
const RESUBMIT_INTERVAL: std::time::Duration = std::time::Duration::from_secs(120);
const TRANSPARENT_UTXO_RECENT_EXTERNAL_LIMIT: usize = 20;
const TRANSPARENT_UTXO_SWEEP_EXTERNAL_LIMIT: usize = 20;

/// Sandblasting attack range (Zcash mainnet). Blocks in this range
/// contain a very large number of outputs from a sustained spam
/// attack, making `scan_cached_blocks` significantly more expensive
/// per block. We reduce the batch size to `BATCH_SIZE_SANDBLASTING`
/// when any part of the scan range falls inside this window to
/// avoid excessive memory pressure and potential timeouts.
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
// `truncate_to_chain_state` only injects a canonical frontier when the requested
// height is below the retained checkpoint window. Start at the pruning depth
// and escalate so corrupted anchor checkpoints do not survive the repair.
const ANCHOR_ROOT_REPAIR_REWIND_DISTANCES: [u32; 3] = [100, 1000, 10_000];

/// Sync-scoped elapsed time reference. Set at sync start.
static SYNC_START: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

fn elapsed() -> String {
    SYNC_START
        .lock()
        .ok()
        .and_then(|g| g.map(|t| format!("{:.1}s", t.elapsed().as_secs_f64())))
        .unwrap_or_default()
}

fn batch_size_for_range(base_batch_size: u32, start: BlockHeight, range_end: BlockHeight) -> u32 {
    let start_u32 = u32::from(start);
    let range_end_u32 = u32::from(range_end);
    // Overlap check: range [start, range_end) ∩ [SANDBLASTING_START, SANDBLASTING_END)
    if start_u32 < SANDBLASTING_END && range_end_u32 > SANDBLASTING_START {
        BATCH_SIZE_SANDBLASTING
    } else {
        base_batch_size
    }
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

pub(super) fn env_override_clamped(name: &str, default: u64, min: u64, max: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(default)
}

fn effective_prefetch_depth(running_mode: u8) -> usize {
    let default = if running_mode == 2 {
        PREFETCH_DEPTH_BACKGROUND
    } else {
        PREFETCH_DEPTH_FOREGROUND
    };
    env_override_clamped("ZCASH_SYNC_PREFETCH_DEPTH", default as u64, 0, 1) as usize
}

fn effective_resubmit_interval() -> std::time::Duration {
    std::time::Duration::from_secs(env_override_clamped(
        "ZCASH_SYNC_RESUBMIT_INTERVAL_SECS",
        RESUBMIT_INTERVAL.as_secs(),
        10,
        3_600,
    ))
}

fn can_spawn_prefetch(
    queued_batches: usize,
    depth: usize,
    current_wire_bytes: u64,
    queued_blocks: u64,
    next_batch_blocks: u64,
    estimated_wire_bytes_per_block: u64,
    resident_budget: u64,
) -> bool {
    if queued_batches >= depth {
        return false;
    }
    current_wire_bytes
        .saturating_add(
            queued_blocks
                .saturating_add(next_batch_blocks)
                .saturating_mul(estimated_wire_bytes_per_block),
        )
        .saturating_mul(PREFETCH_DECODED_MEMORY_FACTOR)
        <= resident_budget
}

fn prefetch_wire_floor(start: BlockHeight) -> u64 {
    let height = u32::from(start);
    if (SANDBLASTING_START..SANDBLASTING_END).contains(&height) {
        PREFETCH_SANDBLASTING_WIRE_BYTES_PER_BLOCK
    } else {
        PREFETCH_WIRE_FLOOR_BYTES_PER_BLOCK
    }
}

fn memory_bounded_batch_size(
    base_batch_size: u32,
    start: BlockHeight,
    range_end: BlockHeight,
    estimated_wire_bytes_per_block: u64,
    resident_budget: u64,
) -> u32 {
    let protocol_cap = batch_size_for_range(base_batch_size, start, range_end);
    let bytes_per_block = estimated_wire_bytes_per_block.max(prefetch_wire_floor(start));
    let estimated_resident_per_block =
        bytes_per_block.saturating_mul(PREFETCH_DECODED_MEMORY_FACTOR);
    let memory_cap = if estimated_resident_per_block == 0 {
        protocol_cap
    } else {
        (resident_budget / estimated_resident_per_block).clamp(1, u64::from(u32::MAX)) as u32
    };
    protocol_cap.min(memory_cap)
}

struct DownloadedBatch {
    block_source: block_source::MemoryBlockSource,
    from_state: chain::ChainState,
    canonical_end_hash_at_fetch: BlockHash,
    synthetic_start_anchor: bool,
}

#[derive(Clone, Copy)]
enum EndValidationMode {
    /// Validate the downloaded last block against a concurrently fetched
    /// canonical end state before returning.
    Immediate,
    /// Defer the canonical end-state lookup until the prefetched batch is
    /// consumed. This removes one redundant tree-state RPC per prefetched
    /// batch while retaining a fresh fork check immediately before scan.
    Deferred,
}

fn compact_hash(bytes: &[u8], context: &str) -> Result<BlockHash, String> {
    BlockHash::try_from_slice(bytes)
        .ok_or_else(|| format!("{context} hash has {} bytes, expected 32", bytes.len()))
}

/// Validates that blocks, the starting frontier, and the canonical state at
/// the batch end all describe one contiguous branch before the batch is
/// handed to `scan_cached_blocks`.
fn validate_downloaded_batch(
    batch: &DownloadedBatch,
    start: BlockHeight,
    end_exclusive: BlockHeight,
) -> Result<(), String> {
    let expected_count = u32::from(end_exclusive).saturating_sub(u32::from(start)) as usize;
    if batch.block_source.block_count() != expected_count {
        return Err(format!(
            "batch {}..{} returned {} blocks, expected {expected_count}",
            u32::from(start),
            u32::from(end_exclusive),
            batch.block_source.block_count(),
        ));
    }

    let first = batch
        .block_source
        .first_block()
        .ok_or_else(|| "batch is empty".to_string())?;
    let last = batch
        .block_source
        .last_block()
        .ok_or_else(|| "batch is empty".to_string())?;
    if first.height != u32::from(start) as u64
        || last.height != u32::from(end_exclusive).saturating_sub(1) as u64
    {
        return Err(format!(
            "batch boundary heights are {}..{}, expected {}..{}",
            first.height,
            last.height,
            u32::from(start),
            u32::from(end_exclusive) - 1,
        ));
    }

    if !batch.synthetic_start_anchor {
        let first_prev = compact_hash(&first.prev_hash, "first block prev")?;
        if first_prev != batch.from_state.block_hash() {
            return Err(format!(
                "first block at {} does not extend the fetched start state",
                first.height
            ));
        }
    }

    for pair in batch.block_source.blocks().windows(2) {
        let previous = &pair[0];
        let next = &pair[1];
        let previous_hash = compact_hash(&previous.hash, "previous block")?;
        let next_prev = compact_hash(&next.prev_hash, "next block prev")?;
        if next.height != previous.height.saturating_add(1) || next_prev != previous_hash {
            return Err(format!(
                "compact block chain is discontinuous between heights {} and {}",
                previous.height, next.height
            ));
        }
    }

    let last_hash = compact_hash(&last.hash, "last block")?;
    if last_hash != batch.canonical_end_hash_at_fetch {
        return Err(format!(
            "last block at {} does not match the canonical end state",
            last.height
        ));
    }

    Ok(())
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

fn is_pending_scan_range(range: &ScanRange) -> bool {
    range.priority() != ScanPriority::Ignored && range.priority() != ScanPriority::Scanned
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

fn wallet_summary_heights(db: &WalletDatabase) -> Result<Option<(u64, u64)>, SyncError> {
    db.get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| SyncError::db(format!("get_wallet_summary: {e}")))
        .map(|summary| {
            summary.map(|s| {
                (
                    u32::from(s.fully_scanned_height()) as u64,
                    u32::from(s.chain_tip_height()) as u64,
                )
            })
        })
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
    db: &WalletDatabase,
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

    let Some((fully_scanned_height, db_tip_height)) = wallet_summary_heights(db)? else {
        if current_tip_height == 0 {
            return Ok((0, 0));
        }
        return Err(SyncError::db(format!(
            "sync completion blocked: wallet summary unavailable at tip {current_tip_height}"
        )));
    };

    if db_tip_height != current_tip_height {
        return Err(SyncError::continuity(
            current_tip_height,
            format!(
                "sync completion blocked: wallet DB chain tip {db_tip_height} \
                 does not equal lightwalletd tip {current_tip_height}"
            ),
        ));
    }

    if fully_scanned_height < db_tip_height {
        return Err(SyncError::continuity(
            db_tip_height,
            format!(
                "sync completion blocked: fully scanned height {fully_scanned_height} \
                 below wallet DB chain tip {db_tip_height}"
            ),
        ));
    }

    Ok((fully_scanned_height, db_tip_height))
}

async fn canonical_chain_state_at(
    client: &mut CompactTxStreamerClient<Channel>,
    height: BlockHeight,
) -> Result<chain::ChainState, SyncError> {
    let state = get_tree_state(client, u32::from(height) as u64)
        .await?
        .to_chain_state()
        .map_err(|e| SyncError::parse(format!("parse canonical tree state at {height}: {e}")))?;
    if state.block_height() != height {
        return Err(SyncError::parse(format!(
            "lightwalletd returned tree state for {}, requested {height}",
            state.block_height(),
        )));
    }
    Ok(state)
}

/// librustzcash deliberately retains received-note rows when a transaction is
/// unmined by a rewind so memo and sent-note history are not lost. The retained
/// commitment-tree position and Sapling/Orchard nullifier, however, belong to
/// the orphaned branch. Clear only that re-derivable chain metadata so
/// `check_witnesses` does not ask shardtree for an orphaned leaf and a later
/// re-mining can store the note's new position/nullifier.
fn clear_unmined_note_tree_metadata(db_path: &str) -> Result<usize, SyncError> {
    with_wallet_db_write_lock("sync_engine.clear_unmined_note_tree_metadata", || {
        let mut conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(|e| SyncError::db(format!("open wallet DB for orphan-note cleanup: {e}")))?;
        let tx = conn
            .transaction()
            .map_err(|e| SyncError::db(format!("begin orphan-note cleanup: {e}")))?;
        let mut cleared = 0usize;
        for table in ["sapling_received_notes", "orchard_received_notes"] {
            cleared += tx
                .execute(
                    &format!(
                        "UPDATE {table}
                         SET commitment_tree_position = NULL, nf = NULL
                         WHERE commitment_tree_position IS NOT NULL
                         AND EXISTS (
                            SELECT 1 FROM transactions tx
                            WHERE tx.id_tx = {table}.transaction_id
                            AND tx.mined_height IS NULL
                         )"
                    ),
                    [],
                )
                .map_err(|e| SyncError::db(format!("clear orphaned metadata in {table}: {e}")))?;
        }
        tx.commit()
            .map_err(|e| SyncError::db(format!("commit orphan-note cleanup: {e}")))?;
        Ok(cleared)
    })
}

async fn rewind_for_canonical_tip_mismatch(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    remote_tip: BlockHeight,
    remote_tip_hash: BlockHash,
) -> Result<u64, SyncError> {
    let mismatch_height = u32::from(remote_tip) as u64;
    let remote_tip_u32 = u32::from(remote_tip);
    let local_tip_hash = db
        .get_block_hash(remote_tip)
        .map_err(|e| SyncError::db(format!("get wallet block hash at {remote_tip}: {e}")))?;

    // A backward-moving tip can still be on the same branch. In that case a
    // direct height truncation is sufficient and avoids a tree-state RPC.
    let rewind_anchor = if local_tip_hash == Some(remote_tip_hash) {
        with_wallet_db_write_lock("sync_engine.truncate_to_height.backward_tip", || {
            db.truncate_to_height(remote_tip).map_err(|e| {
                if is_sqlite_lock_contention(&e) {
                    SyncError::other(format!(
                        "truncate_to_height({remote_tip}): SQLite lock contention: {e}"
                    ))
                } else {
                    SyncError::db(format!("truncate_to_height({remote_tip}): {e}"))
                }
            })
        })?
    } else {
        // Hash mismatch means the fork point is unknown. A fixed ten-block
        // rewind can splice a canonical batch onto an orphaned commitment
        // frontier when the reorg is deeper. Find the highest common ancestor
        // with exponentially spaced probes, then binary-search the boundary.
        // This costs O(log reorg_depth) tree-state RPCs on the rare reorg path.
        let mut last_mismatch = remote_tip_u32;
        let mut distance = 1u32;
        let (anchor_state, found_common_ancestor) = loop {
            let candidate_u32 = remote_tip_u32.saturating_sub(distance);
            let candidate = BlockHeight::from_u32(candidate_u32);
            let state = canonical_chain_state_at(client, candidate).await?;
            let local_hash = db
                .get_block_hash(candidate)
                .map_err(|e| SyncError::db(format!("get wallet block hash at {candidate}: {e}")))?;

            if local_hash == Some(state.block_hash()) {
                // `candidate` is equal and `last_mismatch` is unequal. Locate
                // the highest equal height so the rescan is no larger than
                // necessary while still preserving a valid old frontier.
                let mut low_equal = candidate_u32;
                let mut high_mismatch = last_mismatch;
                let mut low_state = state;
                while high_mismatch.saturating_sub(low_equal) > 1 {
                    let mid_u32 = low_equal + (high_mismatch - low_equal) / 2;
                    let mid = BlockHeight::from_u32(mid_u32);
                    let mid_state = canonical_chain_state_at(client, mid).await?;
                    let mid_local_hash = db.get_block_hash(mid).map_err(|e| {
                        SyncError::db(format!("get wallet block hash at {mid}: {e}"))
                    })?;
                    if mid_local_hash == Some(mid_state.block_hash()) {
                        low_equal = mid_u32;
                        low_state = mid_state;
                    } else {
                        high_mismatch = mid_u32;
                    }
                }
                break (low_state, true);
            }

            // If wallet block metadata is no longer retained, the canonical
            // state at this lower height is still a safe reset anchor;
            // truncate_to_chain_state can inject its frontiers below the
            // retained checkpoint window without vendoring shardtree.
            if candidate_u32 == 0 || local_hash.is_none() {
                break (state, false);
            }

            last_mismatch = candidate_u32;
            distance = distance.saturating_mul(2).min(remote_tip_u32);
        };
        let anchor_height = anchor_state.block_height();
        with_wallet_db_write_lock(
            "sync_engine.truncate_to_chain_state.canonical_tip_mismatch",
            || {
                db.truncate_to_chain_state(anchor_state).map_err(|e| {
                    if is_sqlite_lock_contention(&e) {
                        SyncError::other(format!(
                            "truncate_to_chain_state({anchor_height}): SQLite lock contention: {e}"
                        ))
                    } else {
                        SyncError::db(format!("truncate_to_chain_state({anchor_height}): {e}"))
                    }
                })
            },
        )?;
        log::warn!(
            "[{}] sync: canonical mismatch selected rewind anchor {} ({})",
            elapsed(),
            anchor_height,
            if found_common_ancestor {
                "highest common ancestor"
            } else {
                "canonical frontier fallback"
            },
        );
        anchor_height
    };
    let cleared_notes = clear_unmined_note_tree_metadata(db_path)?;
    if cleared_notes > 0 {
        log::info!(
            "[{}] sync: cleared orphan-branch tree metadata from {} unmined note(s)",
            elapsed(),
            cleared_notes,
        );
    }

    let ranges = with_wallet_db_write_lock(
        "sync_engine.update_chain_tip.canonical_tip_mismatch",
        || -> Result<Vec<ScanRange>, SyncError> {
            db.update_chain_tip(remote_tip).map_err(|e| {
                SyncError::db(format!(
                    "update_chain_tip({mismatch_height}) after canonical mismatch: {e}"
                ))
            })?;
            db.suggest_scan_ranges().map_err(|e| {
                SyncError::db(format!(
                    "suggest_scan_ranges after canonical tip mismatch: {e}"
                ))
            })
        },
    )?;
    let pending = pending_scan_blocks(&ranges);
    log::warn!(
        "[{}] sync: canonical tip mismatch rewound wallet to {} and queued {} block(s)",
        elapsed(),
        u32::from(rewind_anchor),
        pending,
    );
    if u32::from(rewind_anchor) < u32::from(remote_tip) && pending == 0 {
        return Err(SyncError::continuity(
            mismatch_height,
            "canonical tip rewind produced no pending scan ranges",
        ));
    }
    Ok(pending)
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
        db.check_witnesses()
            .map_err(|e| SyncError::db(format!("check_witnesses: {e}")))
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
    db_path: &str,
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
    if local_sapling.as_ref() == Some(&canonical_sapling)
        && local_orchard.as_ref() == Some(&canonical_orchard)
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
             canonical_orchard={:?}; rewinding to canonical chain state",
            elapsed(),
            u32::from(target_height),
            *repair_passes_this_run,
            ANCHOR_ROOT_REPAIR_REWIND_DISTANCES.len(),
            local_sapling,
            canonical_sapling,
            local_orchard,
            canonical_orchard,
        );

        let current_tip = BlockHeight::from_u32(current_tip_height as u32);
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

        let cleared_notes = clear_unmined_note_tree_metadata(db_path)?;
        if cleared_notes > 0 {
            log::info!(
                "[{}] sync: cleared orphan-branch tree metadata from {} unmined note(s)",
                elapsed(),
                cleared_notes,
            );
        }

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

async fn refresh_utxos(
    client: &mut CompactTxStreamerClient<Channel>,
    db_data_path: &str,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    tip_height: BlockHeight,
) -> Result<(), SyncError> {
    for account_id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(format!("get_account_ids: {e}")))?
    {
        let account_uuid = account_id.expose_uuid().to_string();
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

        let external_addresses = keys::get_external_transparent_receive_addresses_from_db(
            db_data_path,
            network,
            Some(&account_uuid),
        )
        .map_err(|e| SyncError::db(format!("external transparent receive addresses: {e}")))?;
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
            let start_height = block_height_from_u64(
                batch.start_height,
                "transparent receive UTXO batch start height",
            )?;
            let label = if batch.next_sweep_offset.is_some() {
                format!("transparent external UTXOs sweep batch {}", batch_index + 1)
            } else {
                "transparent external UTXOs recent batch".to_string()
            };
            refresh_transparent_addresses(
                client,
                db,
                batch.addresses,
                start_height,
                &label,
                || mark_transparent_receive_cache_dirty(db_data_path, &account_uuid),
            )
            .await?;
            if let Err(e) = transparent_receive_cache::mark_utxo_refresh_batch_complete(
                db_data_path,
                network,
                &account_uuid,
                &batch.child_indices,
                u64::from(u32::from(tip_height)) + 1,
                batch.next_sweep_offset,
            ) {
                log::warn!(
                    "transparent receive cache: failed to mark UTXO batch complete for account {}: {}",
                    account_uuid,
                    e
                );
            }
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
            .map(|(addr, _)| addr.encode(&network))
            .filter(|addr| !external_selected.contains(addr.as_str()))
            .collect();

        if !non_external_addresses.is_empty() {
            refresh_transparent_addresses(
                client,
                db,
                non_external_addresses,
                safety_start_height,
                "transparent non-external UTXOs",
                || mark_transparent_receive_cache_dirty(db_data_path, &account_uuid),
            )
            .await?;
        }
    }

    Ok(())
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

async fn refresh_transparent_addresses(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    addresses: Vec<String>,
    start_height: BlockHeight,
    label: &str,
    mut mark_cache_dirty: impl FnMut(),
) -> Result<bool, SyncError> {
    if addresses.is_empty() {
        return Ok(false);
    }

    log::info!(
        "[{}] sync: refreshing {} from height {} ({} addresses)",
        elapsed(),
        label,
        u32::from(start_height),
        addresses.len(),
    );

    let mut stream = client
        .get_address_utxos_stream(service::GetAddressUtxosArg {
            addresses,
            start_height: u32::from(start_height) as u64,
            max_entries: 0,
        })
        .await
        .map_err(|e| SyncError::net(format!("get_address_utxos_stream: {e}")))?
        .into_inner();

    let mut received_any = false;
    while let Some(reply) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("get_address_utxos_stream message: {e}")))?
    {
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

        let output = WalletTransparentOutput::from_parts(
            OutPoint::new(txid, index),
            TxOut::new(value, Script(script::Code(reply.script))),
            Some(BlockHeight::from_u32(height)),
        )
        .ok_or_else(|| {
            SyncError::parse("transparent UTXO script did not decode to a wallet address")
        })?;

        with_wallet_db_write_lock("sync_engine.put_received_transparent_utxo", || {
            db.put_received_transparent_utxo(&output)
                .map_err(|e| SyncError::db(format!("put_received_transparent_utxo: {e}")))
        })?;
        if !received_any {
            mark_cache_dirty();
        }
        received_any = true;
    }

    Ok(received_any)
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
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
) -> Result<(), SyncError> {
    let default_batch_size = if running_mode == 2 {
        BATCH_SIZE_BACKGROUND
    } else {
        BATCH_SIZE_FOREGROUND
    };
    let base_batch_size = effective_base_batch_size(default_batch_size);
    log::info!(
        "[{}] sync: starting (mode={}, base_batch={})",
        elapsed(),
        running_mode,
        base_batch_size
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

    // 2. Get chain tip. `current_tip_height` is updated by the
    // periodic refresh (TIP_REFRESH_INTERVAL) so that progress
    // events always reflect the latest known chain height, not the
    // one captured at sync start. The initial `tip` response is
    // also kept around for its other fields but `current_tip_height`
    // is the authoritative value for emitted events.
    let tip = get_latest_block(&mut client).await?;
    let mut current_tip_height: u64 = tip.height;
    let tip_height = BlockHeight::from_u32(tip.height as u32);
    log::info!("[{}] sync: chain tip = {}", elapsed(), tip.height);

    with_wallet_db_write_lock("sync_engine.update_chain_tip.initial", || {
        db.update_chain_tip(tip_height)
            .map_err(|e| SyncError::db(format!("update_chain_tip: {e}")))
    })?;

    // The upstream transparent UTXO refresh does not accept a cancellation
    // predicate, so don't enter it (or continue past it) after a cancel/mode
    // change has already been observed.
    if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
        log::info!(
            "[{}] sync: cancel/mode observed before transparent UTXO refresh, skipping",
            elapsed(),
        );
        return Ok(());
    }

    refresh_utxos(&mut client, db_data_path, &mut db, network, tip_height).await?;

    if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
        log::info!(
            "[{}] sync: exiting after transparent UTXO refresh",
            elapsed()
        );
        return Ok(());
    }

    // 2.5. Resubmit any unmined, unexpired wallet txs now that we
    // know the current tip. Matches the first of the three
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
    if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
        log::info!(
            "[{}] sync: cancel/mode observed before startup resubmit, skipping",
            elapsed(),
        );
    } else {
        let _ = crate::wallet::sync::resubmit_pending_transactions(
            db_data_path,
            &mut client,
            tip.height as u32,
            || {
                cancel.load(Ordering::Relaxed)
                    || desired_mode.load(Ordering::SeqCst) != running_mode
            },
        )
        .await;
    }

    // 3. Download subtree roots (incremental)
    download_subtree_roots(&mut client, &mut db).await?;

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
    let mut initial_total: u64 = {
        let ranges = db
            .suggest_scan_ranges()
            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;
        ranges
            .iter()
            .filter(|r| is_pending_scan_range(r))
            .map(|r| {
                u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start))
                    as u64
            })
            .sum()
    };
    let mut prev_remaining = initial_total;
    log::info!("[{}] sync: {} blocks to scan", elapsed(), initial_total);

    // Bounded counters for reorg-triggered rewinds inside this one sync run,
    // split between the verify phase and the main scan phase. Separate
    // budgets match zcash-android-wallet-sdk's pattern of running a
    // dedicated verify-first loop before the main scan, so a flapping
    // verify range can't eat the main scan's rewind budget.
    let mut verify_rewinds_this_run: u32 = 0;
    let mut main_rewinds_this_run: u32 = 0;
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

    // If the scan loop has been running longer than the configured interval without
    // refreshing the chain tip from lightwalletd, we re-fetch
    // the tip and call `update_chain_tip` so that
    // `suggest_scan_ranges` incorporates any new blocks that
    // appeared while the wallet was catching up.
    //
    // We don't restart the whole sync like the Android SDK does; refreshing
    // the tip is enough because suggest_scan_ranges observes it immediately.
    let mut last_tip_refresh = std::time::Instant::now();

    type PrefetchResult = Result<DownloadedBatch, SyncError>;
    struct Prefetch {
        handle: Option<tokio::task::JoinHandle<PrefetchResult>>,
        start: BlockHeight,
        end: BlockHeight,
    }
    impl Drop for Prefetch {
        fn drop(&mut self) {
            if let Some(h) = self.handle.take() {
                h.abort();
            }
        }
    }
    let prefetch_depth = effective_prefetch_depth(running_mode);
    let batch_resident_budget = if prefetch_depth > 0 {
        PREFETCH_RESIDENT_BUDGET / 2
    } else {
        PREFETCH_RESIDENT_BUDGET
    };
    let mut prefetch: VecDeque<Prefetch> = VecDeque::new();
    let mut estimated_wire_bytes_per_block = 0u64;
    let mut fetch_wait_total = std::time::Duration::ZERO;
    let mut fetch_batches = 0u64;
    let mut stale_prefetches = 0u64;
    let resubmit_interval = effective_resubmit_interval();
    let mut last_resubmit = std::time::Instant::now();
    let mut last_status_poll = std::time::Instant::now();
    let mut resubmit_total = std::time::Duration::ZERO;
    let mut resubmit_passes = 0u64;
    let mut enhancement_total = std::time::Duration::ZERO;
    let mut enhancement_passes = 0u64;
    log::info!(
        "[{}] sync: prefetch depth={}, resident budget={} MiB",
        elapsed(),
        prefetch_depth,
        PREFETCH_RESIDENT_BUDGET / (1024 * 1024),
    );

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
        // Errors are logged and skipped — we just keep the old
        // tip and try again next period.
        if last_tip_refresh.elapsed() >= TIP_REFRESH_INTERVAL {
            match get_latest_block(&mut client).await {
                Ok(fresh_tip) => {
                    let fresh_height = BlockHeight::from_u32(fresh_tip.height as u32);
                    if let Err(e) =
                        with_wallet_db_write_lock("sync_engine.update_chain_tip.periodic", || {
                            db.update_chain_tip(fresh_height)
                        })
                    {
                        log::warn!(
                            "[{}] sync: periodic tip refresh update_chain_tip failed: {e}",
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
                    }
                }
                Err(e) => {
                    log::warn!(
                        "[{}] sync: periodic tip refresh get_latest_block failed: {e}",
                        elapsed(),
                    );
                }
            }
            last_tip_refresh = std::time::Instant::now();
        }

        let ranges = db
            .suggest_scan_ranges()
            .map_err(|e| SyncError::db(format!("suggest_scan_ranges: {e}")))?;

        let range = match ranges.iter().find(|r| is_pending_scan_range(r)) {
            Some(r) => r.clone(),
            None => {
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
                    prefetch.clear();
                    continue;
                } else if let Some(repair_pending_blocks) = repair_anchor_root_mismatch_if_needed(
                    &mut client,
                    &mut db,
                    db_data_path,
                    current_tip_height,
                    &mut anchor_root_repair_passes_this_run,
                )
                .await?
                {
                    force_witness_check_this_run = true;
                    initial_total = repair_pending_blocks;
                    prev_remaining = repair_pending_blocks;
                    prefetch.clear();
                    continue;
                } else {
                    // Completion barrier: drain transaction enhancement first,
                    // then verify the remote canonical (height, hash) against
                    // the wallet DB immediately before emitting completion.
                    let should_exit = || {
                        cancel.load(Ordering::Relaxed)
                            || desired_mode.load(Ordering::SeqCst) != running_mode
                    };
                    let enhancement_start = std::time::Instant::now();
                    let final_outcome =
                        run_enhancement(&mut client, &mut db, db_data_path, network, &should_exit)
                            .await?;
                    enhancement_total += enhancement_start.elapsed();
                    enhancement_passes += 1;
                    if should_exit() {
                        log::info!(
                            "[{}] sync: exiting during final enhancement pass",
                            elapsed()
                        );
                        return Ok(());
                    }
                    if final_outcome.stored > 0 {
                        log::info!(
                            "[{}] sync: final enhancement pass stored {} transaction(s)",
                            elapsed(),
                            final_outcome.stored,
                        );
                    }
                    if let Some(error) = final_outcome.failure {
                        return Err(error);
                    }
                    if !final_outcome.drained {
                        return Err(SyncError::other(
                            "final transaction enhancement queue contains actionable work",
                        ));
                    }

                    let final_tip = get_latest_block(&mut client).await?;
                    let final_tip_height =
                        block_height_from_u64(final_tip.height, "final lightwalletd tip height")?;
                    let final_tip_height_u64 = u32::from(final_tip_height) as u64;
                    let final_tip_hash = compact_hash(&final_tip.hash, "final lightwalletd tip")
                        .map_err(SyncError::parse)?;
                    let summary = wallet_summary_heights(&db)?;
                    let local_db_tip = summary.map(|(_, tip)| tip);
                    let local_hash = db
                        .get_block_hash(final_tip_height)
                        .map_err(|e| SyncError::db(format!("get final wallet block hash: {e}")))?;

                    let local_covers_remote = local_db_tip
                        .map(|height| height >= final_tip_height_u64)
                        .unwrap_or(false);
                    let canonical_mismatch = local_db_tip
                        .map(|height| height > final_tip_height_u64)
                        .unwrap_or(false)
                        || (local_covers_remote && local_hash != Some(final_tip_hash));
                    if canonical_mismatch {
                        let pending = rewind_for_canonical_tip_mismatch(
                            &mut client,
                            &mut db,
                            db_data_path,
                            final_tip_height,
                            final_tip_hash,
                        )
                        .await?;
                        current_tip_height = final_tip_height_u64;
                        initial_total = pending;
                        prev_remaining = pending;
                        force_witness_check_this_run = true;
                        prefetch.clear();
                        continue;
                    }

                    if final_tip_height_u64 != current_tip_height {
                        with_wallet_db_write_lock(
                            "sync_engine.update_chain_tip.completion_refresh",
                            || {
                                db.update_chain_tip(final_tip_height).map_err(|e| {
                                    SyncError::db(format!(
                                        "update_chain_tip({final_tip_height_u64}) before completion: {e}"
                                    ))
                                })
                            },
                        )?;
                        log::info!(
                            "[{}] sync: completion tip changed {} -> {}; rescanning newly queued ranges",
                            elapsed(),
                            current_tip_height,
                            final_tip_height_u64,
                        );
                        current_tip_height = final_tip_height_u64;
                        prefetch.clear();
                        continue;
                    }
                    ensure_complete_scan_state(&db, current_tip_height)?;
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
        // Adaptive batch size: shrink to BATCH_SIZE_SANDBLASTING
        // when the current range overlaps the known Zcash mainnet
        // sandblasting attack window. These blocks contain an
        // order of magnitude more outputs than normal blocks,
        // making scan_cached_blocks much slower per block and
        // using more memory. Matches the SDK's
        // `SANDBLASTING_RANGE` check.
        let batch_size = memory_bounded_batch_size(
            base_batch_size,
            start,
            range.block_range().end,
            estimated_wire_bytes_per_block,
            batch_resident_budget,
        );
        let end = std::cmp::min(start + batch_size, range.block_range().end);
        let batch_blocks = u32::from(end).saturating_sub(u32::from(start)) as u64;
        let current_pct = if initial_total > 0 {
            1.0 - (prev_remaining as f64 / initial_total as f64)
        } else {
            1.0
        };
        progress_fn(SyncProgressEvent {
            scanned_height: u32::from(start) as u64,
            chain_tip_height: current_tip_height,
            percentage: current_pct.clamp(0.0, 1.0),
            display_target_percentage: target_percentage_after_blocks(
                initial_total,
                prev_remaining,
                batch_blocks,
            ),
            display_target_blocks: batch_blocks,
            is_syncing: true,
            is_complete: false,
            has_new_tx: false,
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

        let front_matches = prefetch
            .front()
            .map(|candidate| candidate.start == start && candidate.end == end)
            .unwrap_or(false);
        let fetch_wait_start = std::time::Instant::now();
        let batch = if front_matches {
            let mut prefetched = prefetch.pop_front().expect("matching front exists");
            let handle = prefetched.handle.take().expect("prefetch handle exists");
            match handle.await {
                Ok(Ok(candidate)) => {
                    match prefetched_batch_is_current(&mut client, network, &candidate, end).await {
                        Ok(true) => candidate,
                        Ok(false) => {
                            stale_prefetches += 1;
                            log::warn!(
                                "[{}] sync: prefetched batch {}-{} was orphaned; downloading fresh",
                                elapsed(),
                                u32::from(start),
                                u32::from(end) - 1,
                            );
                            prefetch.clear();
                            download_current_batch(client.clone(), network, start, end).await?
                        }
                        Err(e) => {
                            stale_prefetches += 1;
                            log::warn!(
                                "[{}] sync: could not revalidate prefetched batch {}-{} ({e}); downloading fresh",
                                elapsed(),
                                u32::from(start),
                                u32::from(end) - 1,
                            );
                            prefetch.clear();
                            download_current_batch(client.clone(), network, start, end).await?
                        }
                    }
                }
                Ok(Err(e)) => {
                    log::warn!(
                        "[{}] sync: prefetch download failed ({e}); downloading fresh",
                        elapsed()
                    );
                    prefetch.clear();
                    download_current_batch(client.clone(), network, start, end).await?
                }
                Err(e) => {
                    log::warn!(
                        "[{}] sync: prefetch task failed to join ({e}); downloading fresh",
                        elapsed()
                    );
                    prefetch.clear();
                    download_current_batch(client.clone(), network, start, end).await?
                }
            }
        } else {
            // The first batch, a range/priority change, or a rewind cannot
            // safely reuse predictions from the previous queue.
            prefetch.clear();
            download_current_batch(client.clone(), network, start, end).await?
        };
        let fetch_wait = fetch_wait_start.elapsed();
        fetch_wait_total += fetch_wait;
        fetch_batches += 1;
        let current_batch_wire_bytes = batch.block_source.wire_bytes();
        if batch.block_source.block_count() > 0 {
            estimated_wire_bytes_per_block =
                (current_batch_wire_bytes / batch.block_source.block_count() as u64).max(1);
        }
        log::debug!(
            "[{}] sync: batch {} fetch-wait {:.0}ms ({} blocks, {} KiB wire)",
            elapsed(),
            u32::from(start),
            fetch_wait.as_secs_f64() * 1000.0,
            batch.block_source.block_count(),
            batch.block_source.wire_bytes() / 1024,
        );

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after download", elapsed());
            return Ok(());
        }

        let DownloadedBatch {
            block_source,
            from_state,
            synthetic_start_anchor,
            ..
        } = batch;

        // The downloaded blocks and tree state may be mutually consistent
        // while still starting from a different branch than the wallet DB.
        // Compare the canonical start-state hash with our retained predecessor
        // before touching commitment trees; otherwise a deep reorg can splice
        // a new suffix onto an orphaned frontier without a prev-hash error.
        let local_anchor_mismatch = if synthetic_start_anchor {
            None
        } else {
            let anchor_height = from_state.block_height();
            let local_anchor = db.get_block_hash(anchor_height).map_err(|e| {
                SyncError::db(format!(
                    "get wallet batch anchor hash at {anchor_height}: {e}"
                ))
            })?;
            local_anchor
                .filter(|hash| *hash != from_state.block_hash())
                .map(|local_hash| {
                    SyncError::continuity(
                        u32::from(start) as u64,
                        format!(
                            "wallet anchor {anchor_height} hash {local_hash:?} differs from canonical {:?}",
                            from_state.block_hash(),
                        ),
                    )
                })
        };

        // Start the next download before entering the synchronous scanner so
        // desktop's multi-thread runtime can overlap network I/O with the
        // current batch's CPU/SQLite work. Mobile defaults prefetch off because
        // its current-thread background runtime cannot provide this overlap.
        if local_anchor_mismatch.is_none() && !cancel.load(Ordering::Relaxed) {
            let range_end = range.block_range().end;
            let mut prefetch_start = prefetch.back().map(|item| item.end).unwrap_or(end);
            while prefetch_start < range_end {
                let prefetch_batch = memory_bounded_batch_size(
                    base_batch_size,
                    prefetch_start,
                    range_end,
                    estimated_wire_bytes_per_block,
                    batch_resident_budget,
                );
                let prefetch_end = std::cmp::min(prefetch_start + prefetch_batch, range_end);
                let next_batch_blocks =
                    u32::from(prefetch_end).saturating_sub(u32::from(prefetch_start)) as u64;
                let queued_blocks = prefetch
                    .iter()
                    .map(|item| u32::from(item.end).saturating_sub(u32::from(item.start)) as u64)
                    .sum();
                if !can_spawn_prefetch(
                    prefetch.len(),
                    prefetch_depth,
                    current_batch_wire_bytes,
                    queued_blocks,
                    next_batch_blocks,
                    estimated_wire_bytes_per_block.max(prefetch_wire_floor(prefetch_start)),
                    PREFETCH_RESIDENT_BUDGET,
                ) {
                    break;
                }

                let batch_client = client.clone();
                let batch_start = prefetch_start;
                prefetch.push_back(Prefetch {
                    start: batch_start,
                    end: prefetch_end,
                    handle: Some(tokio::spawn(async move {
                        download_batch(
                            batch_client,
                            network,
                            batch_start,
                            prefetch_end,
                            EndValidationMode::Deferred,
                        )
                        .await
                    })),
                });
                prefetch_start = prefetch_end;
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
        let scan_result = if let Some(anchor_error) = local_anchor_mismatch {
            prefetch.clear();
            Err(anchor_error)
        } else {
            with_wallet_db_write_lock("sync_engine.scan_cached_blocks", || {
                scan_cached_blocks(
                    &network,
                    &block_source,
                    &mut db,
                    start,
                    &from_state,
                    batch_size as usize,
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
            })
        };

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
                    let target = BlockHeight::from_u32(requested_rewind_height as u32);
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
                    let cleared_notes = clear_unmined_note_tree_metadata(db_data_path)?;
                    if cleared_notes > 0 {
                        log::info!(
                            "[{}] sync: cleared orphan-branch tree metadata from {} unmined note(s)",
                            elapsed(),
                            cleared_notes,
                        );
                    }
                    let current_tip = BlockHeight::from_u32(current_tip_height as u32);
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
                    let summary = wallet_summary_heights(&db)?;
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
                    }
                    prefetch.clear();
                    continue;
                }
                RecoveryStrategy::RetryWithBackoff | RecoveryStrategy::Fatal => {
                    return Err(sync_err);
                }
            },
        };

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after scan", elapsed());
            return Ok(());
        }

        let batch_found_tx = scan_summary.received_sapling_note_count() > 0
            || scan_summary.spent_sapling_note_count() > 0
            || scan_summary.received_orchard_note_count() > 0
            || scan_summary.spent_orchard_note_count() > 0;

        let is_last_batch_of_range = end == range.block_range().end;
        let should_exit = || {
            cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode
        };
        let mut has_new_tx = batch_found_tx;

        // Tip refresh and resubmit have independent time/activity policies.
        // Both need an authoritative height, so share one lookup when either
        // is due without coupling enhancement to the same cadence.
        let tip_refresh_due =
            is_last_batch_of_range || last_tip_refresh.elapsed() >= TIP_REFRESH_INTERVAL;
        let resubmit_time_due = last_resubmit.elapsed() >= resubmit_interval;
        let needs_fresh_tip =
            tip_refresh_due || resubmit_time_due || batch_found_tx || is_last_batch_of_range;
        if needs_fresh_tip {
            let resubmit_start = std::time::Instant::now();
            match get_latest_block(&mut client).await {
                Ok(fresh_tip) => {
                    let fresh_height = block_height_from_u64(
                        fresh_tip.height,
                        "post-batch lightwalletd tip height",
                    )?;
                    let fresh_tip_height = u32::from(fresh_height) as u64;
                    let tip_changed = fresh_tip_height != current_tip_height;
                    if fresh_tip_height > current_tip_height {
                        match with_wallet_db_write_lock(
                            "sync_engine.update_chain_tip.post_batch",
                            || db.update_chain_tip(fresh_height),
                        ) {
                            Ok(()) => {
                                current_tip_height = fresh_tip_height;
                            }
                            Err(e) => log::warn!(
                                "[{}] sync: post-batch update_chain_tip({fresh_tip_height}) \
                                 failed, keeping tip at {current_tip_height}: {e}",
                                elapsed(),
                            ),
                        }
                    } else if fresh_tip_height < current_tip_height {
                        log::warn!(
                            "[{}] sync: lightwalletd tip moved backward {} -> {}; canonical hash check will resolve it at completion",
                            elapsed(),
                            current_tip_height,
                            fresh_tip_height,
                        );
                    }
                    last_tip_refresh = std::time::Instant::now();
                    if resubmit_time_due || batch_found_tx || is_last_batch_of_range || tip_changed
                    {
                        let _ = crate::wallet::sync::resubmit_pending_transactions(
                            db_data_path,
                            &mut client,
                            u32::from(fresh_height),
                            || {
                                cancel.load(Ordering::Relaxed)
                                    || desired_mode.load(Ordering::SeqCst) != running_mode
                            },
                        )
                        .await;
                        last_resubmit = std::time::Instant::now();
                        resubmit_passes += 1;
                    }
                }
                Err(e) => log::warn!(
                    "[{}] sync: post-batch tip refresh failed, skipping resubmit: {e}",
                    elapsed(),
                ),
            }
            resubmit_total += resubmit_start.elapsed();
        }

        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests for scheduling: {e}")))?;
        let now = std::time::SystemTime::now();
        let has_immediate_enhancement = requests.iter().any(|request| match request {
            TransactionDataRequest::Enhancement(_) => true,
            TransactionDataRequest::TransactionsInvolvingAddress(request) => {
                request.block_range_end().is_some()
                    && request.request_at().map_or(true, |due| due <= now)
            }
            TransactionDataRequest::GetStatus(_) => false,
        });
        let has_status_requests = requests
            .iter()
            .any(|request| matches!(request, TransactionDataRequest::GetStatus(_)));
        let run_enhancement_now = has_immediate_enhancement
            || batch_found_tx
            || is_last_batch_of_range
            || (has_status_requests && last_status_poll.elapsed() >= STATUS_POLL_INTERVAL);
        if run_enhancement_now {
            let enhancement_start = std::time::Instant::now();
            match run_enhancement(&mut client, &mut db, db_data_path, network, &should_exit).await {
                Ok(outcome) => {
                    has_new_tx |= outcome.stored > 0;
                    if let Some(error) = outcome.failure {
                        log::warn!(
                            "[{}] sync: enhancement pass retained failed work for final retry: {error}",
                            elapsed(),
                        );
                    }
                }
                Err(e) => log::warn!(
                    "[{}] sync: enhancement pass failed (queue retained): {e}",
                    elapsed(),
                ),
            }
            enhancement_total += enhancement_start.elapsed();
            enhancement_passes += 1;
            if has_status_requests {
                last_status_poll = std::time::Instant::now();
            }
        }
        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after post-batch work", elapsed());
            return Ok(());
        }

        // Report progress
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
        }
        prev_remaining = remaining;
        let pct = if initial_total > 0 {
            1.0 - (remaining as f64 / initial_total as f64)
        } else {
            1.0
        };
        let next_display_target_blocks = post_ranges
            .iter()
            .find(|r| is_pending_scan_range(r))
            .map(|r| {
                let next_start = r.block_range().start;
                let next_batch_size = memory_bounded_batch_size(
                    base_batch_size,
                    next_start,
                    r.block_range().end,
                    estimated_wire_bytes_per_block,
                    batch_resident_budget,
                );
                let next_end = std::cmp::min(next_start + next_batch_size, r.block_range().end);
                u32::from(next_end).saturating_sub(u32::from(next_start)) as u64
            })
            .unwrap_or(0);
        let progress = SyncProgressEvent {
            scanned_height: u32::from(end) as u64,
            chain_tip_height: current_tip_height,
            percentage: pct.clamp(0.0, 1.0),
            display_target_percentage: target_percentage_after_blocks(
                initial_total,
                remaining,
                next_display_target_blocks,
            ),
            display_target_blocks: next_display_target_blocks,
            is_syncing: true,
            is_complete: false,
            has_new_tx,
            phase: "scan".into(),
        };
        log::info!(
            "[{}] sync: {:.1}% (remaining={}/{}, scanned={})",
            elapsed(),
            pct * 100.0,
            remaining,
            initial_total,
            initial_total - remaining
        );
        progress_fn(progress);
        #[cfg(debug_assertions)]
        maybe_sleep_for_e2e_sync_batch_delay().await;
    }

    let (final_scanned_height, final_tip_height) =
        ensure_complete_scan_state(&db, current_tip_height)?;
    log::info!(
        "[{}] sync: completed (fully_scanned={}, chain_tip={})",
        elapsed(),
        final_scanned_height,
        final_tip_height,
    );
    log::info!(
        "[{}] sync: fetch wait {:.2}s across {} batches (stale prefetches={})",
        elapsed(),
        fetch_wait_total.as_secs_f64(),
        fetch_batches,
        stale_prefetches,
    );
    log::info!(
        "[{}] sync: resubmit/tip refresh {:.2}s over {} passes (resubmit_interval={}s)",
        elapsed(),
        resubmit_total.as_secs_f64(),
        resubmit_passes,
        resubmit_interval.as_secs(),
    );
    log::info!(
        "[{}] sync: enhancement {:.2}s over {} passes",
        elapsed(),
        enhancement_total.as_secs_f64(),
        enhancement_passes,
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
        phase: String::new(),
    };
    progress_fn(final_progress);

    // Completion must not wait behind a potentially busy checkpoint. Both the
    // FRB and iOS FFI entry points create a Tokio runtime per sync call, and
    // dropping that runtime waits for its `spawn_blocking` tasks. Use a
    // detached OS thread so the sync call and SYNC_RUNNING flag can finish
    // independently after the user-visible completion event is delivered.
    drop(db);
    spawn_wallet_wal_checkpoint(db_data_path.to_string());

    Ok(())
}

// ==================== Helpers ====================

fn open_db(path: &str, network: WalletNetwork) -> Result<WalletDatabase, SyncError> {
    open_sync_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT)
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

fn should_use_empty_chain_state(
    network: &WalletNetwork,
    start: BlockHeight,
) -> Result<bool, SyncError> {
    let sapling_activation_height = network
        .activation_height(NetworkUpgrade::Sapling)
        .ok_or_else(|| SyncError::parse("Sapling activation height is unavailable"))?;
    Ok(start <= sapling_activation_height)
}

async fn fetch_validated_chain_state(
    client: &mut CompactTxStreamerClient<Channel>,
    height: BlockHeight,
) -> Result<chain::ChainState, SyncError> {
    let state = get_tree_state(client, u32::from(height) as u64)
        .await?
        .to_chain_state()
        .map_err(|e| SyncError::parse(format!("parse tree state at {height}: {e}")))?;
    if state.block_height() != height {
        return Err(SyncError::net(format!(
            "lightwalletd returned tree state for {}, requested {height}",
            state.block_height()
        )));
    }
    Ok(state)
}

async fn fetch_batch_start_state(
    client: &mut CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    start: BlockHeight,
) -> Result<(chain::ChainState, bool), SyncError> {
    if should_use_empty_chain_state(&network, start)? {
        Ok((
            chain::ChainState::empty(start - 1, BlockHash([0; 32])),
            true,
        ))
    } else {
        Ok((fetch_validated_chain_state(client, start - 1).await?, false))
    }
}

/// Downloads blocks and both boundary states concurrently. Boundary
/// validation happens before returning, so even the initial synchronous batch
/// cannot mix compact blocks and a tree frontier from different forks.
async fn download_current_batch(
    client: CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    start: BlockHeight,
    end_exclusive: BlockHeight,
) -> Result<DownloadedBatch, SyncError> {
    for attempt in 0..2 {
        match download_batch(
            client.clone(),
            network,
            start,
            end_exclusive,
            EndValidationMode::Immediate,
        )
        .await
        {
            Err(SyncError::Network(message))
                if attempt == 0 && message.contains("inconsistent downloaded batch") =>
            {
                log::warn!(
                    "[{}] sync: batch boundary changed during download; retrying locally",
                    elapsed(),
                );
            }
            result => return result,
        }
    }
    unreachable!("bounded batch retry always returns on its final attempt")
}

async fn download_batch(
    client: CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    start: BlockHeight,
    end_exclusive: BlockHeight,
    end_validation: EndValidationMode,
) -> Result<DownloadedBatch, SyncError> {
    let mut blocks_client = client.clone();
    let mut start_client = client.clone();
    let mut end_client = client;
    let end_height = end_exclusive - 1;

    let (block_source, (from_state, synthetic_start_anchor), end_state) = tokio::try_join!(
        download_blocks(&mut blocks_client, start, end_height),
        fetch_batch_start_state(&mut start_client, network, start),
        fetch_batch_end_state(&mut end_client, network, end_height, end_validation),
    )?;

    // For pre-Sapling batches there is no meaningful commitment-tree state;
    // deferred prefetch validation likewise waits until consumption for the
    // canonical end state. In both cases retain the stream's last hash as the
    // expected value. A prefetched post-Sapling batch compares it to a fresh
    // tree-state hash immediately before scan.
    let canonical_end_hash_at_fetch = match end_state {
        Some(state) => state.block_hash(),
        None => {
            let last = block_source
                .last_block()
                .ok_or_else(|| SyncError::net("empty compact-block batch"))?;
            compact_hash(&last.hash, "last block")
                .map_err(|e| SyncError::net(format!("invalid pre-Sapling batch: {e}")))?
        }
    };

    let batch = DownloadedBatch {
        block_source,
        from_state,
        canonical_end_hash_at_fetch,
        synthetic_start_anchor,
    };
    validate_downloaded_batch(&batch, start, end_exclusive)
        .map_err(|e| SyncError::net(format!("inconsistent downloaded batch: {e}")))?;
    Ok(batch)
}

async fn fetch_batch_end_state(
    client: &mut CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    end_height: BlockHeight,
    end_validation: EndValidationMode,
) -> Result<Option<chain::ChainState>, SyncError> {
    if matches!(end_validation, EndValidationMode::Deferred)
        || should_use_empty_chain_state(&network, end_height)?
    {
        Ok(None)
    } else {
        fetch_validated_chain_state(client, end_height)
            .await
            .map(Some)
    }
}

/// Re-checks a prefetched batch immediately before consumption. A successful
/// prefetch may be several scan batches old; this closes the window where a
/// reorg could otherwise leave a mutually consistent but orphaned batch in
/// memory.
async fn prefetched_batch_is_current(
    client: &mut CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    batch: &DownloadedBatch,
    end_exclusive: BlockHeight,
) -> Result<bool, SyncError> {
    if should_use_empty_chain_state(&network, end_exclusive - 1)? {
        // There is no canonical tree-state RPC before Sapling. A fork in this
        // historical range is still caught by scan_cached_blocks' continuity
        // checks when the batch is consumed.
        return Ok(true);
    }
    let current = fetch_validated_chain_state(client, end_exclusive - 1).await?;
    Ok(prefetched_batch_matches_state(batch, &current))
}

fn prefetched_batch_matches_state(batch: &DownloadedBatch, current: &chain::ChainState) -> bool {
    current.block_hash() == batch.canonical_end_hash_at_fetch
}

// ==================== Tests ====================
//
// Error-taxonomy tests now live alongside their types in `error.rs`. The
// only test that has to stay here is `sqlite_lock_contention_is_recognised`,
// because it exercises the `is_sqlite_lock_contention` helper that still
// lives in this module. A follow-up refactor commit moves the helper (and
// this test) into the lwd submodule.

#[cfg(test)]
mod tests {
    use super::*;

    fn test_downloaded_batch() -> DownloadedBatch {
        use zcash_client_backend::proto::compact_formats::CompactBlock;

        let anchor_hash = BlockHash([0; 32]);
        let first_hash = BlockHash([1; 32]);
        let last_hash = BlockHash([2; 32]);
        DownloadedBatch {
            block_source: block_source::MemoryBlockSource::new(vec![
                CompactBlock {
                    height: 10,
                    hash: first_hash.0.to_vec(),
                    prev_hash: anchor_hash.0.to_vec(),
                    ..Default::default()
                },
                CompactBlock {
                    height: 11,
                    hash: last_hash.0.to_vec(),
                    prev_hash: first_hash.0.to_vec(),
                    ..Default::default()
                },
            ]),
            from_state: chain::ChainState::empty(BlockHeight::from_u32(9), anchor_hash),
            canonical_end_hash_at_fetch: last_hash,
            synthetic_start_anchor: false,
        }
    }

    #[test]
    fn downloaded_batch_requires_matching_start_and_end_boundaries() {
        let mut batch = test_downloaded_batch();
        assert!(validate_downloaded_batch(
            &batch,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(12)
        )
        .is_ok());

        batch.canonical_end_hash_at_fetch = BlockHash([9; 32]);
        assert!(validate_downloaded_batch(
            &batch,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(12)
        )
        .unwrap_err()
        .contains("canonical end state"));

        let mut batch = test_downloaded_batch();
        batch.block_source = block_source::MemoryBlockSource::new(vec![
            zcash_client_backend::proto::compact_formats::CompactBlock {
                height: 10,
                hash: vec![1; 32],
                prev_hash: vec![7; 32],
                ..Default::default()
            },
            zcash_client_backend::proto::compact_formats::CompactBlock {
                height: 11,
                hash: vec![2; 32],
                prev_hash: vec![1; 32],
                ..Default::default()
            },
        ]);
        assert!(validate_downloaded_batch(
            &batch,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(12)
        )
        .unwrap_err()
        .contains("start state"));
    }

    #[test]
    fn prefetched_batch_rejects_a_reorged_end_state() {
        let batch = test_downloaded_batch();
        let same_fork =
            chain::ChainState::empty(BlockHeight::from_u32(11), batch.canonical_end_hash_at_fetch);
        let replacement_fork =
            chain::ChainState::empty(BlockHeight::from_u32(11), BlockHash([8; 32]));

        assert!(prefetched_batch_matches_state(&batch, &same_fork));
        assert!(!prefetched_batch_matches_state(&batch, &replacement_fork));
    }

    #[test]
    fn prefetch_budget_counts_estimated_decoded_memory() {
        assert!(can_spawn_prefetch(0, 1, 1_000, 0, 10, 100, 6_000));
        assert!(!can_spawn_prefetch(0, 1, 1_000, 0, 10, 100, 5_999));
        assert!(!can_spawn_prefetch(0, 1, 10_000, 0, 10_000, 10_000, 1));
        assert!(!can_spawn_prefetch(1, 1, 0, 0, 1, 1, u64::MAX));
    }

    #[test]
    fn sandblasting_floor_prevents_mobile_queue_overshoot() {
        let start = BlockHeight::from_u32(SANDBLASTING_START);
        let estimate = prefetch_wire_floor(start);
        let one_batch_blocks = BATCH_SIZE_SANDBLASTING as u64;
        assert!(can_spawn_prefetch(
            0,
            1,
            0,
            0,
            one_batch_blocks,
            estimate,
            32 * 1024 * 1024,
        ));
        assert!(!can_spawn_prefetch(
            1,
            1,
            0,
            one_batch_blocks,
            one_batch_blocks,
            estimate,
            32 * 1024 * 1024,
        ));
    }

    #[test]
    fn observed_dense_blocks_reduce_the_next_batch_size() {
        let start = BlockHeight::from_u32(SANDBLASTING_END + 100);
        let end = start + BATCH_SIZE_FOREGROUND;
        let normal = memory_bounded_batch_size(
            BATCH_SIZE_FOREGROUND,
            start,
            end,
            PREFETCH_WIRE_FLOOR_BYTES_PER_BLOCK,
            64 * 1024 * 1024,
        );
        let dense = memory_bounded_batch_size(
            BATCH_SIZE_FOREGROUND,
            start,
            end,
            256 * 1024,
            64 * 1024 * 1024,
        );

        assert_eq!(normal, BATCH_SIZE_FOREGROUND);
        assert!(dense < normal);
        assert!(dense > 0);
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
}
