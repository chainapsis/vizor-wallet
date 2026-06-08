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

use std::collections::{HashMap, HashSet};

use rusqlite::OptionalExtension;
use zcash_client_backend::data_api::{wallet::ConfirmationsPolicy, WalletRead, WalletWrite};
use zcash_protocol::{
    consensus::BlockHeight,
    memo::{Memo, MemoBytes},
};

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
    address_request: AddressRequestKind,
) -> Result<String, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let req = address_request.to_unified_address_request()?;

    let (ua, _) = with_wallet_db_write_lock("transactions.get_next_available_address", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.get_next_available_address(account_id, req)
            .map_err(|e| format!("{e}"))?
            .ok_or_else(|| "No address available".to_string())
    })?;
    Ok(ua.encode(&network))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AddressRequestKind {
    Shielded,
    Orchard,
}

pub fn parse_address_request_kind(request: &str) -> Result<AddressRequestKind, String> {
    match request {
        "shielded" => Ok(AddressRequestKind::Shielded),
        "orchard" => Ok(AddressRequestKind::Orchard),
        _ => Err(format!(
            "Unsupported address request '{request}'. Expected 'shielded' or 'orchard'."
        )),
    }
}

impl AddressRequestKind {
    fn to_unified_address_request(self) -> Result<zcash_keys::keys::UnifiedAddressRequest, String> {
        match self {
            AddressRequestKind::Shielded => shielded_address_request(),
            AddressRequestKind::Orchard => Ok(orchard_address_request()),
        }
    }
}

fn shielded_address_request() -> Result<zcash_keys::keys::UnifiedAddressRequest, String> {
    use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};

    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
    )
    .map_err(|_| "bad shielded address request".to_string())
}

fn orchard_address_request() -> zcash_keys::keys::UnifiedAddressRequest {
    zcash_keys::keys::UnifiedAddressRequest::ORCHARD
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

// ======================== Transaction History ========================

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

pub(crate) struct TransactionDetail {
    pub txid_hex: String,
    pub tx_kind: String,
    pub primary_address: Option<String>,
    pub memo: Option<String>,
    pub outputs: Vec<TransactionDetailOutput>,
}

pub(crate) struct TransactionDetailOutput {
    pub address: Option<String>,
    pub amount_zatoshi: u64,
    pub pool: String,
}

pub(crate) struct ExportBirthdayAnchor {
    pub block_height: u64,
}

#[derive(Clone)]
struct TxBase {
    txid: Vec<u8>,
    mined_height: Option<u32>,
    expired_unmined: bool,
    account_balance_delta: i64,
    fee: u64,
    block_time: u64,
    total_spent: u64,
    total_received: u64,
    is_shielding: bool,
    expiry_height: Option<i64>,
    tx_index: i64,
    created: Option<String>,
    created_time: u64,
}

struct TxOutput {
    txid: Vec<u8>,
    output_pool: i64,
    output_index: i64,
    from_account_uuid: Option<Vec<u8>>,
    to_account_uuid: Option<Vec<u8>>,
    to_address: Option<String>,
    sent_to_address: Option<String>,
    transparent_receiver_address: Option<String>,
    to_key_scope: Option<i64>,
    value: u64,
    memo: Option<Vec<u8>>,
}

impl TxOutput {
    fn detail_address(&self, tx_kind: &str) -> Option<String> {
        if tx_kind == "sent" {
            if self.output_pool == 0 {
                return self
                    .transparent_receiver_address
                    .clone()
                    .or_else(|| self.sent_to_address.clone())
                    .or_else(|| self.to_address.clone());
            }

            self.sent_to_address
                .clone()
                .or_else(|| self.to_address.clone())
        } else {
            self.to_address.clone()
        }
    }
}

#[derive(Default, Clone)]
struct ActivityAmounts {
    amount: u64,
    has_transparent: bool,
    has_shielded: bool,
}

impl ActivityAmounts {
    fn add_output(&mut self, output: &TxOutput) {
        self.amount = self.amount.saturating_add(output.value);
        match output.output_pool {
            0 => self.has_transparent = true,
            2 | 3 => self.has_shielded = true,
            _ => {}
        }
    }

    fn display_pool(&self) -> &'static str {
        match (self.has_transparent, self.has_shielded) {
            (true, false) => "transparent",
            (false, true) => "shielded",
            (true, true) => "mixed",
            (false, false) => "unknown",
        }
    }
}

#[derive(Default, Clone)]
struct ActivitySummary {
    sent: ActivityAmounts,
    received: ActivityAmounts,
    shielded: ActivityAmounts,
    has_own_transparent_output: bool,
    has_external_transparent_send: bool,
}

struct ClassifiedTx {
    info: TransactionInfo,
    sort_pending_rank: u8,
    sort_timestamp: u64,
    sort_mined_height: u64,
    tx_index: i64,
    row_order: u8,
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
    let read_tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("SQL error: {e}"))?;
    let bases = read_history_bases(&read_tx, &uuid_bytes)?;
    if bases.is_empty() {
        return Ok(Vec::new());
    }

    let outputs_by_txid = read_history_outputs(&read_tx, &uuid_bytes)?;
    let summaries: HashMap<Vec<u8>, ActivitySummary> = bases
        .iter()
        .map(|base| {
            let outputs = outputs_by_txid
                .get(&base.txid)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            (
                base.txid.clone(),
                summarize_activity_outputs(base, outputs, uuid_bytes.as_slice()),
            )
        })
        .collect();
    let external_send_keys = build_external_send_keys(&bases, &summaries);
    let suppressed_funding_step_fees =
        build_suppressed_funding_step_fees(&bases, &summaries, &external_send_keys);

    let mut visible = Vec::new();
    for base in &bases {
        let summary = summaries.get(&base.txid).cloned().unwrap_or_default();
        if should_suppress_funding_step(base, &summary, &external_send_keys) {
            continue;
        }

        let extra_sent_fee = if summary.has_external_transparent_send {
            funding_step_key(base)
                .and_then(|key| suppressed_funding_step_fees.get(&key).copied())
                .unwrap_or(0)
        } else {
            0
        };

        visible.extend(classify_history_tx(base, &summary, extra_sent_fee));
    }

    visible.retain(|tx| {
        tx.info.display_amount > 0 || tx.info.tx_kind == "unknown" || tx.info.tx_kind == "shielded"
    });

    visible.sort_by(|a, b| {
        b.sort_pending_rank
            .cmp(&a.sort_pending_rank)
            .then_with(|| b.sort_timestamp.cmp(&a.sort_timestamp))
            .then_with(|| b.sort_mined_height.cmp(&a.sort_mined_height))
            .then_with(|| b.tx_index.cmp(&a.tx_index))
            .then_with(|| b.info.txid_hex.cmp(&a.info.txid_hex))
            .then_with(|| a.row_order.cmp(&b.row_order))
    });

    if let Some(limit) = limit {
        visible.truncate(limit as usize);
    }

    Ok(visible.into_iter().map(|tx| tx.info).collect())
}

