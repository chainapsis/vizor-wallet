//! Background observer for lightwalletd's `GetMempoolStream`.
//!
//! The block-scan loop in `sync_engine::mod` catches wallet-related
//! transactions at the granularity of a block batch — fast enough
//! for most flows, but always *after* the tx has been mined. This
//! observer closes that gap for wallet-relevant mempool traffic:
//! already-known outbound transactions are confirmed as propagated,
//! and new inbound shielded transactions are trial-decrypted and
//! stored as unmined wallet transactions before the next block.
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
//!     means we inherit the same TLS transport the scan loop uses.
//!
//!   * **Write only after a wallet hit.** The hot path parses the
//!     txid, skips txs already seen in this observer session, and
//!     checks for existing unmined wallet rows. Unknown txs go
//!     through read-only trial decryption first; only txs that
//!     decrypt for one of our UFVKs call `decrypt_and_store_transaction`.
//!     That keeps SQLite write contention proportional to wallet
//!     relevance instead of global mempool volume.
//!
//!   * **Reconnect semantics match the SDK.** lightwalletd closes
//!     the stream every time a new block is mined — normal EOF,
//!     not an error. We treat that as "sleep 1s, reconnect". Real
//!     errors use a 1s / 30s backoff ladder (first failure: 1s,
//!     subsequent consecutive failures: 30s), reset to zero on any
//!     successful connect. Cancel is checked inside the sleep so
//!     we don't block `stop_mempool_observer()` for 30s.

use std::collections::{BTreeSet, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use zcash_client_backend::{data_api::WalletRead, proto::service::RawTransaction};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

use crate::wallet::network::WalletNetwork;

use super::lwd::start_mempool_stream;
use super::open_lwd_channel;

/// Event emitted by [`run_mempool_observer`] for every transaction
/// arriving on the mempool stream that we can parse.
///
/// `matched` is `true` when the txid is wallet-relevant: either it
/// was already present in the wallet DB as unmined, or the observer
/// decrypted and stored a new inbound shielded transaction.
#[derive(Clone, Debug)]
pub struct MempoolTxEvent {
    /// Lower-case hex of the txid (stable across consumers).
    pub txid_hex: String,
    /// Account UUIDs that this tx currently maps to in the wallet.
    /// Empty means the event is wallet-relevant but not account-scoped
    /// enough for the Rust side to tell Dart which active account to
    /// refresh. Dart keeps the pre-existing "refresh active account"
    /// behavior in that case.
    pub account_uuids: Vec<String>,
    /// Whether the txid corresponds to a row in the wallet's
    /// `transactions` table with `mined_height IS NULL`.
    pub matched: bool,
}

struct TxidSeenCache {
    max_len: usize,
    order: VecDeque<Vec<u8>>,
    entries: HashSet<Vec<u8>>,
}

impl TxidSeenCache {
    fn new(max_len: usize) -> Self {
        Self {
            max_len,
            order: VecDeque::new(),
            entries: HashSet::new(),
        }
    }

    fn contains(&self, txid_bytes: &[u8]) -> bool {
        self.entries.contains(txid_bytes)
    }

    fn insert(&mut self, txid_bytes: Vec<u8>) {
        if self.max_len == 0 || !self.entries.insert(txid_bytes.clone()) {
            return;
        }

        self.order.push_back(txid_bytes);
        while self.order.len() > self.max_len {
            if let Some(oldest) = self.order.pop_front() {
                self.entries.remove(&oldest);
            }
        }
    }
}

const STATS_LOG_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Debug)]
struct MempoolObserverStats {
    window_started_at: Instant,
    tx_count: u64,
    tx_bytes: u64,
    seen_skip: u64,
    parse_fail: u64,
    pending_lookup_fail: u64,
    known_pending_hit: u64,
    trial_decrypt_count: u64,
    trial_decrypt_hit: u64,
    trial_decrypt_fail: u64,
    trial_decrypt_total: Duration,
    trial_decrypt_max: Duration,
    store_ok: u64,
    store_fail: u64,
    store_total: Duration,
    store_max: Duration,
    stream_connects: u64,
    stream_eofs: u64,
    stream_errors: u64,
}

#[derive(Debug, Default)]
struct KnownPendingTx {
    matched: bool,
    account_uuids: Vec<String>,
}

