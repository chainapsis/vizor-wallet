//! Background observer for lightwalletd's `GetMempoolStream`.
//!
//! The block-scan loop in `sync_engine::mod` catches wallet-related
//! transactions at the granularity of a block batch — fast enough
//! for most flows, but always *after* the tx has been mined. This
//! observer closes that gap for outbound sends: as soon as
//! lightwalletd relays the wallet's own transaction back through
//! its mempool stream, we emit a `MempoolTxEvent { matched: true }`
//! and the Dart side refreshes balance + history without waiting
//! for the next block.
//!
//! Design choices:
//!
//!   * **Parallel to sync, not inside it.** The observer runs as an
//!     independent tokio task with its own lifecycle, matching the
//!     `startObservingMempool()` coroutine in
//!     zcash-android-wallet-sdk's `CompactBlockProcessor.kt`. This
//!     means the sync loop's progress isn't held up by mempool
//!     traffic, and the observer can keep running across sync
//!     iterations.
//!
//!   * **Dedicated lwd channel.** We never share the sync loop's
//!     gRPC client — long-running bidi streams don't play well with
//!     a channel that is simultaneously driving unary / server-
//!     streaming calls for compact blocks. Each reconnect opens a
//!     fresh channel via [`super::open_lwd_channel`], which also
//!     means we inherit the same Tor-or-plain-TLS transport choice
//!     the scan loop uses (see `api::sync::USE_TOR`).
//!
//!   * **Read-only DB access.** V1 of the observer does *not* call
//!     `decrypt_and_store_transaction`. It parses the raw bytes
//!     just far enough to get the txid, then checks whether that
//!     txid already exists in the wallet's `transactions` table
//!     with `mined_height IS NULL`. That is enough to power the
//!     "outbound tx just hit mempool" UX without racing against
//!     the sync loop's writes. A future v2 can re-add decryption
//!     for earlier discovery of *inbound* txs at the cost of
//!     handling SQLite write contention more carefully.
//!
//!   * **Reconnect semantics match the SDK.** lightwalletd closes
//!     the stream every time a new block is mined — normal EOF,
//!     not an error. We treat that as "sleep 1s, reconnect". Real
//!     errors use a 1s / 30s backoff ladder (first failure: 1s,
//!     subsequent consecutive failures: 30s), reset to zero on any
//!     successful connect. Cancel is checked inside the sleep so
//!     we don't block `stop_mempool_observer()` for 30s.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use zcash_client_backend::proto::service::RawTransaction;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BranchId, Network};

use super::lwd::start_mempool_stream;
use super::open_lwd_channel;

/// Event emitted by [`run_mempool_observer`] for every transaction
/// arriving on the mempool stream that we can parse.
///
/// `matched` is `true` when the txid is already known to the wallet
/// DB with `mined_height IS NULL` — i.e. an outbound send that the
/// network just relayed back to us, or any previously-recorded
/// pending tx that's still in the mempool. Dart consumers use
/// that flag to decide whether to trigger a balance refresh.
#[derive(Clone, Debug)]
pub struct MempoolTxEvent {
    /// Lower-case hex of the txid (stable across consumers).
    pub txid_hex: String,
    /// Whether the txid corresponds to a row in the wallet's
    /// `transactions` table with `mined_height IS NULL`.
    pub matched: bool,
}