pub(crate) fn get_oldest_mined_transaction_anchor(
    db_path: &str,
    account_uuid: &str,
) -> Result<Option<ExportBirthdayAnchor>, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            mined_height
        FROM v_transactions
        WHERE account_uuid = ?1
          AND mined_height IS NOT NULL
        ORDER BY mined_height ASC, COALESCE(tx_index, -1) ASC
        LIMIT 1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    stmt.query_row(
        rusqlite::params![account_id.expose_uuid().as_bytes().as_slice()],
        |row| {
            let block_height = row.get::<_, u32>(0)?;
            Ok(ExportBirthdayAnchor {
                block_height: u64::from(block_height),
            })
        },
    )
    .optional()
    .map_err(|e| format!("Query error: {e}"))
}

pub(crate) fn get_export_birthday_anchor(
    db_path: &str,
    account_uuid: &str,
) -> Result<ExportBirthdayAnchor, String> {
    if let Some(anchor) = get_oldest_mined_transaction_anchor(db_path, account_uuid)? {
        return Ok(anchor);
    }

    get_account_birthday_height(db_path, account_uuid)?
        .map(|block_height| ExportBirthdayAnchor { block_height })
        .ok_or_else(|| "Account birthday not found".to_string())
}

fn get_account_birthday_height(db_path: &str, account_uuid: &str) -> Result<Option<u64>, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare("SELECT birthday_height FROM accounts WHERE uuid = ?1")
        .map_err(|e| format!("SQL error: {e}"))?;

    stmt.query_row(
        rusqlite::params![account_id.expose_uuid().as_bytes().as_slice()],
        |row| {
            let block_height = row.get::<_, u32>(0)?;
            Ok(u64::from(block_height))
        },
    )
    .optional()
    .map_err(|e| format!("Query error: {e}"))
}

pub fn get_transaction_detail(
    db_path: &str,
    _network: WalletNetwork,
    account_uuid: &str,
    txid_hex: &str,
    tx_kind: &str,
) -> Result<TransactionDetail, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();
    let txid = hex::decode(txid_hex).map_err(|e| format!("Invalid txid: {e}"))?;
    if txid.len() != 32 {
        return Err("Invalid txid length".to_string());
    }

    let conn = open_readonly_conn(db_path)?;
    let read_tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("SQL error: {e}"))?;
    let Some(base) = read_history_base_by_txid(&read_tx, &uuid_bytes, &txid)? else {
        return Err("Transaction not found".to_string());
    };
    let mut outputs = read_outputs_for_tx(&read_tx, &uuid_bytes, &txid)?;
    outputs.sort_by(|a, b| {
        a.output_index
            .cmp(&b.output_index)
            .then_with(|| a.output_pool.cmp(&b.output_pool))
    });

    let visible_outputs = outputs
        .iter()
        .filter(|output| detail_includes_output(&base, output, uuid_bytes.as_slice(), tx_kind))
        .collect::<Vec<_>>();
    let memo = visible_outputs
        .iter()
        .find_map(|output| decode_text_memo(output.memo.as_deref()));
    let primary_address = if tx_kind == "sent" {
        visible_outputs
            .iter()
            .find_map(|output| output.detail_address(tx_kind))
    } else {
        None
    };
    let outputs = visible_outputs
        .into_iter()
        .map(|output| TransactionDetailOutput {
            address: output.detail_address(tx_kind),
            amount_zatoshi: output.value,
            pool: output_pool_label(output.output_pool).to_string(),
        })
        .collect();

    Ok(TransactionDetail {
        txid_hex: hex::encode(&base.txid),
        tx_kind: tx_kind.to_string(),
        primary_address,
        memo,
        outputs,
    })
}

fn read_history_base_by_txid(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Option<TxBase>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            vt.txid,
            vt.mined_height,
            vt.expired_unmined,
            vt.account_balance_delta,
            COALESCE(vt.fee_paid, 0) AS fee_paid,
            COALESCE(vt.block_time, 0) AS block_time,
            COALESCE(vt.total_spent, 0) AS total_spent,
            COALESCE(vt.total_received, 0) AS total_received,
            COALESCE(vt.is_shielding, 0) AS is_shielding,
            vt.expiry_height,
            COALESCE(vt.tx_index, -1) AS tx_index,
            tx.created,
            CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time
        FROM v_transactions vt
        LEFT JOIN transactions tx ON tx.txid = vt.txid
        WHERE vt.account_uuid = ?1
          AND vt.txid = ?2
        LIMIT 1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let row = stmt
        .query_row(rusqlite::params![account_uuid, txid], |row| {
            Ok(TxBase {
                txid: row.get(0)?,
                mined_height: row.get(1)?,
                expired_unmined: row.get(2)?,
                account_balance_delta: row.get(3)?,
                fee: row.get::<_, i64>(4)?.unsigned_abs(),
                block_time: row.get::<_, i64>(5)?.unsigned_abs(),
                total_spent: row.get::<_, i64>(6)?.unsigned_abs(),
                total_received: row.get::<_, i64>(7)?.unsigned_abs(),
                is_shielding: row.get(8)?,
                expiry_height: row.get(9)?,
                tx_index: row.get(10)?,
                created: row.get(11)?,
                created_time: row.get::<_, i64>(12)?.unsigned_abs(),
            })
        })
        .optional()
        .map_err(|e| format!("Query error: {e}"))?;

    Ok(row)
}