impl MempoolObserverStats {
    fn new(now: Instant) -> Self {
        Self {
            window_started_at: now,
            tx_count: 0,
            tx_bytes: 0,
            seen_skip: 0,
            parse_fail: 0,
            pending_lookup_fail: 0,
            known_pending_hit: 0,
            trial_decrypt_count: 0,
            trial_decrypt_hit: 0,
            trial_decrypt_fail: 0,
            trial_decrypt_total: Duration::ZERO,
            trial_decrypt_max: Duration::ZERO,
            store_ok: 0,
            store_fail: 0,
            store_total: Duration::ZERO,
            store_max: Duration::ZERO,
            stream_connects: 0,
            stream_eofs: 0,
            stream_errors: 0,
        }
    }

    fn record_tx(&mut self, bytes: usize) {
        self.tx_count += 1;
        self.tx_bytes = self.tx_bytes.saturating_add(bytes as u64);
    }

    fn record_seen_skip(&mut self) {
        self.seen_skip += 1;
    }

    fn record_parse_fail(&mut self) {
        self.parse_fail += 1;
    }

    fn record_pending_lookup_fail(&mut self) {
        self.pending_lookup_fail += 1;
    }

    fn record_known_pending_hit(&mut self) {
        self.known_pending_hit += 1;
    }

    fn record_trial_decrypt(&mut self, duration: Duration, hit: bool) {
        self.trial_decrypt_count += 1;
        if hit {
            self.trial_decrypt_hit += 1;
        }
        self.trial_decrypt_total += duration;
        self.trial_decrypt_max = self.trial_decrypt_max.max(duration);
    }

    fn record_trial_decrypt_fail(&mut self, duration: Duration) {
        self.trial_decrypt_fail += 1;
        self.record_trial_decrypt(duration, false);
    }

    fn record_store(&mut self, duration: Duration, ok: bool) {
        if ok {
            self.store_ok += 1;
        } else {
            self.store_fail += 1;
        }
        self.store_total += duration;
        self.store_max = self.store_max.max(duration);
    }

    fn record_stream_connect(&mut self) {
        self.stream_connects += 1;
    }

    fn record_stream_eof(&mut self) {
        self.stream_eofs += 1;
    }

    fn record_stream_error(&mut self) {
        self.stream_errors += 1;
    }

    fn take_summary_if_due(&mut self, now: Instant) -> Option<String> {
        let elapsed = now.duration_since(self.window_started_at);
        if elapsed < STATS_LOG_INTERVAL {
            return None;
        }

        let line = self.summary_line(elapsed);
        *self = Self::new(now);
        line
    }

    fn summary_line(&self, elapsed: Duration) -> Option<String> {
        if !self.has_activity() {
            return None;
        }

        let store_count = self.store_ok + self.store_fail;
        Some(format!(
            "mempool: stats {}s tx={} bytes={} seen_skip={} known_hit={} \
             decrypt={} decrypt_hit={} decrypt_fail={} decrypt_avg={:.1}ms \
             decrypt_max={:.1}ms store_ok={} store_fail={} store_avg={:.1}ms \
             store_max={:.1}ms parse_fail={} pending_lookup_fail={} \
             stream_connect={} stream_eof={} stream_error={}",
            elapsed.as_secs(),
            self.tx_count,
            self.tx_bytes,
            self.seen_skip,
            self.known_pending_hit,
            self.trial_decrypt_count,
            self.trial_decrypt_hit,
            self.trial_decrypt_fail,
            average_ms(self.trial_decrypt_total, self.trial_decrypt_count),
            duration_ms(self.trial_decrypt_max),
            self.store_ok,
            self.store_fail,
            average_ms(self.store_total, store_count),
            duration_ms(self.store_max),
            self.parse_fail,
            self.pending_lookup_fail,
            self.stream_connects,
            self.stream_eofs,
            self.stream_errors,
        ))
    }

    fn has_activity(&self) -> bool {
        self.tx_count > 0
            || self.stream_connects > 0
            || self.stream_eofs > 0
            || self.stream_errors > 0
    }
}

fn duration_ms(duration: Duration) -> f64 {
    duration.as_secs_f64() * 1000.0
}

fn average_ms(total: Duration, count: u64) -> f64 {
    if count == 0 {
        0.0
    } else {
        duration_ms(total) / count as f64
    }
}

