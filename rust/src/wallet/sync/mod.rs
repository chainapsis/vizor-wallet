use zcash_client_backend::{
    data_api::{
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::ConfirmationsPolicy,
        WalletCommitmentTrees, WalletRead, WalletWrite,
    },
    proto::service::TreeState,
};
use zcash_client_sqlite::{
    chain::{init::init_blockmeta_db, BlockMeta},
    AccountUuid, FsBlockDb,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_for_read_with_timeout,
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        READ_DB_BUSY_TIMEOUT, WALLET_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

mod pczt;
mod send;
mod transactions;

// Re-export the split submodules at the `wallet::sync` path so every
// `crate::wallet::sync::propose_send` / `::get_wallet_balance` /
// `::extract_and_broadcast_pczt` etc. call path keeps resolving with
// the same visibility the monolithic `sync.rs` had before the refactor.
// Functions were `pub fn` in the old file → `pub use`. Return-value
// structs were `pub(crate) struct` → `pub(crate) use` (they're
// reachable from anywhere in the crate but not re-exported to
// downstream consumers, which matches the pre-refactor surface
// exactly).
pub use pczt::{
    add_proofs_to_pczt, create_pczt_from_proposal, discard_proposal, extract_and_broadcast_pczt,
    redact_pczt_for_signer, ExtractAndBroadcastPcztResult,
};
pub(crate) use send::estimate_send_max;
pub(crate) use send::{
    create_shield_transparent_pczt, get_shield_transparent_status, shield_transparent_balance,
};
pub use send::{
    estimate_fee, execute_proposal, execute_proposal_with_seed_loader, propose_send,
    ExecuteProposalResult,
};
// Internal-only re-export for `sync_engine::run_sync_impl`'s
// auto-resubmit pass. Not part of the `wallet::sync` public surface.
pub(crate) use send::resubmit_pending_transactions;
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::ProposalResult;
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::SendMaxEstimateResult;
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::ShieldTransparentPcztResult;
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::ShieldTransparentResult;
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::ShieldTransparentStatus;
pub use transactions::{
    decrypt_and_store_transaction, get_next_available_address,
    get_previous_transaction_count_for_address, get_transaction_data_requests,
    get_transaction_detail, get_transaction_history, get_wallet_balance,
    parse_address_request_kind, set_transaction_status, AddressRequestKind,
};
#[allow(unused_imports)] // ditto
pub(crate) use transactions::{
    get_export_birthday_anchor, get_oldest_mined_transaction_anchor, ExportBirthdayAnchor,
    TransactionDetail, TransactionDetailOutput, TransactionInfo, TxDataRequest, WalletBalance,
    WalletBalanceAvailability,
};

pub(super) fn open_wallet_db(
    db_path: &str,
    network: WalletNetwork,
) -> Result<WalletDatabase, String> {
    open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)
}

pub(crate) fn open_wallet_db_for_read(
    db_path: &str,
    network: WalletNetwork,
) -> Result<WalletDatabase, String> {
    open_wallet_db_for_read_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)
}

pub(crate) fn open_readonly_conn(db_path: &str) -> Result<rusqlite::Connection, String> {
    open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))
}

pub(crate) fn open_readonly_conn_fail_fast(db_path: &str) -> Result<rusqlite::Connection, String> {
    open_readonly_conn_with_timeout(db_path, None)
}

fn open_block_cache(cache_path: &str) -> Result<FsBlockDb, String> {
    std::fs::create_dir_all(cache_path).map_err(|e| format!("Failed to create cache dir: {e}"))?;
    let mut db_cache = FsBlockDb::for_path(cache_path)
        .map_err(|e| format!("Failed to open block cache: {e:?}"))?;
    init_blockmeta_db(&mut db_cache).map_err(|e| format!("Failed to init block cache: {e}"))?;
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

pub fn update_chain_tip(db_path: &str, network: WalletNetwork, height: u64) -> Result<(), String> {
    with_wallet_db_write_lock("sync.update_chain_tip", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.update_chain_tip(BlockHeight::from_u32(height as u32))
            .map_err(|e| format!("Failed to update chain tip: {e}"))
    })
}

