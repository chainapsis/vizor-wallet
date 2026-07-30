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

mod broadcast;
mod migration;
mod migration_wallet_ops;
mod pczt;
mod proposal_locks;
mod send;
mod transactions;

pub(crate) use broadcast::parse_separate_relay_transaction;

// Re-export the split submodules at the `wallet::sync` path so every
// `crate::wallet::sync::propose_send` / `::get_wallet_balance` /
// `::extract_and_broadcast_pczt` etc. call path keeps resolving with
// the same visibility the monolithic `sync.rs` had before the refactor.
// Functions were `pub fn` in the old file → `pub use`. Return-value
// structs were `pub(crate) struct` → `pub(crate) use` (they're
// reachable from anywhere in the crate but not re-exported to
// downstream consumers, which matches the pre-refactor surface
// exactly).
pub(crate) use migration::{
    configure_fast_testnet_migration, delete_account_migration_rows_with_tx, migration_status,
    proof_retry_height, reconcile_wallet_locks_after_sync, separate_relay_migration_transaction,
    MigrationPartState, MigrationPreparationOutputKind, MigrationPreparationTransactionState,
    MigrationScheduleEntry, MigrationStatus, PreparationTimingPolicy,
};
pub(crate) use pczt::extract_compact_sigs_from_pczt;
pub use pczt::{
    add_proofs_to_pczt, create_pczt_from_proposal, discard_proposal, extract_and_broadcast_pczt,
    redact_pczt_for_signer, retain_proposal_lock_until_expiry, ExtractAndBroadcastPcztResult,
};
pub(crate) use proposal_locks::recover_previous_process as recover_orphaned_send_locks;
pub(crate) use send::estimate_send_max;
pub(crate) use send::{
    advance_orchard_migration_preparation_for_run, complete_orchard_migration_batch_pczt,
    complete_orchard_migration_denominations_pczt, complete_orchard_migration_immediate_pczt,
    complete_orchard_migration_single_qr_pczt, create_or_resume_private_migration_draft,
    discard_all_keystone_migration_requests, discard_keystone_migration_request,
    discard_keystone_migration_requests_for_account, keystone_migration_proof_status,
    migrate_orchard_to_ironwood, migrate_orchard_to_ironwood_immediately,
    orchard_migration_proof_readiness, orchard_migration_proof_readiness_at_scanned_height,
    prepare_orchard_migration_batch_pczt, prepare_orchard_migration_denominations_pczt,
    prepare_orchard_migration_immediate_pczt, prepare_orchard_migration_single_qr_pczt,
    retain_prepared_note_anchor_checkpoints_after_scan, retire_unbroadcast_orchard_migration,
    KeystoneSignedMigrationMessage, OrchardMigrationImmediatePlan,
};
pub use send::{
    broadcast_due_orchard_migration_transactions, broadcast_one_due_orchard_migration_transaction,
    estimate_fee, execute_proposal, execute_proposal_with_seed_loader, propose_send,
    ExecuteProposalResult, IronwoodMigrationResult,
};
pub(crate) use send::{
    create_shield_transparent_pczt, get_shield_transparent_status, shield_transparent_balance,
};
pub(crate) use send::{get_orchard_migration_immediate_plan, get_orchard_migration_private_plan};
// Internal-only re-export for `sync_engine::run_sync_impl`'s
// auto-resubmit pass. Not part of the `wallet::sync` public surface.
pub(crate) use send::migration_anchor_retention_required;
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
#[allow(unused_imports)] // names reachable via `crate::wallet::sync::*`; pre-refactor surface
pub(crate) use send::{KeystoneMigrationMessage, KeystoneMigrationSigningRequest};
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
    pub proposal_id: u64,
    pub proposal: zcash_client_backend::proposal::Proposal<
        send::WalletFeeRule,
        zcash_client_sqlite::ReceivedNoteId,
    >,
    pub proposed_tx_version: Option<zcash_primitives::transaction::TxVersion>,
    /// When `true`, the proposal was fee-counted with unpadded Orchard-pool
    /// bundles (migration children only) and the PCZT must be built with
    /// `BundlePadding::UNPADDED` to balance. See `zip317_helper`.
    pub unpadded_orchard_pool_bundles: bool,
    pub network: WalletNetwork,
    pub account_id: AccountUuid,
    pub send_flow_id: String,
}

