//! Read-only transaction / balance / pending-tx query surface.
//!
//! Everything in this module is an "ask the wallet a question"
//! helper that the FRB layer in `api/sync.rs` or the C FFI layer in
//! `ffi.rs` calls per user action:
//!
//!   - Balance / address queries (`get_wallet_balance`,
//!     `get_next_available_address`).
//!   - Transaction list + on-chain enhancement requests
//!     (`get_transaction_history`, `get_transaction_data_requests`,
//!     `decrypt_and_store_transaction`, `set_transaction_status`).
//!   - Pending-tx tracking for the iOS "tx track" Live Activity
//!     (`get_pending_transactions`, `check_tx_mined`).
//!
//! None of these belong to the orchestration loop — the loop lives
//! in `sync_engine/mod.rs`. They're one-shot lookups the UI drives
//! directly, so extracting them into their own submodule keeps
//! `sync/mod.rs` focused on per-wallet infrastructure (DB open,
//! chain-tip update, scan range management) and the shared
//! PROPOSAL_STORE used by both the software and PCZT send paths.

use zcash_client_backend::data_api::{wallet::ConfirmationsPolicy, WalletRead, WalletWrite};
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::keys::parse_account_uuid;
use crate::wallet::network::WalletNetwork;

use super::{open_readonly_conn, open_wallet_db, open_wallet_db_for_read};

// ======================== Balance ========================

pub(crate) struct WalletBalance {
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
    pub transparent_pending: u64,
    pub sapling_pending: u64,
    pub orchard_pending: u64,
}

pub fn get_wallet_balance(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<WalletBalance, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let target_id = parse_account_uuid(account_uuid)?;
    match db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("{e}"))?
    {
        Some(s) => match s.account_balances().get(&target_id) {
            Some(b) => Ok(WalletBalance {
                transparent: u64::from(b.unshielded_balance().spendable_value()),
                sapling: u64::from(b.sapling_balance().spendable_value()),
                orchard: u64::from(b.orchard_balance().spendable_value()),
                transparent_pending: u64::from(
                    b.unshielded_balance().change_pending_confirmation(),
                ) + u64::from(
                    b.unshielded_balance().value_pending_spendability(),
                ),
                sapling_pending: u64::from(b.sapling_balance().change_pending_confirmation())
                    + u64::from(b.sapling_balance().value_pending_spendability()),
                orchard_pending: u64::from(b.orchard_balance().change_pending_confirmation())
                    + u64::from(b.orchard_balance().value_pending_spendability()),
            }),
            None => Ok(WalletBalance {
                transparent: 0,
                sapling: 0,
                orchard: 0,
                transparent_pending: 0,
                sapling_pending: 0,
                orchard_pending: 0,
            }),
        },
        None => Ok(WalletBalance {
            transparent: 0,
            sapling: 0,
            orchard: 0,
            transparent_pending: 0,
            sapling_pending: 0,
            orchard_pending: 0,
        }),
    }
}

// ======================== Diversified Address ========================

pub fn get_next_available_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<String, String> {
    use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
    let account_id = parse_account_uuid(account_uuid)?;
    let req = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
    )
    .map_err(|_| "bad request")?;
    let (ua, _) = with_wallet_db_write_lock("transactions.get_next_available_address", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.get_next_available_address(account_id, req)
            .map_err(|e| format!("{e}"))?
            .ok_or_else(|| "No address available".to_string())
    })?;
    Ok(ua.encode(&network))
}

// ======================== Transaction Enhancement Requests ========================

pub(crate) struct TxDataRequest {
    pub request_type: String, // "get_status", "enhancement", "address_txids"
    pub txid: Option<String>,
    pub address: Option<String>,
    pub block_range_start: Option<u64>,
    pub block_range_end: Option<u64>,
}

