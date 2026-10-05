//! Fee enrichment shared by public payload and transparent-history paths.

use rusqlite::OptionalExtension as _;
use std::collections::BTreeMap;

use tonic::transport::Channel;
use transparent::bundle::OutPoint;
use zcash_client_backend::{
    data_api::WalletRead, proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BranchId;
use zcash_protocol::value::{BalanceError, Zatoshis};

use crate::wallet::db::{
    open_readonly_conn_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT,
};

use super::super::super::{SyncError, WalletDatabase};

/// Backfills fees for stored transactions whose status requests are dormant
/// while their mined heights are known.
pub(in crate::wallet::sync_engine::enhancement) async fn backfill_stored_fees(
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

pub(in crate::wallet::sync_engine::enhancement) fn stored_transaction_ids_missing_fee(
    db_path: &str,
) -> Result<Vec<TxId>, SyncError> {
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
                 AND vt.total_spent > 0
             )",
        )
        .map_err(|e| SyncError::db(format!("prepare missing fee scan: {e}")))?;
    let rows = stmt
        .query_map([], |row| row.get(0).map(TxId::from_bytes))
        .map_err(|e| SyncError::db(format!("query missing fees: {e}")))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| SyncError::db(format!("read missing fee transaction: {e}")))
}

pub(in crate::wallet::sync_engine::enhancement) async fn fill_missing_fee(
    _client: &mut CompactTxStreamerClient<Channel>,
    db_path: &str,
    tx: &Transaction,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    if should_exit() {
        return Ok(());
    }
    fill_fee_from_local(db_path, tx)
}

pub(in crate::wallet::sync_engine::enhancement) fn should_fill_missing_fee(
    db_path: &str,
    tx: &Transaction,
) -> Result<bool, SyncError> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| SyncError::db(format!("open wallet DB for fee lookup: {e}")))?;
    conn.busy_timeout(SYNC_DB_BUSY_TIMEOUT)
        .map_err(|e| SyncError::db(format!("configure fee lookup busy timeout: {e}")))?;

    // Only transactions the wallet funded show a fee. A received transaction's
    // fee needs its sender's parent transactions, which the wallet does not hold.
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
                 AND vt.total_spent > 0
             )",
            rusqlite::params![tx.txid().as_ref()],
            |row| row.get(0),
        )
        .map_err(|e| SyncError::db(format!("query missing fee: {e}")))?;

    Ok(fillable_rows > 0)
}

pub(in crate::wallet::sync_engine::enhancement) fn is_null_outpoint(outpoint: &OutPoint) -> bool {
    outpoint.hash() == &[0u8; 32] && outpoint.n() == u32::MAX
}

pub(in crate::wallet::sync_engine::enhancement) fn fee_from_prevout_values(
    tx: &Transaction,
    prevout_values: &BTreeMap<OutPoint, Zatoshis>,
) -> Result<Option<Zatoshis>, BalanceError> {
    tx.fee_paid(|outpoint| {
        Ok::<Option<Zatoshis>, BalanceError>(prevout_values.get(outpoint).copied())
    })
}

pub(in crate::wallet::sync_engine::enhancement) fn persist_fee_if_missing(
    db_path: &str,
    tx: &Transaction,
    fee: Zatoshis,
) -> Result<(), SyncError> {
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

pub(in crate::wallet::sync_engine::enhancement) fn fill_fee_from_local(
    db_path: &str,
    tx: &Transaction,
) -> Result<(), SyncError> {
    if !should_fill_missing_fee(db_path, tx)? {
        return Ok(());
    }
    let Some(prevout_values) = local_prevout_values(db_path, tx)? else {
        return Ok(());
    };
    let Some(fee) = fee_from_prevout_values(tx, &prevout_values)
        .map_err(|e| SyncError::parse(format!("fee computation failed: {e:?}")))?
    else {
        return Ok(());
    };
    persist_fee_if_missing(db_path, tx, fee)
}

fn local_prevout_values(
    db_path: &str,
    tx: &Transaction,
) -> Result<Option<BTreeMap<OutPoint, Zatoshis>>, SyncError> {
    let mut values = BTreeMap::new();
    let Some(bundle) = tx.transparent_bundle() else {
        return Ok(Some(values));
    };
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))
        .map_err(|e| SyncError::db(format!("open wallet DB for local fee lookup: {e}")))?;
    for txin in &bundle.vin {
        let outpoint = txin.prevout();
        if is_null_outpoint(outpoint) {
            return Ok(None);
        }
        let parent = outpoint.hash().as_slice();
        let wallet_value = conn
            .query_row(
                "SELECT tro.value_zat
                 FROM transparent_received_outputs tro
                 JOIN transactions parent ON parent.id_tx = tro.transaction_id
                 WHERE parent.txid = ?1 AND tro.output_index = ?2",
                rusqlite::params![parent, outpoint.n()],
                |row| row.get::<_, u64>(0),
            )
            .optional()
            .map_err(|e| SyncError::db(format!("query wallet prevout value: {e}")))?
            .and_then(|value| Zatoshis::from_u64(value).ok());
        let value = match wallet_value {
            Some(value) => Some(value),
            None => conn
                .query_row(
                    "SELECT raw FROM transactions WHERE txid = ?1 AND raw IS NOT NULL",
                    rusqlite::params![parent],
                    |row| row.get::<_, Vec<u8>>(0),
                )
                .optional()
                .map_err(|e| SyncError::db(format!("query stored parent raw: {e}")))?
                .and_then(|raw| output_value(&raw, outpoint.n())),
        };
        let Some(value) = value else {
            return Ok(None);
        };
        values.insert(outpoint.clone(), value);
    }
    Ok(Some(values))
}

fn output_value(parent: &[u8], index: u32) -> Option<Zatoshis> {
    let parent = Transaction::read(parent, BranchId::Sapling).ok()?;
    let output = parent
        .transparent_bundle()?
        .vout
        .get(usize::try_from(index).ok()?)?;
    Some(output.value())
}
