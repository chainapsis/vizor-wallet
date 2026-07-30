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
//! Librustzcash signals these gaps through `db.transaction_data_requests()`.
//! Missing transaction data and transparent history normally come from
//! lightwalletd. Status requests with local evidence are handled without a
//! transaction-specific server lookup: recovery waits for compact scanning to
//! restore a prior mined height, while locally created transactions stay local
//! until scanning mines them or passes their expiry. A relay migration
//! transaction accepted before local storage is restored stays with the
//! migration worker instead. The loop retries up to three times because
//! servicing one request can populate another.

use std::collections::{BTreeMap, HashSet};

use rusqlite::OptionalExtension;
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

use crate::wallet::db::{
    open_readonly_conn_with_timeout, with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT,
    SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync::{parse_separate_relay_transaction, separate_relay_migration_transaction};

use super::{lwd, SyncError, WalletDatabase};

const SAPLING_POOL_CODE: i64 = 2;
const ORCHARD_POOL_CODE: i64 = 3;
const IRONWOOD_POOL_CODE: i64 = 4;

/// Services `db.transaction_data_requests()` against lightwalletd until
/// the queue is empty or no request is actionable. Status-only requests
/// in `deferred_status_txids` remain queued for compact scanning. Returns
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
    deferred_status_txids: &HashSet<Vec<u8>>,
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
        let actionable = requests
            .iter()
            .any(|request| request_is_actionable(request, deferred_status_txids));
        if !actionable {
            break;
        }

        let mut serviced_any = false;

        for req in &requests {
            match req {
                TransactionDataRequest::GetStatus(txid)
                    if deferred_status_txids.contains(txid.as_ref().as_slice()) =>
                {
                    continue
                }
                TransactionDataRequest::GetStatus(txid)
                | TransactionDataRequest::Enhancement(txid) => {
                    let txid_str = format!("{txid}");

                    if matches!(req, TransactionDataRequest::GetStatus(_)) {
                        match scanned_mined_height(db, *txid) {
                            Ok(Some(mined_height)) => {
                                let can_resolve_locally = match db.get_transaction(*txid) {
                                    Ok(Some(tx)) => {
                                        if let Err(e) =
                                            fill_missing_transparent_fee(client, db_path, &tx).await
                                        {
                                            log::warn!(
                                                "sync: transparent fee enhancement failed for {txid_str}: {e}"
                                            );
                                        }
                                        true
                                    }
                                    Ok(None) => true,
                                    Err(e) => {
                                        log::error!(
                                            "sync: could not read stored transaction for local status resolution: {e}"
                                        );
                                        false
                                    }
                                };
                                if can_resolve_locally {
                                    match resolve_status_from_scanned_height(
                                        db,
                                        *txid,
                                        mined_height,
                                    ) {
                                        Ok(()) => {
                                            serviced_any = true;
                                            continue;
                                        }
                                        Err(e) => log::error!(
                                            "sync: could not resolve transaction status locally: {e}"
                                        ),
                                    }
                                }
                            }
                            Ok(None) => {}
                            Err(e) => log::error!(
                                "sync: could not read locally restored transaction status: {e}"
                            ),
                        }
                    }

                    let local = if let Some(local) = locally_created_transaction(db_path, *txid)? {
                        Some(local)
                    } else if let Some(relay) = separate_relay_migration_transaction(db_path, *txid)
                        .map_err(SyncError::db)?
                    {
                        let Some(raw_tx) = relay.raw_tx else {
                            // The migration worker retains an encrypted copy and restores wallet
                            // storage on its next credentialed advance.
                            continue;
                        };
                        Some(LocallyCreatedTransaction {
                            tx: parse_separate_relay_transaction(
                                *txid,
                                &raw_tx,
                                relay.expiry_height,
                            )
                            .map_err(SyncError::parse)?,
                            expiry_height: relay.expiry_height,
                        })
                    } else {
                        None
                    };
                    if let Some(local) = local {
                        match req {
                            TransactionDataRequest::Enhancement(_) => {
                                let mined_height = db.get_tx_height(*txid).map_err(|e| {
                                    SyncError::db(format!(
                                        "get_tx_height for locally created transaction {txid}: {e}"
                                    ))
                                })?;
                                with_wallet_db_write_lock(
                                    "sync_engine.enhance.locally_created_transaction",
                                    || {
                                        decrypt_and_store_transaction(
                                            &network,
                                            db,
                                            &local.tx,
                                            mined_height,
                                        )
                                    },
                                )
                                .map_err(|e| {
                                    SyncError::db(format!(
                                        "store locally created transaction {txid}: {e}"
                                    ))
                                })?;
                                serviced_any = true;
                            }
                            TransactionDataRequest::GetStatus(_) => {
                                let mined_height = db.get_tx_height(*txid).map_err(|e| {
                                    SyncError::db(format!(
                                        "get_tx_height for locally created transaction {txid}: {e}"
                                    ))
                                })?;
                                let fully_scanned_height = if mined_height.is_none() {
                                    super::wallet_summary_heights(db)?.map(|(scanned, _)| scanned)
                                } else {
                                    None
                                };
                                let status = match local_transaction_status(
                                    mined_height,
                                    fully_scanned_height,
                                    local.expiry_height,
                                ) {
                                    LocalTransactionStatus::Mined(height) => {
                                        Some(TransactionStatus::Mined(height))
                                    }
                                    LocalTransactionStatus::Expired => {
                                        Some(TransactionStatus::NotInMainChain)
                                    }
                                    LocalTransactionStatus::Pending => None,
                                };
                                if let Some(status) = status {
                                    with_wallet_db_write_lock(
                                        "sync_engine.enhance.local_transaction_status",
                                        || db.set_transaction_status(*txid, status),
                                    )
                                    .map_err(|e| {
                                        SyncError::db(format!(
                                            "set locally created transaction status for {txid}: {e}"
                                        ))
                                    })?;
                                    serviced_any = true;
                                }
                            }
                            TransactionDataRequest::TransactionsInvolvingAddress(_) => {
                                unreachable!()
                            }
                        }
                        continue;
                    }
                    if failed_txids.contains(&txid_str) {
                        continue;
                    }

                    match lwd::get_transaction(client, txid.as_ref().to_vec()).await {
                        Ok(raw) => {
                            serviced_any = true;
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
                                serviced_any = true;
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

                    match lwd::get_taddress_txids(client, addr_str, start, end.saturating_sub(1))
                        .await
                    {
                        Ok(mut stream) => {
                            serviced_any = true;
                            let mut fee_client = client.clone();
                            loop {
                                match lwd::next_stream_message(
                                    &mut stream,
                                    "get_taddress_txids stream",
                                )
                                .await
                                {
                                    Ok(Some(raw)) => {
                                        if !raw.data.is_empty() {
                                            let mined_height =
                                                mined_height_from_raw_height(raw.height)?;
                                            match Transaction::read(
                                                &raw.data[..],
                                                BranchId::Sapling,
                                            ) {
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
                                                            "sync: decrypt_and_store_transaction (addr) failed: {e}"
                                                        );
                                                    }
                                                    if let Err(e) = fill_missing_transparent_fee(
                                                        &mut fee_client,
                                                        db_path,
                                                        &tx,
                                                    )
                                                    .await
                                                    {
                                                        log::warn!(
                                                            "sync: transparent fee enhancement (addr) failed for {}: {e}",
                                                            tx.txid()
                                                        );
                                                    }
                                                }
                                                Err(e) => {
                                                    log::warn!(
                                                        "sync: Transaction::read (addr) failed: {e}"
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    Ok(None) => break,
                                    Err(e) => return Err(e),
                                }
                            }
                        }
                        Err(e) => return Err(e),
                    }
                }
            }
        }
        if !serviced_any {
            break;
        }
    }
    Ok(())
}

struct LocallyCreatedTransaction {
    tx: Transaction,
    expiry_height: u32,
}

fn locally_created_transaction(
    db_path: &str,
    txid: zcash_primitives::transaction::TxId,
) -> Result<Option<LocallyCreatedTransaction>, SyncError> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))
        .map_err(SyncError::db)?;
    let local_row = conn
        .query_row(
            "SELECT t.raw, t.expiry_height
             FROM transactions t
             WHERE t.txid = ?1
               AND (t.target_height IS NOT NULL OR t.created IS NOT NULL)
               AND t.raw IS NOT NULL
               AND t.expiry_height > 0
               AND (
                   EXISTS (
                       SELECT 1 FROM v_received_outputs ro
                       WHERE ro.transaction_id = t.id_tx AND ro.pool IN (?2, ?3, ?4)
                   )
                   OR EXISTS (
                       SELECT 1 FROM v_received_output_spends ros
                       WHERE ros.transaction_id = t.id_tx AND ros.pool IN (?2, ?3, ?4)
                   )
               )",
            rusqlite::params![
                txid.as_ref(),
                SAPLING_POOL_CODE,
                ORCHARD_POOL_CODE,
                IRONWOOD_POOL_CODE
            ],
            |row| Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, u32>(1)?)),
        )
        .optional()
        .map_err(|e| SyncError::db(format!("read locally created transaction {txid}: {e}")))?;
    let Some((raw_tx, expiry_height)) = local_row else {
        return Ok(None);
    };

    let tx = Transaction::read(&raw_tx[..], BranchId::Sapling)
        .map_err(|e| SyncError::parse(format!("parse locally created transaction {txid}: {e}")))?;
    if tx.txid() != txid || u32::from(tx.expiry_height()) != expiry_height {
        return Err(SyncError::parse(format!(
            "locally created transaction metadata does not match {txid}"
        )));
    }
    Ok(Some(LocallyCreatedTransaction { tx, expiry_height }))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LocalTransactionStatus {
    Mined(BlockHeight),
    Expired,
    Pending,
}

