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
//! Librustzcash signals these gaps through two snapshots. Payload retrieval is
//! routed by `transaction_enhancement_work()` and scheduled by
//! `enhance_pir::EnhancementSync`, which hands only routed public requests to
//! [`PublicPayloads`] (`GetTransaction` + `decrypt_and_store_transaction`).
//! Status observation and transparent-address history come from
//! `transaction_data_requests()` and are serviced by
//! [`run_transaction_data_requests`], which ignores payload requests so that no
//! second routing decision can dispatch them. Both loops are bounded because
//! servicing one request can legally populate new requests (e.g. a
//! newly-decrypted transaction may reveal additional parent transactions).

use std::collections::{BTreeMap, HashSet};
use std::rc::Rc;

use rusqlite::{types::Value, vtab::array::Array};

use futures::{FutureExt, StreamExt};

use tonic::{transport::Channel, Code, Status};
use transparent::bundle::OutPoint;
use zcash_client_backend::{
    data_api::{
        wallet::decrypt_and_store_transaction, PublicTransactionEnhancementRequest,
        TransactionDataRequest, WalletRead, WalletWrite,
    },
    proto::service::{compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction},
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::{BlockHeight, BranchId};
use zcash_protocol::value::{BalanceError, Zatoshis};

use crate::wallet::db::{
    open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::transaction_data::payload::get_transaction_payload;
use zakura_transaction_status::{lightwalletd::LightwalletdSource, StatusRequest};

use super::{block_source::MemoryBlockSource, lwd, SyncError, WalletDatabase};

/// A shared transaction can retain raw bytes after account deletion while losing
/// that account's sent outputs. Requeue it when encountered by a new scan.
///
/// Caller holds the wallet write lock. Queue before the scan so the existing
/// durable enhancement queue survives cancellation, errors, and process exit.
/// No import-time or startup sweep: only transactions in this downloaded batch.
/// Heights include transparent-only transactions omitted from compact blocks;
/// hashes also cover transactions whose mined height was cleared by a rewind.
pub(super) fn queue_stored_transactions(
    db_path: &str,
    blocks: &MemoryBlockSource,
) -> Result<(), SyncError> {
    let Some(heights) = blocks.height_range() else {
        return Ok(());
    };
    let hashes: Array = Rc::new(
        blocks
            .transaction_hashes()
            .map(|hash| Value::Blob(hash.to_vec()))
            .collect(),
    );
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    // query_type=1 is the SDK's Enhancement request. Status requests (0) and
    // dependency links already in the queue must be preserved.
    let count = conn
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type, dependent_transaction_id)
         SELECT txid, 1, NULL FROM transactions
         WHERE raw IS NOT NULL
           AND (txid IN rarray(?1) OR mined_height BETWEEN ?2 AND ?3)
         ON CONFLICT (txid, query_type) DO NOTHING",
            rusqlite::params![hashes, heights.start(), heights.end()],
        )
        .map_err(|error| SyncError::db(format!("queue scanned stored transactions: {error}")))?;
    if count > 0 {
        log::info!("sync: queued {count} stored transaction(s) for scan-time enhancement");
    }
    Ok(())
}

fn store_transaction_observation(
    db: &mut WalletDatabase,
    txid: TxId,
    observation: crate::wallet::transaction_data::TransactionObservation,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.enhance.set_transaction_status", || {
        db.set_transaction_status(txid, observation.wallet_status())
    })
    .map_err(|e: zcash_client_sqlite::error::SqliteClientError| {
        SyncError::db(format!("set_transaction_status: {e}"))
    })
}

/// Retrieves routed public payloads over lightwalletd for one sync pass.
///
/// Callers pass only [`PublicTransactionEnhancementRequest`]s taken from the
/// wallet's routed enhancement snapshot; this type never selects work itself.
/// An explicit "txid not recognized" response retires only enhancement work.
/// Other failures leave the request durable, skip that transaction for the
/// rest of the pass, and are reported by [`Self::finish`] as a retryable error.
#[derive(Default)]
pub(super) struct PublicPayloads {
    failed: HashSet<TxId>,
    deferred_error: Option<SyncError>,
}

