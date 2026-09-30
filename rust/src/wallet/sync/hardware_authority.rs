//! Final transparent-input authorization for every hardware broadcast path.
//!
//! Signing can outlive recovery authority. Validate using the library's input
//! selector at the current network target, then keep a SQLite writer reservation
//! through the bounded SendTransaction attempt. This prevents policy changes,
//! rewinds, or evidence withdrawal between validation and submission, including
//! writes from another connection. No transaction is stored here: dropping the
//! connection rolls back the reservation on success, failure, or cancellation.

use std::future::Future;

use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::WalletRead;
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    sync_engine::enhancement::transparent_ledger_mode_for,
};

/// Authorizes `tx` immediately before polling `send`. Earlier finalized batch
/// transactions may supply local chained inputs (TEX); the output must exist.
/// Unknown, withdrawn, competing-spent, immature, or unauthorized wallet inputs fail
/// before `send` is polled. Exact stored retries may consume their own recorded inputs.
/// Shielded-only transactions require no reservation.
pub(crate) async fn dispatch<T>(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
    send: impl Future<Output = T>,
) -> Result<T, String> {
    let inputs = tx.transparent_bundle().map_or(&[][..], |b| &b.vin[..]);
    if inputs.is_empty() {
        return Ok(send.await);
    }
    let target = u32::try_from(network_tip)
        .ok()
        .and_then(|h| h.checked_add(1))
        .map(BlockHeight::from_u32)
        .ok_or_else(|| "Transparent broadcast target exceeds u32".to_string())?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    conn.execute_batch("BEGIN IMMEDIATE")
        .map_err(|e| format!("Reserve transparent broadcast authority: {e}"))?;
    let db = WalletDb::from_connection(conn, network, SystemClock, OsRng)
        .with_transparent_ledger_mode(transparent_ledger_mode_for(db_path));
    // Checking the mode also rejects a weaker handle on a durable private wallet.
    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerRead;
    db.transparent_ledger_mode()
        .map_err(|e| format!("Transparent broadcast authority unavailable: {e}"))?;
    if db.chain_height().map_err(|e| e.to_string())?.is_none() {
        return Err("Transparent broadcast authority unavailable: chain height unknown".into());
    }
    db.check_transparent_transaction_inputs(tx, earlier, target.into())
        .map_err(|e| format!("Transparent broadcast authority unavailable: {e}"))?;
    let result = send.await;
    drop(db);
    Ok(result)
}

/// Reconciles finalized bytes against mined wallet evidence before considering expiry.
/// The read transaction binds the compatibility check and evidence to one snapshot.
pub(crate) fn stored_mined(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
) -> Result<bool, String> {
    use rusqlite::OptionalExtension;
    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerRead;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    conn.execute_batch("BEGIN").map_err(|e| e.to_string())?;
    let db = crate::wallet::db::wallet_db_on(&conn, db_path, network);
    db.transparent_ledger_mode()
        .map_err(|e| format!("Stored transaction authority unavailable: {e}"))?;
    let mut raw = Vec::new();
    tx.write(&mut raw).map_err(|e| e.to_string())?;
    let stored: Option<Vec<u8>> = conn
        .query_row(
            "SELECT raw FROM transactions WHERE txid = ?1 AND mined_height IS NOT NULL",
            [tx.txid().as_ref()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .flatten();
    Ok(stored.as_deref() == Some(raw.as_slice()))
}