pub fn get_transaction_data_requests(
    db_path: &str,
    network: WalletNetwork,
) -> Result<Vec<TxDataRequest>, String> {
    use zcash_client_backend::data_api::TransactionDataRequest;

    let db = open_wallet_db_for_read(db_path, network)?;
    let requests = db.transaction_data_requests().map_err(|e| format!("{e}"))?;

    Ok(requests
        .into_iter()
        .map(|r| match r {
            TransactionDataRequest::GetStatus(txid) => TxDataRequest {
                request_type: "get_status".into(),
                txid: Some(format!("{txid}")),
                address: None,
                block_range_start: None,
                block_range_end: None,
            },
            TransactionDataRequest::Enhancement(txid) => TxDataRequest {
                request_type: "enhancement".into(),
                txid: Some(format!("{txid}")),
                address: None,
                block_range_start: None,
                block_range_end: None,
            },
            TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                let addr =
                    zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
                TxDataRequest {
                    request_type: "address_txids".into(),
                    txid: None,
                    address: Some(addr),
                    block_range_start: Some(u32::from(req.block_range_start()) as u64),
                    block_range_end: req.block_range_end().map(|h| u32::from(h) as u64),
                }
            }
        })
        .collect())
}

pub fn decrypt_and_store_transaction(
    db_path: &str,
    network: WalletNetwork,
    tx_bytes: &[u8],
    mined_height: Option<u64>,
) -> Result<(), String> {
    use zcash_client_backend::data_api::wallet::decrypt_and_store_transaction;
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::BranchId;

    let tx = Transaction::read(tx_bytes, BranchId::Sapling)
        .map_err(|e| format!("Failed to read transaction: {e}"))?;
    let height = mined_height.map(|h| BlockHeight::from_u32(h as u32));

    with_wallet_db_write_lock("transactions.decrypt_and_store_transaction", || {
        let mut db = open_wallet_db(db_path, network)?;
        decrypt_and_store_transaction(&network, &mut db, &tx, height)
            .map_err(|e| format!("Failed to decrypt/store transaction: {e}"))
    })
}

pub fn set_transaction_status(
    db_path: &str,
    network: WalletNetwork,
    txid_hex: &str,
    status: i64,
) -> Result<(), String> {
    use zcash_client_backend::data_api::TransactionStatus;

    let txid_bytes = hex::decode(txid_hex).map_err(|e| format!("Bad txid hex: {e}"))?;
    let txid = zcash_primitives::transaction::TxId::from_bytes(
        txid_bytes.try_into().map_err(|_| "TxId must be 32 bytes")?,
    );

    let tx_status = match status {
        -2 => TransactionStatus::TxidNotRecognized,
        -1 => TransactionStatus::NotInMainChain,
        h => TransactionStatus::Mined(BlockHeight::from_u32(h as u32)),
    };

    with_wallet_db_write_lock("transactions.set_transaction_status", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.set_transaction_status(txid, tx_status)
            .map_err(|e| format!("Failed to set status: {e}"))
    })
}

// ======================== Transaction History (SQL) ========================

pub(crate) struct TransactionInfo {
    pub txid_hex: String,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub account_balance_delta: i64,
    pub fee: u64,
    pub block_time: u64,
    pub is_transparent: bool,
    pub tx_kind: String,
    pub display_amount: u64,
    pub display_pool: String,
    pub created_time: u64,
}

