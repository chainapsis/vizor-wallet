use rand::rngs::OsRng;
use zcash_client_backend::{
    data_api::{
        WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::ConfirmationsPolicy,
    },
    fees::StandardFeeRule,
    proto::service::TreeState,
};
use zcash_client_sqlite::{
    AccountUuid, FsBlockDb,
    WalletDb,
    chain::{BlockMeta, init::init_blockmeta_db},
    util::SystemClock,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, Network};

use crate::wallet::keys::parse_account_uuid;

mod pczt;
mod send;

pub(crate) use pczt::{
    add_proofs_to_pczt, create_pczt_from_proposal, discard_proposal, extract_and_broadcast_pczt,
    redact_pczt_for_signer,
};
pub(crate) use send::{estimate_fee, execute_proposal, propose_send};

pub(super) type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

pub(super) fn open_wallet_db(db_path: &str, network: Network) -> Result<WalletDatabase, String> {
    WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))
}

fn open_block_cache(cache_path: &str) -> Result<FsBlockDb, String> {
    std::fs::create_dir_all(cache_path)
        .map_err(|e| format!("Failed to create cache dir: {e}"))?;
    let mut db_cache = FsBlockDb::for_path(cache_path)
        .map_err(|e| format!("Failed to open block cache: {e:?}"))?;
    init_blockmeta_db(&mut db_cache)
        .map_err(|e| format!("Failed to init block cache: {e}"))?;
    Ok(db_cache)
}

fn get_first_account_id(db: &WalletDatabase) -> Result<zcash_client_sqlite::AccountUuid, String> {
    let accounts = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;
    accounts
        .into_iter()
        .next()
        .ok_or_else(|| "No accounts found in wallet".to_string())
}

// ======================== Sync ========================

pub fn update_chain_tip(db_path: &str, network: Network, height: u64) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    db.update_chain_tip(BlockHeight::from_u32(height as u32))
        .map_err(|e| format!("Failed to update chain tip: {e}"))
}

/// Get next subtree indices to know where to start downloading from.
pub fn get_next_subtree_indices(db_path: &str, network: Network) -> Result<(u64, u64), String> {
    let db = open_wallet_db(db_path, network)?;
    let summary = db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))?;
    match summary {
        Some(s) => Ok((s.next_sapling_subtree_index(), s.next_orchard_subtree_index())),
        None => Ok((0, 0)),
    }
}

pub fn put_sapling_subtree_roots(
    db_path: &str, network: Network, start_index: u64, roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<_> = roots.iter().map(|(h, bytes)| {
        let arr: [u8; 32] = bytes[..32].try_into().map_err(|_| "bad hash len")?;
        let node = Option::from(sapling_crypto::Node::from_bytes(arr)).ok_or("bad sapling hash")?;
        Ok::<_, String>(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(*h as u32), node))
    }).collect::<Result<Vec<_>, _>>()?;
    if !parsed.is_empty() {
        db.put_sapling_subtree_roots(start_index, parsed.as_slice())
            .map_err(|e| format!("{e}"))?;
    }
    Ok(())
}

pub fn put_orchard_subtree_roots(
    db_path: &str, network: Network, start_index: u64, roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<_> = roots.iter().map(|(h, bytes)| {
        let arr: [u8; 32] = bytes[..32].try_into().map_err(|_| "bad hash len")?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&arr)).ok_or("bad orchard hash")?;
        Ok::<_, String>(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(*h as u32), node))
    }).collect::<Result<Vec<_>, _>>()?;
    if !parsed.is_empty() {
        db.put_orchard_subtree_roots(start_index, parsed.as_slice())
            .map_err(|e| format!("{e}"))?;
    }
    Ok(())
}

pub(crate) struct ScanRangeInfo { pub start: u64, pub end: u64, pub priority: u8 }

pub fn suggest_scan_ranges(db_path: &str, network: Network) -> Result<Vec<ScanRangeInfo>, String> {
    let db = open_wallet_db(db_path, network)?;
    let ranges = db.suggest_scan_ranges().map_err(|e| format!("{e}"))?;
    Ok(ranges.into_iter()
        .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
        .map(|r| ScanRangeInfo {
            start: u32::from(r.block_range().start) as u64,
            end: u32::from(r.block_range().end) as u64,
            priority: match r.priority() {
                ScanPriority::Verify => 6, ScanPriority::ChainTip => 5,
                ScanPriority::FoundNote => 4, ScanPriority::OpenAdjacent => 3,
                ScanPriority::Historic => 2, ScanPriority::Scanned => 1,
                ScanPriority::Ignored => 0,
            },
        }).collect())
}

