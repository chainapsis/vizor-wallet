//! Transaction enhancement pass for the sync engine.
//!
//! `scan_cached_blocks` walks compact blocks and discovers transactions
//! that are relevant to the wallet, but a compact block only carries
//! the subset of transaction data needed for shielded-note discovery.
//! Things the wallet still has to learn afterwards:
//!
//!   - The full transaction bytes (for memo decryption, transparent
//!     input/output tracking, etc.).
//!   - Mined status for a transaction the wallet knows about but
//!     hasn't confirmed on-chain yet.
//!   - Transparent-address history in a given block range (used when
//!     the wallet imports or derives a new t-address and has to
//!     backfill its activity).
//!
//! Librustzcash signals these gaps by populating
//! `db.transaction_data_requests()`. This module drains the queue
//! against lightwalletd via three gRPC calls (`GetTransaction`,
//! `TransactionsInvolvingAddress`) and writes the results back into
//! `db` using `decrypt_and_store_transaction` and
//! `set_transaction_status`. The loop retries up to three times
//! because servicing one request can legally populate new requests
//! (e.g. a newly-decrypted transaction may reveal additional parent
//! transactions to enhance).
//!
//! The network fetches run concurrently (bounded by
//! [`enhancement_concurrency`]) because servicing the queue serially
//! cost ~150ms per request against a public lightwalletd — dozens of
//! sequential round-trips that dominated a cold sync's non-scan time.
//! DB writes stay serial under the wallet-DB write lock. The queue is
//! derived from DB state, so a pass is always safe to stop early
//! (`should_exit`) or skip entirely: whatever remains is picked up by
//! the next pass or the next sync run.

use std::collections::{BTreeMap, HashSet};