pub fn get_transaction_history(
    db_path: &str,
    _network: WalletNetwork,
    limit: Option<u32>,
    account_uuid: &str,
) -> Result<Vec<TransactionInfo>, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();

    // Open a separate read-only connection (WalletDb.conn is private).
    let conn = open_readonly_conn(db_path)?;
    let sql = match limit {
        Some(_) => {
            "SELECT vt.txid, vt.mined_height, vt.expired_unmined, vt.account_balance_delta, \
             COALESCE(vt.fee_paid, 0), COALESCE(vt.block_time, 0), \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool = 0 \
                   AND (txo.from_account_uuid = vt.account_uuid OR txo.to_account_uuid = vt.account_uuid) \
             ) AS is_transparent, \
             COALESCE(vt.total_spent, 0) AS total_spent, \
             COALESCE(vt.total_received, 0) AS total_received, \
             COALESCE(vt.is_shielding, 0) AS is_shielding, \
             COALESCE(( \
                 SELECT SUM(txo.value) \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.from_account_uuid = vt.account_uuid \
                   AND txo.to_account_uuid IS NULL \
                   AND txo.is_change = 0 \
             ), 0) AS external_sent_amount, \
             COALESCE(( \
                 SELECT SUM(txo.value) \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.to_account_uuid = vt.account_uuid \
                   AND txo.from_account_uuid IS NULL \
                   AND txo.is_change = 0 \
             ), 0) AS external_received_amount, \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool = 0 \
                   AND ( \
                       (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                       OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                   ) \
             ) AS display_has_transparent, \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool IN (2, 3) \
                   AND ( \
                       (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                       OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                   ) \
             ) AS display_has_shielded, \
             CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time \
             FROM v_transactions vt \
             LEFT JOIN transactions tx ON tx.txid = vt.txid \
             WHERE vt.account_uuid = ?1 \
               AND NOT ( \
                   COALESCE(vt.is_shielding, 0) = 0 \
                   AND COALESCE(vt.total_spent, 0) > 0 \
                   AND COALESCE(vt.total_received, 0) > 0 \
                   AND COALESCE(vt.account_balance_delta, 0) <= 0 \
                   AND tx.created IS NOT NULL \
                   AND NOT EXISTS ( \
                       SELECT 1 \
                       FROM v_tx_outputs txo \
                       WHERE txo.txid = vt.txid \
                         AND ( \
                             (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                             OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                         ) \
                   ) \
                   AND EXISTS ( \
                       SELECT 1 \
                       FROM v_tx_outputs txo \
                       WHERE txo.txid = vt.txid \
                         AND txo.output_pool = 0 \
                         AND txo.from_account_uuid = vt.account_uuid \
                         AND txo.to_account_uuid = vt.account_uuid \
                         AND txo.is_change = 0 \
                   ) \
                   AND EXISTS ( \
                       SELECT 1 \
                       FROM v_transactions sibling_vt \
                       JOIN transactions sibling_tx ON sibling_tx.txid = sibling_vt.txid \
                       WHERE sibling_vt.account_uuid = vt.account_uuid \
                         AND sibling_vt.txid != vt.txid \
                         AND sibling_tx.created = tx.created \
                         AND COALESCE(sibling_vt.expiry_height, -1) = COALESCE(vt.expiry_height, -1) \
                         AND EXISTS ( \
                             SELECT 1 \
                             FROM v_tx_outputs sibling_txo \
                             WHERE sibling_txo.txid = sibling_vt.txid \
                               AND sibling_txo.output_pool = 0 \
                               AND sibling_txo.from_account_uuid = sibling_vt.account_uuid \
                               AND sibling_txo.to_account_uuid IS NULL \
                               AND sibling_txo.is_change = 0 \
                         ) \
                   ) \
               ) \
             ORDER BY COALESCE(vt.mined_height, 999999999) DESC, vt.tx_index DESC \
             LIMIT ?2"
        }
        None => {
            "SELECT vt.txid, vt.mined_height, vt.expired_unmined, vt.account_balance_delta, \
             COALESCE(vt.fee_paid, 0), COALESCE(vt.block_time, 0), \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool = 0 \
                   AND (txo.from_account_uuid = vt.account_uuid OR txo.to_account_uuid = vt.account_uuid) \
             ) AS is_transparent, \
             COALESCE(vt.total_spent, 0) AS total_spent, \
             COALESCE(vt.total_received, 0) AS total_received, \
             COALESCE(vt.is_shielding, 0) AS is_shielding, \
             COALESCE(( \
                 SELECT SUM(txo.value) \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.from_account_uuid = vt.account_uuid \
                   AND txo.to_account_uuid IS NULL \
                   AND txo.is_change = 0 \
             ), 0) AS external_sent_amount, \
             COALESCE(( \
                 SELECT SUM(txo.value) \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.to_account_uuid = vt.account_uuid \
                   AND txo.from_account_uuid IS NULL \
                   AND txo.is_change = 0 \
             ), 0) AS external_received_amount, \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool = 0 \
                   AND ( \
                       (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                       OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                   ) \
             ) AS display_has_transparent, \
             EXISTS( \
                 SELECT 1 \
                 FROM v_tx_outputs txo \
                 WHERE txo.txid = vt.txid \
                   AND txo.output_pool IN (2, 3) \
                   AND ( \
                       (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                       OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                   ) \
             ) AS display_has_shielded, \
             CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time \
             FROM v_transactions vt \
             LEFT JOIN transactions tx ON tx.txid = vt.txid \
             WHERE vt.account_uuid = ?1 \
               AND NOT ( \
                   COALESCE(vt.is_shielding, 0) = 0 \
                   AND COALESCE(vt.total_spent, 0) > 0 \
                   AND COALESCE(vt.total_received, 0) > 0 \
                   AND COALESCE(vt.account_balance_delta, 0) <= 0 \
                   AND tx.created IS NOT NULL \
                   AND NOT EXISTS ( \
                       SELECT 1 \
                       FROM v_tx_outputs txo \
                       WHERE txo.txid = vt.txid \
                         AND ( \
                             (txo.from_account_uuid = vt.account_uuid AND txo.to_account_uuid IS NULL AND txo.is_change = 0) \
                             OR (txo.to_account_uuid = vt.account_uuid AND txo.from_account_uuid IS NULL AND txo.is_change = 0) \
                         ) \
                   ) \
                   AND EXISTS ( \
                       SELECT 1 \
                       FROM v_tx_outputs txo \
                       WHERE txo.txid = vt.txid \
                         AND txo.output_pool = 0 \
                         AND txo.from_account_uuid = vt.account_uuid \
                         AND txo.to_account_uuid = vt.account_uuid \
                         AND txo.is_change = 0 \
                   ) \
                   AND EXISTS ( \
                       SELECT 1 \
                       FROM v_transactions sibling_vt \
                       JOIN transactions sibling_tx ON sibling_tx.txid = sibling_vt.txid \
                       WHERE sibling_vt.account_uuid = vt.account_uuid \
                         AND sibling_vt.txid != vt.txid \
                         AND sibling_tx.created = tx.created \
                         AND COALESCE(sibling_vt.expiry_height, -1) = COALESCE(vt.expiry_height, -1) \
                         AND EXISTS ( \
                             SELECT 1 \
                             FROM v_tx_outputs sibling_txo \
                             WHERE sibling_txo.txid = sibling_vt.txid \
                               AND sibling_txo.output_pool = 0 \
                               AND sibling_txo.from_account_uuid = sibling_vt.account_uuid \
                               AND sibling_txo.to_account_uuid IS NULL \
                               AND sibling_txo.is_change = 0 \
                         ) \
                   ) \
               ) \
             ORDER BY COALESCE(vt.mined_height, 999999999) DESC, vt.tx_index DESC"
        }
    };
    let mut stmt = conn.prepare(sql).map_err(|e| format!("SQL error: {e}"))?;

    let map_row = |row: &rusqlite::Row| -> rusqlite::Result<TransactionInfo> {
        let txid_blob: Vec<u8> = row.get(0)?;
        let mined_height: Option<u32> = row.get(1)?;
        let expired_unmined: bool = row.get(2)?;
        let balance_delta: i64 = row.get(3)?;
        let fee: u64 = row.get::<_, i64>(4)?.unsigned_abs();
        let block_time: u64 = row.get::<_, i64>(5)?.unsigned_abs();
        let is_transparent: bool = row.get(6)?;
        let total_spent = row.get::<_, i64>(7)?.unsigned_abs();
        let total_received = row.get::<_, i64>(8)?.unsigned_abs();
        let is_shielding: bool = row.get(9)?;
        let external_sent_amount = row.get::<_, i64>(10)?.unsigned_abs();
        let external_received_amount = row.get::<_, i64>(11)?.unsigned_abs();
        let display_has_transparent: bool = row.get(12)?;
        let display_has_shielded: bool = row.get(13)?;
        let created_time = row.get::<_, i64>(14)?.unsigned_abs();

        let display_pool = if is_shielding {
            "shielded"
        } else {
            match (display_has_transparent, display_has_shielded) {
                (true, false) => "transparent",
                (false, true) => "shielded",
                (true, true) => "mixed",
                (false, false) => "unknown",
            }
        }
        .to_string();

        let (tx_kind, display_amount) = if is_shielding {
            ("shielded", total_received)
        } else if external_sent_amount > 0 {
            ("sent", external_sent_amount)
        } else if external_received_amount > 0 {
            ("received", external_received_amount)
        } else if total_spent > 0 && total_received > 0 {
            ("internal", total_received)
        } else if balance_delta > 0 {
            ("received", balance_delta as u64)
        } else {
            ("unknown", 0)
        };

        Ok(TransactionInfo {
            txid_hex: hex::encode(&txid_blob),
            mined_height: mined_height.unwrap_or(0) as u64,
            expired_unmined,
            account_balance_delta: balance_delta,
            fee,
            block_time,
            is_transparent,
            tx_kind: tx_kind.to_string(),
            display_amount,
            display_pool,
            created_time,
        })
    };

    let rows = if let Some(n) = limit {
        stmt.query_map(rusqlite::params![&uuid_bytes, n], map_row)
    } else {
        stmt.query_map(rusqlite::params![&uuid_bytes], map_row)
    }
    .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

