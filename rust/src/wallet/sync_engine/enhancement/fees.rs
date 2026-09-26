//! Fee enrichment shared by public payload and transparent-history paths.

use std::collections::BTreeMap;

use tonic::transport::Channel;
use transparent::bundle::OutPoint;
use zcash_client_backend::{
    data_api::WalletRead, proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BranchId;
use zcash_protocol::value::{BalanceError, Zatoshis};

use crate::wallet::{
    db::{with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT},
    transaction_data::payload::get_transaction_payload,
};

use super::{
    super::super::{SyncError, WalletDatabase},
    super::transport::cancelable,
};

/// Backfills fees for stored transactions whose status requests are dormant
/// while their mined heights are known.
pub(super) async fn backfill_stored_fees(
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

pub(super) fn stored_transaction_ids_missing_fee(db_path: &str) -> Result<Vec<TxId>, SyncError> {
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

pub(in crate::wallet::sync_engine::enhancement) async fn fill_missing_fee(
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

pub(super) fn should_fill_missing_fee(db_path: &str, tx: &Transaction) -> Result<bool, SyncError> {
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

pub(super) fn is_null_outpoint(outpoint: &OutPoint) -> bool {
    outpoint.hash() == &[0u8; 32] && outpoint.n() == u32::MAX
}

pub(super) fn fee_from_prevout_values(
    tx: &Transaction,
    prevout_values: &BTreeMap<OutPoint, Zatoshis>,
) -> Result<Option<Zatoshis>, BalanceError> {
    tx.fee_paid(|outpoint| {
        Ok::<Option<Zatoshis>, BalanceError>(prevout_values.get(outpoint).copied())
    })
}

pub(super) fn persist_fee_if_missing(
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