impl PublicPayloads {
    /// Dispatches each request not already failed in this pass, stopping
    /// before the next dispatch once `should_exit` is set.
    pub(super) async fn run(
        &mut self,
        client: &mut CompactTxStreamerClient<Channel>,
        db: &mut WalletDatabase,
        db_path: &str,
        network: WalletNetwork,
        requests: &[PublicTransactionEnhancementRequest],
        should_exit: &impl Fn() -> bool,
    ) {
        for request in requests {
            if should_exit() {
                return;
            }
            let txid = request.txid();
            if self.failed.contains(&txid) {
                continue;
            }
            let txid_str = format!("{txid}");

            match cancelable(get_transaction_payload(client, txid), should_exit).await {
                Ok(raw) => match decode_enhancement_payload(&raw, txid) {
                    Ok((tx, mined_height)) => {
                        if let Err(e) = with_wallet_db_write_lock(
                            "sync_engine.enhance.decrypt_and_store_transaction",
                            || decrypt_and_store_transaction(&network, db, &tx, mined_height),
                        ) {
                            log::error!("sync: decrypt_and_store_transaction failed: {e}");
                            self.failed.insert(txid);
                            self.deferred_error.get_or_insert_with(|| {
                                SyncError::db(format!(
                                    "decrypt_and_store_transaction failed for {txid_str}: {e}"
                                ))
                            });
                        }
                        if let Err(e) = fill_missing_fee(client, db_path, &tx, should_exit).await {
                            log::warn!("sync: fee enhancement failed for {txid_str}: {e}");
                        }
                    }
                    Err(e) => {
                        log::warn!("sync: invalid enhancement payload for {txid_str}: {e}");
                        self.failed.insert(txid);
                        self.deferred_error.get_or_insert(e);
                    }
                },
                Err(e) => match classify_get_transaction_error(&e) {
                    GetTransactionErrorAction::CompleteEnhancementNotFound => {
                        log::warn!("sync: get_transaction did not recognize {txid_str}: {e}");
                        self.failed.insert(txid);
                        if let Err(e) = with_wallet_db_write_lock(
                            "sync_engine.enhance.notify_transaction_enhancement_not_found",
                            || db.notify_transaction_enhancement_not_found(txid),
                        ) {
                            log::error!(
                                "sync: notify_transaction_enhancement_not_found failed: {e}"
                            );
                            self.deferred_error.get_or_insert_with(|| {
                                SyncError::db(format!(
                                    "notify_transaction_enhancement_not_found failed for {txid}: {e}"
                                ))
                            });
                        }
                    }
                    GetTransactionErrorAction::RetryAsNetwork => {
                        self.failed.insert(txid);
                        self.deferred_error.get_or_insert_with(|| {
                            SyncError::net(format!("get_transaction failed for {txid_str}: {e}"))
                        });
                    }
                },
            }
        }
    }

    /// Reports the first retryable payload failure of this pass, if any.
    pub(super) fn finish(self) -> Result<(), SyncError> {
        self.deferred_error.map_or(Ok(()), Err)
    }
}

