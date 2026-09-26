//! Durable scan-time queue seeding for stored transaction payloads.

use std::rc::Rc;

use rusqlite::{types::Value, vtab::array::Array};

use crate::wallet::db::{open_wallet_raw_conn_with_timeout, SYNC_DB_BUSY_TIMEOUT};

use super::super::super::{block_source::MemoryBlockSource, SyncError};

/// Requeues stored transactions encountered by the current compact-block batch.
///
/// The caller holds the wallet write lock and invokes this before scanning.
/// Existing status requests and dependency links are preserved. There is no
/// startup-wide sweep: this operation is intentionally scoped to the current
/// downloaded batch so the queue remains durable across cancellation or exit.
pub(in crate::wallet::sync_engine) fn queue_stored_transactions(
    db_path: &str,
    blocks: &MemoryBlockSource,
) -> Result<(), SyncError> {
    let Some(heights) = blocks.height_range() else {
        return Ok(());
    };
    let transaction_hashes: Array = Rc::new(
        blocks
            .transaction_hashes()
            .map(|hash| Value::Blob(hash.to_vec()))
            .collect(),
    );
    let connection =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;

    // query_type=1 is the SDK's payload-enhancement request.
    let queued_count = connection
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type, dependent_transaction_id)
         SELECT txid, 1, NULL FROM transactions
         WHERE raw IS NOT NULL
           AND (txid IN rarray(?1) OR mined_height BETWEEN ?2 AND ?3)
         ON CONFLICT (txid, query_type) DO NOTHING",
            rusqlite::params![transaction_hashes, heights.start(), heights.end()],
        )
        .map_err(|error| SyncError::db(format!("queue scanned stored transactions: {error}")))?;
    if queued_count > 0 {
        log::info!("sync: queued {queued_count} stored transaction(s) for scan-time enhancement");
    }
    Ok(())
}
