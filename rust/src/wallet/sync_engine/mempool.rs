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

        // Consume the stream until EOF, error, or cancel.
        //
        // The naive version of this loop — `loop { if cancel { bail }
        // else stream.message().await }` — only notices a cancel
        // *between* stream messages. In practice lightwalletd
        // closes the mempool stream only when a new block is
        // mined, which on Zcash mainnet is ~75s per block. That
        // means a `stop_mempool_observer()` call can take up to
        // ~75s to actually take effect while we're blocked inside
        // `stream.message().await`, and the Dart-side 5s wait
        // loop in `restartSync` times out long before the
        // observer actually releases. The next `startSync` then
        // sees the old observer still running and skips starting
        // a new one — the exact regression Codex 3rd-round review
        // flagged.
        //
        // `tokio::select!` fixes this: we race the gRPC read
        // against a 100ms cancel poll, and when the cancel poll
        // wins we drop the in-flight `message()` future. Dropping
        // a tonic streaming future cancels the underlying HTTP/2
        // read, so teardown is bounded by the poll cadence rather
        // than by the server's next block boundary.
        let stream_exit = loop {
            tokio::select! {
                // Bias toward the cancel branch so a cancel that
                // fires while `message()` is already ready still
                // takes priority. This avoids consuming one more
                // mempool tx after the user pressed stop.
                biased;
                _ = watch_for_cancel(&cancel) => {
                    log::info!("mempool: observer cancelled mid-stream");
                    return Ok(());
                }
                msg = stream.message() => {
                    match msg {
                        Ok(Some(raw_tx)) => {
                            handle_mempool_tx(&db_path, &raw_tx, &emit);
                        }
                        Ok(None) => {
                            // Clean EOF. lightwalletd documents this
                            // as the normal case when a new block is
                            // mined (see the comment on
                            // `start_mempool_stream`). Reconnect
                            // without bumping the error counter.
                            log::debug!(
                                "mempool: stream closed by server (new block?)"
                            );
                            break StreamExit::CleanEof;
                        }
                        Err(e) => {
                            log::warn!("mempool: stream error: {e}");
                            consecutive_errors += 1;
                            break StreamExit::Error;
                        }
                    }
                }
            }
        };

        // Drop the stream before the reconnect sleep so the old
        // HTTP/2 read is torn down promptly. (The select arm that
        // broke us out already cancelled the in-flight `message`,
        // but the `Streaming<T>` value itself still holds the
        // tonic channel state; letting it live through the sleep
        // would keep the server-side subscription alive a bit
        // longer than necessary.)
        drop(stream);
        let _ = stream_exit;

        // Short sleep before reconnect. Cancel-aware.
        sleep_respecting_cancel(INITIAL_BACKOFF, &cancel).await;
    }
}

/// Why the inner `tokio::select!` loop broke out of its stream
/// consumption. Used only for its symbol — the outer loop
/// currently treats clean EOF and tonic errors identically
/// (reconnect with 1s backoff for EOF, 1s/30s ladder for errors
/// is governed by `consecutive_errors` instead), but keeping
/// the enum makes future "EOF is normal / error backs off more
/// aggressively" tweaks a local change instead of a signature
/// churn.
enum StreamExit {
    CleanEof,
    Error,
}