/// Services status observation and transparent-address history from
/// `db.transaction_data_requests()` until no such request is actionable.
/// Payload ([`TransactionDataRequest::Enhancement`]) requests are ignored:
/// they are routed and dispatched only by the enhancement scheduler.
/// Returns `SyncError::Db` if `db.transaction_data_requests()` itself fails;
/// status transport failures bubble up as `SyncError::Network`.
pub(super) async fn run_transaction_data_requests(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    should_exit: &(impl Fn() -> bool + Sync),
) -> Result<(), SyncError> {
    let status_client = client.clone();
    let public_source =
        LightwalletdSource::new(move || async move { Ok(status_client) }, should_exit);
    let mut status_reader = super::status_pir::reader(db_path, network, should_exit, public_source);
    let mut observed_statuses = HashSet::new();
    // Retry a failed address on a later invocation, not in all three queue passes.
    let mut failed_addresses = HashSet::new();

    backfill_stored_fees(client, db, db_path, should_exit).await?;

    for _ in 0..3 {
        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests: {e}")))?;
        let status_requests: Vec<_> = requests
            .iter()
            .cloned()
            .filter_map(TransactionDataRequest::into_status_request)
            .filter(|request| !observed_statuses.contains(&request.txid()))
            .collect();
        // Payload requests never make this pass actionable. Nor do
        // address-scoped requests without an `end` height, which we can't
        // service without synthesizing a range; break rather than looping
        // forever on the same inert queue.
        let actionable = !status_requests.is_empty()
            || requests.iter().any(|request| match request {
                TransactionDataRequest::TransactionsInvolvingAddress(request) => {
                    request.block_range_end().is_some()
                        && !failed_addresses.contains(&request.address())
                }
                _ => false,
            });
        if !actionable {
            break;
        }

        for request in status_requests {
            let txid = request.txid();
            let observation = match status_reader
                .observe(StatusRequest {
                    txid,
                    coverage: zakura_pir_status::LocalCoverageContext::default(),
                })
                .await
            {
                Ok(observation) => observation.into(),
                Err(zakura_transaction_status::StatusError::Cancelled) => return Ok(()),
                Err(error) => return Err(SyncError::net(error.to_string())),
            };
            if should_exit() {
                return Ok(());
            }
            store_transaction_observation(db, txid, observation)?;
            observed_statuses.insert(txid);
        }
        let mut planned = super::address_history::plan(&requests);
        planned.retain(|group| !failed_addresses.contains(&group[0].address()));
        let download_client = client.clone();
        let open: super::address_history::OpenHistory = Box::new(move |req| {
            let mut client = download_client.clone();
            async move {
                let address =
                    zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
                let stream = lwd::get_taddress_txids(
                    &mut client,
                    address,
                    u64::from(u32::from(req.block_range_start())),
                    u64::from(u32::from(req.block_range_end().unwrap())) - 1,
                )
                .await?;
                Ok(
                    futures::stream::try_unfold(stream, |mut stream| async move {
                        Ok(
                            lwd::next_stream_message(&mut stream, "get_taddress_txids stream")
                                .await?
                                .map(|raw| (raw, stream)),
                        )
                    })
                    .boxed(),
                )
            }
            .boxed()
        });
        let mut reads = super::address_history::HistoryReads::new(planned, open);
        loop {
            let event = tokio::select! {
                biased;
                _ = super::watch_for_exit(should_exit) => return Ok(()),
                event = reads.next() => event,
            };
            let Some((mut read, result)) = event else {
                break;
            };
            if should_exit() {
                return Ok(());
            }
            let req = read.request().clone();
            match result? {
                Some(raw) => {
                    let tx = match store_address_transaction(&network, db, &raw.data, raw.height) {
                        Ok(tx) => tx,
                        Err(error) => {
                            log::warn!("sync: address transaction processing failed; leaving range unchecked for retry: {error}");
                            failed_addresses.insert(req.address());
                            continue;
                        }
                    };
                    let fee_result = tokio::select! {
                        biased;
                        _ = super::watch_for_exit(should_exit) => return Ok(()),
                        result = fill_missing_fee(client, db_path, &tx, should_exit) => result,
                    };
                    if let Err(error) = fee_result {
                        log::warn!(
                            "sync: fee enhancement (addr) failed for {}: {error}",
                            tx.txid()
                        );
                    }
                }
                None => {
                    if let Err(error) =
                        with_wallet_db_write_lock("sync_engine.notify_address_checked", || {
                            db.notify_address_checked(
                                req.clone(),
                                req.block_range_end().unwrap() - 1,
                            )
                        })
                    {
                        log::warn!("sync: address completion write failed; retrying on a later sync: {error}");
                        failed_addresses.insert(req.address());
                        continue;
                    }
                    read.finish_range();
                }
            }
            reads.resume(read);
        }
    }
    Ok(())
}