// ======================== Pending TX Tracking ========================

pub(crate) struct PendingTxInfo {
    pub txid_bytes: Vec<u8>,
    pub txid_hex: String,
    pub expiry_height: u64,
}

/// A wallet-created transaction that is eligible for automatic
/// resubmit: unmined, not past its expiry height, and sending value
/// out of the wallet.
///
/// `raw_tx` is the full serialized transaction bytes ready to feed
/// back into `send_transaction` — no re-encoding required. The
/// resubmit path at `sync::send::resubmit_pending_transactions`
/// consumes this struct directly.
pub(crate) struct ResubmittableTx {
    pub txid_bytes: Vec<u8>,
    pub raw_tx: Vec<u8>,
    pub expiry_height: u32,
}

/// Return every wallet transaction that is eligible for automatic
/// resubmit at `current_height`.
///
/// Mirrors zcash-android-wallet-sdk's `SELECTION_TRX_RESUBMISSION`
/// predicate — see the Phase 3 design notes for why we follow the
/// SDK exactly:
///
///   * `mined_height IS NULL` — the transaction has not yet been
///     confirmed in a block.
///   * `expiry_height > ?current_height` — the transaction is still
///     valid to relay; once the current tip passes `expiry_height`
///     the network will drop it and there is nothing we can do by
///     resubmitting.
///   * `account_balance_delta < 0` — the net balance change for the
///     account is negative, i.e. this is an outbound transaction
///     the wallet originated. Inbound transactions the sync loop
///     merely discovered on-chain (via `get_transaction` enhance
///     calls) should never be "resubmitted".
///   * `raw IS NOT NULL` — we actually have the serialized bytes to
///     broadcast. Defense-in-depth on top of the delta filter.
///
/// A transaction that touches more than one of the wallet's own
/// accounts shows up as more than one row in `v_transactions`; we
/// `SELECT DISTINCT` on `(txid, raw, expiry_height)` to collapse
/// that into a single broadcast instead of double-sending the same
/// bytes.
pub(crate) fn get_resubmittable_txs(
    db_path: &str,
    current_height: u32,
) -> Result<Vec<ResubmittableTx>, String> {
    let conn = open_readonly_conn(db_path)?;

    let mut stmt = conn
        .prepare(
            "SELECT DISTINCT txid, raw, expiry_height \
             FROM v_transactions \
             WHERE mined_height IS NULL \
               AND expiry_height > ?1 \
               AND account_balance_delta < 0 \
               AND raw IS NOT NULL",
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map([current_height], |row| {
            let txid_bytes: Vec<u8> = row.get(0)?;
            let raw_tx: Vec<u8> = row.get(1)?;
            // `expiry_height > ?1` in the WHERE clause guarantees a
            // non-null positive value, but rusqlite still types the
            // column as nullable — unwrap via COALESCE-equivalent
            // on the Rust side instead of patching the SQL.
            let expiry_height: u32 = row
                .get::<_, Option<i64>>(2)?
                .map(|h| h.max(0) as u32)
                .unwrap_or(0);
            Ok(ResubmittableTx {
                txid_bytes,
                raw_tx,
                expiry_height,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

/// Get all pending (unmined, unexpired) transactions that we
/// created (have raw bytes).
pub fn get_pending_transactions(db_path: &str) -> Result<Vec<PendingTxInfo>, String> {
    let conn = open_readonly_conn(db_path)?;

    let mut stmt = conn
        .prepare(
            "SELECT txid, COALESCE(expiry_height, 0) \
             FROM transactions \
             WHERE mined_height IS NULL AND expired_unmined = 0 AND raw IS NOT NULL",
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map([], |row| {
            let txid_bytes: Vec<u8> = row.get(0)?;
            let expiry_height: u64 = row.get::<_, i64>(1)?.unsigned_abs();
            let txid_hex = hex::encode(&txid_bytes);
            Ok(PendingTxInfo {
                txid_bytes,
                txid_hex,
                expiry_height,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

/// Check if a transaction has been mined by querying lightwalletd.
/// Returns: `0` = still in mempool, `> 0` = mined at that height,
/// `-1` = error / not found.
pub async fn check_tx_mined(lightwalletd_url: &str, txid_bytes: &[u8]) -> i64 {
    use zcash_client_backend::proto::service::TxFilter;

    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(pair) => pair,
        Err(e) => {
            log::warn!("txtrack: {e}");
            return -1;
        }
    };

    let filter = TxFilter {
        block: None,
        index: 0,
        hash: txid_bytes.to_vec(),
    };

    match client.get_transaction(filter).await {
        Ok(resp) => {
            let height = resp.into_inner().height;
            // height 0 = mempool, 0xffffffffffffffff = fork, else = mined
            if height == 0 || height == u64::MAX {
                0 // still pending
            } else {
                height as i64
            }
        }
        Err(e) => {
            log::warn!("txtrack: GetTransaction failed: {e}");
            -1
        }
    }
}

#[cfg(test)]
mod tests {
    //! SQL-predicate regression tests for `get_resubmittable_txs`.
    //!
    //! `get_resubmittable_txs` is a thin wrapper around a `v_transactions`
    //! SELECT, but the SELECT is the entire contract: it's the piece that
    //! encodes the four resubmit invariants we copied from
    //! `zcash-android-wallet-sdk`'s `SELECTION_TRX_RESUBMISSION`.
    //!
    //! We test against a stand-in schema: a real SQLite DB with a plain
    //! `v_transactions` table mirroring the columns the production view
    //! exposes. That's enough for the WHERE clause to exercise each
    //! filter independently without standing up the whole
    //! `zcash_client_sqlite` migration stack.
    //!
    //! If the production `v_transactions` view ever gains (or loses)
    //! one of the columns we query here (`txid`, `raw`, `mined_height`,
    //! `expiry_height`, `account_balance_delta`), the real build breaks
    //! loudly at the first real query — but these unit tests still
    //! exercise the logic, so a regression in the SQL text shows up here
    //! first.
    use super::*;
    use tempfile::NamedTempFile;

    /// Build a throwaway SQLite database with a minimal
    /// `v_transactions` table and return its `NamedTempFile`
    /// handle. Tests keep the handle alive for the duration of the
    /// test so the file isn't auto-deleted under them.
    fn fresh_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE v_transactions (
                 txid BLOB NOT NULL,
                 raw BLOB,
                 mined_height INTEGER,
                 expiry_height INTEGER,
                 account_balance_delta INTEGER NOT NULL
             );",
        )
        .unwrap();
        file
    }

    /// Insert one synthetic row into `v_transactions`.
    fn insert_row(
        db: &NamedTempFile,
        txid: &[u8],
        raw: Option<&[u8]>,
        mined_height: Option<i64>,
        expiry_height: Option<i64>,
        account_balance_delta: i64,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "INSERT INTO v_transactions (txid, raw, mined_height, expiry_height, account_balance_delta)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![txid, raw, mined_height, expiry_height, account_balance_delta],
        )
        .unwrap();
    }

    fn fake_txid(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    fn fake_raw() -> Vec<u8> {
        vec![0xDE, 0xAD, 0xBE, 0xEF]
    }

    #[test]
    fn resubmit_excludes_mined_txs() {
        // A tx with `mined_height IS NOT NULL` is already on-chain;
        // resubmitting would be pointless at best and could surface a
        // confusing rejection from lightwalletd.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x01),
            Some(&fake_raw()),
            Some(1_000_000), // mined_height set → mined
            Some(1_000_100),
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 900_000).unwrap();
        assert!(
            got.is_empty(),
            "mined tx must not be a resubmit candidate, got {got:?}",
            got = got.len(),
        );
    }

    #[test]
    fn resubmit_excludes_expired_txs() {
        // `expiry_height > current_height` is the network's
        // still-relayable check. A tx whose expiry equals the current
        // height is already past the window.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x02),
            Some(&fake_raw()),
            None,
            Some(1_000_000), // expiry == current → expired
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "tx with expiry==current must be excluded");

        // Walk the boundary: one block below current is definitely expired.
        let db2 = fresh_db();
        insert_row(
            &db2,
            &fake_txid(0x02),
            Some(&fake_raw()),
            None,
            Some(999_999),
            -5_000,
        );
        let got2 = get_resubmittable_txs(db2.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got2.is_empty(), "tx with expiry<current must be excluded");
    }

    #[test]
    fn resubmit_excludes_received_txs() {
        // `account_balance_delta >= 0` means the account gained or broke
        // even on this tx — it's an incoming transfer we just happened to
        // have raw bytes for (e.g. re-read from lightwalletd during a
        // rescan). Resubmitting "our" received txs back to the network
        // would be meaningless.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x03),
            Some(&fake_raw()),
            None,
            Some(1_000_100),
            5_000, // positive delta → inbound
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "received-only tx must be excluded");

        // Also the zero case: a break-even tx shouldn't show up either
        // (it's still not an "outbound" the wallet needs to keep alive).
        let db2 = fresh_db();
        insert_row(
            &db2,
            &fake_txid(0x03),
            Some(&fake_raw()),
            None,
            Some(1_000_100),
            0,
        );
        let got2 = get_resubmittable_txs(db2.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got2.is_empty(), "zero-delta tx must be excluded");
    }

    #[test]
    fn resubmit_excludes_raw_null_txs() {
        // `raw IS NULL` means we don't have bytes to broadcast. This row
        // exists because sync learned about the tx via decrypt-and-store
        // without the raw bundle, and there's nothing we can resubmit.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x04),
            None, // raw NULL
            None,
            Some(1_000_100),
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "raw-null tx must be excluded");
    }

    #[test]
    fn resubmit_includes_valid_outbound_pending() {
        // The happy path: unmined, inside expiry, outbound, raw present.
        let db = fresh_db();
        let txid = fake_txid(0x05);
        let raw = fake_raw();
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -5_000);
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(got.len(), 1, "outbound pending tx must appear exactly once");
        assert_eq!(got[0].txid_bytes, txid.to_vec());
        assert_eq!(got[0].raw_tx, raw);
        assert_eq!(got[0].expiry_height, 1_000_100);
    }

    #[test]
    fn resubmit_dedupes_multi_account_rows() {
        // A tx that touches two of the wallet's own accounts shows up as
        // two rows in `v_transactions`. `SELECT DISTINCT txid, raw,
        // expiry_height` should collapse that to one broadcast — double-
        // sending identical bytes would be a regression.
        let db = fresh_db();
        let txid = fake_txid(0x06);
        let raw = fake_raw();
        // Two rows for the same tx, different account-level deltas, both
        // still outbound at the row level (account-internal transfer with
        // a net negative for both of the wallet's participating accounts
        // after fees — contrived but possible).
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -3_000);
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -2_000);

        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(
            got.len(),
            1,
            "multi-account rows with same (txid, raw, expiry) must dedupe",
        );
    }

    #[test]
    fn resubmit_returns_empty_when_table_empty() {
        // Baseline: an empty table must return `Ok(vec![])`, not an
        // error. `resubmit_pending_transactions` relies on this to
        // decide the "nothing to do" case.
        let db = fresh_db();
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty());
    }
}
