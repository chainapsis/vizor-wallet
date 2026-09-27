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
pub(super) fn persist_work_observation(
    db: &mut WalletDatabase,
    work: zcash_client_backend::data_api::status::TransactionStatusWork,
    observation: TransactionObservation,
    required_through: Option<u32>,
    decision_hash: Option<zcash_primitives::block::BlockHash>,
) -> Result<(), SyncError> {
    use zcash_client_backend::data_api::{
        status::{TransactionStatusRead, TransactionStatusWork},
        WalletRead,
    };
    with_wallet_db_write_lock("sync_engine.enhance.persist_status_work", || {
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
                    return Ok::<_, zcash_client_sqlite::error::SqliteClientError>(());
                }
            }
            db.set_transaction_status(work.txid(), observation.wallet_status())
        })
    })
    .map_err(|error| SyncError::db(format!("set_transaction_status: {error}")))
}
