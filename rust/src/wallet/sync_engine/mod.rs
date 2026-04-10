use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;

use rand::rngs::OsRng;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use zcash_client_backend::{
    data_api::{
        WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{self, error::Error as ChainError, scan_cached_blocks, CommitmentTreeRoot},
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
use zcash_client_sqlite::{WalletDb, error::SqliteClientError, util::SystemClock};
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, Network};

mod error;

pub(crate) use error::{SyncError, RecoveryStrategy, REWIND_DISTANCE, MAX_REWINDS_PER_RUN};

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

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const BATCH_SIZE_FOREGROUND: u32 = 300;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
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
    let batch_size = if running_mode == 2 { BATCH_SIZE_BACKGROUND } else { BATCH_SIZE_FOREGROUND };
    log::info!("[{}] sync: starting (mode={}, batch={})", elapsed(), running_mode, batch_size);

    // 1. Connect gRPC. `_tor_guard` keeps the isolated Tor circuit
    //    alive for the rest of this function when Tor is enabled, and
    //    is `None` in the plain-TLS case. Do not move it into a
    //    sub-scope — its lifetime must match `client`'s.
    let (mut client, _tor_guard) = open_lwd_channel(lightwalletd_url).await?;

    // Open DB once — reused for the entire sync
    let mut db = open_db(db_data_path, network)?;

    // 2. Get chain tip
    let tip = client
        .get_latest_block(ChainSpec::default())
        .await
        .map_err(|e| SyncError::net(format!("get_latest_block: {e}")))?
        .into_inner();
    let tip_height = BlockHeight::from_u32(tip.height as u32);
    log::info!("[{}] sync: chain tip = {}", elapsed(), tip.height);

    db.update_chain_tip(tip_height)
        .map_err(|e| SyncError::db(format!("update_chain_tip: {e}")))?;

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
        let end = std::cmp::min(start + batch_size, range.block_range().end);
        log::info!(
            "[{}] sync: scanning {}-{} (priority {:?}{})",
            elapsed(),
            u32::from(start),
            u32::from(end) - 1,
            range.priority(),
            if is_verify_phase { ", verify phase" } else { "" },
        );

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

fn open_db(path: &str, network: Network) -> Result<WalletDatabase, SyncError> {
    WalletDb::for_path(path, network, SystemClock, OsRng)
        .map_err(|e| SyncError::db(format!("DB open: {e}")))
}

/// Drop guard keeping the Tor circuit alive for a lightwalletd
/// connection opened via `open_lwd_channel`. `None` for the plain-TLS
/// path; `Some(_)` for the Tor path. Callers must bind this alongside
/// the returned client so the guard lives as long as the client does.
pub(crate) type LwdTorGuard = Option<crate::wallet::tor::IsolatedCircuitGuard>;

/// Opens a tonic gRPC channel to the given lightwalletd URL and returns
/// `(client, tor_guard)`. Branches on the `USE_TOR` atomic in
/// `api::sync`: if enabled, the connection is routed through an
/// isolated Tor circuit via `wallet::tor::connect_lightwalletd`, and
/// `tor_guard` carries the `IsolatedCircuitGuard` that must stay alive
/// for as long as the returned client. If disabled, the connection
/// goes through plain tonic TLS and `tor_guard` is `None`.
///
/// Callers bind both results into `let` statements at function scope:
///
/// ```ignore
/// let (mut client, _tor_guard) = open_lwd_channel(url).await?;
/// // use `client` as before; `_tor_guard` just lives alongside it.
/// ```
///
/// Callers outside this module still surface the `SyncError` as a
/// `String` via `.map_err(|e| e.to_string())`; the crate's public FRB
/// surface returns `Result<_, String>` for FFI compat.
pub(crate) async fn open_lwd_channel(
    lightwalletd_url: &str,
) -> Result<(CompactTxStreamerClient<Channel>, LwdTorGuard), SyncError> {
    // `SeqCst` pairs with the `SeqCst` store in
    // `api::sync::set_tor_enabled`. A `Relaxed` load here would let a
    // concurrent reader on ARM observe the stale pre-toggle value and
    // legally pick the wrong transport for this connection, which is
    // exactly the privacy-boundary race the Tor toggle is supposed to
    // prevent. Use the same ordering on both ends.
    if crate::api::sync::USE_TOR.load(Ordering::SeqCst) {
        let tor_dir = crate::api::sync::get_tor_dir().map_err(SyncError::net)?;
        let (client, guard) =
            crate::wallet::tor::connect_lightwalletd(tor_dir, lightwalletd_url).await?;
        log::info!("sync: lightwalletd connected via Tor");
        Ok((client, Some(guard)))
    } else {
        let channel = Endpoint::from_shared(lightwalletd_url.to_string())
            .map_err(|e| SyncError::net(format!("invalid URL: {e}")))?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| SyncError::net(format!("TLS error: {e}")))?
            .connect()
            .await
            .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?;
        Ok((CompactTxStreamerClient::new(channel), None))
    }
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


async fn download_subtree_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
) -> Result<(), SyncError> {
    let (sap_start, orch_start) = {
        let summary = db
            .get_wallet_summary(ConfirmationsPolicy::default())
            .map_err(|e| SyncError::db(format!("get_wallet_summary: {e}")))?;
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
        .map_err(|e| SyncError::net(format!("sapling subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("sapling subtree roots stream: {e}")))?
    {
        // `SubtreeRoot::root_hash` is `bytes = "vec"` in the proto, not a
        // fixed-length field. A slice expression like `root_hash[..32]`
        // would panic before `try_into()` runs if the server sent fewer
        // than 32 bytes, so convert from the full buffer via `as_slice`
        // and let `try_into` reject both short and long payloads.
        let bytes: [u8; 32] = root
            .root_hash
            .as_slice()
            .try_into()
            .map_err(|_| {
                SyncError::parse(format!(
                    "sapling subtree root: expected 32 bytes, got {}",
                    root.root_hash.len()
                ))
            })?;
        let node = Option::from(sapling_crypto::Node::from_bytes(bytes))
            .ok_or_else(|| SyncError::parse("sapling subtree root: bad node bytes".to_string()))?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    log::info!("[{}] sync: downloaded {} sapling subtree roots", elapsed(), roots.len());
    if !roots.is_empty() {
        db.put_sapling_subtree_roots(sap_start, roots.as_slice())
            .map_err(|e| SyncError::db(format!("put_sapling_subtree_roots: {e}")))?;
    }

    // Orchard
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: orch_start as u32,
            shielded_protocol: service::ShieldedProtocol::Orchard.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| SyncError::net(format!("orchard subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("orchard subtree roots stream: {e}")))?
    {
        let bytes: [u8; 32] = root
            .root_hash
            .as_slice()
            .try_into()
            .map_err(|_| {
                SyncError::parse(format!(
                    "orchard subtree root: expected 32 bytes, got {}",
                    root.root_hash.len()
                ))
            })?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes))
            .ok_or_else(|| SyncError::parse("orchard subtree root: bad node bytes".to_string()))?;
        roots.push(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(root.completing_block_height as u32), node));
    }
    log::info!("[{}] sync: downloaded {} orchard subtree roots", elapsed(), roots.len());
    if !roots.is_empty() {
        db.put_orchard_subtree_roots(orch_start, roots.as_slice())
            .map_err(|e| SyncError::db(format!("put_orchard_subtree_roots: {e}")))?;
    }

    log::info!("[{}] sync: subtree roots done", elapsed());
    Ok(())
}

async fn download_blocks(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
) -> Result<MemoryBlockSource, SyncError> {
    let mut stream = client
        .get_block_range(BlockRange {
            start: Some(BlockId { height: u32::from(start) as u64, hash: vec![] }),
            end: Some(BlockId { height: u32::from(end) as u64, hash: vec![] }),
        })
        .await
        .map_err(|e| SyncError::net(format!("get_block_range: {e}")))?
        .into_inner();

    let mut blocks = Vec::new();
    while let Some(block) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("get_block_range stream: {e}")))?
    {
        blocks.push(block);
    }

    Ok(MemoryBlockSource { blocks })
}

async fn run_enhancement(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    network: Network,
) -> Result<(), SyncError> {
    let mut failed_txids = std::collections::HashSet::new();

    for _ in 0..3 {
        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests: {e}")))?;
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
