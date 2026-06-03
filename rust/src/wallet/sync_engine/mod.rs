use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use nonempty::NonEmpty;
use shardtree::error::{InsertionError, ShardTreeError};
use tonic::transport::Channel;
use zcash_client_backend::{
    data_api::{
        chain::{self, error::Error as ChainError, scan_cached_blocks},
        scanning::{ScanPriority, ScanRange},
        wallet::ConfirmationsPolicy,
        WalletCommitmentTrees, WalletRead, WalletWrite,
    },
    proto::service,
};
use zcash_client_sqlite::error::SqliteClientError;
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        SYNC_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

use {
    ::transparent::{
        address::Script,
        bundle::{OutPoint, TxOut},
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
    get_latest_block, get_transaction, open_lwd_channel, send_transaction,
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

const SAPLING_ACTIVATION_HEIGHT: u32 = 419200;
const MAX_WITNESS_REPAIR_PASSES_PER_RUN: u32 = 3;
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

    if db_tip_height < current_tip_height {
        return Err(SyncError::continuity(
            current_tip_height,
            format!(
                "sync completion blocked: wallet DB chain tip {db_tip_height} \
                 lags lightwalletd tip {current_tip_height}"
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

fn queue_witness_repairs_if_needed(
    db: &mut WalletDatabase,
    current_tip_height: u64,
    repair_passes_this_run: &mut u32,
) -> Result<Option<u64>, SyncError> {
    let rescan_ranges = with_wallet_db_write_lock("sync_engine.check_witnesses", || {
        db.check_witnesses()
            .map_err(|e| SyncError::db(format!("check_witnesses: {e}")))
    })?;

    let Some(nonempty_ranges) = NonEmpty::from_vec(rescan_ranges) else {
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
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), SyncError> {
    for account_id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(format!("get_account_ids: {e}")))?
    {
        let start_height = db
            .utxo_query_height(account_id)
            .map_err(|e| SyncError::db(format!("utxo_query_height: {e}")))?;
        let addresses: Vec<String> = db
            .get_transparent_receivers(account_id, true, true)
            .map_err(|e| SyncError::db(format!("get_transparent_receivers: {e}")))?
            .into_keys()
            .map(|addr| addr.encode(&network))
            .collect();

        if !addresses.is_empty() {
            refresh_transparent_addresses(client, db, addresses, start_height, "transparent UTXOs")
                .await?;
        }
    }

    Ok(())
}

async fn refresh_transparent_addresses(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    addresses: Vec<String>,
    start_height: BlockHeight,
    label: &str,
) -> Result<(), SyncError> {
    if addresses.is_empty() {
        return Ok(());
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
    }

    Ok(())
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

    // Match the cancellation granularity we already use for
    // `run_enhancement`: let this stage run to completion once it has
    // started, but don't enter it (or continue past it) after a
    // cancel/mode change has already been observed.
    if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
        log::info!(
            "[{}] sync: cancel/mode observed before transparent UTXO refresh, skipping",
            elapsed(),
        );
        return Ok(());
    }

    refresh_utxos(&mut client, &mut db, network).await?;

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

    // Phase-transition markers used only for logging. Progress through the
    // scan queue is implicitly ordered by `ScanPriority::Verify` >
    // everything else, so an explicit state machine isn't needed — we just
    // log when we first see a verify range and when we first see a
    // non-verify range so diagnosis of a reorg-heavy sync is easier.
    let mut verify_phase_announced = false;
    let mut main_phase_announced = false;

    /// If the scan loop has been running longer than this without
    /// refreshing the chain tip from lightwalletd, we re-fetch
    /// the tip and call `update_chain_tip` so that
    /// `suggest_scan_ranges` incorporates any new blocks that
    /// appeared while the wallet was catching up.
    ///
    /// Matches zcash-android-wallet-sdk's
    /// `SYNCHRONIZATION_RESTART_TIMEOUT = 10.minutes`
    /// (CompactBlockProcessor.kt:1197). We don't restart the
    /// whole sync like the SDK does — just refreshing the tip is
    /// enough because our `suggest_scan_ranges` call at the top
    /// of each loop iteration already reflects the new tip once
    /// `update_chain_tip` has written it to the DB.
    const TIP_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(600);
    let mut last_tip_refresh = std::time::Instant::now();

    // Prefetched block source from the previous iteration.
    // When the scan loop processes a range that spans multiple batches,
    // we kick off a background download of the next batch while running
    // enhancement / resubmit / progress reporting for the current
    // batch. This overlaps network I/O (download) with CPU-bound
    // work (enhancement) and unrelated gRPC calls (resubmit), matching
    // the SDK's `.buffer(1)` pipelining pattern in
    // `CompactBlockProcessor.kt:1666`.
    //
    // `None` on the first iteration and whenever the previous batch
    // was the last in its range (so there's nothing to prefetch until
    // `suggest_scan_ranges` runs again).
    type PrefetchResult =
        Result<crate::wallet::sync_engine::block_source::MemoryBlockSource, SyncError>;
    /// Prefetched block download state. Implements `Drop` to
    /// abort the spawned tokio task when the loop exits for any
    /// reason (cancel, mode change, error, break, reorg
    /// `continue`) so detached downloads can't outlive the sync
    /// session and leak network traffic after shutdown.
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
    let mut prefetch: Option<Prefetch> = None;

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
                    &mut db,
                    current_tip_height,
                    &mut witness_repair_passes_this_run,
                )? {
                    initial_total = repair_pending_blocks;
                    prev_remaining = repair_pending_blocks;
                    prefetch = None;
                    continue;
                } else if let Some(repair_pending_blocks) = repair_anchor_root_mismatch_if_needed(
                    &mut client,
                    &mut db,
                    current_tip_height,
                    &mut anchor_root_repair_passes_this_run,
                )
                .await?
                {
                    initial_total = repair_pending_blocks;
                    prev_remaining = repair_pending_blocks;
                    prefetch = None;
                    continue;
                } else {
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
        let batch_size = batch_size_for_range(base_batch_size, start, range.block_range().end);
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

        // Download blocks into memory — or use the prefetched data
        // from the previous iteration if it matches this batch.
        let block_source = if let Some(mut pf) = prefetch.take() {
            if pf.start == start && pf.end == end {
                // Prefetch matches. Take the handle out of the
                // Option so Drop doesn't abort a completed task.
                let handle = pf.handle.take().expect("prefetch handle present");
                match handle.await {
                    Ok(Ok(bs)) => {
                        log::debug!(
                            "[{}] sync: using prefetched blocks for {}-{}",
                            elapsed(),
                            u32::from(start),
                            u32::from(end) - 1,
                        );
                        bs
                    }
                    _ => {
                        // Prefetch failed — download synchronously.
                        log::warn!("[{}] sync: prefetch failed, downloading fresh", elapsed(),);
                        download_blocks(&mut client, start, end - 1).await?
                    }
                }
            } else {
                // Range changed (reorg, priority switch, etc.) —
                // Drop the Prefetch, which aborts the background task.
                drop(pf);
                download_blocks(&mut client, start, end - 1).await?
            }
        } else {
            download_blocks(&mut client, start, end - 1).await?
        };

        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after download", elapsed());
            return Ok(());
        }

        // Get tree state
        let from_state = if u32::from(start) <= SAPLING_ACTIVATION_HEIGHT {
            chain::ChainState::empty(start - 1, BlockHash([0u8; 32]))
        } else {
            let ts = get_tree_state(&mut client, u32::from(start - 1) as u64).await?;
            ts.to_chain_state()
                .map_err(|e| SyncError::parse(format!("parse tree state: {e}")))?
        };

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
        let scan_result = with_wallet_db_write_lock("sync_engine.scan_cached_blocks", || {
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
                    prefetch = None;
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

        // Enhancement
        run_enhancement(&mut client, &mut db, db_data_path, network).await?;

        // Post-batch auto-resubmit. Matches zcash-android-wallet-sdk's
        // lines 593/701 call sites (end of verify batch / end of
        // regular batch).
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
        match get_latest_block(&mut client)
            .await
            .map(|tip| tip.height as u32)
        {
            Ok(fresh_tip_height) => {
                // Promote the fresh tip to the authoritative value
                // so progress events and the final completion event
                // use the latest chain height, not the one from
                // sync startup. Also update the DB so
                // suggest_scan_ranges picks up any new blocks that
                // appeared since the initial (or last periodic) tip
                // fetch.
                //
                // IMPORTANT: update_chain_tip MUST succeed before
                // we bump current_tip_height. If the DB write fails,
                // suggest_scan_ranges still operates on the old tip
                // and the loop may break with isComplete=true —
                // bumping current_tip_height prematurely would make
                // the completion event claim a height the wallet
                // never actually scanned. (Codex 3rd-round finding.)
                if (fresh_tip_height as u64) > current_tip_height {
                    let fresh_bh = BlockHeight::from_u32(fresh_tip_height);
                    match with_wallet_db_write_lock(
                        "sync_engine.update_chain_tip.post_batch",
                        || db.update_chain_tip(fresh_bh),
                    ) {
                        Ok(_) => {
                            current_tip_height = fresh_tip_height as u64;
                        }
                        Err(e) => {
                            log::warn!(
                                "[{}] sync: post-batch update_chain_tip({fresh_tip_height}) \
                                 failed, keeping tip at {current_tip_height}: {e}",
                                elapsed(),
                            );
                        }
                    }
                }
                let _ = crate::wallet::sync::resubmit_pending_transactions(
                    db_data_path,
                    &mut client,
                    fresh_tip_height,
                    || {
                        cancel.load(Ordering::Relaxed)
                            || desired_mode.load(Ordering::SeqCst) != running_mode
                    },
                )
                .await;
            }
            Err(e) => {
                log::warn!(
                    "[{}] sync: resubmit tip refresh failed, skipping pass: {e}",
                    elapsed(),
                );
            }
        }
        if cancel.load(Ordering::Relaxed) || desired_mode.load(Ordering::SeqCst) != running_mode {
            log::info!("[{}] sync: exiting after resubmit pass", elapsed());
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
                let next_batch_size =
                    batch_size_for_range(base_batch_size, next_start, r.block_range().end);
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

        // Prefetch: if the current range still has blocks beyond
        // `end`, kick off a background download of the next batch
        // now, while the next loop iteration does suggest_scan_ranges
        // + phase bookkeeping + (potentially) enhancement for the
        // batch we just finished. The download runs on a cloned
        // gRPC client so it doesn't conflict with the main client's
        // unary RPCs (tree_state, get_latest_block, etc.).
        //
        // When the range is exhausted (end == range.end), we skip
        // the prefetch — the next range comes from
        // suggest_scan_ranges() which needs the DB state the current
        // scan just committed, and we can't predict it in advance.
        if end < range.block_range().end && !cancel.load(Ordering::Relaxed) {
            let pf_start = end;
            // Recompute batch_size for the prefetch range in case
            // it crosses a sandblasting boundary differently.
            let pf_batch = batch_size_for_range(base_batch_size, pf_start, range.block_range().end);
            let pf_end = std::cmp::min(pf_start + pf_batch, range.block_range().end);
            let mut pf_client = client.clone();
            prefetch = Some(Prefetch {
                start: pf_start,
                end: pf_end,
                handle: Some(tokio::spawn(async move {
                    download_blocks(&mut pf_client, pf_start, pf_end - 1).await
                })),
            });
        }
    }

    let (final_scanned_height, final_tip_height) =
        ensure_complete_scan_state(&db, current_tip_height)?;
    log::info!(
        "[{}] sync: completed (fully_scanned={}, chain_tip={})",
        elapsed(),
        final_scanned_height,
        final_tip_height,
    );
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