use futures::StreamExt;
use tokio::sync::mpsc;
use tonic::{transport::Channel, Code, Status};
use transparent::bundle::OutPoint;
use zcash_client_backend::{
    data_api::{
        wallet::decrypt_and_store_transaction, TransactionDataRequest, TransactionStatus,
        WalletRead, WalletWrite,
    },
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::{BlockHeight, BranchId};
use zcash_protocol::value::{BalanceError, Zatoshis};

use crate::wallet::db::{with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT};
use crate::wallet::network::WalletNetwork;

use super::{lwd, SyncError, WalletDatabase};

const ADDRESS_TX_CHANNEL_CAPACITY: usize = 4;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const DEFAULT_ENHANCEMENT_CONCURRENCY: u64 = 8;
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const DEFAULT_ENHANCEMENT_CONCURRENCY: u64 = 4;

/// Drains `db.transaction_data_requests()` against lightwalletd until
/// the queue is empty or no request is actionable. Network fetches run
/// concurrently (bounded); results are applied serially under the
/// wallet-DB write lock.
///
/// Returns an [`EnhancementOutcome`]: `stored` counts transactions applied
/// via `decrypt_and_store_transaction` for `Enhancement` and
/// address-scoped requests — the ones that add user-visible history data
/// (memos, sent-tx recipients, transparent history rows) — and the caller
/// folds a non-zero count into the batch's `has_new_tx` progress flag so
/// the Dart side refreshes the visible history. `GetStatus` re-stores of a
/// still-pending tx are deliberately NOT counted: those requests persist
/// while the tx is unmined and would otherwise flag `has_new_tx` on every
/// pass without anything user-visible changing. `drained` tells the caller
/// whether the post-loop drain still has work (see the struct docs).
///
/// `should_exit` is consulted between rounds, between concurrent fetch
/// completions (dropping the stream aborts in-flight RPCs), and between
/// serial applies. When it fires, the pass stops promptly; the DB-derived
/// queue means anything unserviced is retried by a later pass.
///
/// Failure policy: once anything has been committed in a pass, its
/// `stored` count must reach the caller (the `has_new_tx` refresh signal
/// depends on it, and serviced queue entries will not re-count on retry).
/// So per-item failures are logged and skipped, an explicit "txid not
/// recognized" response is recorded via `set_transaction_status` so it
/// doesn't get retried forever, and a transient network failure ends the
/// pass after the current round — but never discards the count. `Err` is
/// returned only when reading the request queue itself fails.
/// Result of an enhancement pass.
pub(super) struct EnhancementOutcome {
    /// Transactions applied via `decrypt_and_store_transaction` for
    /// `Enhancement` and address-scoped requests (drives `has_new_tx`).
    pub stored: usize,
    /// True only when the pass verifiably left no actionable NEW work:
    /// the queue read back empty/inert, or an entire round produced the
    /// identical request set as the previous one (whatever remains is
    /// persistent, e.g. GetStatus for a still-unmined send). False on
    /// early exits (cancel, network error) and on 3-round exhaustion with
    /// fresh work still appearing — callers use this to decide whether the
    /// post-loop drain still has anything to do.
    pub drained: bool,
}

pub(super) async fn run_enhancement<ShouldExit>(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    should_exit: &ShouldExit,
) -> Result<EnhancementOutcome, SyncError>
where
    ShouldExit: Fn() -> bool + Sync,
{
    let mut failed_txids: HashSet<String> = HashSet::new();
    let mut stored: usize = 0;
    let mut drained = false;
    let mut prev_signature: Option<std::collections::BTreeSet<String>> = None;

    // Telemetry to locate the cost of an enhancement pass.
    let enh_t0 = std::time::Instant::now();
    let mut n_status_reqs = 0u64;
    let mut n_addr_reqs = 0u64;
    let mut fee_time = std::time::Duration::ZERO;

    'rounds: for _ in 0..3 {
        if should_exit() {
            break;
        }
        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests: {e}")))?;
        if requests.is_empty() {
            drained = true;
            break;
        }

        // If nothing in the queue is actionable (e.g. address-scoped
        // requests without an `end` height, which we can't service
        // without synthesizing a range), break rather than looping
        // forever on the same inert queue.
        let actionable = requests.iter().any(|r| match r {
            TransactionDataRequest::Enhancement(_) | TransactionDataRequest::GetStatus(_) => true,
            TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                req.block_range_end().is_some()
            }
        });
        if !actionable {
            drained = true;
            break;
        }

        // Rounds exist only to service requests that servicing itself
        // enqueued (a decrypted tx can reveal parents to enhance). If this
        // round's request set is identical to the previous one, nothing new
        // arrived — whatever remains is persistent (GetStatus for a
        // still-unmined send regenerates until it mines) and re-servicing
        // it is pure duplication: up to 3 identical full-raw-tx fetches per
        // pass, every sync cycle, for the tx's whole unmined lifetime.
        let signature: std::collections::BTreeSet<String> = requests
            .iter()
            .map(|r| match r {
                TransactionDataRequest::GetStatus(txid) => format!("s:{txid}"),
                TransactionDataRequest::Enhancement(txid) => format!("e:{txid}"),
                TransactionDataRequest::TransactionsInvolvingAddress(req) => format!(
                    "a:{:?}:{}:{:?}",
                    req.address(),
                    req.block_range_start(),
                    req.block_range_end(),
                ),
            })
            .collect();
        if prev_signature.as_ref() == Some(&signature) {
            drained = true;
            break;
        }
        prev_signature = Some(signature);

        let concurrency = enhancement_concurrency();

        // --- txid-scoped requests: concurrent GetTransaction, serial apply ---
        // Coalesce request kinds for the same txid. Librustzcash may ask for
        // both status and full enhancement at once; one raw transaction RPC
        // can service both without racing two identical fetches/applies.
        let mut status_by_txid: BTreeMap<TxId, (bool, bool)> = BTreeMap::new();
        for request in &requests {
            match request {
                TransactionDataRequest::GetStatus(txid) => {
                    status_by_txid.entry(*txid).or_default().0 = true;
                }
                TransactionDataRequest::Enhancement(txid) => {
                    status_by_txid.entry(*txid).or_default().1 = true;
                }
                TransactionDataRequest::TransactionsInvolvingAddress(_) => {}
            }
        }
        let status_items: Vec<(TxId, bool, bool)> = status_by_txid
            .into_iter()
            .filter(|(txid, _)| !failed_txids.contains(&format!("{txid}")))
            .map(|(txid, (needs_status, is_enhancement))| (txid, needs_status, is_enhancement))
            .collect();
        n_status_reqs += status_items.len() as u64;

        // Once anything has been committed to the DB in this pass, `stored`
        // must survive to the return value — the caller derives the batch's
        // `has_new_tx` (and hence the Dart history refresh) from it, and the
        // serviced queue entries will NOT re-count on a retry. So from here
        // on, per-item failures are logged and skipped, and a transient
        // network failure ends the pass early (`round_network_error`) but
        // never discards the count via `?`/`return Err`.
        //
        // Each result is applied AS IT ARRIVES from the bounded concurrent
        // stream: peak memory is ~`concurrency` in-flight responses instead
        // of the whole pass's payloads (raw transactions run to ~2 MB
        // each), and a cancel or `break 'rounds` drops the stream — which
        // aborts the in-flight fetches — without first draining every
        // response. The fee lookups use a dedicated client clone because
        // the stream holds a shared borrow of `client` while alive.
        let mut round_network_error = false;
        let mut fee_client = client.clone();
        let mut fetch_stream = futures::stream::iter(status_items)
            .map(|(txid, needs_status, is_enhancement)| {
                let mut c = client.clone();
                async move {
                    let res = tokio::select! {
                        result = lwd::get_transaction(&mut c, txid.as_ref().to_vec()) => {
                            Some(result)
                        }
                        _ = wait_until_exit(should_exit) => None,
                    };
                    (txid, needs_status, is_enhancement, res)
                }
            })
            .buffer_unordered(concurrency);
        while let Some((txid, needs_status, is_enhancement, res)) = fetch_stream.next().await {
            let Some(res) = res else {
                break 'rounds;
            };
            if should_exit() {
                break 'rounds;
            }
            let txid_str = format!("{txid}");
            match res {
                Ok(raw) => {
                    let mined_height = match mined_height_from_raw_height(raw.height) {
                        Ok(h) => h,
                        Err(e) => {
                            log::warn!("sync: invalid mined height for {txid_str} (skipping): {e}");
                            continue;
                        }
                    };
                    if !raw.data.is_empty() {
                        match Transaction::read(&raw.data[..], BranchId::Sapling) {
                            Ok(tx) => {
                                match with_wallet_db_write_lock(
                                    "sync_engine.enhance.decrypt_and_store_transaction",
                                    || {
                                        decrypt_and_store_transaction(
                                            &network,
                                            db,
                                            &tx,
                                            mined_height,
                                        )
                                    },
                                ) {
                                    Ok(()) => {
                                        if is_enhancement {
                                            stored += 1;
                                        }
                                    }
                                    Err(e) => log::error!(
                                        "sync: decrypt_and_store_transaction failed: {e}"
                                    ),
                                }
                                let fee_t = std::time::Instant::now();
                                if let Err(e) = fill_missing_transparent_fee(
                                    &mut fee_client,
                                    db_path,
                                    &tx,
                                    should_exit,
                                )
                                .await
                                {
                                    log::warn!(
                                        "sync: transparent fee enhancement failed for {txid_str}: {e}"
                                    );
                                }
                                fee_time += fee_t.elapsed();
                            }
                            Err(e) => {
                                log::warn!("sync: Transaction::read failed for {txid_str}: {e}")
                            }
                        }
                    }
                    if needs_status {
                        match transaction_status_from_raw_height(raw.height) {
                            Ok(status) => {
                                if let Err(e) = with_wallet_db_write_lock(
                                    "sync_engine.enhance.set_transaction_status",
                                    || db.set_transaction_status(txid, status),
                                ) {
                                    log::error!("sync: set_transaction_status failed: {e}");
                                }
                            }
                            Err(e) => log::warn!(
                                "sync: invalid status height for {txid_str} (skipping): {e}"
                            ),
                        }
                    }
                }
                Err(e) => match classify_get_transaction_error(&e) {
                    GetTransactionErrorAction::MarkTxidNotRecognized => {
                        log::warn!("sync: get_transaction did not recognize {txid_str}: {e}");
                        failed_txids.insert(txid_str);
                        if let Err(e) = with_wallet_db_write_lock(
                            "sync_engine.enhance.set_transaction_status",
                            || {
                                db.set_transaction_status(
                                    txid,
                                    TransactionStatus::TxidNotRecognized,
                                )
                            },
                        ) {
                            log::error!("sync: set_transaction_status failed: {e}");
                        }
                    }
                    GetTransactionErrorAction::RetryAsNetwork => {
                        // Transient network failure: keep applying the
                        // results that DID arrive, then end the pass after
                        // this round instead of spinning two more rounds
                        // against a failing endpoint. The DB-derived queue
                        // retries on the next pass.
                        log::warn!(
                            "sync: get_transaction failed for {txid_str} \
                             (ending pass after this round): {e}"
                        );
                        round_network_error = true;
                    }
                },
            }
        }
        if should_exit() {
            break;
        }

        // --- address-scoped requests: concurrent history streams, serial apply ---
        let addr_items: Vec<(String, u64, u64)> = requests
            .iter()
            .filter_map(|r| match r {
                TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                    req.block_range_end().map(|end_height| {
                        let addr_str = zcash_keys::encoding::encode_transparent_address_p(
                            &network,
                            &req.address(),
                        );
                        let start = u32::from(req.block_range_start()) as u64;
                        let end = u32::from(end_height) as u64;
                        (addr_str, start, end.saturating_sub(1))
                    })
                }
                _ => None,
            })
            .collect();
        n_addr_reqs += addr_items.len() as u64;

        // Each address fetch owns a bounded channel. The network task parses
        // one transaction and sends it immediately; the caller applies items
        // serially while other addresses continue up to the channel bound.
        // This prevents a single heavily-used transparent address from
        // accumulating its entire history in a Vec before the first DB write.
        let mut addr_stream = futures::stream::iter(addr_items)
            .map(|(addr_str, start, end)| {
                let mut c = client.clone();
                async move { start_address_txs(&mut c, addr_str, start, end, should_exit).await }
            })
            .buffer_unordered(concurrency);
        while let Some(result) = addr_stream.next().await {
            if should_exit() {
                break 'rounds;
            }
            let mut fetch = match result {
                Ok(Some(fetch)) => fetch,
                Ok(None) => break 'rounds,
                Err(e) => {
                    // One address's history stream failing must not discard
                    // the other addresses' results (or the pass's stored
                    // count): log, mark the round, keep applying.
                    log::warn!(
                        "sync: address history fetch failed \
                         (continuing with other addresses): {e}"
                    );
                    round_network_error = true;
                    continue;
                }
            };
            loop {
                let next = tokio::select! {
                    item = fetch.receiver.recv() => item,
                    _ = wait_until_exit(should_exit) => break 'rounds,
                };
                let Some(next) = next else {
                    break;
                };
                let (mined_height, tx) = match next {
                    Ok(item) => item,
                    Err(e) => {
                        log::warn!(
                            "sync: address history stream failed (continuing with other addresses): {e}"
                        );
                        round_network_error = true;
                        break;
                    }
                };
                if should_exit() {
                    break 'rounds;
                }
                match with_wallet_db_write_lock(
                    "sync_engine.enhance.decrypt_and_store_transaction",
                    || decrypt_and_store_transaction(&network, db, &tx, mined_height),
                ) {
                    Ok(()) => stored += 1,
                    Err(e) => {
                        log::error!("sync: decrypt_and_store_transaction (addr) failed: {e}")
                    }
                }
                let fee_t = std::time::Instant::now();
                if let Err(e) =
                    fill_missing_transparent_fee(&mut fee_client, db_path, &tx, should_exit).await
                {
                    log::warn!(
                        "sync: transparent fee enhancement (addr) failed for {}: {e}",
                        tx.txid()
                    );
                }
                fee_time += fee_t.elapsed();
            }
        }
        drop(addr_stream);

        if round_network_error {
            break;
        }
    }

    let total = enh_t0.elapsed();
    if total.as_millis() > 50 {
        log::info!(
            "enhance: pass took {:.2}s (status/enh reqs={}, addr reqs={}, stored={}, transparent-fee {:.2}s)",
            total.as_secs_f64(),
            n_status_reqs,
            n_addr_reqs,
            stored,
            fee_time.as_secs_f64(),
        );
    }
    Ok(EnhancementOutcome { stored, drained })
}

