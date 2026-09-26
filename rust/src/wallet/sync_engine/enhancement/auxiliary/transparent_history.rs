//! Transparent-address history transaction ingestion.

use zcash_client_backend::data_api::wallet::decrypt_and_store_transaction;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

use crate::wallet::{
    db::with_wallet_db_write_lock,
    network::WalletNetwork,
    sync_engine::{SyncError, WalletDatabase},
};

use super::super::payload::public_lwd::mined_height_from_raw_height;

/// Parses and stores one streamed transaction before its address range may be
/// acknowledged. A failure therefore leaves the durable range retryable.
pub(super) fn store_address_transaction(
    network: &WalletNetwork,
    db: &mut WalletDatabase,
    bytes: &[u8],
    raw_height: u64,
) -> Result<Transaction, SyncError> {
    let mined_height = mined_height_from_raw_height(raw_height)?;
    let transaction = Transaction::read(bytes, BranchId::Sapling)
        .map_err(|error| SyncError::parse(format!("Transaction::read (addr): {error}")))?;
    with_wallet_db_write_lock("sync_engine.enhance.decrypt_and_store_transaction", || {
        decrypt_and_store_transaction(network, db, &transaction, mined_height)
    })
    .map_err(|error| SyncError::db(format!("decrypt_and_store_transaction (addr): {error}")))?;
    Ok(transaction)
}