/// Parse and store before allowing the caller to acknowledge an address range.
fn store_address_transaction(
    network: &WalletNetwork,
    db: &mut WalletDatabase,
    bytes: &[u8],
    raw_height: u64,
) -> Result<Transaction, SyncError> {
    let mined_height = mined_height_from_raw_height(raw_height)?;
    let tx = Transaction::read(bytes, BranchId::Sapling)
        .map_err(|e| SyncError::parse(format!("Transaction::read (addr): {e}")))?;
    with_wallet_db_write_lock("sync_engine.enhance.decrypt_and_store_transaction", || {
        decrypt_and_store_transaction(network, db, &tx, mined_height)
    })
    .map_err(|e| SyncError::db(format!("decrypt_and_store_transaction (addr): {e}")))?;
    Ok(tx)
}

/// Backfills fees for stored transactions whose status requests are dormant
/// while their mined heights are known.
async fn backfill_stored_fees(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &WalletDatabase,
    db_path: &str,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    for txid in stored_transaction_ids_missing_fee(db_path)? {
        if should_exit() {
            return Ok(());
        }
        let txid_str = format!("{txid}");
        match db.get_transaction(txid) {
            Ok(Some(tx)) => {
                if let Err(e) = fill_missing_fee(client, db_path, &tx, should_exit).await {
                    log::warn!("sync: stored fee enhancement failed for {txid_str}: {e}");
                }
            }
            Ok(None) => {}
            Err(e) => log::warn!(
                "sync: could not read stored transaction for fee enhancement {txid_str}: {e}"
            ),
        }
    }

    Ok(())
}

fn stored_transaction_ids_missing_fee(db_path: &str) -> Result<Vec<TxId>, SyncError> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee scan: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee scan busy timeout: {e}")))?;

    let mut stmt = conn
        .prepare(
            "SELECT t.txid
             FROM transactions t
             WHERE t.raw IS NOT NULL
             AND t.fee IS NULL
             AND (t.tx_index IS NULL OR t.tx_index != 0)
             AND EXISTS (
                 SELECT 1
                 FROM v_transactions vt
                 WHERE vt.txid = t.txid
             )",
        )
        .map_err(|e| SyncError::db(format!("prepare missing fee scan: {e}")))?;
    let rows = stmt
        .query_map([], |row| row.get(0).map(TxId::from_bytes))
        .map_err(|e| SyncError::db(format!("query missing fees: {e}")))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| SyncError::db(format!("read missing fee transaction: {e}")))
}

async fn fill_missing_fee(
    client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    tx: &Transaction,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    if !should_fill_missing_fee(db_path, tx)? {
        return Ok(());
    }

    // Fully shielded transactions need no parent lookup: their fee is
    // determined entirely by the public shielded-pool value balances. Persist
    // that fee too so these rows do not remain in the backfill query forever.
    let prevout_values = match tx.transparent_bundle() {
        Some(bundle) if !bundle.vin.is_empty() => {
            let values = fetch_transparent_prevout_values(client, tx, should_exit).await?;
            if values.is_empty() {
                return Ok(());
            }
            values
        }
        _ => BTreeMap::new(),
    };

    let Some(fee) = fee_from_prevout_values(tx, &prevout_values)
        .map_err(|e| SyncError::parse(format!("fee computation failed: {e:?}")))?
    else {
        return Ok(());
    };

    persist_fee_if_missing(db_path, tx, fee)
}

