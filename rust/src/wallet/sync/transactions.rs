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
use zcash_protocol::consensus::{BlockHeight, Network};

use crate::wallet::keys::parse_account_uuid;

use super::open_wallet_db;

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
    network: Network,
    account_uuid: &str,
) -> Result<WalletBalance, String> {
    let db = open_wallet_db(db_path, network)?;
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
                transparent_pending: u64::from(b.unshielded_balance().change_pending_confirmation())
                    + u64::from(b.unshielded_balance().value_pending_spendability()),
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
    network: Network,
    account_uuid: &str,
) -> Result<String, String> {
    use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let req = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
    )
    .map_err(|_| "bad request")?;
    let (ua, _) = db
        .get_next_available_address(account_id, req)
        .map_err(|e| format!("{e}"))?
        .ok_or("No address available")?;
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
    network: Network,
) -> Result<Vec<TxDataRequest>, String> {
    use zcash_client_backend::data_api::TransactionDataRequest;

    let db = open_wallet_db(db_path, network)?;
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
                let addr = zcash_keys::encoding::encode_transparent_address_p(
                    &network,
                    &req.address(),
                );
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
    network: Network,
    tx_bytes: &[u8],
    mined_height: Option<u64>,
) -> Result<(), String> {
    use zcash_client_backend::data_api::wallet::decrypt_and_store_transaction;
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::BranchId;

    let mut db = open_wallet_db(db_path, network)?;
    let tx = Transaction::read(tx_bytes, BranchId::Sapling)
        .map_err(|e| format!("Failed to read transaction: {e}"))?;
    let height = mined_height.map(|h| BlockHeight::from_u32(h as u32));

    decrypt_and_store_transaction(&network, &mut db, &tx, height)
        .map_err(|e| format!("Failed to decrypt/store transaction: {e}"))
}

pub fn set_transaction_status(
    db_path: &str,
    network: Network,
    txid_hex: &str,
    status: i64,
) -> Result<(), String> {
    use zcash_client_backend::data_api::TransactionStatus;

    let mut db = open_wallet_db(db_path, network)?;
    let txid_bytes = hex::decode(txid_hex).map_err(|e| format!("Bad txid hex: {e}"))?;
    let txid = zcash_primitives::transaction::TxId::from_bytes(
        txid_bytes.try_into().map_err(|_| "TxId must be 32 bytes")?,
    );

    let tx_status = match status {
        -2 => TransactionStatus::TxidNotRecognized,
        -1 => TransactionStatus::NotInMainChain,
        h => TransactionStatus::Mined(BlockHeight::from_u32(h as u32)),
    };

    db.set_transaction_status(txid, tx_status)
        .map_err(|e| format!("Failed to set status: {e}"))
}

// ======================== Transaction History (SQL) ========================

pub(crate) struct TransactionInfo {
    pub txid_hex: String,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub account_balance_delta: i64,
    pub fee: u64,
    pub block_time: u64,
}

pub fn get_transaction_history(
    db_path: &str,
    _network: Network,
    limit: Option<u32>,
    account_uuid: &str,
) -> Result<Vec<TransactionInfo>, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();

    // Open a separate read-only connection (WalletDb.conn is private).
    let conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .map_err(|e| format!("Failed to open DB: {e}"))?;
    let sql = match limit {
        Some(_) => {
            "SELECT txid, mined_height, expired_unmined, account_balance_delta, \
             COALESCE(fee_paid, 0), COALESCE(block_time, 0) \
             FROM v_transactions \
             WHERE account_uuid = ?1 \
             ORDER BY COALESCE(mined_height, 999999999) DESC, tx_index DESC \
             LIMIT ?2"
        }
        None => {
            "SELECT txid, mined_height, expired_unmined, account_balance_delta, \
             COALESCE(fee_paid, 0), COALESCE(block_time, 0) \
             FROM v_transactions \
             WHERE account_uuid = ?1 \
             ORDER BY COALESCE(mined_height, 999999999) DESC, tx_index DESC"
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
        Ok(TransactionInfo {
            txid_hex: hex::encode(&txid_blob),
            mined_height: mined_height.unwrap_or(0) as u64,
            expired_unmined,
            account_balance_delta: balance_delta,
            fee,
            block_time,
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

/// Get all pending (unmined, unexpired) transactions that we
/// created (have raw bytes).
pub fn get_pending_transactions(db_path: &str) -> Result<Vec<PendingTxInfo>, String> {
    let conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .map_err(|e| format!("Failed to open DB: {e}"))?;

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

    let (mut client, _tor_guard) =
        match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
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