pub fn write_block_metadata(cache_path: &str, blocks: &[(u64, Vec<u8>, u32, u32, u32)]) -> Result<(), String> {
    let db_cache = open_block_cache(cache_path)?;
    let metas: Vec<BlockMeta> = blocks.iter().map(|(h, hash, time, sc, oc)| {
        let mut arr = [0u8; 32];
        arr[..hash.len().min(32)].copy_from_slice(&hash[..hash.len().min(32)]);
        BlockMeta { height: BlockHeight::from_u32(*h as u32), block_hash: BlockHash(arr), block_time: *time, sapling_outputs_count: *sc, orchard_actions_count: *oc }
    }).collect();
    db_cache.write_block_metadata(&metas).map_err(|e| format!("{e:?}"))
}

pub fn scan_blocks(
    db_path: &str, cache_path: &str, network: Network, from_height: u64,
    ts_network: &str, ts_height: u64, ts_hash: &str, ts_time: u32, ts_sapling: &str, ts_orchard: &str,
    limit: u64,
) -> Result<u64, String> {
    let db_cache = open_block_cache(cache_path)?;
    let mut db_data = open_wallet_db(db_path, network)?;
    let from_state = if ts_hash.is_empty() {
        zcash_client_backend::data_api::chain::ChainState::empty(
            BlockHeight::from_u32((from_height - 1) as u32), BlockHash([0u8; 32]),
        )
    } else {
        TreeState { network: ts_network.into(), height: ts_height, hash: ts_hash.into(), time: ts_time, sapling_tree: ts_sapling.into(), orchard_tree: ts_orchard.into() }
            .to_chain_state().map_err(|e| format!("{e}"))?
    };
    let result = scan_cached_blocks(&network, &db_cache, &mut db_data, BlockHeight::from_u32(from_height as u32), &from_state, limit as usize)
        .map_err(|e| format!("{e}"))?;
    Ok((u32::from(result.scanned_range().end) - u32::from(result.scanned_range().start)) as u64)
}

// ======================== Balance & Progress ========================

pub(crate) struct SyncProgress { pub scanned_height: u64, pub chain_tip_height: u64, pub is_syncing: bool }

pub fn get_sync_progress(db_path: &str, network: Network) -> Result<SyncProgress, String> {
    let db = open_wallet_db(db_path, network)?;
    match db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))? {
        Some(s) => Ok(SyncProgress {
            scanned_height: u32::from(s.fully_scanned_height()) as u64,
            chain_tip_height: u32::from(s.chain_tip_height()) as u64,
            is_syncing: s.fully_scanned_height() < s.chain_tip_height(),
        }),
        None => Ok(SyncProgress { scanned_height: 0, chain_tip_height: 0, is_syncing: false }),
    }
}

pub(crate) struct WalletBalance {
    pub transparent: u64, pub sapling: u64, pub orchard: u64,
    pub transparent_pending: u64, pub sapling_pending: u64, pub orchard_pending: u64,
}

pub fn get_wallet_balance(db_path: &str, network: Network, account_uuid: &str) -> Result<WalletBalance, String> {
    let db = open_wallet_db(db_path, network)?;
    let target_id = parse_account_uuid(account_uuid)?;
    match db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))? {
        Some(s) => {
            match s.account_balances().get(&target_id) {
                Some(b) => Ok(WalletBalance {
                    transparent: u64::from(b.unshielded_balance().spendable_value()),
                    sapling: u64::from(b.sapling_balance().spendable_value()),
                    orchard: u64::from(b.orchard_balance().spendable_value()),
                    transparent_pending: u64::from(b.unshielded_balance().change_pending_confirmation()) + u64::from(b.unshielded_balance().value_pending_spendability()),
                    sapling_pending: u64::from(b.sapling_balance().change_pending_confirmation()) + u64::from(b.sapling_balance().value_pending_spendability()),
                    orchard_pending: u64::from(b.orchard_balance().change_pending_confirmation()) + u64::from(b.orchard_balance().value_pending_spendability()),
                }),
                None => Ok(WalletBalance { transparent: 0, sapling: 0, orchard: 0, transparent_pending: 0, sapling_pending: 0, orchard_pending: 0 }),
            }
        }
        None => Ok(WalletBalance { transparent: 0, sapling: 0, orchard: 0, transparent_pending: 0, sapling_pending: 0, orchard_pending: 0 }),
    }
}

// ======================== Rewind ========================

pub fn rewind_to_height(db_path: &str, network: Network, height: u64) -> Result<u64, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let result = db.truncate_to_height(BlockHeight::from_u32(height as u32)).map_err(|e| format!("{e}"))?;
    Ok(u32::from(result) as u64)
}

// ======================== Address Validation ========================

