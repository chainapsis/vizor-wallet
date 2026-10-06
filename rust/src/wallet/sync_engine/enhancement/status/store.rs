//! Persistence boundary for transaction-status observations.

use zcash_client_backend::data_api::WalletWrite;
#[cfg(test)]
use zcash_primitives::transaction::TxId;

use crate::wallet::{
    db::with_wallet_db_write_lock,
    sync_engine::{SyncError, WalletDatabase},
    transaction_data::TransactionObservation,
};

/// Persists an observation without completing or otherwise mutating payload
/// enhancement intent for the same transaction.
///
/// Private and public sources have different proof requirements for
/// `NotFound`; source-specific validation must be complete before calling this
/// function. `Mempool` and `Forked` intentionally map to the wallet's common
/// not-in-main-chain state.
#[cfg(test)]
pub(in crate::wallet::sync_engine::enhancement) fn persist_status_observation(
    db: &mut WalletDatabase,
    txid: TxId,
    observation: TransactionObservation,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.enhance.set_transaction_status", || {
        db.set_transaction_status(txid, observation.wallet_status())
    })
    .map_err(|error: zcash_client_sqlite::error::SqliteClientError| {
        SyncError::db(format!("set_transaction_status: {error}"))
    })
}

/// A private negative observation applies only to the work and decision height that were
/// queried. A concurrent rewind, policy change, or tip advance makes it inconclusive.
/// Returns true only for conclusive recovery observations held pending until
/// the caller verifies the tip; no status row is removed in that case.
pub(super) fn persist_work_observation(
    db: &mut WalletDatabase,
    db_path: &str,
    work: zcash_client_backend::data_api::status::TransactionStatusWork,
    observation: TransactionObservation,
    required_through: Option<u32>,
    decision_hash: Option<zcash_primitives::block::BlockHash>,
) -> Result<bool, SyncError> {
    use zcash_client_backend::data_api::{
        status::{TransactionStatusRead, TransactionStatusWork},
        WalletRead,
    };
    with_wallet_db_write_lock("sync_engine.enhance.persist_status_work", || {
        // Preserve the durable status guard until the caller verifies the remote
        // tip identity. This applies equally to public and private observations.
        let defer_nonmined = if !matches!(observation, TransactionObservation::Mined(_)) {
            let conn = crate::wallet::db::open_readonly_conn_with_timeout(
                db_path,
                Some(crate::wallet::db::SYNC_DB_BUSY_TIMEOUT),
            )
            .map_err(SyncError::db)?;
            crate::wallet::sync::has_recovered_status_work(&conn, work.txid().as_ref())
                .map_err(SyncError::db)?
        } else {
            false
        };
        db.transactionally(|db| {
            if matches!(work, TransactionStatusWork::Private(_))
                && matches!(observation, TransactionObservation::NotFound)
            {
                if required_through.is_none()
                    || decision_hash.is_none()
                    || db.get_block_hash(zcash_protocol::consensus::BlockHeight::from_u32(
                        required_through.unwrap_or(0),
                    ))? != decision_hash
                    || db.chain_height()?.map(u32::from) != required_through
                    || db.transaction_status_work_for(work.txid())? != work
                {
                    return Ok::<_, zcash_client_sqlite::error::SqliteClientError>(false);
                }
            }
            if defer_nonmined {
                return Ok(true);
            }
            db.set_transaction_status(work.txid(), observation.wallet_status())?;
            Ok(false)
        })
        .map_err(|error| SyncError::db(format!("set_transaction_status: {error}")))
    })
}