/// Returns when `cancel` flips to `true`. Used inside the
/// observer's `tokio::select!` so a cancel arriving while the
/// tonic stream is blocked inside `message().await` preempts
/// the read within at most 100ms instead of waiting for the
/// server's next block-boundary EOF.
async fn watch_for_cancel(cancel: &Arc<AtomicBool>) {
    loop {
        if cancel.load(Ordering::Relaxed) {
            return;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
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

#[cfg(test)]
mod tests {
    //! Unit tests for the mempool observer's DB-facing helpers and
    //! its cancel-aware sleep.
    //!
    //! We can't unit-test `run_mempool_observer` itself without a
    //! live lightwalletd — that's integration-test territory. What
    //! we *can* test in isolation is:
    //!
    //!   * `is_known_pending_txid`, the read-only predicate that
    //!     decides whether each parsed mempool tx sets
    //!     `matched = true`. Its SQL has to stay in sync with the
    //!     `transactions` table shape and the "unmined" definition
    //!     (`mined_height IS NULL`).
    //!
    //!   * `sleep_respecting_cancel`, which must (a) return early
    //!     when `cancel` flips and (b) at minimum sleep through the
    //!     requested duration when `cancel` stays false. Both
    //!     properties are load-bearing for the reconnect loop's
    //!     responsiveness.
    use super::*;
    use tempfile::NamedTempFile;

    /// Create a throwaway SQLite database with a stand-in
    /// `transactions` table. `zcash_client_sqlite` stores far more
    /// columns here than we query, so we only materialize the ones
    /// `is_known_pending_txid` actually reads.
    fn fresh_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 txid BLOB NOT NULL,
                 mined_height INTEGER
             );",
        )
        .unwrap();
        file
    }

    fn insert_tx(db: &NamedTempFile, txid: &[u8], mined_height: Option<i64>) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, ?2)",
            rusqlite::params![txid, mined_height],
        )
        .unwrap();
    }

    #[test]
    fn is_known_pending_txid_finds_unmined_tx() {
        let db = fresh_db();
        let txid = [0x01u8; 32];
        insert_tx(&db, &txid, None);
        let found = is_known_pending_txid(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(found, "unmined tx in DB must register as known pending");
    }

    #[test]
    fn is_known_pending_txid_ignores_mined_tx() {
        // The whole point of the "unmined" filter: if sync already
        // settled this tx into a block, we don't care that it's
        // bouncing around the mempool (shouldn't be anyway, but
        // lightwalletd can briefly relay stale mined txs).
        let db = fresh_db();
        let txid = [0x02u8; 32];
        insert_tx(&db, &txid, Some(2_500_000));
        let found = is_known_pending_txid(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(!found, "mined tx must NOT count as known pending");
    }

    #[test]
    fn is_known_pending_txid_handles_unknown_tx() {
        let db = fresh_db();
        let known_txid = [0x03u8; 32];
        let unknown_txid = [0x04u8; 32];
        insert_tx(&db, &known_txid, None);
        let found = is_known_pending_txid(db.path().to_str().unwrap(), &unknown_txid).unwrap();
        assert!(!found, "txid not in DB must return false");
    }

    #[test]
    fn is_known_pending_txid_handles_empty_db() {
        // Baseline: cold wallet with no txs at all still returns Ok(false),
        // not an error. The observer's fall-through branch relies on
        // this — a missing-row condition is "not matched", not a bug.
        let db = fresh_db();
        let txid = [0x05u8; 32];
        let found = is_known_pending_txid(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(!found);
    }

    #[tokio::test]
    async fn sleep_respecting_cancel_returns_early_on_cancel() {
        // Flip the cancel flag and the sleep must return well before
        // the nominal duration elapses. We use a 2s nominal duration
        // and a 300ms hard ceiling to leave slack for CI jitter while
        // still catching the "ignores cancel" regression (that would
        // wait the full 2s).
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_clone = cancel.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            cancel_clone.store(true, Ordering::Relaxed);
        });
        let start = Instant::now();
        sleep_respecting_cancel(Duration::from_secs(2), &cancel).await;
        let elapsed = start.elapsed();
        assert!(
            elapsed < Duration::from_millis(500),
            "sleep must return early after cancel: elapsed={elapsed:?}"
        );
    }

    #[tokio::test]
    async fn watch_for_cancel_returns_when_flag_flips() {
        // `watch_for_cancel` is used inside the observer's
        // `tokio::select!` to preempt a stream read that's stuck
        // waiting on lightwalletd. If it didn't return promptly
        // after `cancel` flipped, the select arm would never
        // win and `stop_mempool_observer` would silently wait
        // for the next block-boundary EOF (~75s on mainnet).
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_clone = cancel.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            cancel_clone.store(true, Ordering::Relaxed);
        });
        let start = Instant::now();
        watch_for_cancel(&cancel).await;
        let elapsed = start.elapsed();
        assert!(
            elapsed < Duration::from_millis(500),
            "watch_for_cancel must return promptly after cancel: {elapsed:?}"
        );
    }

    #[tokio::test]
    async fn sleep_respecting_cancel_waits_when_not_cancelled() {
        // Complement of the above: when cancel stays false the
        // helper must actually wait out the requested duration
        // (otherwise the reconnect backoff ladder degenerates into
        // a tight loop).
        let cancel = Arc::new(AtomicBool::new(false));
        let start = Instant::now();
        sleep_respecting_cancel(Duration::from_millis(250), &cancel).await;
        let elapsed = start.elapsed();
        assert!(
            elapsed >= Duration::from_millis(200),
            "sleep must wait at least ~duration: elapsed={elapsed:?}"
        );
    }
}