fn local_transaction_status(
    mined_height: Option<BlockHeight>,
    fully_scanned_height: Option<u64>,
    expiry_height: u32,
) -> LocalTransactionStatus {
    if let Some(height) = mined_height {
        LocalTransactionStatus::Mined(height)
    } else if fully_scanned_height.is_some_and(|height| height >= u64::from(expiry_height)) {
        LocalTransactionStatus::Expired
    } else {
        LocalTransactionStatus::Pending
    }
}

/// Whether servicing `request` can make progress right now: full-data
/// enhancements always can, status-only requests unless their transaction is
/// deferred for compact scanning, and address-scoped requests only when they
/// carry a bounded block range.
fn request_is_actionable(
    request: &TransactionDataRequest,
    deferred_status_txids: &HashSet<Vec<u8>>,
) -> bool {
    match request {
        TransactionDataRequest::Enhancement(_) => true,
        TransactionDataRequest::GetStatus(txid) => {
            !deferred_status_txids.contains(txid.as_ref().as_slice())
        }
        TransactionDataRequest::TransactionsInvolvingAddress(req) => {
            req.block_range_end().is_some()
        }
    }
}

fn scanned_mined_height(db: &WalletDatabase, txid: TxId) -> Result<Option<BlockHeight>, SyncError> {
    db.get_tx_height(txid)
        .map_err(|e| SyncError::db(format!("get transaction height: {e}")))
}