/// Get next subtree indices to know where to start downloading from.
pub fn get_next_subtree_indices(
    db_path: &str,
    network: WalletNetwork,
) -> Result<(u64, u64, u64), String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let summary = db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("{e}"))?;
    match summary {
        Some(s) => Ok((
            s.next_sapling_subtree_index(),
            s.next_orchard_subtree_index(),
            s.next_ironwood_subtree_index(),
        )),
        None => Ok((0, 0, 0)),
    }
}

pub fn put_sapling_subtree_roots(
    db_path: &str,
    network: WalletNetwork,
    start_index: u64,
    roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let parsed: Vec<_> = roots
        .iter()
        .map(|(h, bytes)| {
            let arr: [u8; 32] = bytes.as_slice().try_into().map_err(|_| "bad hash len")?;
            let node =
                Option::from(sapling_crypto::Node::from_bytes(arr)).ok_or("bad sapling hash")?;
            Ok::<_, String>(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(*h as u32),
                node,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if parsed.is_empty() {
        Ok(())
    } else {
        with_wallet_db_write_lock("sync.put_sapling_subtree_roots", || {
            let mut db = open_wallet_db(db_path, network)?;
            db.put_sapling_subtree_roots(start_index, parsed.as_slice())
                .map_err(|e| format!("{e}"))
        })
    }
}

pub fn put_orchard_subtree_roots(
    db_path: &str,
    network: WalletNetwork,
    start_index: u64,
    roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let parsed: Vec<_> = roots
        .iter()
        .map(|(h, bytes)| {
            let arr: [u8; 32] = bytes.as_slice().try_into().map_err(|_| "bad hash len")?;
            let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&arr))
                .ok_or("bad orchard hash")?;
            Ok::<_, String>(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(*h as u32),
                node,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if parsed.is_empty() {
        Ok(())
    } else {
        with_wallet_db_write_lock("sync.put_orchard_subtree_roots", || {
            let mut db = open_wallet_db(db_path, network)?;
            db.put_orchard_subtree_roots(start_index, parsed.as_slice())
                .map_err(|e| format!("{e}"))
        })
    }
}

pub fn put_ironwood_subtree_roots(
    db_path: &str,
    network: WalletNetwork,
    start_index: u64,
    roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let parsed: Vec<_> = roots
        .iter()
        .map(|(h, bytes)| {
            let arr: [u8; 32] = bytes.as_slice().try_into().map_err(|_| "bad hash len")?;
            let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&arr))
                .ok_or("bad ironwood hash")?;
            Ok::<_, String>(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(*h as u32),
                node,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if parsed.is_empty() {
        Ok(())
    } else {
        with_wallet_db_write_lock("sync.put_ironwood_subtree_roots", || {
            let mut db = open_wallet_db(db_path, network)?;
            db.put_ironwood_subtree_roots(start_index, parsed.as_slice())
                .map_err(|e| format!("{e}"))
        })
    }
}

pub(crate) struct ScanRangeInfo {
    pub start: u64,
    pub end: u64,
    pub priority: u8,
}

pub fn suggest_scan_ranges(
    db_path: &str,
    network: WalletNetwork,
) -> Result<Vec<ScanRangeInfo>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let ranges = db.suggest_scan_ranges().map_err(|e| format!("{e}"))?;
    Ok(ranges
        .into_iter()
        .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
        .map(|r| ScanRangeInfo {
            start: u32::from(r.block_range().start) as u64,
            end: u32::from(r.block_range().end) as u64,
            priority: match r.priority() {
                ScanPriority::Verify => 6,
                ScanPriority::ChainTip => 5,
                ScanPriority::FoundNote => 4,
                ScanPriority::OpenAdjacent => 3,
                ScanPriority::Historic => 2,
                ScanPriority::Scanned => 1,
                ScanPriority::Ignored => 0,
            },
        })
        .collect())
}

pub fn write_block_metadata(
    cache_path: &str,
    blocks: &[(u64, Vec<u8>, u32, u32, u32)],
) -> Result<(), String> {
    let db_cache = open_block_cache(cache_path)?;
    let metas: Vec<BlockMeta> = blocks
        .iter()
        .map(|(h, hash, time, sc, oc)| {
            let mut arr = [0u8; 32];
            arr[..hash.len().min(32)].copy_from_slice(&hash[..hash.len().min(32)]);
            BlockMeta {
                height: BlockHeight::from_u32(*h as u32),
                block_hash: BlockHash(arr),
                block_time: *time,
                sapling_outputs_count: *sc,
                orchard_actions_count: *oc,
            }
        })
        .collect();
    db_cache
        .write_block_metadata(&metas)
        .map_err(|e| format!("{e:?}"))
}

pub fn scan_blocks(
    db_path: &str,
    cache_path: &str,
    network: WalletNetwork,
    from_height: u64,
    ts_network: &str,
    ts_height: u64,
    ts_hash: &str,
    ts_time: u32,
    ts_sapling: &str,
    ts_orchard: &str,
    ts_ironwood: &str,
    limit: u64,
) -> Result<u64, String> {
    let db_cache = open_block_cache(cache_path)?;
    let from_state = if ts_hash.is_empty() {
        zcash_client_backend::data_api::chain::ChainState::empty(
            BlockHeight::from_u32((from_height - 1) as u32),
            BlockHash([0u8; 32]),
        )
    } else {
        TreeState {
            network: ts_network.into(),
            height: ts_height,
            hash: ts_hash.into(),
            time: ts_time,
            sapling_tree: ts_sapling.into(),
            orchard_tree: ts_orchard.into(),
            ironwood_tree: ts_ironwood.into(),
        }
        .to_chain_state()
        .map_err(|e| format!("{e}"))?
    };
    let result = with_wallet_db_write_lock("sync.scan_blocks", || {
        let mut db_data = open_wallet_db(db_path, network)?;
        scan_cached_blocks(
            &network,
            &db_cache,
            &mut db_data,
            BlockHeight::from_u32(from_height as u32),
            &from_state,
            limit as usize,
        )
        .map_err(|e| format!("{e}"))
    })?;
    Ok((u32::from(result.scanned_range().end) - u32::from(result.scanned_range().start)) as u64)
}

// ======================== Balance & Progress ========================

pub(crate) struct SyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub is_syncing: bool,
    pub is_complete: bool,
}

fn is_completed_sync_status(
    scanned_height: u64,
    chain_tip_height: u64,
    last_completed_height: Option<u64>,
) -> bool {
    chain_tip_height > 0
        && scanned_height >= chain_tip_height
        && last_completed_height == Some(chain_tip_height)
}

pub fn get_sync_progress(db_path: &str, network: WalletNetwork) -> Result<SyncProgress, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    match db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("{e}"))?
    {
        Some(s) => {
            let scanned_height = u32::from(s.fully_scanned_height()) as u64;
            let chain_tip_height = u32::from(s.chain_tip_height()) as u64;
            let last_completed_height = super::sync_engine::completed_sync_height_for_status(
                db_path,
                scanned_height,
                chain_tip_height,
            )
            .unwrap_or_else(|e| {
                log::warn!("sync: completed-height metadata unavailable: {e}");
                None
            });
            Ok(SyncProgress {
                scanned_height,
                chain_tip_height,
                is_syncing: s.fully_scanned_height() < s.chain_tip_height(),
                is_complete: is_completed_sync_status(
                    scanned_height,
                    chain_tip_height,
                    last_completed_height,
                ),
            })
        }
        None => Ok(SyncProgress {
            scanned_height: 0,
            chain_tip_height: 0,
            is_syncing: false,
            is_complete: false,
        }),
    }
}

// ======================== Rewind ========================

pub fn rewind_to_height(db_path: &str, network: WalletNetwork, height: u64) -> Result<u64, String> {
    let result = with_wallet_db_write_lock("sync.rewind_to_height", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.truncate_to_height(BlockHeight::from_u32(height as u32))
            .map_err(|e| format!("{e}"))
    })?;
    Ok(u32::from(result) as u64)
}