fn read_history_bases(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
) -> Result<Vec<TxBase>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            vt.txid,
            vt.mined_height,
            vt.expired_unmined,
            vt.account_balance_delta,
            COALESCE(vt.fee_paid, 0) AS fee_paid,
            COALESCE(vt.block_time, 0) AS block_time,
            COALESCE(vt.total_spent, 0) AS total_spent,
            COALESCE(vt.total_received, 0) AS total_received,
            COALESCE(vt.is_shielding, 0) AS is_shielding,
            vt.expiry_height,
            COALESCE(vt.tx_index, -1) AS tx_index,
            tx.created,
            CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time
        FROM v_transactions vt
        LEFT JOIN transactions tx ON tx.txid = vt.txid
        WHERE vt.account_uuid = ?1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map(rusqlite::params![account_uuid], |row| {
            Ok(TxBase {
                txid: row.get(0)?,
                mined_height: row.get(1)?,
                expired_unmined: row.get(2)?,
                account_balance_delta: row.get(3)?,
                fee: row.get::<_, i64>(4)?.unsigned_abs(),
                block_time: row.get::<_, i64>(5)?.unsigned_abs(),
                total_spent: row.get::<_, i64>(6)?.unsigned_abs(),
                total_received: row.get::<_, i64>(7)?.unsigned_abs(),
                is_shielding: row.get(8)?,
                expiry_height: row.get(9)?,
                tx_index: row.get(10)?,
                created: row.get(11)?,
                created_time: row.get::<_, i64>(12)?.unsigned_abs(),
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

fn read_history_outputs(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
) -> Result<HashMap<Vec<u8>, Vec<TxOutput>>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            txo.txid,
            txo.output_pool,
            txo.output_index,
            txo.from_account_uuid,
            txo.to_account_uuid,
            txo.to_address,
            (
                SELECT sn.to_address
                FROM sent_notes sn
                JOIN transactions st ON st.id_tx = sn.transaction_id
                JOIN accounts from_acc ON from_acc.id = sn.from_account_id
                WHERE st.txid = txo.txid
                  AND from_acc.uuid = ?1
                  AND sn.output_pool = txo.output_pool
                  AND sn.output_index = txo.output_index
                  AND sn.to_address IS NOT NULL
                LIMIT 1
            ) AS sent_to_address,
            NULL AS transparent_receiver_address,
            (
                SELECT a.key_scope
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                LIMIT 1
            ) AS to_key_scope,
            txo.value,
            txo.memo
        FROM v_tx_outputs txo
        JOIN (
            SELECT DISTINCT txid
            FROM v_transactions
            WHERE account_uuid = ?1
        ) active_tx ON active_tx.txid = txo.txid
        WHERE txo.from_account_uuid = ?1
           OR txo.to_account_uuid = ?1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map(rusqlite::params![account_uuid], |row| {
            Ok(TxOutput {
                txid: row.get(0)?,
                output_pool: row.get(1)?,
                output_index: row.get(2)?,
                from_account_uuid: row.get(3)?,
                to_account_uuid: row.get(4)?,
                to_address: row.get(5)?,
                sent_to_address: row.get(6)?,
                transparent_receiver_address: row.get(7)?,
                to_key_scope: row.get(8)?,
                value: row.get::<_, i64>(9)?.unsigned_abs(),
                memo: row.get(10)?,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    let mut outputs = HashMap::<Vec<u8>, Vec<TxOutput>>::new();
    for row in rows {
        let output = row.map_err(|e| format!("Row error: {e}"))?;
        outputs.entry(output.txid.clone()).or_default().push(output);
    }
    Ok(outputs)
}

fn read_outputs_for_tx(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Vec<TxOutput>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            txo.txid,
            txo.output_pool,
            txo.output_index,
            txo.from_account_uuid,
            txo.to_account_uuid,
            txo.to_address,
            (
                SELECT sn.to_address
                FROM sent_notes sn
                JOIN transactions st ON st.id_tx = sn.transaction_id
                JOIN accounts from_acc ON from_acc.id = sn.from_account_id
                WHERE st.txid = txo.txid
                  AND from_acc.uuid = ?1
                  AND sn.output_pool = txo.output_pool
                  AND sn.output_index = txo.output_index
                  AND sn.to_address IS NOT NULL
                LIMIT 1
            ) AS sent_to_address,
            (
                SELECT a.cached_transparent_receiver_address
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND txo.output_pool = 0
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                  AND a.cached_transparent_receiver_address IS NOT NULL
                LIMIT 1
            ) AS transparent_receiver_address,
            (
                SELECT a.key_scope
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                LIMIT 1
            ) AS to_key_scope,
            txo.value,
            txo.memo
        FROM v_tx_outputs txo
        WHERE txo.txid = ?2
          AND (
              txo.from_account_uuid = ?1
              OR txo.to_account_uuid = ?1
          )
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map(rusqlite::params![account_uuid, txid], |row| {
            Ok(TxOutput {
                txid: row.get(0)?,
                output_pool: row.get(1)?,
                output_index: row.get(2)?,
                from_account_uuid: row.get(3)?,
                to_account_uuid: row.get(4)?,
                to_address: row.get(5)?,
                sent_to_address: row.get(6)?,
                transparent_receiver_address: row.get(7)?,
                to_key_scope: row.get(8)?,
                value: row.get::<_, i64>(9)?.unsigned_abs(),
                memo: row.get(10)?,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

fn summarize_activity_outputs(
    base: &TxBase,
    outputs: &[TxOutput],
    account_uuid: &[u8],
) -> ActivitySummary {
    let mut summary = ActivitySummary::default();

    for output in outputs {
        let from_own = output.from_account_uuid.as_deref() == Some(account_uuid);
        let to_own = output.to_account_uuid.as_deref() == Some(account_uuid);

        if base.is_shielding {
            if to_own && is_shielded_pool(output.output_pool) {
                summary.shielded.add_output(output);
            }
            continue;
        }

        if output.output_pool == 0 && from_own && to_own {
            summary.has_own_transparent_output = true;
        }

        let visible_self_output = from_own && to_own && is_user_visible_self_output(output);
        let visible_sent = from_own && (!to_own || visible_self_output);
        let visible_received = to_own && (!from_own || visible_self_output);

        if visible_sent {
            summary.sent.add_output(output);
            if output.output_pool == 0 && !to_own {
                summary.has_external_transparent_send = true;
            }
        }
        if visible_received {
            summary.received.add_output(output);
        }
    }

    summary
}

fn detail_includes_output(
    base: &TxBase,
    output: &TxOutput,
    account_uuid: &[u8],
    tx_kind: &str,
) -> bool {
    let from_own = output.from_account_uuid.as_deref() == Some(account_uuid);
    let to_own = output.to_account_uuid.as_deref() == Some(account_uuid);

    match tx_kind {
        "shielded" => base.is_shielding && to_own && is_shielded_pool(output.output_pool),
        "sent" => {
            !base.is_shielding && from_own && (!to_own || is_user_visible_self_output(output))
        }
        "received" | "receiving" => {
            !base.is_shielding && to_own && (!from_own || is_user_visible_self_output(output))
        }
        _ => false,
    }
}

fn is_shielded_pool(output_pool: i64) -> bool {
    matches!(output_pool, 2 | 3)
}

fn output_pool_label(output_pool: i64) -> &'static str {
    match output_pool {
        0 => "transparent",
        2 | 3 => "shielded",
        _ => "unknown",
    }
}

fn is_user_visible_self_output(output: &TxOutput) -> bool {
    let has_external_or_foreign_scope = matches!(output.to_key_scope, Some(0) | Some(-1));

    match output.output_pool {
        // Transparent self outputs are user-visible only when they land on a
        // normal external/foreign receiver. Internal and ephemeral receivers
        // are change/funding mechanics.
        0 => has_external_or_foreign_scope,
        // `is_change` is best-effort for wallet-owned outputs and can also be
        // set on explicit self-transfers. Treat external/foreign receivers and
        // sent-note recipients as visible; keep internal change hidden.
        2 | 3 => has_external_or_foreign_scope || output.sent_to_address.is_some(),
        _ => false,
    }
}

fn decode_text_memo(memo: Option<&[u8]>) -> Option<String> {
    let memo = memo?;
    let memo_bytes = MemoBytes::from_bytes(memo).ok()?;
    match Memo::try_from(&memo_bytes).ok()? {
        Memo::Text(text) => {
            let text = String::from(text);
            if text.trim().is_empty() {
                None
            } else {
                Some(text)
            }
        }
        Memo::Empty | Memo::Future(_) | Memo::Arbitrary(_) => None,
    }
}

fn build_external_send_keys(
    bases: &[TxBase],
    summaries: &HashMap<Vec<u8>, ActivitySummary>,
) -> HashSet<(String, i64)> {
    bases
        .iter()
        .filter_map(|base| {
            let summary = summaries.get(&base.txid)?;
            if summary.has_external_transparent_send {
                base.created
                    .as_ref()
                    .map(|created| (created.clone(), base.expiry_key()))
            } else {
                None
            }
        })
        .collect()
}

fn build_suppressed_funding_step_fees(
    bases: &[TxBase],
    summaries: &HashMap<Vec<u8>, ActivitySummary>,
    external_send_keys: &HashSet<(String, i64)>,
) -> HashMap<(String, i64), u64> {
    let mut fees = HashMap::new();

    for base in bases {
        let summary = summaries.get(&base.txid).cloned().unwrap_or_default();
        if !should_suppress_funding_step(base, &summary, external_send_keys) {
            continue;
        }
        if let Some(key) = funding_step_key(base) {
            let entry = fees.entry(key).or_insert(0_u64);
            *entry = entry.saturating_add(base.fee);
        }
    }

    fees
}

fn funding_step_key(base: &TxBase) -> Option<(String, i64)> {
    base.created
        .as_ref()
        .map(|created| (created.clone(), base.expiry_key()))
}

fn should_suppress_funding_step(
    base: &TxBase,
    summary: &ActivitySummary,
    external_send_keys: &HashSet<(String, i64)>,
) -> bool {
    !base.is_shielding
        && base.total_spent > 0
        && base.total_received > 0
        && base.account_balance_delta <= 0
        && base.created.is_some()
        && summary.sent.amount == 0
        && summary.received.amount == 0
        && summary.has_own_transparent_output
        && external_send_keys
            .contains(&(base.created.clone().unwrap_or_default(), base.expiry_key()))
}

fn classify_history_tx(
    base: &TxBase,
    summary: &ActivitySummary,
    extra_sent_fee: u64,
) -> Vec<ClassifiedTx> {
    if base.is_shielding {
        let amount = if summary.shielded.amount > 0 {
            summary.shielded.amount
        } else {
            base.total_received
        };
        return vec![build_classified_tx(
            base, "shielded", amount, "shielded", false, 0,
        )];
    }

    let mut rows = Vec::new();
    if summary.sent.amount > 0 {
        rows.push(build_classified_tx_with_fee(
            base,
            "sent",
            summary.sent.amount,
            summary.sent.display_pool(),
            summary.sent.has_transparent,
            1,
            base.fee.saturating_add(extra_sent_fee),
        ));
    }
    if summary.received.amount > 0 {
        rows.push(build_classified_tx(
            base,
            receiving_tx_kind(base),
            summary.received.amount,
            summary.received.display_pool(),
            summary.received.has_transparent,
            2,
        ));
    }

    if rows.is_empty() {
        if base.mined_height.is_none() && base.account_balance_delta < 0 && base.total_spent > 0 {
            let sent_amount = base
                .account_balance_delta
                .unsigned_abs()
                .saturating_sub(base.fee);
            if sent_amount > 0 {
                rows.push(build_classified_tx(
                    base,
                    "sent",
                    sent_amount,
                    "unknown",
                    false,
                    1,
                ));
                return rows;
            }
        }
        if base.total_spent > 0 && base.total_received > 0 {
            return rows;
        }
        if base.account_balance_delta > 0 {
            rows.push(build_classified_tx(
                base,
                receiving_tx_kind(base),
                base.account_balance_delta as u64,
                "unknown",
                false,
                2,
            ));
        } else {
            rows.push(build_classified_tx(base, "unknown", 0, "unknown", false, 3));
        }
    }

    rows
}

fn receiving_tx_kind(base: &TxBase) -> &'static str {
    if base.mined_height.is_none() && !base.expired_unmined {
        "receiving"
    } else {
        "received"
    }
}

fn build_classified_tx(
    base: &TxBase,
    tx_kind: &str,
    display_amount: u64,
    display_pool: &str,
    is_transparent: bool,
    row_order: u8,
) -> ClassifiedTx {
    build_classified_tx_with_fee(
        base,
        tx_kind,
        display_amount,
        display_pool,
        is_transparent,
        row_order,
        base.fee,
    )
}

fn build_classified_tx_with_fee(
    base: &TxBase,
    tx_kind: &str,
    display_amount: u64,
    display_pool: &str,
    is_transparent: bool,
    row_order: u8,
    fee: u64,
) -> ClassifiedTx {
    let sort_timestamp = base.display_timestamp();
    ClassifiedTx {
        info: TransactionInfo {
            txid_hex: hex::encode(&base.txid),
            mined_height: base.mined_height.unwrap_or(0) as u64,
            expired_unmined: base.expired_unmined,
            account_balance_delta: base.account_balance_delta,
            fee,
            block_time: base.block_time,
            is_transparent,
            tx_kind: tx_kind.to_string(),
            display_amount,
            display_pool: display_pool.to_string(),
            created_time: base.created_time,
        },
        sort_pending_rank: u8::from(base.mined_height.is_none() && !base.expired_unmined),
        sort_timestamp,
        sort_mined_height: base.mined_height.unwrap_or(0) as u64,
        tx_index: base.tx_index,
        row_order,
    }
}

impl TxBase {
    fn expiry_key(&self) -> i64 {
        self.expiry_height.unwrap_or(-1)
    }

    fn display_timestamp(&self) -> u64 {
        if self.block_time > 0 {
            self.block_time
        } else {
            self.created_time
        }
    }
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
    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(pair) => pair,
        Err(e) => {
            log::warn!("txtrack: {e}");
            return -1;
        }
    };

    match crate::wallet::sync_engine::get_transaction(&mut client, txid_bytes.to_vec()).await {
        Ok(raw) => {
            let height = raw.height;
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

    fn test_account_uuid() -> uuid::Uuid {
        uuid::Uuid::from_u128(0x7e2b16db08384ddba8026fd48b9e0d02)
    }

    fn second_test_account_uuid() -> uuid::Uuid {
        uuid::Uuid::from_u128(0x3eb4ded306b74bf2a5393f1b78d792a6)
    }

    fn fresh_history_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 uuid BLOB NOT NULL UNIQUE,
                 birthday_height INTEGER NOT NULL DEFAULT 0
             );
             CREATE TABLE addresses (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 account_id INTEGER NOT NULL,
                 key_scope INTEGER NOT NULL,
                 address TEXT NOT NULL,
                 cached_transparent_receiver_address TEXT
             );
             CREATE TABLE v_transactions (
                 account_uuid BLOB NOT NULL,
                 txid BLOB NOT NULL,
                 mined_height INTEGER,
                 expired_unmined INTEGER NOT NULL,
                 account_balance_delta INTEGER NOT NULL,
                 fee_paid INTEGER,
                 block_time INTEGER,
                 total_spent INTEGER,
                 total_received INTEGER,
                 is_shielding INTEGER,
                 expiry_height INTEGER,
                 tx_index INTEGER
             );
             CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY AUTOINCREMENT,
                 txid BLOB NOT NULL UNIQUE,
                 created TEXT
             );
             CREATE TABLE sent_notes (
                 transaction_id INTEGER NOT NULL,
                 output_pool INTEGER NOT NULL,
                 output_index INTEGER NOT NULL,
                 from_account_id INTEGER NOT NULL,
                 to_account_id INTEGER,
                 to_address TEXT,
                 value INTEGER NOT NULL,
                 memo BLOB
             );
             CREATE TABLE v_tx_outputs (
                 txid BLOB NOT NULL,
                 output_pool INTEGER NOT NULL,
                 output_index INTEGER NOT NULL,
                 from_account_uuid BLOB,
                 to_account_uuid BLOB,
                 to_address TEXT,
                 value INTEGER NOT NULL,
                 is_change INTEGER NOT NULL,
                 memo BLOB
             );",
        )
        .unwrap();
        file
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_history_tx(
        db: &NamedTempFile,
        account: uuid::Uuid,
        txid: &[u8],
        mined_height: Option<i64>,
        tx_index: i64,
        expiry_height: Option<i64>,
        account_balance_delta: i64,
        total_spent: i64,
        total_received: i64,
        is_shielding: bool,
        created: Option<&str>,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        ensure_account_row(&conn, account);
        conn.execute(
            "INSERT INTO transactions (txid, created) VALUES (?1, ?2)",
            rusqlite::params![txid, created],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO v_transactions (
                 account_uuid, txid, mined_height, expired_unmined,
                 account_balance_delta, fee_paid, block_time, total_spent,
                 total_received, is_shielding, expiry_height, tx_index
             ) VALUES (?1, ?2, ?3, 0, ?4, 0, 0, ?5, ?6, ?7, ?8, ?9)",
            rusqlite::params![
                account.as_bytes().as_slice(),
                txid,
                mined_height,
                account_balance_delta,
                total_spent,
                total_received,
                is_shielding,
                expiry_height,
                tx_index,
            ],
        )
        .unwrap();
    }

    fn ensure_account_row(conn: &rusqlite::Connection, account: uuid::Uuid) -> i64 {
        conn.execute(
            "INSERT OR IGNORE INTO accounts (uuid) VALUES (?1)",
            rusqlite::params![account.as_bytes().as_slice()],
        )
        .unwrap();
        conn.query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            rusqlite::params![account.as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn insert_output(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
    ) -> i64 {
        insert_output_with_address(
            db,
            txid,
            output_pool,
            from_account,
            to_account,
            value,
            is_change,
            None,
            None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_output_with_address(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
        to_address: Option<&str>,
        to_key_scope: Option<i64>,
    ) -> i64 {
        insert_output_with_address_and_memo(
            db,
            txid,
            output_pool,
            from_account,
            to_account,
            value,
            is_change,
            to_address,
            to_key_scope,
            None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_output_with_address_and_memo(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
        to_address: Option<&str>,
        to_key_scope: Option<i64>,
        memo: Option<&[u8]>,
    ) -> i64 {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        if let Some(account) = from_account {
            ensure_account_row(&conn, account);
        }
        if let Some(account) = to_account {
            let account_id = ensure_account_row(&conn, account);
            if let (Some(address), Some(key_scope)) = (to_address, to_key_scope) {
                conn.execute(
                    "INSERT INTO addresses (
                         account_id, key_scope, address, cached_transparent_receiver_address
                     ) VALUES (?1, ?2, ?3, ?3)",
                    rusqlite::params![account_id, key_scope, address],
                )
                .unwrap();
            }
        }
        let output_index = conn
            .query_row(
                "SELECT COALESCE(MAX(output_index) + 1, 0)
                 FROM v_tx_outputs
                 WHERE txid = ?1 AND output_pool = ?2",
                rusqlite::params![txid, output_pool],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        let from_bytes = from_account.map(|uuid| uuid.as_bytes().to_vec());
        let to_bytes = to_account.map(|uuid| uuid.as_bytes().to_vec());
        conn.execute(
            "INSERT INTO v_tx_outputs (
                 txid, output_pool, output_index, from_account_uuid,
                 to_account_uuid, to_address, value, is_change, memo
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            rusqlite::params![
                txid,
                output_pool,
                output_index,
                from_bytes,
                to_bytes,
                to_address,
                value,
                is_change,
                memo,
            ],
        )
        .unwrap();
        output_index
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_sent_note(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        output_index: i64,
        from_account: uuid::Uuid,
        to_account: Option<uuid::Uuid>,
        to_address: Option<&str>,
        value: i64,
        memo: Option<&[u8]>,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let transaction_id = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        let from_account_id = ensure_account_row(&conn, from_account);
        let to_account_id = to_account.map(|account| ensure_account_row(&conn, account));
        conn.execute(
            "INSERT INTO sent_notes (
                 transaction_id, output_pool, output_index, from_account_id,
                 to_account_id, to_address, value, memo
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                transaction_id,
                output_pool,
                output_index,
                from_account_id,
                to_account_id,
                to_address,
                value,
                memo,
            ],
        )
        .unwrap();
    }

    fn set_cached_transparent_receiver_address(
        db: &NamedTempFile,
        account: uuid::Uuid,
        address: &str,
        transparent_address: &str,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let account_id = ensure_account_row(&conn, account);
        let changed = conn
            .execute(
                "UPDATE addresses
                 SET cached_transparent_receiver_address = ?3
                 WHERE account_id = ?1 AND address = ?2",
                rusqlite::params![account_id, address, transparent_address],
            )
            .unwrap();
        assert_eq!(changed, 1);
    }

    fn mark_expired_unmined(db: &NamedTempFile, txid: &[u8]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET expired_unmined = 1 WHERE txid = ?1",
            rusqlite::params![txid],
        )
        .unwrap();
    }

    fn clear_tx_index(db: &NamedTempFile, txid: &[u8]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET tx_index = NULL WHERE txid = ?1",
            rusqlite::params![txid],
        )
        .unwrap();
    }

    fn set_history_fee(db: &NamedTempFile, txid: &[u8], fee_paid: i64) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET fee_paid = ?2 WHERE txid = ?1",
            rusqlite::params![txid, fee_paid],
        )
        .unwrap();
    }

    fn set_account_birthday(db: &NamedTempFile, account: uuid::Uuid, birthday_height: i64) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        ensure_account_row(&conn, account);
        conn.execute(
            "UPDATE accounts SET birthday_height = ?2 WHERE uuid = ?1",
            rusqlite::params![account.as_bytes().as_slice(), birthday_height],
        )
        .unwrap();
    }

    #[test]
    fn export_birthday_anchor_uses_oldest_mined_tx_for_account() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let newer = fake_txid(0x71);
        let older_late_index = fake_txid(0x72);
        let older_early_index = fake_txid(0x73);
        let other_older = fake_txid(0x74);
        let pending = fake_txid(0x75);

        insert_history_tx(
            &db,
            account,
            &newer,
            Some(300),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &older_late_index,
            Some(200),
            5,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &older_early_index,
            Some(200),
            1,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            other_account,
            &other_older,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_oldest_mined_transaction_anchor(db.path().to_str().unwrap(), &account.to_string())
                .unwrap()
                .unwrap();

        assert_eq!(got.block_height, 200);
    }

    #[test]
    fn export_birthday_anchor_returns_none_without_mined_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let pending = fake_txid(0x81);
        let other_mined = fake_txid(0x82);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );
        insert_history_tx(
            &db,
            other_account,
            &other_mined,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_oldest_mined_transaction_anchor(db.path().to_str().unwrap(), &account.to_string())
                .unwrap();

        assert!(got.is_none());
    }

    #[test]
    fn export_birthday_anchor_falls_back_to_account_birthday_without_mined_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let pending = fake_txid(0x91);
        let other_mined = fake_txid(0x92);

        set_account_birthday(&db, account, 333_100);
        set_account_birthday(&db, other_account, 111_100);
        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );
        insert_history_tx(
            &db,
            other_account,
            &other_mined,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_export_birthday_anchor(db.path().to_str().unwrap(), &account.to_string()).unwrap();

        assert_eq!(got.block_height, 333_100);
    }

    #[test]
    fn history_suppresses_funding_step_after_limit_filtering() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let external_send = fake_txid(0xA1);
        let funding_step = fake_txid(0xA2);
        let created = "2026-04-28T13:03:00Z";

        insert_history_tx(
            &db,
            account,
            &funding_step,
            None,
            2,
            Some(1_000_100),
            -40_000,
            18_302_101,
            18_262_101,
            false,
            Some(created),
        );
        set_history_fee(&db, &funding_step, 40_000);
        insert_output_with_address(
            &db,
            &funding_step,
            0,
            Some(account),
            Some(account),
            10_010_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );

        insert_history_tx(
            &db,
            account,
            &external_send,
            None,
            1,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some(created),
        );
        set_history_fee(&db, &external_send, 10_000);
        insert_output(
            &db,
            &external_send,
            0,
            Some(account),
            None,
            10_000_000,
            false,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(external_send));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].fee, 50_000);
    }

    #[test]
    fn history_splits_same_account_transparent_self_send() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xB1);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -40_000,
            18_302_101,
            18_262_101,
            false,
            Some("2026-04-28T13:03:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            0,
            Some(account),
            Some(account),
            18_262_101,
            false,
            Some("t-self"),
            Some(0),
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 18_262_101);
        assert_eq!(got[0].display_pool, "transparent");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 18_262_101);
        assert_eq!(got[1].display_pool, "transparent");
    }

    #[test]
    fn history_treats_send_to_other_local_account_as_sent() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let txid = fake_txid(0xB2);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -5_000_000,
            5_000_000,
            0,
            false,
            Some("2026-04-28T14:03:00Z"),
        );
        insert_output(
            &db,
            &txid,
            0,
            Some(account),
            Some(other_account),
            5_000_000,
            false,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 5_000_000);
    }

    #[test]
    fn history_treats_receive_from_other_local_account_as_received() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let txid = fake_txid(0xB3);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            5_000_000,
            0,
            5_000_000,
            false,
            Some("2026-04-28T14:04:00Z"),
        );
        insert_output(
            &db,
            &txid,
            0,
            Some(other_account),
            Some(account),
            5_000_000,
            false,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "received");
        assert_eq!(got[0].display_amount, 5_000_000);
    }

    #[test]
    fn history_splits_same_account_shielded_self_send_and_hides_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC0);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            17_252_101,
            17_237_101,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            16_237_101,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_000_000);
        assert_eq!(got[0].display_pool, "shielded");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_000_000);
        assert_eq!(got[1].display_pool, "shielded");
    }

    #[test]
    fn history_uses_sent_note_when_self_send_key_scope_is_unresolved() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC7);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_015_000,
            1_000_000,
            false,
            Some("2026-04-28T16:36:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self-unresolved"),
            None,
        );
        insert_sent_note(
            &db,
            &self_tx,
            3,
            output_index,
            account,
            Some(account),
            Some("u-self-unresolved"),
            1_000_000,
            None,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_000_000);
        assert_eq!(got[0].display_pool, "shielded");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_000_000);
        assert_eq!(got[1].display_pool, "shielded");
    }

    #[test]
    fn history_preserves_mixed_pool_for_visible_self_outputs() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC6);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            6_115_000,
            6_100_000,
            false,
            Some("2026-04-28T16:40:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            0,
            Some(account),
            Some(account),
            100_000,
            true,
            Some("t-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            5_000_000,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_100_000);
        assert_eq!(got[0].display_pool, "mixed");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_100_000);
        assert_eq!(got[1].display_pool, "mixed");
    }

    #[test]
    fn history_hides_change_only_internal_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let change_only_tx = fake_txid(0xC3);

        insert_history_tx(
            &db,
            account,
            &change_only_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            17_252_102,
            17_242_102,
            false,
            Some("2026-04-28T15:43:00Z"),
        );
        insert_output_with_address(
            &db,
            &change_only_tx,
            3,
            Some(account),
            Some(account),
            7_242_102,
            true,
            Some("u-change-1"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &change_only_tx,
            3,
            Some(account),
            Some(account),
            10_000_000,
            true,
            Some("u-change-2"),
            Some(1),
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert!(got.is_empty());
    }

    #[test]
    fn history_keeps_shielding_tx_as_single_shielded_row() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let shielding_tx = fake_txid(0xC4);

        insert_history_tx(
            &db,
            account,
            &shielding_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            10_010_000,
            10_000_000,
            true,
            Some("2026-04-28T15:44:00Z"),
        );
        insert_output(
            &db,
            &shielding_tx,
            3,
            Some(account),
            Some(account),
            10_000_000,
            true,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(shielding_tx));
        assert_eq!(got[0].tx_kind, "shielded");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].display_pool, "shielded");
    }

    #[test]
    fn history_sent_to_transparent_excludes_shielded_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xC5);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_265_000,
            1_150_000,
            false,
            Some("2026-04-28T16:45:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            150_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            None,
            100_000,
            false,
            Some("t-recipient"),
            None,
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 100_000);
        assert_eq!(got[0].display_pool, "transparent");
    }

    #[test]
    fn detail_sent_row_returns_recipient_address_and_memo() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD1);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -1_010_000,
            1_010_000,
            0,
            false,
            Some("2026-04-28T17:00:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            None,
            1_000_000,
            false,
            Some("u-recipient"),
            None,
            Some(b"hello from activity"),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.txid_hex, hex::encode(txid));
        assert_eq!(got.tx_kind, "sent");
        assert_eq!(got.primary_address.as_deref(), Some("u-recipient"));
        assert_eq!(got.memo.as_deref(), Some("hello from activity"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("u-recipient"));
        assert_eq!(got.outputs[0].amount_zatoshi, 1_000_000);
        assert_eq!(got.outputs[0].pool, "shielded");
    }

    #[test]
    fn detail_sent_to_transparent_prefers_external_recipient_over_shielded_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD7);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_265_000,
            1_150_000,
            false,
            Some("2026-04-28T17:05:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            150_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            None,
            100_000,
            false,
            Some("t-recipient"),
            None,
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs[0].amount_zatoshi, 100_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_sent_to_own_transparent_receiver_uses_sent_note_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD8);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            1,
            Some(1_000_100),
            -15_000,
            6_980_000,
            6_965_000,
            false,
            Some("2026-05-15T06:11:44Z"),
        );
        let recipient_output_index = insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            1_200_000,
            false,
            Some("u-merged-own-transparent-receiver"),
            Some(0),
        );
        set_cached_transparent_receiver_address(
            &db,
            account,
            "u-merged-own-transparent-receiver",
            "t-recipient",
        );
        insert_sent_note(
            &db,
            &txid,
            0,
            recipient_output_index,
            account,
            None,
            Some("t-recipient"),
            1_200_000,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            5_765_000,
            true,
            None,
            None,
            Some(&[0xF6]),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs[0].amount_zatoshi, 1_200_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_sent_to_transparent_pool_prefers_cached_transparent_receiver() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD9);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            18_990_000,
            18_975_000,
            false,
            Some("2026-05-14T13:14:15Z"),
        );
        let recipient_output_index = insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            11_000_000,
            false,
            Some("u-known-receiver"),
            Some(0),
        );
        set_cached_transparent_receiver_address(
            &db,
            account,
            "u-known-receiver",
            "t-known-receiver",
        );
        insert_sent_note(
            &db,
            &txid,
            0,
            recipient_output_index,
            account,
            None,
            Some("u-known-receiver"),
            11_000_000,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            7_975_000,
            true,
            None,
            None,
            Some(&[0xF6]),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-known-receiver"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-known-receiver"));
        assert_eq!(got.outputs[0].amount_zatoshi, 11_000_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_received_row_does_not_invent_from_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD2);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            Some("2026-04-28T17:01:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-receiver"),
            Some(0),
            Some(b"incoming memo"),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "received");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.memo.as_deref(), Some("incoming memo"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("u-my-receiver"));
    }

    #[test]
    fn detail_receiving_row_uses_received_outputs() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD6);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-pending-receiver"),
            Some(0),
            Some(b"pending incoming memo"),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "receiving",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "receiving");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.memo.as_deref(), Some("pending incoming memo"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(
            got.outputs[0].address.as_deref(),
            Some("u-my-pending-receiver")
        );
    }

    #[test]
    fn detail_separates_same_account_self_send_by_kind() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD3);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            false,
            Some("2026-04-28T17:02:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
            Some(b"self memo"),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            500_000,
            true,
            Some("u-change"),
            Some(1),
        );

        let sent = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();
        let received = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        assert_eq!(sent.primary_address.as_deref(), Some("u-self"));
        assert_eq!(sent.memo.as_deref(), Some("self memo"));
        assert_eq!(sent.outputs.len(), 1);
        assert_eq!(sent.outputs[0].amount_zatoshi, 1_000_000);
        assert_eq!(received.primary_address, None);
        assert_eq!(received.memo.as_deref(), Some("self memo"));
        assert_eq!(received.outputs.len(), 1);
        assert_eq!(received.outputs[0].amount_zatoshi, 1_000_000);
    }

    #[test]
    fn detail_hides_change_only_outputs_and_empty_memos() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD4);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            false,
            Some("2026-04-28T17:03:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
            Some(&[0xF6]),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address, None);
        assert_eq!(got.memo, None);
        assert!(got.outputs.is_empty());
    }

    #[test]
    fn detail_shielding_row_has_no_primary_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD5);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            true,
            Some("2026-04-28T17:04:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-shielded-self"),
            Some(0),
        );

        let got = get_transaction_detail(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "shielded",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "shielded");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].amount_zatoshi, 1_000_000);
    }

    #[test]
    fn history_sorts_by_display_timestamp_before_limit() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let older_failed = fake_txid(0xC1);
        let newer_self_send = fake_txid(0xC2);

        insert_history_tx(
            &db,
            account,
            &older_failed,
            None,
            2,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        mark_expired_unmined(&db, &older_failed);
        insert_output(
            &db,
            &older_failed,
            0,
            Some(account),
            None,
            10_000_000,
            false,
        );

        insert_history_tx(
            &db,
            account,
            &newer_self_send,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -40_000,
            17_040_000,
            17_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output_with_address(
            &db,
            &newer_self_send,
            0,
            Some(account),
            Some(account),
            17_000_000,
            false,
            Some("t-newer-self"),
            Some(0),
        );

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 3);
        assert_eq!(got[0].txid_hex, hex::encode(newer_self_send));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[1].txid_hex, hex::encode(newer_self_send));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[2].txid_hex, hex::encode(older_failed));
        assert!(got[2].expired_unmined);

        let limited = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(limited.len(), 1);
        assert_eq!(limited[0].txid_hex, hex::encode(newer_self_send));
        assert_eq!(limited[0].tx_kind, "sent");
    }

    #[test]
    fn history_prioritizes_unmined_receiving_rows() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let confirmed = fake_txid(0xE1);
        let pending = fake_txid(0xE2);

        insert_history_tx(
            &db,
            account,
            &confirmed,
            Some(1_000_000),
            1,
            Some(1_000_100),
            1_000_000,
            0,
            1_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output(&db, &confirmed, 3, None, Some(account), 1_000_000, false);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            None,
        );
        insert_output(&db, &pending, 3, None, Some(account), 2_000_000, false);

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(pending));
        assert_eq!(got[0].tx_kind, "receiving");
        assert_eq!(got[0].mined_height, 0);
        assert_eq!(got[0].display_amount, 2_000_000);
    }

    #[test]
    fn history_prioritizes_active_unmined_sent_rows() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let confirmed = fake_txid(0xE3);
        let pending = fake_txid(0xE4);

        insert_history_tx(
            &db,
            account,
            &confirmed,
            Some(1_000_000),
            1,
            Some(1_000_100),
            1_000_000,
            0,
            1_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output(&db, &confirmed, 3, None, Some(account), 1_000_000, false);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(1_000_100),
            -1_010_000,
            1_010_000,
            0,
            false,
            None,
        );
        insert_output(&db, &pending, 3, Some(account), None, 1_000_000, false);

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(pending));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].mined_height, 0);
        assert_eq!(got[0].display_amount, 1_000_000);
    }

    #[test]
    fn history_accepts_unmined_tx_with_null_tx_index() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD1);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            0,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        clear_tx_index(&db, &txid);
        insert_output(&db, &txid, 0, Some(account), None, 10_000_000, false);

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
    }

    #[test]
    fn history_shows_unmined_sent_when_output_metadata_missing() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD2);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            0,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            9_000_000,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        set_history_fee(&db, &txid, 10_000);
        insert_output(&db, &txid, 3, Some(account), Some(account), 9_000_000, true);

        let got = get_transaction_history(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].mined_height, 0);
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