pub fn validate_address(address: &str) -> Result<String, String> {
    use zcash_address::ZcashAddress;
    let addr = ZcashAddress::try_from_encoded(address).map_err(|e| format!("Invalid: {e}"))?;
    let debug = format!("{:?}", addr);
    if debug.contains("Unified") { Ok("unified".into()) }
    else if debug.contains("Sapling") { Ok("sapling".into()) }
    else if debug.contains("P2pkh") || debug.contains("P2sh") { Ok("transparent".into()) }
    else { Ok("unknown".into()) }
}

// ======================== Send ========================

/// Propose a transfer. Returns (proposal_id, needs_sapling_params, fee_zatoshi).
/// The proposal is stored internally and referenced by proposal_id for execute_proposal.
// In-memory proposal store (proposals are short-lived, between
// propose and execute). Kept in `sync/mod.rs` because it is shared
// between the software send flow (`send::execute_proposal`) and the
// hardware PCZT pipeline (`pczt::create_pczt_from_proposal`); placing
// it in either submodule would create a cross-submodule dependency.
use std::collections::HashMap;
use std::sync::Mutex;

pub(super) struct StoredProposal {
    pub proposal: zcash_client_backend::proposal::Proposal<
        StandardFeeRule,
        zcash_client_sqlite::ReceivedNoteId,
    >,
    pub network: Network,
    pub account_id: AccountUuid,
}

pub(super) static PROPOSAL_STORE: std::sync::LazyLock<Mutex<ProposalStore>> =
    std::sync::LazyLock::new(|| {
        Mutex::new(ProposalStore {
            proposals: HashMap::new(),
            next_id: 1,
        })
    });

pub(super) struct ProposalStore {
    pub proposals: HashMap<u64, StoredProposal>,
    pub next_id: u64,
}

// ======================== Diversified Address ========================

pub fn get_next_available_address(db_path: &str, network: Network, account_uuid: &str) -> Result<String, String> {
    use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let req = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, ReceiverRequirement::Require, ReceiverRequirement::Omit,
    ).map_err(|_| "bad request")?;
    let (ua, _) = db.get_next_available_address(account_id, req)
        .map_err(|e| format!("{e}"))?.ok_or("No address available")?;
    Ok(ua.encode(&network))
}

// ======================== Enhancement ========================

pub(crate) struct TxDataRequest {
    pub request_type: String, // "get_status", "enhancement", "address_txids"
    pub txid: Option<String>,
    pub address: Option<String>,
    pub block_range_start: Option<u64>,
    pub block_range_end: Option<u64>,
}

pub fn get_transaction_data_requests(
    db_path: &str, network: Network,
) -> Result<Vec<TxDataRequest>, String> {
    use zcash_client_backend::data_api::TransactionDataRequest;

    let db = open_wallet_db(db_path, network)?;
    let requests = db.transaction_data_requests().map_err(|e| format!("{e}"))?;

    Ok(requests.into_iter().map(|r| match r {
        TransactionDataRequest::GetStatus(txid) => TxDataRequest {
            request_type: "get_status".into(),
            txid: Some(format!("{txid}")),
            address: None, block_range_start: None, block_range_end: None,
        },
        TransactionDataRequest::Enhancement(txid) => TxDataRequest {
            request_type: "enhancement".into(),
            txid: Some(format!("{txid}")),
            address: None, block_range_start: None, block_range_end: None,
        },
        TransactionDataRequest::TransactionsInvolvingAddress(req) => {
            let addr = zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
            TxDataRequest {
                request_type: "address_txids".into(),
                txid: None,
                address: Some(addr),
                block_range_start: Some(u32::from(req.block_range_start()) as u64),
                block_range_end: req.block_range_end().map(|h| u32::from(h) as u64),
            }
        }
    }).collect())
}

pub fn decrypt_and_store_transaction(
    db_path: &str, network: Network, tx_bytes: &[u8], mined_height: Option<u64>,
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
    db_path: &str, network: Network, txid_hex: &str, status: i64,
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
    db_path: &str, _network: Network, limit: Option<u32>, account_uuid: &str,
) -> Result<Vec<TransactionInfo>, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();

    // Open a separate read-only connection (WalletDb.conn is private)
    let conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).map_err(|e| format!("Failed to open DB: {e}"))?;
    let sql = match limit {
        Some(_) => "SELECT txid, mined_height, expired_unmined, account_balance_delta, \
             COALESCE(fee_paid, 0), COALESCE(block_time, 0) \
             FROM v_transactions \
             WHERE account_uuid = ?1 \
             ORDER BY COALESCE(mined_height, 999999999) DESC, tx_index DESC \
             LIMIT ?2",
        None => "SELECT txid, mined_height, expired_unmined, account_balance_delta, \
             COALESCE(fee_paid, 0), COALESCE(block_time, 0) \
             FROM v_transactions \
             WHERE account_uuid = ?1 \
             ORDER BY COALESCE(mined_height, 999999999) DESC, tx_index DESC",
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
    }.map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