async fn fetch_transparent_prevout_values(
    client: &mut CompactTxStreamerClient<Channel>,
    tx: &Transaction,
    should_exit: &impl Fn() -> bool,
) -> Result<BTreeMap<OutPoint, Zatoshis>, SyncError> {
    let Some(bundle) = tx.transparent_bundle() else {
        return Ok(BTreeMap::new());
    };

    let mut prevout_values = BTreeMap::new();
    for txin in &bundle.vin {
        let outpoint = txin.prevout();
        if is_null_outpoint(outpoint) {
            return Ok(BTreeMap::new());
        }
        if prevout_values.contains_key(outpoint) {
            continue;
        }

        let parent_raw = match cancelable(
            get_transaction_payload(client, TxId::from_bytes(*outpoint.hash())),
            should_exit,
        )
        .await
        {
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

fn should_fill_missing_fee(db_path: &str, tx: &Transaction) -> Result<bool, SyncError> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee lookup: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee lookup busy timeout: {e}")))?;

    // Backfill transaction fees for every wallet-relevant transaction,
    // including receives. Received receipts label this separately as a network
    // fee because the sender paid it.
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
        .map_err(|e| SyncError::db(format!("query missing fee: {e}")))?;

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
        .map_err(|_| SyncError::parse("fee exceeded SQLite integer range"))?;
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee update: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee update busy timeout: {e}")))?;

    with_wallet_db_write_lock("sync_engine.enhance.persist_fee", || {
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
    CompleteEnhancementNotFound,
    RetryAsNetwork,
}

fn classify_get_transaction_error(status: &Status) -> GetTransactionErrorAction {
    match status.code() {
        Code::NotFound => GetTransactionErrorAction::CompleteEnhancementNotFound,
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

fn decode_enhancement_payload(
    raw: &RawTransaction,
    expected_txid: TxId,
) -> Result<(Transaction, Option<BlockHeight>), SyncError> {
    let mined_height = mined_height_from_raw_height(raw.height)?;
    let tx = Transaction::read(&raw.data[..], BranchId::Sapling)
        .map_err(|e| SyncError::parse(format!("enhancement transaction: {e}")))?;
    if tx.txid() != expected_txid {
        return Err(SyncError::parse("enhancement transaction ID mismatch"));
    }
    Ok((tx, mined_height))
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::proto::compact_formats::{CompactBlock, CompactTx};

    #[test]
    fn scan_enhancement_is_batch_scoped_durable_and_preserves_existing_requests() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        rusqlite::vtab::array::load_module(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (txid BLOB PRIMARY KEY, raw BLOB, mined_height INTEGER);
             CREATE TABLE tx_retrieval_queue (
                txid BLOB, query_type INTEGER, dependent_transaction_id INTEGER,
                PRIMARY KEY(txid, query_type));
             INSERT INTO transactions VALUES (X'01', X'AB', NULL), (X'02', NULL, 10),
                (X'03', X'CD', 11), (X'05', X'EF', 10), (X'06', X'EF', 9);
             INSERT INTO tx_retrieval_queue VALUES (X'01', 0, 7), (X'03', 1, 9);",
        )
        .unwrap();
        // 01: stored raw, missing details; 02: newly scanned, no raw yet;
        // 03/06: outside this batch; 04: unrelated chain transaction;
        // 05: transparent-only transaction omitted from compact data.
        let blocks = MemoryBlockSource::new(vec![CompactBlock {
            height: 10,
            vtx: [1, 2, 4]
                .into_iter()
                .map(|id| CompactTx {
                    txid: vec![id],
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        }]);
        queue_stored_transactions(file.path().to_str().unwrap(), &blocks).unwrap();
        queue_stored_transactions(file.path().to_str().unwrap(), &blocks).unwrap();
        drop(conn);
        // Reopen without running enhancement: a cancelled scan retains intent.
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let rows: Vec<(Vec<u8>, i64, Option<i64>)> = conn.prepare(
            "SELECT txid, query_type, dependent_transaction_id FROM tx_retrieval_queue ORDER BY txid, query_type"
        ).unwrap().query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
            .unwrap().collect::<Result<_, _>>().unwrap();
        assert_eq!(
            rows,
            vec![
                (vec![1], 0, Some(7)),
                (vec![1], 1, None),
                (vec![3], 1, Some(9)),
                (vec![5], 1, None)
            ]
        );
    }

    fn scanned_transaction_missing_fee_test_db(
        mined_height: BlockHeight,
    ) -> (tempfile::NamedTempFile, WalletDatabase, Transaction) {
        let (tx, raw) = transparent_fee_test_tx_and_bytes();
        let txid = tx.txid();
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            db_path,
            WalletNetwork::Regtest,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        zcash_client_sqlite::wallet::init::init_wallet_db(&mut db, None).unwrap();
        db.update_chain_tip(mined_height + 10).unwrap();
        drop(db);

        let conn = rusqlite::Connection::open(db_path).unwrap();
        conn.execute(
            "INSERT INTO transactions
                (txid, mined_height, raw, fee, min_observed_height)
             VALUES (?1, ?2, ?3, NULL, ?2)",
            rusqlite::params![txid.as_ref(), u32::from(mined_height), raw],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO accounts
                (uuid, account_kind, uivk, birthday_height, has_spend_key)
             VALUES (randomblob(16), 1, 'test-uivk', 1, 0)",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO sapling_received_notes
                (transaction_id, output_index, account_id, diversifier, value,
                 rcm, is_change, commitment_tree_position, recipient_key_scope)
             SELECT id_tx, 0, 1, X'00', 1, X'00', 1, 1, 1
             FROM transactions WHERE txid = ?1",
            rusqlite::params![txid.as_ref()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type)
             VALUES (?1, 0)",
            rusqlite::params![txid.as_ref()],
        )
        .unwrap();
        drop(conn);

        let db = crate::wallet::db::open_wallet_db_with_timeout(
            db_path,
            WalletNetwork::Regtest,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        (file, db, tx)
    }

    #[test]
    fn observation_does_not_hydrate_payload_or_fees() {
        use crate::wallet::transaction_data::TransactionObservation;
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100));
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool).unwrap();
        let row: (Option<Vec<u8>>, Option<i64>, Option<i64>) = conn
            .query_row(
                "SELECT raw, fee, confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(row, (None, None, Some(110)));
    }

    #[test]
    fn observation_cannot_retire_pending_payload_work() {
        use crate::wallet::transaction_data::TransactionObservation;
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100));
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();
        for observation in [
            TransactionObservation::NotFound,
            TransactionObservation::Mempool,
            TransactionObservation::Forked,
            TransactionObservation::Mined(BlockHeight::from_u32(100)),
        ] {
            store_transaction_observation(&mut db, tx.txid(), observation).unwrap();
            let requests = db.transaction_data_requests().unwrap();
            assert!(requests.contains(&TransactionDataRequest::Enhancement(tx.txid())));
        }
        // Payload completion does not affect status persistence.
        conn.execute("DELETE FROM tx_retrieval_queue WHERE query_type = 1", [])
            .unwrap();
        store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool).unwrap();
    }

    #[test]
    fn payload_absence_and_status_observation_complete_independently() {
        use crate::wallet::transaction_data::TransactionObservation;
        for status_first in [false, true] {
            let (file, mut db, tx) =
                scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100));
            let conn = rusqlite::Connection::open(file.path()).unwrap();
            conn.execute(
                "UPDATE transactions SET raw = NULL, mined_height = NULL",
                [],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
                rusqlite::params![tx.txid().as_ref()],
            )
            .unwrap();
            if status_first {
                store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool)
                    .unwrap();
            }
            db.notify_transaction_enhancement_not_found(tx.txid())
                .unwrap();
            let requests = db.transaction_data_requests().unwrap();
            assert!(!requests.contains(&TransactionDataRequest::Enhancement(tx.txid())));
            if !status_first {
                assert!(requests.contains(&TransactionDataRequest::GetStatus(tx.txid())));
                store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool)
                    .unwrap();
            }
        }
    }

    #[tokio::test]
    async fn failed_payload_is_retryable_and_status_pass_never_dispatches_payloads() {
        use bytes::Bytes;
        use http_body_util::Full;
        use hyper::service::service_fn;
        use prost::Message;
        use std::sync::atomic::{AtomicUsize, Ordering};

        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100));
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let calls = std::sync::Arc::new(AtomicUsize::new(0));
        let calls_for_server = calls.clone();
        let (_, raw_bytes) = transparent_fee_test_tx_and_bytes();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = hyper_util::rt::TokioIo::new(stream);
            let service = service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                let calls = calls_for_server.clone();
                let raw_bytes = raw_bytes.clone();
                async move {
                    assert!(request.uri().path().ends_with("/GetTransaction"));
                    let response = if calls.fetch_add(1, Ordering::SeqCst) == 0 {
                        hyper::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", "14")
                            .header("grpc-message", "temporary failure")
                            .body(Full::new(Bytes::new()))
                            .unwrap()
                    } else {
                        let raw = RawTransaction {
                            data: raw_bytes,
                            height: 0,
                        };
                        let message = raw.encode_to_vec();
                        let mut frame = vec![0];
                        frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
                        frame.extend_from_slice(&message);
                        hyper::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", "0")
                            .body(Full::new(Bytes::from(frame)))
                            .unwrap()
                    };
                    Ok::<_, std::convert::Infallible>(response)
                }
            });
            hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
                .serve_connection(io, service)
                .await
                .unwrap();
        });
        let channel = tonic::transport::Endpoint::from_shared(format!("http://{address}"))
            .unwrap()
            .connect()
            .await
            .unwrap();
        let mut client = CompactTxStreamerClient::new(channel);
        let db_path = file.path().to_str().unwrap();
        let routed = [TransactionDataRequest::Enhancement(tx.txid())
            .into_public_enhancement_request()
            .unwrap()];
        let mut payloads = PublicPayloads::default();
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            payloads.run(
                &mut client,
                &mut db,
                db_path,
                WalletNetwork::Regtest,
                &routed,
                &|| false,
            ),
        )
        .await
        .expect("payload dispatch timed out");
        // The status pass never dispatches payload work, even though the
        // failed payload request remains queued.
        let status = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            run_transaction_data_requests(
                &mut client,
                &mut db,
                db_path,
                WalletNetwork::Regtest,
                &|| false,
            ),
        )
        .await
        .expect("status pass timed out");
        server.abort();

        assert!(status.is_ok());
        assert!(
            matches!(payloads.finish(), Err(SyncError::Network(message)) if message.contains("temporary failure"))
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert!(db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::Enhancement(tx.txid())));
        let observed: Option<i64> = conn
            .query_row(
                "SELECT confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(observed, Some(110));
    }

    fn transparent_fee_test_tx_and_bytes() -> (Transaction, Vec<u8>) {
        let tx_bytes = hex::decode(
            "0400008085202f8901aee37187e843da597683c26c01457f5fd3b1a038996ef74dc8d60d483aaf395a000000006b483045022100874c70db77ea9e93f75cc83a9e141e17c8eb97588e29fe4e307631fdde4f162a02203493df62d648cd86a1189eaf9bcafc652bc14c5df02519d9e45e25b32aaffb5b012102106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716ffffffff02764e1900000000001976a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac560ca400000000001976a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac00000000000000000000000000000000000000",
        )
        .unwrap();
        let tx = Transaction::read(&tx_bytes[..], BranchId::Sapling).unwrap();
        (tx, tx_bytes)
    }

    fn transparent_fee_test_tx() -> Transaction {
        transparent_fee_test_tx_and_bytes().0
    }

    fn no_transparent_inputs_test_tx() -> Transaction {
        use zcash_primitives::transaction::{Authorized, TransactionData, TxVersion};

        TransactionData::<Authorized>::from_parts(
            TxVersion::V5,
            BranchId::Nu5,
            0,
            BlockHeight::from_u32(1),
            None,
            None,
            None,
            None,
        )
        .freeze()
        .unwrap()
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
    fn get_transaction_not_found_completes_enhancement_only() {
        let status = Status::new(Code::NotFound, "txid not recognized");

        assert_eq!(
            classify_get_transaction_error(&status),
            GetTransactionErrorAction::CompleteEnhancementNotFound,
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
    fn scanned_transaction_missing_fee_is_selected_when_status_request_is_dormant() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, db, tx) = scanned_transaction_missing_fee_test_db(mined_height);
        let txid = tx.txid();

        assert!(!db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::GetStatus(txid)));
        assert_eq!(
            stored_transaction_ids_missing_fee(file.path().to_str().unwrap()).unwrap(),
            vec![txid]
        );
        assert_eq!(db.get_transaction(txid).unwrap().unwrap().txid(), txid);
    }

    #[test]
    fn coinbase_transaction_is_not_selected_for_fee_backfill() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, _db, tx) = scanned_transaction_missing_fee_test_db(mined_height);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET tx_index = 0 WHERE txid = ?1",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();

        assert!(
            stored_transaction_ids_missing_fee(file.path().to_str().unwrap())
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn fee_without_transparent_inputs_is_persisted() {
        // Fully shielded transactions follow this path: no transparent
        // prevouts are required to compute their fee from public value
        // balances. This minimal transaction isolates that property.
        let tx = no_transparent_inputs_test_tx();
        let db = transparent_fee_test_db(&tx, 1);
        let fee = fee_from_prevout_values(&tx, &BTreeMap::new())
            .unwrap()
            .unwrap();

        assert!(should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
        persist_fee_if_missing(db.path().to_str().unwrap(), &tx, fee).unwrap();
        assert!(!should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());

        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let stored_fee: i64 = conn
            .query_row(
                "SELECT fee FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stored_fee, 0);
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

        assert!(!should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn transparent_fee_backfill_allows_positive_wallet_delta() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 1_000_000);

        assert!(should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn transparent_fee_backfill_allows_negative_wallet_delta() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, -40_000);

        assert!(should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn raw_height_out_of_u32_range_is_parse_error() {
        assert!(matches!(
            mined_height_from_raw_height(u32::MAX as u64 + 1),
            Err(SyncError::Parse(_)),
        ));
    }

    #[test]
    fn enhancement_payload_requires_matching_identity_and_valid_height() {
        let (tx, data) = transparent_fee_test_tx_and_bytes();
        let raw = RawTransaction { data, height: 100 };
        assert!(decode_enhancement_payload(&raw, tx.txid()).is_ok());
        assert!(matches!(
            decode_enhancement_payload(&raw, TxId::from_bytes([0; 32])),
            Err(SyncError::Parse(_))
        ));
        assert!(matches!(
            decode_enhancement_payload(
                &RawTransaction {
                    height: u32::MAX as u64 + 1,
                    ..raw
                },
                tx.txid()
            ),
            Err(SyncError::Parse(_))
        ));
    }
}

/// Cancellation is checked before dispatch and after completion, and dropping
/// the request future interrupts an in-flight wait. No queued request survives.
async fn cancelable<T, E: CancelError>(
    request: impl std::future::Future<Output = Result<T, E>>,
    should_exit: &impl Fn() -> bool,
) -> Result<T, E> {
    if should_exit() {
        return Err(E::cancelled());
    }
    let result = tokio::select! {
        biased;
        _ = super::watch_for_exit(should_exit) => return Err(E::cancelled()),
        result = request => result,
    };
    if should_exit() {
        return Err(E::cancelled());
    }
    result
}

trait CancelError {
    fn cancelled() -> Self;
}
impl CancelError for SyncError {
    fn cancelled() -> Self {
        Self::other("enhancement cancelled")
    }
}
impl CancelError for Status {
    fn cancelled() -> Self {
        Self::cancelled("enhancement cancelled")
    }
}

#[cfg(test)]
mod cancellation_tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    #[tokio::test]
    async fn cancelled_public_batch_never_dispatches_the_next_transaction() {
        let cancelled = AtomicBool::new(false);
        let dispatched = AtomicUsize::new(0);
        let exit = || cancelled.load(Ordering::SeqCst);
        let first = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                cancelled.store(true, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(first.is_err());
        let second = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(second.is_err());
        assert_eq!(dispatched.load(Ordering::SeqCst), 1);
    }
    #[tokio::test]
    async fn cancellation_drops_a_waiting_public_request() {
        let cancelled = AtomicBool::new(false);
        let exit = || cancelled.load(Ordering::SeqCst);
        let request = cancelable(std::future::pending::<Result<(), SyncError>>(), &exit);
        let cancel = async {
            tokio::task::yield_now().await;
            cancelled.store(true, Ordering::SeqCst);
        };
        let (result, _) = tokio::join!(request, cancel);
        assert!(result.is_err());
    }
}