/// Run the mempool observer until `cancel` is set.
///
/// This is an infinite-retry loop. Every iteration:
///
///   1. Opens a fresh lwd channel (plain TLS).
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
    network: WalletNetwork,
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
    let mut seen_cache = TxidSeenCache::new(2048);
    let mut stats = MempoolObserverStats::new(Instant::now());

    /// Pick the backoff delay based on how many consecutive errors
    /// we've accumulated. First failure: 1s. Subsequent: 30s.
    /// Matches the SDK's `LightWalletClientImpl.kt:313–327`
    /// reconnect ladder and is applied uniformly to *all* error
    /// paths (channel-open, RPC-start, AND stream-read failures —
    /// the old code only applied it to the first two, leaving
    /// stream-read errors on a fixed 1s reconnect forever).
    fn backoff_for(consecutive_errors: u32) -> Duration {
        if consecutive_errors <= 1 {
            INITIAL_BACKOFF
        } else {
            LATER_BACKOFF
        }
    }

    loop {
        if cancel.load(Ordering::Relaxed) {
            log::info!("mempool: observer cancelled");
            return Ok(());
        }

        // Open a fresh lwd channel for this stream attempt.
        //
        // Wrapped in `tokio::select!` with the cancel poll so a
        // `stop_mempool_observer()` arriving while we're blocked
        // on a TLS handshake / gRPC connect preempts
        // the wait within ~100ms instead of stalling until the
        // network operation returns. Without this, `restartSync`'s
        // 5s ceiling can expire before the old observer releases
        // (Codex 4th-round finding 1).
        let channel_result = tokio::select! {
            biased;
            _ = watch_for_cancel(&cancel) => {
                log::info!("mempool: observer cancelled during channel open");
                return Ok(());
            }
            r = open_lwd_channel(&lightwalletd_url) => r,
        };
        let mut client = match channel_result {
            Ok(pair) => pair,
            Err(e) => {
                log::warn!("mempool: open_lwd_channel failed: {e}");
                consecutive_errors += 1;
                sleep_respecting_cancel(backoff_for(consecutive_errors), &cancel).await;
                continue;
            }
        };

        // Start the mempool stream — also cancel-aware.
        let stream_result = tokio::select! {
            biased;
            _ = watch_for_cancel(&cancel) => {
                log::info!("mempool: observer cancelled during stream start");
                return Ok(());
            }
            r = start_mempool_stream(&mut client) => r,
        };
        let mut stream = match stream_result {
            Ok(s) => s,
            Err(e) => {
                log::warn!("mempool: start_mempool_stream failed: {e}");
                consecutive_errors += 1;
                sleep_respecting_cancel(backoff_for(consecutive_errors), &cancel).await;
                continue;
            }
        };

        log::info!("mempool: observer connected");
        stats.record_stream_connect();
        log_stats_if_due(&mut stats);
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
                            handle_mempool_tx(
                                &db_path,
                                network,
                                &mut seen_cache,
                                &mut stats,
                                &raw_tx,
                                &emit,
                            );
                            log_stats_if_due(&mut stats);
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
                            stats.record_stream_eof();
                            break StreamExit::CleanEof;
                        }
                        Err(e) => {
                            log::warn!("mempool: stream error: {e}");
                            consecutive_errors += 1;
                            stats.record_stream_error();
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

        // Choose reconnect delay based on why we broke out:
        //
        //   * CleanEof (new block mined, server closed stream):
        //     normal event, sleep 1s and reconnect. Reset the
        //     error counter so a subsequent real error still gets
        //     the "first failure = 1s" ramp.
        //
        //   * Error (tonic / HTTP/2 failure on the stream): apply
        //     the same 1s/30s backoff ladder as the channel-open
        //     and stream-start error paths. `consecutive_errors`
        //     was already incremented inside the inner loop; use
        //     it directly.
        //
        // Before this fix, both branches unconditionally slept 1s,
        // so a server that accepted the stream but immediately
        // errored it caused a tight 1s reconnect loop forever
        // (Codex 4th-round finding 2).
        let reconnect_delay = match stream_exit {
            StreamExit::CleanEof => {
                consecutive_errors = 0;
                INITIAL_BACKOFF
            }
            StreamExit::Error => backoff_for(consecutive_errors),
        };
        log_stats_if_due(&mut stats);
        sleep_respecting_cancel(reconnect_delay, &cancel).await;
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

/// Parse `raw_tx`, compute the txid, skip duplicate observations,
/// and emit a [`MempoolTxEvent`] only for wallet-relevant txs.
///
/// Unmatched transactions (other people's txs) are silently
/// dropped on the Rust side without crossing the FRB bridge.
/// Unknown txs may still pay the cost of trial decryption, but they
/// never take the wallet DB write lock unless a shielded output
/// decrypts for one of our accounts.
///
/// All failures are logged and swallowed — one un-parseable tx
/// must not break the observer loop.
fn handle_mempool_tx<F>(
    db_path: &str,
    network: WalletNetwork,
    seen_cache: &mut TxidSeenCache,
    stats: &mut MempoolObserverStats,
    raw_tx: &RawTransaction,
    emit: &F,
) where
    F: Fn(MempoolTxEvent),
{
    stats.record_tx(raw_tx.data.len());

    // Parse far enough to get the txid. `BranchId::Sapling` matches
    // what the sync loop's enhance path uses; any new-network-era
    // txs that fail parse here would also fail there and surface
    // via the regular scan instead.
    let tx = match Transaction::read(&raw_tx.data[..], BranchId::Sapling) {
        Ok(t) => t,
        Err(e) => {
            stats.record_parse_fail();
            log::debug!("mempool: Transaction::read failed: {e}");
            return;
        }
    };
    let txid = tx.txid();
    let txid_hex = format!("{txid}");
    let txid_bytes = txid.as_ref().to_vec();

    if seen_cache.contains(&txid_bytes) {
        stats.record_seen_skip();
        return;
    }

    let known = match lookup_known_pending_tx(db_path, &txid_bytes) {
        Ok(known) => known,
        Err(e) => {
            stats.record_pending_lookup_fail();
            log::debug!("mempool: DB lookup for {txid_hex} failed: {e}");
            return;
        }
    };

    if known.matched || !known.account_uuids.is_empty() {
        stats.record_known_pending_hit();
        emit_wallet_relevant_tx(
            txid_hex,
            txid_bytes,
            known.account_uuids,
            seen_cache,
            emit,
            "matched tx",
        );
        return;
    }

    let decrypt_started_at = Instant::now();
    let account_uuids = match trial_decrypt_account_uuids(db_path, network, &tx) {
        Ok(accounts) => {
            stats.record_trial_decrypt(decrypt_started_at.elapsed(), !accounts.is_empty());
            accounts
        }
        Err(e) => {
            stats.record_trial_decrypt_fail(decrypt_started_at.elapsed());
            log::debug!("mempool: trial decrypt for {txid_hex} failed: {e}");
            return;
        }
    };

    if account_uuids.is_empty() {
        seen_cache.insert(txid_bytes);
        return;
    }

    let store_started_at = Instant::now();
    match crate::wallet::sync::decrypt_and_store_transaction(db_path, network, &raw_tx.data, None) {
        Ok(()) => {
            stats.record_store(store_started_at.elapsed(), true);
            emit_wallet_relevant_tx(
                txid_hex,
                txid_bytes,
                account_uuids,
                seen_cache,
                emit,
                "stored inbound tx",
            );
        }
        Err(e) => {
            stats.record_store(store_started_at.elapsed(), false);
            log::warn!("mempool: failed to store inbound tx {txid_hex}: {e}");
        }
    }
}

fn log_stats_if_due(stats: &mut MempoolObserverStats) {
    if let Some(line) = stats.take_summary_if_due(Instant::now()) {
        log::info!("{line}");
    }
}

fn emit_wallet_relevant_tx<F>(
    txid_hex: String,
    txid_bytes: Vec<u8>,
    account_uuids: Vec<String>,
    seen_cache: &mut TxidSeenCache,
    emit: &F,
    log_label: &str,
) where
    F: Fn(MempoolTxEvent),
{
    seen_cache.insert(txid_bytes);
    log::info!("mempool: {log_label} {txid_hex}");
    emit(MempoolTxEvent {
        txid_hex: txid_hex.clone(),
        account_uuids: account_uuids.clone(),
        matched: true,
    });
}

/// Read-only lookup: does the wallet know about this txid as an
/// unmined transaction, and which accounts currently map to it?
/// Uses one SQLite connection for both checks and never takes the
/// wallet write lock, so it is safe while the scan loop is writing.
fn lookup_known_pending_tx(db_path: &str, txid_bytes: &[u8]) -> Result<KnownPendingTx, String> {
    use rusqlite::OptionalExtension;

    let conn = crate::wallet::sync::open_readonly_conn_fail_fast(db_path)
        .map_err(|e| format!("open DB: {e}"))?;

    let matched = conn
        .query_row(
            "SELECT 1 FROM transactions WHERE txid = ?1 AND mined_height IS NULL LIMIT 1",
            [txid_bytes],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|e| format!("transactions query: {e}"))?
        .is_some();

    let mut stmt = conn
        .prepare(
            "SELECT DISTINCT account_uuid \
             FROM v_transactions \
             WHERE txid = ?1 AND mined_height IS NULL",
        )
        .map_err(|e| format!("account prepare: {e}"))?;

    let rows = stmt
        .query_map([txid_bytes], |row| {
            let bytes: Vec<u8> = row.get(0)?;
            let uuid = uuid::Uuid::from_slice(&bytes).map_err(|e| {
                rusqlite::Error::FromSqlConversionFailure(
                    bytes.len(),
                    rusqlite::types::Type::Blob,
                    Box::new(e),
                )
            })?;
            Ok(uuid.to_string())
        })
        .map_err(|e| format!("account query: {e}"))?;

    let mut account_uuids = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("account row: {e}"))?;
    account_uuids.sort();

    Ok(KnownPendingTx {
        matched,
        account_uuids,
    })
}

