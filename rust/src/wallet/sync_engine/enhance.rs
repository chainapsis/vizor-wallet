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

use std::collections::{BTreeMap, HashSet};

use tonic::{transport::Channel, Code, Status};
use transparent::bundle::OutPoint;
use zcash_client_backend::{
    data_api::{
        wallet::decrypt_and_store_transaction, TransactionDataRequest, TransactionStatus,
        WalletRead, WalletWrite,
    },
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId};
use zcash_protocol::value::{BalanceError, Zatoshis};

use crate::wallet::db::{with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT};
use crate::wallet::network::WalletNetwork;

use super::{lwd, SyncError, WalletDatabase};

/// Drains `db.transaction_data_requests()` against lightwalletd until
/// the queue is empty or no request is actionable. Returns
/// `SyncError::Db` if `db.transaction_data_requests()` itself fails.
/// Per-request failures are split by semantics: an explicit
/// "txid not recognized" response is recorded via
/// `set_transaction_status` so it doesn't get retried forever, while
/// transient network failures bubble up as `SyncError::Network` so the
/// outer sync retry path can recover without deleting the request.
pub(super) async fn run_enhancement(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
) -> Result<(), SyncError> {
    let mut failed_txids: HashSet<String> = HashSet::new();

    for _ in 0..3 {
        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests: {e}")))?;
        if requests.is_empty() {
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
            break;
        }

        for req in &requests {
            match req {
                TransactionDataRequest::GetStatus(txid)
                | TransactionDataRequest::Enhancement(txid) => {
                    let txid_str = format!("{txid}");
                    if failed_txids.contains(&txid_str) {
                        continue;
                    }

                    match lwd::get_transaction(client, txid.as_ref().to_vec()).await {
                        Ok(raw) => {
                            let mined_height = mined_height_from_raw_height(raw.height)?;
                            if !raw.data.is_empty() {
                                match Transaction::read(&raw.data[..], BranchId::Sapling) {
                                    Ok(tx) => {
                                        if let Err(e) = with_wallet_db_write_lock(
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
                                            log::error!(
                                                "sync: decrypt_and_store_transaction failed: {e}"
                                            );
                                        }
                                        if let Err(e) =
                                            fill_missing_transparent_fee(client, db_path, &tx).await
                                        {
                                            log::warn!(
                                                "sync: transparent fee enhancement failed for {txid_str}: {e}"
                                            );
                                        }
                                    }
                                    Err(e) => log::warn!(
                                        "sync: Transaction::read failed for {txid_str}: {e}"
                                    ),
                                }
                            }
                            if matches!(req, TransactionDataRequest::GetStatus(_)) {
                                let status = transaction_status_from_raw_height(raw.height)?;
                                if let Err(e) = with_wallet_db_write_lock(
                                    "sync_engine.enhance.set_transaction_status",
                                    || db.set_transaction_status(*txid, status),
                                ) {
                                    log::error!("sync: set_transaction_status failed: {e}");
                                }
                            }
                        }
                        Err(e) => match classify_get_transaction_error(&e) {
                            GetTransactionErrorAction::MarkTxidNotRecognized => {
                                log::warn!(
                                    "sync: get_transaction did not recognize {txid_str}: {e}"
                                );
                                failed_txids.insert(txid_str);
                                if let Err(e) = with_wallet_db_write_lock(
                                    "sync_engine.enhance.set_transaction_status",
                                    || {
                                        db.set_transaction_status(
                                            *txid,
                                            TransactionStatus::TxidNotRecognized,
                                        )
                                    },
                                ) {
                                    log::error!("sync: set_transaction_status failed: {e}");
                                }
                            }
                            GetTransactionErrorAction::RetryAsNetwork => {
                                return Err(SyncError::net(format!(
                                    "get_transaction failed for {txid_str}: {e}"
                                )));
                            }
                        },
                    }
                }
                TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                    let end_height = match req.block_range_end() {
                        Some(h) => h,
                        None => continue,
                    };
                    let addr_str = zcash_keys::encoding::encode_transparent_address_p(
                        &network,
                        &req.address(),
                    );
                    let start = u32::from(req.block_range_start()) as u64;
                    let end = u32::from(end_height) as u64;

                    let found = process_taddress_history(
                        client,
                        db,
                        db_path,
                        network,
                        addr_str,
                        start,
                        end.saturating_sub(1),
                    )
                    .await?;

                    if !found {
                        with_wallet_db_write_lock(
                            "sync_engine.enhance.notify_address_checked",
                            || {
                                db.notify_address_checked(req.clone(), end_height - 1)
                                    .map_err(|e| {
                                        SyncError::db(format!("notify_address_checked: {e}"))
                                    })
                            },
                        )?;
                    }
                }
            }
        }
    }
    Ok(())
}

pub(super) async fn process_taddress_history(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    address: String,
    start_height: u64,
    end_height: u64,
) -> Result<bool, SyncError> {
    if start_height > end_height {
        return Ok(false);
    }

    let mut found = false;
    let mut stream = lwd::get_taddress_txids(client, address, start_height, end_height).await?;
    let mut fee_client = client.clone();
    loop {
        match lwd::next_stream_message(&mut stream, "get_taddress_txids stream").await? {
            Some(raw) => {
                if !raw.data.is_empty() {
                    found = true;
                    let mined_height = mined_height_from_raw_height(raw.height)?;
                    match Transaction::read(&raw.data[..], BranchId::Sapling) {
                        Ok(tx) => {
                            if let Err(e) = with_wallet_db_write_lock(
                                "sync_engine.enhance.decrypt_and_store_transaction",
                                || decrypt_and_store_transaction(&network, db, &tx, mined_height),
                            ) {
                                log::error!(
                                    "sync: decrypt_and_store_transaction (addr) failed: {e}"
                                );
                            }
                            if let Err(e) =
                                fill_missing_transparent_fee(&mut fee_client, db_path, &tx).await
                            {
                                log::warn!(
                                    "sync: transparent fee enhancement (addr) failed for {}: {e}",
                                    tx.txid()
                                );
                            }
                        }
                        Err(e) => {
                            log::warn!("sync: Transaction::read (addr) failed: {e}");
                        }
                    }
                }
            }
            None => break,
        }
    }

    Ok(found)
}

async fn fill_missing_transparent_fee(
    client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    tx: &Transaction,
) -> Result<(), SyncError> {
    let Some(bundle) = tx.transparent_bundle() else {
        return Ok(());
    };
    if bundle.vin.is_empty() || !should_fill_missing_transparent_fee(db_path, tx)? {
        return Ok(());
    }

    let prevout_values = fetch_transparent_prevout_values(client, tx).await?;
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

async fn fetch_transparent_prevout_values(
    client: &mut CompactTxStreamerClient<Channel>,
    tx: &Transaction,
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

        let parent_raw = match lwd::get_transaction(client, outpoint.hash().to_vec()).await {
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

fn should_fill_missing_transparent_fee(db_path: &str, tx: &Transaction) -> Result<bool, SyncError> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee lookup: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee lookup busy timeout: {e}")))?;

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
                 AND COALESCE(vt.account_balance_delta, 0) < 0
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
        conn.execute(
            "INSERT INTO v_transactions (txid, account_balance_delta)
             VALUES (?1, ?2)",
            rusqlite::params![tx.txid().as_ref(), account_balance_delta],
        )
        .unwrap();
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
    fn transparent_fee_backfill_requires_wallet_spend_evidence() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 1_000_000);

        assert!(!should_fill_missing_transparent_fee(db.path().to_str().unwrap(), &tx).unwrap());
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