// ======================== Address Validation ========================

pub fn validate_address(address: &str) -> Result<String, String> {
    use zcash_address::ZcashAddress;
    use zcash_keys::address::Address;

    let addr: Address = ZcashAddress::try_from_encoded(address)
        .map_err(|e| format!("Invalid: {e}"))?
        .convert()
        .map_err(|e| format!("Invalid: {e}"))?;

    match addr {
        Address::Unified(_) => Ok("unified".into()),
        Address::Sapling(_) => Ok("sapling".into()),
        Address::Transparent(_) => Ok("transparent".into()),
        Address::Tex(_) => Ok("tex".into()),
    }
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
        send::WalletFeeRule,
        zcash_client_sqlite::ReceivedNoteId,
    >,
    pub network: WalletNetwork,
    pub account_id: AccountUuid,
    pub send_flow_id: String,
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

pub(super) fn consume_stored_proposal(
    proposal_id: u64,
    send_flow_id: &str,
    not_found_message: &str,
) -> Result<StoredProposal, String> {
    let mut store = PROPOSAL_STORE
        .lock()
        .map_err(|e| format!("Lock error: {e}"))?;

    match store.proposals.get(&proposal_id) {
        Some(stored) if stored.send_flow_id == send_flow_id => {}
        Some(_) => {
            log::warn!("proposal store: send flow mismatch for proposal_id={proposal_id}");
            return Err("Send flow mismatch".to_string());
        }
        None => return Err(not_found_message.to_string()),
    }

    store
        .proposals
        .remove(&proposal_id)
        .ok_or_else(|| not_found_message.to_string())
}

pub(super) fn discard_stored_proposal(proposal_id: u64, send_flow_id: &str) {
    match PROPOSAL_STORE.lock() {
        Ok(mut store) => match store.proposals.get(&proposal_id) {
            Some(stored) if stored.send_flow_id == send_flow_id => {
                store.proposals.remove(&proposal_id);
            }
            Some(_) => {
                log::warn!(
                    "proposal store: discard ignored for send flow mismatch proposal_id={proposal_id}"
                );
            }
            None => {}
        },
        Err(e) => {
            log::warn!("proposal store: discard lock failed: {e}");
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
    //! A full insert→consume→replay test would require constructing a real
    //! `Proposal<WalletFeeRule, ReceivedNoteId>`, which in turn needs a
    //! live wallet DB with spendable notes and a lightwalletd chain tip.
    //! That belongs in an integration test, not a unit test here.

    use super::*;

    #[test]
    fn sync_completion_requires_matching_persisted_tip() {
        assert!(is_completed_sync_status(100, 100, Some(100)));
        assert!(!is_completed_sync_status(100, 100, None));
        assert!(!is_completed_sync_status(100, 100, Some(99)));
        assert!(!is_completed_sync_status(99, 100, Some(100)));
        assert!(!is_completed_sync_status(0, 0, Some(0)));
    }

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
    fn validate_address_classifies_tex_addresses() {
        assert_eq!(
            validate_address("tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte").unwrap(),
            "tex"
        );
        assert_eq!(
            validate_address("textest1qyqszqgpqyqszqgpqyqszqgpqyqszqgpfcjgfy").unwrap(),
            "tex"
        );
    }

    #[test]
    fn validate_address_rejects_invalid_address() {
        assert!(validate_address("not-an-address").is_err());
    }

    #[test]
    fn validate_address_rejects_sprout_addresses() {
        use zcash_address::ToAddress;

        let sprout = zcash_address::ZcashAddress::from_sprout(
            zcash_protocol::consensus::NetworkType::Main,
            [0; 64],
        )
        .to_string();

        assert!(validate_address(&sprout).is_err());
    }

    #[test]
    fn discard_proposal_is_idempotent_for_missing_id() {
        // Should not panic, should not poison the mutex.
        let id = unique_proposal_id();
        discard_proposal(id, "missing-flow");
        discard_proposal(id, "missing-flow"); // second call must also be a no-op
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
            WalletNetwork::Main,
            id,
            "missing-flow",
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
            WalletNetwork::Main,
            id,
            "missing-flow",
        );
        discard_proposal(id, "missing-flow"); // cleanup must not panic
    }
}