fn trial_decrypt_account_uuids(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
) -> Result<Vec<String>, String> {
    let db = crate::wallet::sync::open_wallet_db_for_read(db_path, network)
        .map_err(|e| format!("open wallet DB: {e}"))?;
    let ufvks = db
        .get_unified_full_viewing_keys()
        .map_err(|e| format!("get UFVKs: {e}"))?;
    let decrypted = zcash_client_backend::decrypt_transaction(
        &network,
        None,
        db.chain_height()
            .map_err(|e| format!("chain height: {e}"))?,
        tx,
        &ufvks,
    );

    let mut accounts = BTreeSet::new();
    for output in decrypted.sapling_outputs() {
        accounts.insert(output.account().expose_uuid().to_string());
    }
    for output in decrypted.orchard_outputs() {
        accounts.insert(output.account().expose_uuid().to_string());
    }

    Ok(accounts.into_iter().collect())
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
    //!   * `lookup_known_pending_tx`, the read-only lookup that
    //!     decides whether each parsed mempool tx is already known
    //!     and which account UUIDs it maps to. Its SQL has to stay
    //!     in sync with the `transactions` / `v_transactions` table
    //!     shapes and the "unmined" definition (`mined_height IS NULL`).
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
    /// `lookup_known_pending_tx` actually reads.
    fn fresh_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 txid BLOB NOT NULL,
                 mined_height INTEGER
             );
             CREATE TABLE v_transactions (
                 account_uuid BLOB NOT NULL,
                 txid BLOB NOT NULL,
                 mined_height INTEGER,
                 block_time INTEGER
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

    fn insert_v_transaction(
        db: &NamedTempFile,
        txid: &[u8],
        account_uuid: uuid::Uuid,
        mined_height: Option<i64>,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "INSERT INTO v_transactions (account_uuid, txid, mined_height)
             VALUES (?1, ?2, ?3)",
            rusqlite::params![account_uuid.as_bytes().as_slice(), txid, mined_height],
        )
        .unwrap();
    }

    #[test]
    fn lookup_known_pending_tx_finds_unmined_tx() {
        let db = fresh_db();
        let txid = [0x01u8; 32];
        insert_tx(&db, &txid, None);
        let found = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(
            found.matched,
            "unmined tx in DB must register as known pending"
        );
    }

    #[test]
    fn lookup_known_pending_tx_ignores_mined_tx() {
        // The whole point of the "unmined" filter: if sync already
        // settled this tx into a block, we don't care that it's
        // bouncing around the mempool (shouldn't be anyway, but
        // lightwalletd can briefly relay stale mined txs).
        let db = fresh_db();
        let txid = [0x02u8; 32];
        insert_tx(&db, &txid, Some(2_500_000));
        let found = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(!found.matched, "mined tx must NOT count as known pending");
    }

    #[test]
    fn lookup_known_pending_tx_handles_unknown_tx() {
        let db = fresh_db();
        let known_txid = [0x03u8; 32];
        let unknown_txid = [0x04u8; 32];
        insert_tx(&db, &known_txid, None);
        let found = lookup_known_pending_tx(db.path().to_str().unwrap(), &unknown_txid).unwrap();
        assert!(!found.matched, "txid not in DB must return false");
    }

    #[test]
    fn lookup_known_pending_tx_handles_empty_db() {
        // Baseline: cold wallet with no txs at all still returns Ok(false),
        // not an error. The observer's fall-through branch relies on
        // this — a missing-row condition is "not matched", not a bug.
        let db = fresh_db();
        let txid = [0x05u8; 32];
        let found = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(!found.matched);
    }

    #[test]
    fn seen_cache_evicts_oldest_txid() {
        let mut cache = TxidSeenCache::new(2);
        let first = vec![0x01; 32];
        let second = vec![0x02; 32];
        let third = vec![0x03; 32];

        cache.insert(first.clone());
        cache.insert(second.clone());
        assert!(cache.contains(&first));
        assert!(cache.contains(&second));

        cache.insert(third.clone());
        assert!(!cache.contains(&first));
        assert!(cache.contains(&second));
        assert!(cache.contains(&third));
    }

    #[test]
    fn lookup_known_pending_tx_returns_distinct_accounts() {
        let db = fresh_db();
        let txid = [0x06u8; 32];
        let first_uuid = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let second_uuid = uuid::Uuid::parse_str("67e55044-10b1-426f-9247-bb680e5fe0c8").unwrap();
        insert_v_transaction(&db, &txid, first_uuid, None);
        insert_v_transaction(&db, &txid, first_uuid, None);
        insert_v_transaction(&db, &txid, second_uuid, None);
        insert_v_transaction(
            &db,
            &[0x07u8; 32],
            uuid::Uuid::parse_str("2c2f2a4b-9c64-41f8-9801-fd06553fd4f6").unwrap(),
            None,
        );

        let known = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();
        assert_eq!(
            known.account_uuids,
            vec![first_uuid.to_string(), second_uuid.to_string()]
        );
    }

    #[test]
    fn lookup_known_pending_tx_ignores_mined_account_rows() {
        let db = fresh_db();
        let txid = [0x08u8; 32];
        let uuid = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        insert_v_transaction(&db, &txid, uuid, Some(2_500_000));

        let known = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();
        assert!(known.account_uuids.is_empty());
    }

    #[test]
    fn lookup_known_pending_tx_returns_match_and_accounts() {
        let db = fresh_db();
        let txid = [0x09u8; 32];
        let first_uuid = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let second_uuid = uuid::Uuid::parse_str("67e55044-10b1-426f-9247-bb680e5fe0c8").unwrap();
        insert_tx(&db, &txid, None);
        insert_v_transaction(&db, &txid, second_uuid, None);
        insert_v_transaction(&db, &txid, first_uuid, None);
        insert_v_transaction(&db, &txid, first_uuid, None);

        let known = lookup_known_pending_tx(db.path().to_str().unwrap(), &txid).unwrap();

        assert!(known.matched);
        assert_eq!(
            known.account_uuids,
            vec![first_uuid.to_string(), second_uuid.to_string()]
        );
    }

    #[test]
    fn stats_summary_reports_volume_and_latency() {
        let start = Instant::now();
        let mut stats = MempoolObserverStats::new(start);
        stats.record_tx(100);
        stats.record_tx(50);
        stats.record_seen_skip();
        stats.record_known_pending_hit();
        stats.record_trial_decrypt(Duration::from_millis(10), false);
        stats.record_trial_decrypt(Duration::from_millis(30), true);
        stats.record_store(Duration::from_millis(40), true);
        stats.record_store(Duration::from_millis(80), false);

        let line = stats.summary_line(Duration::from_secs(30)).unwrap();
        assert!(line.contains("tx=2"));
        assert!(line.contains("bytes=150"));
        assert!(line.contains("seen_skip=1"));
        assert!(line.contains("known_hit=1"));
        assert!(line.contains("decrypt=2"));
        assert!(line.contains("decrypt_hit=1"));
        assert!(line.contains("decrypt_avg=20.0ms"));
        assert!(line.contains("decrypt_max=30.0ms"));
        assert!(line.contains("store_ok=1"));
        assert!(line.contains("store_fail=1"));
        assert!(line.contains("store_avg=60.0ms"));
        assert!(line.contains("store_max=80.0ms"));
    }

    #[test]
    fn stats_take_summary_resets_after_interval() {
        let start = Instant::now();
        let mut stats = MempoolObserverStats::new(start);
        stats.record_tx(10);

        assert!(stats
            .take_summary_if_due(start + Duration::from_secs(29))
            .is_none());
        assert!(stats
            .take_summary_if_due(start + Duration::from_secs(30))
            .is_some());
        assert!(
            stats
                .take_summary_if_due(start + Duration::from_secs(60))
                .is_none(),
            "no activity after reset should not log empty windows"
        );
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
