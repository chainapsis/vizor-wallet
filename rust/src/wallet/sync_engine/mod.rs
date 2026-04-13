use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use rand::rngs::OsRng;
use zcash_client_backend::{
    data_api::{
        WalletRead, WalletWrite,
        chain::{self, error::Error as ChainError, scan_cached_blocks},
        scanning::ScanPriority,
    },
    proto::service::{BlockId, ChainSpec},
};
use zcash_client_sqlite::{WalletDb, error::SqliteClientError, util::SystemClock};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, Network};

mod block_source;
mod enhance;
mod error;
mod lwd;
pub(crate) mod mempool;

pub(crate) use error::SyncError;
use error::{RecoveryStrategy, MAX_REWINDS_PER_RUN};
use enhance::run_enhancement;
pub(crate) use lwd::open_lwd_channel;
use lwd::{download_blocks, download_subtree_roots};

/// Progress event sent to caller (Dart or Swift).
#[derive(Clone, Debug)]
pub struct SyncProgressEvent {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
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
const BATCH_SIZE_BACKGROUND: u32 = 100;

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

/// Sync-scoped elapsed time reference. Set at sync start.
static SYNC_START: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);

fn elapsed() -> String {
    SYNC_START.lock().ok()
        .and_then(|g| g.map(|t| format!("{:.1}s", t.elapsed().as_secs_f64())))
        .unwrap_or_default()
}