/// Concurrency for the enhancement network fetches. Overridable via
/// `ZCASH_SYNC_ENHANCE_CONCURRENCY` for benchmark sweeps; defaults to 8 on
/// desktop and 4 on mobile, clamped to `[1, 32]`.
fn enhancement_concurrency() -> usize {
    super::env_override_clamped(
        "ZCASH_SYNC_ENHANCE_CONCURRENCY",
        DEFAULT_ENHANCEMENT_CONCURRENCY,
        1,
        32,
    ) as usize
}

/// Stream a transparent address's transaction history in `[start, end]`
/// and parse each returned transaction. Network-only (no DB writes) so it
/// can run concurrently with other address scans; the caller applies the
/// results serially under the wallet-DB write lock.
struct AddressTxFetch {
    receiver: mpsc::Receiver<Result<(Option<BlockHeight>, Transaction), SyncError>>,
    handle: tokio::task::JoinHandle<()>,
}

impl Drop for AddressTxFetch {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

/// Starts a transparent-address history stream and forwards parsed
/// transactions through a bounded channel. The returned task is aborted when
/// the consumer stops early (cancel, mode switch, or a failed sibling).
async fn start_address_txs<ShouldExit>(
    client: &mut CompactTxStreamerClient<Channel>,
    address: String,
    start: u64,
    end: u64,
    should_exit: &ShouldExit,
) -> Result<Option<AddressTxFetch>, SyncError>
where
    ShouldExit: Fn() -> bool + Sync,
{
    let stream_result = tokio::select! {
        result = lwd::get_taddress_txids(client, address, start, end) => Some(result),
        _ = wait_until_exit(should_exit) => None,
    };
    let Some(stream_result) = stream_result else {
        return Ok(None);
    };
    let mut stream = stream_result?;
    let (sender, receiver) = mpsc::channel(ADDRESS_TX_CHANNEL_CAPACITY);
    let handle = tokio::spawn(async move {
        loop {
            match lwd::next_stream_message(&mut stream, "get_taddress_txids stream").await {
                Ok(Some(raw)) => {
                    if raw.data.is_empty() {
                        continue;
                    }
                    let mined_height = match mined_height_from_raw_height(raw.height) {
                        Ok(height) => height,
                        Err(e) => {
                            let _ = sender.send(Err(e)).await;
                            break;
                        }
                    };
                    match Transaction::read(&raw.data[..], BranchId::Sapling) {
                        Ok(tx) => {
                            if sender.send(Ok((mined_height, tx))).await.is_err() {
                                break;
                            }
                        }
                        Err(e) => log::warn!("sync: Transaction::read (addr) failed: {e}"),
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    let _ = sender.send(Err(e)).await;
                    break;
                }
            }
        }
    });
    Ok(Some(AddressTxFetch { receiver, handle }))
}

async fn fill_missing_transparent_fee<ShouldExit>(
    client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    tx: &Transaction,
    should_exit: &ShouldExit,
) -> Result<(), SyncError>
where
    ShouldExit: Fn() -> bool + Sync,
{
    if should_exit() {
        return Ok(());
    }
    let Some(bundle) = tx.transparent_bundle() else {
        return Ok(());
    };
    if bundle.vin.is_empty() || !should_fill_missing_transparent_fee(db_path, tx)? {
        return Ok(());
    }

    let prevout_values = fetch_transparent_prevout_values(client, tx, should_exit).await?;
    if prevout_values.is_empty() {
        return Ok(());
    }

    let Some(fee) = fee_from_prevout_values(tx, &prevout_values)
        .map_err(|e| SyncError::parse(format!("transparent fee computation failed: {e:?}")))?
    else {
        return Ok(());
    };

    persist_fee_if_missing(db_path, tx, fee)
}

async fn fetch_transparent_prevout_values<ShouldExit>(
    client: &mut CompactTxStreamerClient<Channel>,
    tx: &Transaction,
    should_exit: &ShouldExit,
) -> Result<BTreeMap<OutPoint, Zatoshis>, SyncError>
where
    ShouldExit: Fn() -> bool + Sync,
{
    let Some(bundle) = tx.transparent_bundle() else {
        return Ok(BTreeMap::new());
    };

    let mut prevout_values = BTreeMap::new();
    for txin in &bundle.vin {
        if should_exit() {
            return Ok(BTreeMap::new());
        }
        let outpoint = txin.prevout();
        if is_null_outpoint(outpoint) {
            return Ok(BTreeMap::new());
        }
        if prevout_values.contains_key(outpoint) {
            continue;
        }

        let parent_result = tokio::select! {
            result = lwd::get_transaction(client, outpoint.hash().to_vec()) => Some(result),
            _ = wait_until_exit(should_exit) => None,
        };
        let Some(parent_result) = parent_result else {
            return Ok(BTreeMap::new());
        };
        let parent_raw = match parent_result {
            Ok(raw) => raw,
            Err(e) => {
                log::warn!(
                    "sync: could not fetch transparent prevout {}:{} for fee on {}: {e}",
                    hex::encode(outpoint.hash()),
                    outpoint.n(),
                    tx.txid()
                );
                return Ok(BTreeMap::new());
            }
        };
        if parent_raw.data.is_empty() {
            return Ok(BTreeMap::new());
        }

        let parent_tx = match Transaction::read(&parent_raw.data[..], BranchId::Sapling) {
            Ok(tx) => tx,
            Err(e) => {
                log::warn!(
                    "sync: could not parse transparent prevout transaction {} for fee on {}: {e}",
                    hex::encode(outpoint.hash()),
                    tx.txid()
                );
                return Ok(BTreeMap::new());
            }
        };

        let Some(parent_bundle) = parent_tx.transparent_bundle() else {
            return Ok(BTreeMap::new());
        };
        let Ok(output_index) = usize::try_from(outpoint.n()) else {
            return Ok(BTreeMap::new());
        };
        let Some(parent_output) = parent_bundle.vout.get(output_index) else {
            return Ok(BTreeMap::new());
        };

        prevout_values.insert(outpoint.clone(), parent_output.value());
    }

    Ok(prevout_values)
}

/// Resolves as soon as the caller's cancel/mode predicate becomes true.
/// Keeping this as the second branch of each network `select!` means a sync
/// handoff does not have to wait for a slow or stalled lightwalletd RPC.
async fn wait_until_exit<ShouldExit>(should_exit: &ShouldExit)
where
    ShouldExit: Fn() -> bool + Sync,
{
    while !should_exit() {
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
}

fn should_fill_missing_transparent_fee(db_path: &str, tx: &Transaction) -> Result<bool, SyncError> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee lookup: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee lookup busy timeout: {e}")))?;

    // Backfill transaction-level transparent fees for every wallet-relevant
    // transaction, including receives. Received receipts label this separately
    // as a network fee because the sender paid it.
    let fillable_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*)
             FROM transactions t
             WHERE t.txid = ?1
             AND t.fee IS NULL
             AND EXISTS (
                 SELECT 1
                 FROM v_transactions vt
                 WHERE vt.txid = t.txid
             )",
            rusqlite::params![tx.txid().as_ref()],
            |row| row.get(0),
        )
        .map_err(|e| SyncError::db(format!("query transparent fee: {e}")))?;