#[derive(Clone)]
pub(super) struct StoredProposalLock {
    pub proposal: zcash_client_backend::proposal::Proposal<
        send::WalletFeeRule,
        zcash_client_sqlite::ReceivedNoteId,
    >,
    pub network: WalletNetwork,
    pub db_path: String,
    pub owner: zcash_client_backend::wallet::LockOwner,
    pub send_flow_id: String,
}

pub(super) static PROPOSAL_STORE: std::sync::LazyLock<Mutex<ProposalStore>> =
    std::sync::LazyLock::new(|| {
        Mutex::new(ProposalStore {
            proposals: HashMap::new(),
            locks: HashMap::new(),
            next_id: 1,
        })
    });

pub(super) struct ProposalStore {
    pub proposals: HashMap<u64, StoredProposal>,
    pub locks: HashMap<u64, StoredProposalLock>,
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

pub(super) fn stored_proposal_lock(
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<StoredProposalLock, String> {
    let store = PROPOSAL_STORE
        .lock()
        .map_err(|e| format!("Lock error: {e}"))?;
    match store.locks.get(&proposal_id) {
        Some(lock) if lock.send_flow_id == send_flow_id => Ok(lock.clone()),
        Some(_) => {
            log::warn!("proposal store: lock send flow mismatch for proposal_id={proposal_id}");
            Err("Send flow mismatch".to_string())
        }
        None => Err("Proposal input lock not found".to_string()),
    }
}

fn unlock_stored_proposal(
    proposal_id: u64,
    send_flow_id: &str,
    lock: StoredProposalLock,
) -> Result<(), String> {
    with_wallet_db_write_lock("sync.unlock_stored_proposal", || {
        let mut db = open_wallet_db(&lock.db_path, lock.network)?;
        // The wallet write lock is always acquired before the proposal-store
        // mutex (the same order used while creating proposals). Re-checking
        // here prevents a retain call that won the race from being followed by
        // a stale DB unlock.
        let mut store = PROPOSAL_STORE
            .lock()
            .map_err(|e| format!("Lock proposal store before DB unlock: {e}"))?;
        let current = match store.locks.get(&proposal_id) {
            Some(current) if current.send_flow_id == send_flow_id => current.clone(),
            Some(_) => return Err("Send flow mismatch before DB unlock".to_string()),
            None => return Ok(()),
        };
        zcash_client_backend::data_api::wallet::unlock_proposal_inputs(
            &mut db,
            &current.proposal,
            current.owner,
        )
        .map_err(|e| format!("Unlock abandoned send proposal inputs: {e}"))?;
        proposal_locks::remove(&current.db_path, current.owner)?;
        store.locks.remove(&proposal_id);
        Ok(())
    })
}

pub(super) fn finish_stored_proposal(
    proposal_id: u64,
    send_flow_id: &str,
    release_inputs: bool,
) -> Result<(), String> {
    let lock = {
        let mut store = PROPOSAL_STORE
            .lock()
            .map_err(|e| format!("Lock proposal store for finish: {e}"))?;
        let Some(lock) = store.locks.get(&proposal_id).cloned() else {
            return Ok(());
        };
        if lock.send_flow_id != send_flow_id {
            return Err("Send flow mismatch".to_string());
        }
        if !release_inputs {
            store.locks.remove(&proposal_id);
            drop(store);
            return proposal_locks::remove(&lock.db_path, lock.owner);
        }
        lock.clone()
    };

    // The DB helper re-checks ownership while holding both locks. On DB
    // failure the owner record remains in place, allowing an idempotent retry.
    unlock_stored_proposal(proposal_id, send_flow_id, lock)
}

pub(super) fn discard_stored_proposal(proposal_id: u64, send_flow_id: &str) -> Result<(), String> {
    let should_release = {
        let mut store = PROPOSAL_STORE
            .lock()
            .map_err(|e| format!("Lock proposal store for discard: {e}"))?;
        match store.proposals.get(&proposal_id) {
            Some(stored) if stored.send_flow_id == send_flow_id => {
                store.proposals.remove(&proposal_id);
                true
            }
            Some(_) => return Err("Send flow mismatch".to_string()),
            None => match store.locks.get(&proposal_id) {
                Some(lock) if lock.send_flow_id == send_flow_id => true,
                Some(_) => return Err("Send flow mismatch".to_string()),
                None => false,
            },
        }
    };
    if should_release {
        finish_stored_proposal(proposal_id, send_flow_id, true)?;
    }
    Ok(())
}

/// Removes all in-memory capability to reuse or explicitly unlock a proposal,
/// while leaving its wallet-level input lock to expire at its original height.
///
/// This is used when a broadcast may have reached the network but local
/// transaction storage did not complete. Releasing the DB lock in that state
/// could allow an immediate conflicting send.
pub(super) fn retain_stored_proposal_lock_until_expiry(
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<(), String> {
    let lock = {
        let store = PROPOSAL_STORE
            .lock()
            .map_err(|e| format!("Lock proposal store to inspect retained DB lock: {e}"))?;
        match store.locks.get(&proposal_id) {
            Some(lock) if lock.send_flow_id == send_flow_id => Some(lock.clone()),
            Some(_) => return Err("Send flow mismatch".to_string()),
            None => None,
        }
    };
    let Some(lock) = lock else {
        return Ok(());
    };

    with_wallet_db_write_lock("sync.retain_stored_proposal_lock", || {
        let mut store = PROPOSAL_STORE
            .lock()
            .map_err(|e| format!("Lock proposal store to retain DB lock: {e}"))?;
        let Some(current) = store.locks.get(&proposal_id) else {
            return Ok(());
        };
        if current.send_flow_id != send_flow_id || current.owner != lock.owner {
            return Err("Send flow changed before retaining DB lock".to_string());
        }
        proposal_locks::mark_retain_until_expiry(&lock.db_path, lock.owner)?;
        if let Some(proposal) = store.proposals.get(&proposal_id) {
            if proposal.send_flow_id != send_flow_id {
                return Err("Send flow mismatch".to_string());
            }
            store.proposals.remove(&proposal_id);
        }
        // Remove the unlock capability in the same critical section as the
        // replayable proposal. A concurrent discard can therefore observe
        // either the complete pre-retain state or the complete retained state,
        // never the gap between them.
        store.locks.remove(&proposal_id);
        Ok(())
    })
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
        discard_proposal(id, "missing-flow").unwrap();
        discard_proposal(id, "missing-flow").unwrap(); // second call must also be a no-op
    }

    #[tokio::test]
    async fn create_pczt_from_proposal_errors_for_missing_id() {
        // A replay attempt (or a bogus ID from stale UI state) must surface
        // a clean "not found" error rather than panicking or creating a
        // bogus PCZT. We pass an invalid db_path because the "not found"
        // check fires before any DB work; if the behavior regresses to
        // touching the DB first, this test will reveal it via a different
        // error message.
        let id = unique_proposal_id();
        let result = create_pczt_from_proposal(
            "/nonexistent/path/that/should/not/exist.db",
            "https://unused.invalid",
            WalletNetwork::Main,
            id,
            "missing-flow",
        )
        .await;

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

    #[tokio::test]
    async fn discard_proposal_after_create_pczt_failure_is_still_noop() {
        // Simulates the Dart `finally` cleanup path: after create_pczt
        // fails with "not found" (so the proposal was never there), the
        // finally block still calls discard_proposal. That call must be
        // safe even though the ID has never been in the store.
        let id = unique_proposal_id();
        let _ = create_pczt_from_proposal(
            "/nonexistent/path/that/should/not/exist.db",
            "https://unused.invalid",
            WalletNetwork::Main,
            id,
            "missing-flow",
        )
        .await;
        discard_proposal(id, "missing-flow").unwrap(); // cleanup must not panic
    }
}
