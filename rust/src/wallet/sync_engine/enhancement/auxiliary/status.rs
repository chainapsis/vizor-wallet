//! Persistence boundary for transaction-status observations.

use zcash_client_backend::data_api::WalletWrite;
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
pub(super) fn persist_status_observation(
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