/// Run the mempool observer until `cancel` is set.
///
/// This is an infinite-retry loop. Every iteration:
///
///   1. Opens a fresh lwd channel (inheriting Tor/plain-TLS from
///      the current `USE_TOR` atomic).
///   2. Starts a `GetMempoolStream` RPC.
///   3. Consumes incoming [`RawTransaction`]s until the stream
///      closes or errors out.
///   4. Sleeps according to the backoff ladder, then loops.
///
/// Returns `Ok(())` when `cancel` is set. Returns `Err(_)` only
/// for unrecoverable setup errors (network type, etc.) that the
/// outer task can't do anything about — network / gRPC failures
/// are handled inside the retry loop and never surface as `Err`.
///
/// `emit` is called once per successfully-parsed mempool tx. The
/// closure runs on the tokio task driving this observer, so any
/// heavy work inside `emit` blocks the next mempool tx from being
/// processed; the Dart-facing FRB wrapper forwards to a
/// `StreamSink` which is effectively a non-blocking push.
pub(crate) async fn run_mempool_observer<F>(
    db_path: String,
    _network: Network,
    lightwalletd_url: String,
    cancel: Arc<AtomicBool>,
    emit: F,
) -> Result<(), String>
where
    F: Fn(MempoolTxEvent) + Send + Sync,
{
    const INITIAL_BACKOFF: Duration = Duration::from_secs(1);
    const LATER_BACKOFF: Duration = Duration::from_secs(30);

    let mut consecutive_errors: u32 = 0;

    loop {
        if cancel.load(Ordering::Relaxed) {
            log::info!("mempool: observer cancelled");
            return Ok(());
        }

        // Open a fresh lwd channel for this stream attempt.
        let (mut client, _tor_guard) = match open_lwd_channel(&lightwalletd_url).await {
            Ok(pair) => pair,
            Err(e) => {
                log::warn!("mempool: open_lwd_channel failed: {e}");
                consecutive_errors += 1;
                let delay = if consecutive_errors <= 1 {
                    INITIAL_BACKOFF
                } else {
                    LATER_BACKOFF
                };
                sleep_respecting_cancel(delay, &cancel).await;
                continue;
            }
        };

        // Start the mempool stream.
        let mut stream = match start_mempool_stream(&mut client).await {
            Ok(s) => s,
            Err(e) => {
                log::warn!("mempool: start_mempool_stream failed: {e}");
                consecutive_errors += 1;
                let delay = if consecutive_errors <= 1 {
                    INITIAL_BACKOFF
                } else {
                    LATER_BACKOFF
                };
                sleep_respecting_cancel(delay, &cancel).await;
                continue;
            }
        };

        log::info!("mempool: observer connected");
        consecutive_errors = 0;

        // Consume the stream until EOF or error.
        loop {
            if cancel.load(Ordering::Relaxed) {
                log::info!("mempool: observer cancelled mid-stream");
                return Ok(());
            }
            match stream.message().await {
                Ok(Some(raw_tx)) => {
                    handle_mempool_tx(&db_path, &raw_tx, &emit);
                }
                Ok(None) => {
                    // Clean EOF. lightwalletd documents this as
                    // the normal case when a new block is mined
                    // (see comment on `start_mempool_stream`).
                    // Sleep briefly and reconnect without
                    // incrementing the error counter.
                    log::debug!("mempool: stream closed by server (new block?)");
                    break;
                }
                Err(e) => {
                    log::warn!("mempool: stream error: {e}");
                    consecutive_errors += 1;
                    break;
                }
            }
        }

        // Short sleep before reconnect. Cancel-aware.
        sleep_respecting_cancel(INITIAL_BACKOFF, &cancel).await;
    }
}

/// Parse `raw_tx`, compute the txid, check whether the wallet DB
/// knows about it as an unmined entry, and emit a
/// [`MempoolTxEvent`]. All failures are logged and swallowed — one
/// un-parseable tx must not break the observer loop.
fn handle_mempool_tx<F>(db_path: &str, raw_tx: &RawTransaction, emit: &F)
where
    F: Fn(MempoolTxEvent),
{
    // Parse far enough to get the txid. `BranchId::Sapling` matches
    // what the sync loop's enhance path uses; any new-network-era
    // txs that fail parse here would also fail there and surface
    // via the regular scan instead.
    let tx = match Transaction::read(&raw_tx.data[..], BranchId::Sapling) {
        Ok(t) => t,
        Err(e) => {
            log::debug!("mempool: Transaction::read failed: {e}");
            return;
        }
    };
    let txid = tx.txid();
    let txid_hex = format!("{txid}");
    let txid_bytes = txid.as_ref().to_vec();

    let matched = match is_known_pending_txid(db_path, &txid_bytes) {
        Ok(b) => b,
        Err(e) => {
            log::debug!("mempool: DB lookup for {txid_hex} failed: {e}");
            false
        }
    };

    log::debug!("mempool: tx {txid_hex} matched={matched}");
    emit(MempoolTxEvent { txid_hex, matched });
}

/// Read-only check: does the wallet know about this txid as an
/// unmined transaction? One SELECT against `transactions`, no
/// joins, no write lock — safe to run concurrently with the sync
/// loop's writes.
fn is_known_pending_txid(db_path: &str, txid_bytes: &[u8]) -> Result<bool, String> {
    use rusqlite::OptionalExtension;

    let conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .map_err(|e| format!("open DB: {e}"))?;

    let found: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM transactions WHERE txid = ?1 AND mined_height IS NULL LIMIT 1",
            [txid_bytes],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("query: {e}"))?;

    Ok(found.is_some())
}

/// Cancel-aware sleep. Breaks into 100ms slices so a pending
/// cancel is noticed within that window instead of waiting for
/// the full duration.
async fn sleep_respecting_cancel(duration: Duration, cancel: &Arc<AtomicBool>) {
    let start = Instant::now();
    while start.elapsed() < duration {
        if cancel.load(Ordering::Relaxed) {
            return;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