type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

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
    network: Network,
    cancel: Arc<AtomicBool>,
    running_mode: u8,
    desired_mode: &AtomicU8,
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
) -> Result<(), SyncError> {
    let base_batch_size = if running_mode == 2 { BATCH_SIZE_BACKGROUND } else { BATCH_SIZE_FOREGROUND };
    log::info!("[{}] sync: starting (mode={}, base_batch={})", elapsed(), running_mode, base_batch_size);

    // 1. Connect gRPC (plain TLS via tonic + webpki roots).
    let mut client = open_lwd_channel(lightwalletd_url).await?;

    // Open DB once — reused for the entire sync
    let mut db = open_db(db_data_path, network)?;

    // 2. Get chain tip. `current_tip_height` is updated by the
    // periodic refresh (TIP_REFRESH_INTERVAL) so that progress
    // events always reflect the latest known chain height, not the
    // one captured at sync start. The initial `tip` response is
    // also kept around for its other fields but `current_tip_height`
    // is the authoritative value for emitted events.
    let tip = client
        .get_latest_block(ChainSpec::default())
        .await
        .map_err(|e| SyncError::net(format!("get_latest_block: {e}")))?
        .into_inner();
    let mut current_tip_height: u64 = tip.height;
    let tip_height = BlockHeight::from_u32(tip.height as u32);
    log::info!("[{}] sync: chain tip = {}", elapsed(), tip.height);

    db.update_chain_tip(tip_height)
        .map_err(|e| SyncError::db(format!("update_chain_tip: {e}")))?;

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
        ranges.iter()
            .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
            .map(|r| u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64)
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
    type PrefetchResult = Result<
        crate::wallet::sync_engine::block_source::MemoryBlockSource,
        SyncError,
    >;
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
            match client
                .get_latest_block(ChainSpec::default())
                .await
                .map(|resp| resp.into_inner())
            {
                Ok(fresh_tip) => {
                    let fresh_height = BlockHeight::from_u32(fresh_tip.height as u32);
                    if let Err(e) = db.update_chain_tip(fresh_height) {
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

        let range = match ranges.iter().find(|r| {
            r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned
        }) {
            Some(r) => r.clone(),
            None => break, // Fully synced
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
                log::info!("[{}] sync: verify phase complete, entering main scan", elapsed());
            } else {
                log::info!("[{}] sync: entering main scan phase (no verify work)", elapsed());
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
        let batch_size = {
            let start_u32 = u32::from(start);
            let range_end_u32 = u32::from(range.block_range().end);
            // Overlap check: range [start, range_end) ∩ [SANDBLASTING_START, SANDBLASTING_END)
            if start_u32 < SANDBLASTING_END && range_end_u32 > SANDBLASTING_START {
                BATCH_SIZE_SANDBLASTING
            } else {
                base_batch_size
            }
        };
        let end = std::cmp::min(start + batch_size, range.block_range().end);
        log::info!(
            "[{}] sync: scanning {}-{} (priority {:?}{}, batch={})",
            elapsed(),
            u32::from(start),
            u32::from(end) - 1,
            range.priority(),
            if is_verify_phase { ", verify phase" } else { "" },
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
                        log::warn!(
                            "[{}] sync: prefetch failed, downloading fresh",
                            elapsed(),
                        );
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
            let ts = client
                .get_tree_state(BlockId { height: u32::from(start - 1) as u64, hash: vec![] })
                .await
                .map_err(|e| SyncError::net(format!("get_tree_state: {e}")))?
                .into_inner();
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
        let scan_result = scan_cached_blocks(
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
                    let target = BlockHeight::from_u32(to_height as u32);
                    let actual_rewind_height = match db.truncate_to_height(target) {
                        Ok(h) => h,
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
                            })?
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
                            return Err(SyncError::db(format!(
                                "truncate_to_height({requested_height}): no safe rewind height"
                            )));
                        }
                        Err(e) if is_sqlite_lock_contention(&e) => {
                            // Transient lock contention on the rewind. The
                            // outer retry wrapper will re-invoke run_sync_impl
                            // after a backoff, which re-detects the continuity
                            // error and triggers the rewind again. If the
                            // lock has cleared by then, the retry succeeds.
                            return Err(SyncError::other(format!(
                                "truncate_to_height({to_height}): SQLite lock contention: {e}"
                            )));
                        }
                        Err(e) => {
                            return Err(SyncError::db(format!(
                                "truncate_to_height({to_height}): {e}"
                            )));
                        }
                    };
                    log::info!(
                        "[{}] sync: {phase_name} rewound to {actual_rewind_height} after reorg \
                         (attempt {}/{}); restarting scan loop",
                        elapsed(),
                        *current_rewinds,
                        MAX_REWINDS_PER_RUN,
                    );
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
        run_enhancement(&mut client, &mut db, network).await?;

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
        match client
            .get_latest_block(ChainSpec::default())
            .await
            .map(|resp| resp.into_inner().height as u32)
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
                    match db.update_chain_tip(fresh_bh) {
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
        let remaining: u64 = post_ranges.iter()
            .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
            .map(|r| u32::from(r.block_range().end).saturating_sub(u32::from(r.block_range().start)) as u64)
            .sum();
        // Adjust initial_total if new ranges appeared (e.g. new account added mid-sync).
        // Use scanned + remaining as the true total, so progress never goes backward.
        let scanned_so_far = initial_total.saturating_sub(prev_remaining);
        let new_total = scanned_so_far + remaining;
        if new_total > initial_total {
            log::info!("[{}] sync: new scan ranges detected, adjusted total {} -> {}", elapsed(), initial_total, new_total);
            initial_total = new_total;
        }
        prev_remaining = remaining;
        let pct = if initial_total > 0 { 1.0 - (remaining as f64 / initial_total as f64) } else { 1.0 };
        let progress = SyncProgressEvent {
            scanned_height: u32::from(end) as u64,
            chain_tip_height: current_tip_height,
            percentage: pct.clamp(0.0, 1.0),
            is_syncing: true,
            is_complete: false,
            has_new_tx,
            phase: "scan".into(),
        };
        log::info!("[{}] sync: {:.1}% (remaining={}/{}, scanned={})", elapsed(), pct * 100.0, remaining, initial_total, initial_total - remaining);
        progress_fn(progress);

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
            let pf_batch = {
                let s = u32::from(pf_start);
                let re = u32::from(range.block_range().end);
                if s < SANDBLASTING_END && re > SANDBLASTING_START {
                    BATCH_SIZE_SANDBLASTING
                } else {
                    base_batch_size
                }
            };
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

    log::info!("[{}] sync: completed", elapsed());
    // Final progress
    let final_progress = SyncProgressEvent {
        scanned_height: current_tip_height,
        chain_tip_height: current_tip_height,
        percentage: 1.0,
        is_syncing: false,
        is_complete: true,
        has_new_tx: false,
        phase: String::new(),
    };
    progress_fn(final_progress);

    Ok(())
}

// ==================== Helpers ====================

fn open_db(path: &str, network: Network) -> Result<WalletDatabase, SyncError> {
    WalletDb::for_path(path, network, SystemClock, OsRng)
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
        let block_conflict =
            SqliteClientError::BlockConflict(zcash_protocol::consensus::BlockHeight::from_u32(2_500_000));
        assert!(!is_sqlite_lock_contention(&block_conflict));
    }
}