    Ok(fillable_rows > 0)
}

fn is_null_outpoint(outpoint: &OutPoint) -> bool {
    outpoint.hash() == &[0u8; 32] && outpoint.n() == u32::MAX
}

fn fee_from_prevout_values(
    tx: &Transaction,
    prevout_values: &BTreeMap<OutPoint, Zatoshis>,
) -> Result<Option<Zatoshis>, BalanceError> {
    tx.fee_paid(|outpoint| {
        Ok::<Option<Zatoshis>, BalanceError>(prevout_values.get(outpoint).copied())
    })
}

fn persist_fee_if_missing(db_path: &str, tx: &Transaction, fee: Zatoshis) -> Result<(), SyncError> {
    let fee_zatoshi = i64::try_from(u64::from(fee))
        .map_err(|_| SyncError::parse("transparent fee exceeded SQLite integer range"))?;
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee update: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee update busy timeout: {e}")))?;

    with_wallet_db_write_lock("sync_engine.enhance.persist_transparent_fee", || {
        conn.execute(
            "UPDATE transactions
             SET fee = ?2
             WHERE txid = ?1
             AND fee IS NULL",
            rusqlite::params![tx.txid().as_ref(), fee_zatoshi],
        )
        .map_err(|e| SyncError::db(format!("update transparent fee: {e}")))
    })?;

    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GetTransactionErrorAction {
    MarkTxidNotRecognized,
    RetryAsNetwork,
}

fn classify_get_transaction_error(status: &Status) -> GetTransactionErrorAction {
    match status.code() {
        Code::NotFound => GetTransactionErrorAction::MarkTxidNotRecognized,
        _ => GetTransactionErrorAction::RetryAsNetwork,
    }
}

fn mined_height_from_raw_height(raw_height: u64) -> Result<Option<BlockHeight>, SyncError> {
    match raw_height {
        0 | u64::MAX => Ok(None),
        h if h <= u32::MAX as u64 => Ok(Some(BlockHeight::from_u32(h as u32))),
        h => Err(SyncError::parse(format!(
            "raw transaction height out of range: {h}"
        ))),
    }
}

fn transaction_status_from_raw_height(raw_height: u64) -> Result<TransactionStatus, SyncError> {
    mined_height_from_raw_height(raw_height).map(|height| match height {
        Some(height) => TransactionStatus::Mined(height),
        None => TransactionStatus::NotInMainChain,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn transparent_fee_test_tx() -> Transaction {
        let tx_bytes = hex::decode(
            "0400008085202f8901aee37187e843da597683c26c01457f5fd3b1a038996ef74dc8d60d483aaf395a000000006b483045022100874c70db77ea9e93f75cc83a9e141e17c8eb97588e29fe4e307631fdde4f162a02203493df62d648cd86a1189eaf9bcafc652bc14c5df02519d9e45e25b32aaffb5b012102106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716ffffffff02764e1900000000001976a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac560ca400000000001976a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac00000000000000000000000000000000000000",
        )
        .unwrap();
        Transaction::read(&tx_bytes[..], BranchId::Sapling).unwrap()
    }

    fn transparent_fee_test_db(
        tx: &Transaction,
        account_balance_delta: i64,
    ) -> tempfile::NamedTempFile {
        transparent_fee_test_db_with_optional_wallet_row(tx, Some(account_balance_delta))
    }

    fn transparent_fee_test_db_with_optional_wallet_row(
        tx: &Transaction,
        account_balance_delta: Option<i64>,
    ) -> tempfile::NamedTempFile {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 txid BLOB NOT NULL UNIQUE,
                 fee INTEGER
             );
             CREATE TABLE v_transactions (
                 txid BLOB NOT NULL,
                 account_balance_delta INTEGER NOT NULL
             );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, fee) VALUES (?1, NULL)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();
        if let Some(account_balance_delta) = account_balance_delta {
            conn.execute(
                "INSERT INTO v_transactions (txid, account_balance_delta)
                 VALUES (?1, ?2)",
                rusqlite::params![tx.txid().as_ref(), account_balance_delta],
            )
            .unwrap();
        }
        file
    }

    #[test]
    fn get_transaction_not_found_marks_txid_not_recognized() {
        let status = Status::new(Code::NotFound, "txid not recognized");

        assert_eq!(
            classify_get_transaction_error(&status),
            GetTransactionErrorAction::MarkTxidNotRecognized,
        );
    }

    #[test]
    fn get_transaction_transient_errors_retry_as_network() {
        for code in [
            Code::Unavailable,
            Code::DeadlineExceeded,
            Code::Cancelled,
            Code::Unknown,
            Code::Internal,
        ] {
            let status = Status::new(code, "temporary failure");
            assert_eq!(
                classify_get_transaction_error(&status),
                GetTransactionErrorAction::RetryAsNetwork,
            );
        }
    }

    #[test]
    fn transparent_fee_uses_exact_prevout_output_index() {
        let tx = transparent_fee_test_tx();
        let prevout = tx.transparent_bundle().unwrap().vin[0].prevout().clone();
        let input_value = Zatoshis::from_nonnegative_i64(12_449_548).unwrap();

        let mut wrong_prevout_values = BTreeMap::new();
        wrong_prevout_values.insert(OutPoint::new(*prevout.hash(), prevout.n() + 1), input_value);
        assert_eq!(
            fee_from_prevout_values(&tx, &wrong_prevout_values).unwrap(),
            None
        );

        let mut prevout_values = BTreeMap::new();
        prevout_values.insert(prevout, input_value);
        assert_eq!(
            fee_from_prevout_values(&tx, &prevout_values)
                .unwrap()
                .map(u64::from),
            Some(40_000),
        );
    }

    #[test]
    fn transparent_fee_backfill_requires_wallet_relevance() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db_with_optional_wallet_row(&tx, None);

        assert!(!should_fill_missing_transparent_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn transparent_fee_backfill_allows_positive_wallet_delta() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 1_000_000);

        assert!(should_fill_missing_transparent_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn transparent_fee_backfill_allows_negative_wallet_delta() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, -40_000);

        assert!(should_fill_missing_transparent_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn raw_height_zero_and_fork_sentinel_are_not_main_chain() {
        assert_eq!(
            transaction_status_from_raw_height(0).unwrap(),
            TransactionStatus::NotInMainChain,
        );
        assert_eq!(
            transaction_status_from_raw_height(u64::MAX).unwrap(),
            TransactionStatus::NotInMainChain,
        );
    }

    #[test]
    fn raw_height_nonzero_non_sentinel_is_mined() {
        match transaction_status_from_raw_height(1_234_567).unwrap() {
            TransactionStatus::Mined(height) => {
                assert_eq!(u32::from(height), 1_234_567);
            }
            other => panic!("expected mined status, got {other:?}"),
        }
    }

    #[test]
    fn raw_height_out_of_u32_range_is_parse_error() {
        assert!(matches!(
            mined_height_from_raw_height(u32::MAX as u64 + 1),
            Err(SyncError::Parse(_)),
        ));
    }
}