/// Re-asserts a compact-scan-restored mined status after any missing fee has
/// been backfilled, which also dequeues the `GetStatus` request.
fn resolve_status_from_scanned_height(
    db: &mut WalletDatabase,
    txid: TxId,
    mined_height: BlockHeight,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock(
        "sync_engine.enhance.set_known_mined_transaction_status",
        || {
            db.set_transaction_status(txid, TransactionStatus::Mined(mined_height))
                .map_err(|e| SyncError::db(format!("set known mined transaction status: {e}")))
        },
    )
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

    /// Builds a real migrated wallet DB containing one transaction with a
    /// known mined height plus an explicit status-type retrieval-queue entry
    /// for it, mirroring the post-recovery state `resolve_status_from_scanned_height`
    /// services.
    fn status_recovery_test_db(
        mined_height: BlockHeight,
        fee: Option<i64>,
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
             VALUES (?1, ?2, ?3, ?4, ?2)",
            rusqlite::params![txid.as_ref(), u32::from(mined_height), raw, fee],
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

    fn local_status_test_tx(expiry_height: u32) -> (Transaction, Vec<u8>) {
        let value_commitment = sapling_crypto::value::ValueCommitment::derive(
            sapling_crypto::value::NoteValue::from_raw(1),
            sapling_crypto::value::ValueCommitTrapdoor::random(rand_core::OsRng),
        );
        let mut raw = Vec::with_capacity(1_100);
        raw.extend_from_slice(&0x8000_0004u32.to_le_bytes());
        raw.extend_from_slice(&0x892f_2085u32.to_le_bytes());
        raw.extend_from_slice(&[0, 0]);
        raw.extend_from_slice(&0u32.to_le_bytes());
        raw.extend_from_slice(&expiry_height.to_le_bytes());
        raw.extend_from_slice(&0i64.to_le_bytes());
        raw.push(0);
        raw.push(1);
        raw.extend_from_slice(&value_commitment.to_bytes());
        raw.extend_from_slice(&[0; 64]);
        raw.resize(raw.len() + 580 + 80 + 192, 0);
        raw.push(0);
        raw.resize(raw.len() + 64, 0);

        let tx = Transaction::read(&raw[..], BranchId::Sapling).unwrap();
        (tx, raw)
    }

    fn insert_local_lookup_test_tx(
        conn: &rusqlite::Connection,
        expiry_height: u32,
        target_height: Option<u32>,
        created: Option<&str>,
        received_pool: Option<u32>,
        spent_pool: Option<u32>,
    ) -> zcash_primitives::transaction::TxId {
        let (tx, raw) = local_status_test_tx(expiry_height);
        conn.execute(
            "INSERT INTO transactions (txid, created, target_height, raw, expiry_height)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![
                tx.txid().as_ref(),
                created,
                target_height,
                raw,
                expiry_height
            ],
        )
        .unwrap();
        let transaction_id = conn.last_insert_rowid();
        if let Some(pool) = received_pool {
            conn.execute(
                "INSERT INTO v_received_outputs (transaction_id, pool) VALUES (?1, ?2)",
                rusqlite::params![transaction_id, pool],
            )
            .unwrap();
        }
        if let Some(pool) = spent_pool {
            conn.execute(
                "INSERT INTO v_received_output_spends (transaction_id, pool) VALUES (?1, ?2)",
                rusqlite::params![transaction_id, pool],
            )
            .unwrap();
        }
        tx.txid()
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
    fn local_lookup_requires_origin_expiry_and_compact_block_relevance() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY,
                 txid BLOB NOT NULL UNIQUE,
                 created TEXT,
                 target_height INTEGER,
                 raw BLOB,
                 expiry_height INTEGER
             );
             CREATE TABLE v_received_outputs (transaction_id INTEGER, pool INTEGER);
             CREATE TABLE v_received_output_spends (transaction_id INTEGER, pool INTEGER);",
        )
        .unwrap();

        let target_marked = insert_local_lookup_test_tx(&conn, 100, Some(90), None, Some(2), None);
        let created_marked = insert_local_lookup_test_tx(
            &conn,
            101,
            None,
            Some("2026-07-29 00:00:00"),
            None,
            Some(4),
        );
        let recovered = insert_local_lookup_test_tx(&conn, 102, None, None, Some(2), None);
        let external_shielded = insert_local_lookup_test_tx(&conn, 103, Some(90), None, None, None);
        let transparent_only =
            insert_local_lookup_test_tx(&conn, 104, Some(90), None, Some(0), None);
        let zero_expiry = insert_local_lookup_test_tx(&conn, 0, Some(90), None, Some(3), None);
        drop(conn);

        for txid in [target_marked, created_marked] {
            assert!(
                locally_created_transaction(file.path().to_str().unwrap(), txid)
                    .unwrap()
                    .is_some()
            );
        }
        for txid in [recovered, external_shielded, transparent_only, zero_expiry] {
            assert!(
                locally_created_transaction(file.path().to_str().unwrap(), txid)
                    .unwrap()
                    .is_none()
            );
        }
    }

    #[tokio::test]
    async fn locally_created_status_does_not_contact_lightwalletd() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let network = WalletNetwork::Test;
        let mnemonic = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
        crate::wallet::keys::init_db_and_create_account(
            db_path,
            network,
            &seed,
            Some(1),
            "enhancement-test",
        )
        .unwrap();
        crate::wallet::sync::update_chain_tip(db_path, network, 3_000_000).unwrap();

        let expiry_height = 3_000_100;
        let (tx, raw) = local_status_test_tx(expiry_height);
        let txid = tx.txid();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        conn.execute(
            "INSERT INTO transactions
             (txid, raw, expiry_height, target_height, min_observed_height)
             VALUES (?1, ?2, ?3, 3000000, 1)",
            rusqlite::params![txid.as_ref(), raw, expiry_height],
        )
        .unwrap();
        let transaction_id = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO sapling_received_notes
             (transaction_id, output_index, account_id, diversifier, value, rcm, is_change)
             SELECT ?1, 0, id, zeroblob(11), 1, zeroblob(32), 1
             FROM accounts LIMIT 1",
            [transaction_id],
        )
        .unwrap();
        conn.execute(
            "UPDATE transactions SET target_height = NULL WHERE txid = ?1",
            [txid.as_ref()],
        )
        .unwrap();
        drop(conn);
        crate::wallet::sync::mark_transaction_created_locally(db_path, &txid).unwrap();

        let mut db = super::super::open_db(db_path, network).unwrap();
        let requests = db.transaction_data_requests().unwrap();
        assert!(requests.iter().any(
            |request| matches!(request, TransactionDataRequest::GetStatus(id) if *id == txid)
        ));

        let channel = Channel::from_static("http://127.0.0.1:9").connect_lazy();
        let mut client = CompactTxStreamerClient::new(channel);
        run_enhancement(&mut client, &mut db, db_path, network, &HashSet::new())
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn separate_relay_missing_raw_does_not_contact_lightwalletd() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let network = WalletNetwork::Test;
        let mnemonic = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
        crate::wallet::keys::init_db_and_create_account(
            db_path,
            network,
            &seed,
            Some(1),
            "enhancement-test",
        )
        .unwrap();
        crate::wallet::sync::update_chain_tip(db_path, network, 3_000_000).unwrap();

        let expiry_height = 3_000_100;
        let (preparation_tx, _) = local_status_test_tx(expiry_height);
        let (phase_two_tx, _) = local_status_test_tx(expiry_height + 1);
        let conn = rusqlite::Connection::open(db_path).unwrap();
        for (txid, expiry_height) in [
            (preparation_tx.txid(), expiry_height),
            (phase_two_tx.txid(), expiry_height + 1),
        ] {
            conn.execute(
                "INSERT INTO transactions (txid, expiry_height, min_observed_height)
                 VALUES (?1, ?2, 1)",
                rusqlite::params![txid.as_ref(), expiry_height],
            )
            .unwrap();
        }
        conn.execute_batch(
            "CREATE TABLE vizor_migration_runs (
                 run_id TEXT PRIMARY KEY,
                 created_at_ms INTEGER NOT NULL,
                 denomination_submission_target TEXT NOT NULL
             );
             CREATE TABLE vizor_migration_denomination_stages (
                 run_id TEXT NOT NULL,
                 expected_txid_hex TEXT NOT NULL,
                 expiry_height INTEGER NOT NULL
             );
             CREATE TABLE vizor_migration_pending_txs (
                 run_id TEXT NOT NULL,
                 txid_hex TEXT NOT NULL,
                 expiry_height INTEGER NOT NULL
             );
             INSERT INTO vizor_migration_runs
                 (run_id, created_at_ms, denomination_submission_target)
             VALUES ('run-1', 1, 'relay:https://relay.example/submit');",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stages
                 (run_id, expected_txid_hex, expiry_height)
             VALUES ('run-1', ?1, ?2)",
            rusqlite::params![preparation_tx.txid().to_string(), expiry_height],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_pending_txs
                 (run_id, txid_hex, expiry_height)
             VALUES ('run-1', ?1, ?2)",
            rusqlite::params![phase_two_tx.txid().to_string(), expiry_height + 1],
        )
        .unwrap();
        drop(conn);

        let mut db = super::super::open_db(db_path, network).unwrap();
        let requests = db.transaction_data_requests().unwrap();
        for txid in [preparation_tx.txid(), phase_two_tx.txid()] {
            assert!(requests.iter().any(
                |request| matches!(request, TransactionDataRequest::GetStatus(id) if *id == txid)
            ));
        }

        let channel = Channel::from_static("http://127.0.0.1:9").connect_lazy();
        let mut client = CompactTxStreamerClient::new(channel);
        run_enhancement(&mut client, &mut db, db_path, network, &HashSet::new())
            .await
            .unwrap();
    }

    #[test]
    fn deferred_status_requests_do_not_block_full_data_enhancement() {
        let deferred = HashSet::from([vec![1; 32]]);
        assert!(!request_is_actionable(
            &TransactionDataRequest::GetStatus(TxId::from_bytes([1; 32])),
            &deferred,
        ));
        assert!(request_is_actionable(
            &TransactionDataRequest::GetStatus(TxId::from_bytes([2; 32])),
            &deferred,
        ));
        assert!(request_is_actionable(
            &TransactionDataRequest::Enhancement(TxId::from_bytes([1; 32])),
            &deferred,
        ));
    }

    #[test]
    fn scanned_height_resolves_status_without_transaction_download() {
        let mined_height = BlockHeight::from_u32(500);
        let (_file, mut db, tx) = status_recovery_test_db(mined_height, Some(0));
        let txid = tx.txid();

        assert!(db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::GetStatus(txid)));
        assert_eq!(scanned_mined_height(&db, txid).unwrap(), Some(mined_height));
        resolve_status_from_scanned_height(&mut db, txid, mined_height).unwrap();
        assert!(!db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::GetStatus(txid)));
        assert_eq!(db.get_tx_height(txid).unwrap(), Some(mined_height));
    }

    #[test]
    fn scanned_status_loads_missing_fee_input_before_dequeue() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, mut db, tx) = status_recovery_test_db(mined_height, None);
        let txid = tx.txid();

        assert_eq!(db.get_transaction(txid).unwrap().unwrap().txid(), txid);
        assert!(should_fill_missing_transparent_fee(file.path().to_str().unwrap(), &tx).unwrap());
        assert!(db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::GetStatus(txid)));

        resolve_status_from_scanned_height(&mut db, txid, mined_height).unwrap();
        assert!(!db
            .transaction_data_requests()
            .unwrap()
            .contains(&TransactionDataRequest::GetStatus(txid)));
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

    #[test]
    fn local_status_uses_scanned_mined_height() {
        let height = BlockHeight::from_u32(1_000_010);
        assert_eq!(
            local_transaction_status(Some(height), Some(1_000_100), 1_000_050),
            LocalTransactionStatus::Mined(height)
        );
    }

    #[test]
    fn local_status_expires_only_after_full_scan() {
        assert_eq!(
            local_transaction_status(None, Some(1_000_049), 1_000_050),
            LocalTransactionStatus::Pending
        );
        assert_eq!(
            local_transaction_status(None, None, 1_000_050),
            LocalTransactionStatus::Pending
        );
        assert_eq!(
            local_transaction_status(None, Some(1_000_050), 1_000_050),
            LocalTransactionStatus::Expired
        );
    }
}