// ======================== Pending TX Tracking ========================

pub(crate) struct PendingTxInfo {
    pub txid_bytes: Vec<u8>,
    pub txid_hex: String,
    pub expiry_height: u64,
}

/// Get all pending (unmined, unexpired) transactions that we created (have raw bytes).
pub fn get_pending_transactions(db_path: &str) -> Result<Vec<PendingTxInfo>, String> {
    let conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).map_err(|e| format!("Failed to open DB: {e}"))?;

    let mut stmt = conn.prepare(
        "SELECT txid, COALESCE(expiry_height, 0) \
         FROM transactions \
         WHERE mined_height IS NULL AND expired_unmined = 0 AND raw IS NOT NULL"
    ).map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt.query_map([], |row| {
        let txid_bytes: Vec<u8> = row.get(0)?;
        let expiry_height: u64 = row.get::<_, i64>(1)?.unsigned_abs();
        let txid_hex = hex::encode(&txid_bytes);
        Ok(PendingTxInfo { txid_bytes, txid_hex, expiry_height })
    }).map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

/// Check if a transaction has been mined by querying lightwalletd.
/// Returns: 0 = still in mempool, >0 = mined at height, -1 = error/not found.
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

// ======================== Helpers ========================

pub fn get_blocks_dir(cache_path: &str) -> String {
    format!("{cache_path}/blocks")
}

#[cfg(test)]
mod tests {
    //! Regression tests for PROPOSAL_STORE lifecycle.
    //!
    //! These tests cover the parts of the proposal store that don't require a
    //! real wallet DB (note selection, fee computation, etc. are upstream of
    //! anything testable in isolation). Specifically:
    //!
    //! * `discard_proposal` is idempotent and tolerates nonexistent IDs
    //!   (called from the Dart cancel path and possibly more than once).
    //! * `create_pczt_from_proposal` returns a clean "not found" error for
    //!   an unknown ID instead of panicking or corrupting state — this is
    //!   the path that fires on a replay attempt after the proposal has
    //!   already been consumed.
    //!
    //! A full insert→consume→replay test would require constructing a real
    //! `Proposal<StandardFeeRule, ReceivedNoteId>`, which in turn needs a
    //! live wallet DB with spendable notes and a lightwalletd chain tip.
    //! That belongs in an integration test, not a unit test here.

    use super::*;

    /// Pull a proposal ID that is guaranteed not to collide with anything a
    /// concurrent test might have inserted. We use a fresh counter so each
    /// call yields a distinct u64.
    fn unique_proposal_id() -> u64 {
        use std::sync::atomic::{AtomicU64, Ordering};
        // Start well above next_id's initial value (1) to avoid any overlap
        // with proposals that a parallel test might genuinely insert.
        static COUNTER: AtomicU64 = AtomicU64::new(1_000_000_000);
        COUNTER.fetch_add(1, Ordering::Relaxed)
    }

    #[test]
    fn discard_proposal_is_idempotent_for_missing_id() {
        // Should not panic, should not poison the mutex.
        let id = unique_proposal_id();
        discard_proposal(id);
        discard_proposal(id); // second call must also be a no-op
    }

    #[test]
    fn create_pczt_from_proposal_errors_for_missing_id() {
        // A replay attempt (or a bogus ID from stale UI state) must surface
        // a clean "not found" error rather than panicking or creating a
        // bogus PCZT. We pass an invalid db_path because the "not found"
        // check fires before any DB work; if the behavior regresses to
        // touching the DB first, this test will reveal it via a different
        // error message.
        let id = unique_proposal_id();
        let result = create_pczt_from_proposal(
            "/nonexistent/path/that/should/not/exist.db",
            Network::MainNetwork,
            id,
        );

        match result {
            Err(msg) => {
                assert!(
                    msg.contains("Proposal not found"),
                    "expected 'Proposal not found' error, got: {msg}"
                );
            }
            Ok(_) => panic!("create_pczt_from_proposal succeeded for unknown id {id}"),
        }
    }

    #[test]
    fn discard_proposal_after_create_pczt_failure_is_still_noop() {
        // Simulates the Dart `finally` cleanup path: after create_pczt
        // fails with "not found" (so the proposal was never there), the
        // finally block still calls discard_proposal. That call must be
        // safe even though the ID has never been in the store.
        let id = unique_proposal_id();
        let _ = create_pczt_from_proposal(
            "/nonexistent/path/that/should/not/exist.db",
            Network::MainNetwork,
            id,
        );
        discard_proposal(id); // cleanup must not panic
    }
}
