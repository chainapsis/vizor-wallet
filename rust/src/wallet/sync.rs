use std::convert::Infallible;
use std::num::NonZeroUsize;

use rand::rngs::OsRng;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::{
    data_api::{
        Account as _, InputSource, WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::{
            self, ConfirmationsPolicy,
            input_selection::GreedyInputSelector,
            propose_transfer, create_proposed_transactions,
        },
    },
    fees::{
        DustOutputPolicy, SplitPolicy, StandardFeeRule,
        zip317::MultiOutputChangeStrategy,
    },
    proto::service::TreeState,
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::{
    AccountUuid, FsBlockDb,
    WalletDb,
    chain::{BlockMeta, init::init_blockmeta_db},
    util::SystemClock,
};
use crate::wallet::keys::parse_account_uuid;
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_primitives::block::BlockHash;
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    ShieldedProtocol,
    consensus::{BlockHeight, Network},
    memo::{Memo, MemoBytes},
    value::Zatoshis,
};

type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

fn open_wallet_db(db_path: &str, network: Network) -> Result<WalletDatabase, String> {
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
pub fn propose_send(
    db_path: &str, network: Network, account_uuid: &str,
    to_address: &str, amount_zatoshi: u64, memo_str: Option<&str>,
) -> Result<ProposalResult, String> {
    use zcash_protocol::{PoolType, ShieldedProtocol as SP};

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;

    let to: zcash_address::ZcashAddress = to_address.parse().map_err(|e| format!("Bad address: {e}"))?;
    let value = Zatoshis::from_u64(amount_zatoshi).map_err(|_| "Bad amount")?;
    let memo_bytes = match memo_str {
        Some(m) => {
            let bytes = MemoBytes::from(Memo::from_bytes(m.as_bytes()).map_err(|e| format!("Bad memo: {e}"))?);
            Some(bytes)
        }
        None => None,
    };

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
    let payment = Payment::new(to, value, memo_bytes, None, None, vec![])
        .ok_or("Cannot send memo to this address type")?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db, &network, account_id, &input_selector, &change_strategy,
        request, ConfirmationsPolicy::default(),
    ).map_err(|e| format!("Propose failed: {e}"))?;

    let needs_sapling = proposal.steps().iter().any(|step| {
        step.involves(PoolType::Shielded(SP::Sapling))
    });

    let fee: u64 = proposal.steps().iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum();

    // Store proposal for later execution
    let mut store = PROPOSAL_STORE.lock().map_err(|e| format!("Lock error: {e}"))?;
    let id = store.next_id;
    store.next_id += 1;
    store.proposals.insert(id, StoredProposal { proposal, network, account_id });

    Ok(ProposalResult { proposal_id: id, needs_sapling_params: needs_sapling, fee_zatoshi: fee })
}

/// Estimate the fee for a transfer without storing the proposal.
/// Used for validation only — does not consume resources in PROPOSAL_STORE.
pub fn estimate_fee(
    db_path: &str, network: Network, account_uuid: &str,
    to_address: &str, amount_zatoshi: u64, memo_str: Option<&str>,
) -> Result<u64, String> {
    use zcash_protocol::ShieldedProtocol as SP;

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;

    let to: zcash_address::ZcashAddress = to_address.parse().map_err(|e| format!("Bad address: {e}"))?;
    let value = Zatoshis::from_u64(amount_zatoshi).map_err(|_| "Bad amount")?;
    let memo_bytes = match memo_str {
        Some(m) => {
            let bytes = MemoBytes::from(Memo::from_bytes(m.as_bytes()).map_err(|e| format!("Bad memo: {e}"))?);
            Some(bytes)
        }
        None => None,
    };

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
    let payment = Payment::new(to, value, memo_bytes, None, None, vec![])
        .ok_or("Cannot send memo to this address type")?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db, &network, account_id, &input_selector, &change_strategy,
        request, ConfirmationsPolicy::default(),
    ).map_err(|e| format!("Propose failed: {e}"))?;

    let fee: u64 = proposal.steps().iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum();

    Ok(fee)
}

/// Execute a previously proposed transfer, then broadcast to the network.
/// Returns comma-separated txids on success.
pub async fn execute_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    proposal_id: u64,
    seed_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<String, String> {
    let mut store = PROPOSAL_STORE.lock().map_err(|e| format!("Lock error: {e}"))?;
    let stored = store.proposals.remove(&proposal_id)
        .ok_or("Proposal not found (expired or already executed)")?;
    let network = stored.network;
    drop(store);

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = stored.account_id;
    let account = db.get_account(account_id).map_err(|e| format!("{e}"))?.ok_or("Account not found")?;

    // Scope seed/USK so they are dropped before network I/O (broadcast)
    let txids = {
        let seed = SecretVec::new(seed_bytes.to_vec());
        let zip32_index = account.source().key_derivation().ok_or("No key derivation")?.account_index();
        let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
            .map_err(|e| format!("USK derivation failed: {e:?}"))?;

        match (spend_params_path, output_params_path) {
            (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                let prover = LocalTxProver::new(
                    std::path::Path::new(sp),
                    std::path::Path::new(op),
                );
                create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                    &mut db, &network, &prover, &prover,
                    &wallet::SpendingKeys::from_unified_spending_key(usk),
                    OvkPolicy::Sender, &stored.proposal,
                ).map_err(|e| format!("Create TX failed: {e}"))?
            }
            _ => {
                let spend_prover = NoOpSpendProver;
                let output_prover = NoOpOutputProver;
                create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                    &mut db, &network, &spend_prover, &output_prover,
                    &wallet::SpendingKeys::from_unified_spending_key(usk),
                    OvkPolicy::Sender, &stored.proposal,
                ).map_err(|e| format!("Create TX failed: {e}"))?
            }
        }
        // seed + usk dropped here, before broadcast
    };

    // Connect to lightwalletd once for all broadcasts
    use tonic::transport::{ClientTlsConfig, Endpoint};
    use zcash_client_backend::proto::service::{
        compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction,
    };

    let channel = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| format!("Invalid URL: {e}"))?
        .tls_config(ClientTlsConfig::new().with_webpki_roots())
        .map_err(|e| format!("TLS error: {e}"))?
        .connect()
        .await
        .map_err(|e| format!("gRPC connect failed: {e}"))?;
    let mut client = CompactTxStreamerClient::new(channel);

    // Broadcast each transaction
    let txid_strings: Vec<String> = txids.iter().map(|id| format!("{id}")).collect();

    let read_conn = rusqlite::Connection::open_with_flags(
        db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ).map_err(|e| format!("Failed to open DB for broadcast: {e}"))?;

    let mut broadcast_ok: Vec<String> = Vec::new();
    for txid in &txids {
        let raw_tx = read_conn
            .query_row(
                "SELECT raw FROM transactions WHERE txid = ?1",
                rusqlite::params![txid.as_ref()],
                |row| row.get::<_, Vec<u8>>(0),
            )
            .map_err(|e| format!("Failed to get raw tx for {txid}: {e}"))?;

        match broadcast_raw_transaction(&mut client, &raw_tx).await {
            Ok(()) => {
                broadcast_ok.push(format!("{txid}"));
                log::info!("send: broadcast {txid} ({} bytes)", raw_tx.len());
            }
            Err(e) => {
                return Err(format!(
                    "Broadcast failed after {}/{} txs sent ({}). Error: {e}",
                    broadcast_ok.len(), txids.len(), broadcast_ok.join(",")
                ));
            }
        }
    }

    Ok(txid_strings.join(","))
}

/// Broadcast a raw transaction using an existing gRPC client.
async fn broadcast_raw_transaction(
    client: &mut zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient<tonic::transport::Channel>,
    raw_tx: &[u8],
) -> Result<(), String> {
    use zcash_client_backend::proto::service::RawTransaction;

    let resp = client
        .send_transaction(RawTransaction {
            data: raw_tx.to_vec(),
            height: 0,
        })
        .await
        .map_err(|e| format!("SendTransaction gRPC failed: {e}"))?
        .into_inner();

    if resp.error_code != 0 {
        return Err(format!("Broadcast rejected: {} (code {})", resp.error_message, resp.error_code));
    }

    Ok(())
}

pub(crate) struct ProposalResult {
    pub proposal_id: u64,
    pub needs_sapling_params: bool,
    pub fee_zatoshi: u64,
}

// In-memory proposal store (proposals are short-lived, between propose and execute)
use std::collections::HashMap;
use std::sync::Mutex;

struct StoredProposal {
    proposal: zcash_client_backend::proposal::Proposal<StandardFeeRule, zcash_client_sqlite::ReceivedNoteId>,
    network: Network,
    account_id: AccountUuid,
}

static PROPOSAL_STORE: std::sync::LazyLock<Mutex<ProposalStore>> =
    std::sync::LazyLock::new(|| Mutex::new(ProposalStore { proposals: HashMap::new(), next_id: 1 }));

struct ProposalStore {
    proposals: HashMap<u64, StoredProposal>,
    next_id: u64,
}

// ======================== PCZT (Hardware Wallet) ========================

/// Create a PCZT from a stored proposal (for hardware wallet signing).
pub fn create_pczt_from_proposal(
    db_path: &str, network: Network, proposal_id: u64,
) -> Result<Vec<u8>, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal as zcb_create_pczt;
    use zcash_client_backend::wallet::OvkPolicy;

    let store = PROPOSAL_STORE.lock().map_err(|e| format!("Lock: {e}"))?;
    let stored = store.proposals.get(&proposal_id)
        .ok_or("Proposal not found")?;

    let mut db = open_wallet_db(db_path, network)?;
    let pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
        &mut db, &network, stored.account_id, OvkPolicy::Sender, &stored.proposal,
    ).map_err(|e| format!("Create PCZT failed: {e}"))?;

    Ok(pczt.serialize())
}

/// Add Orchard (and if needed Sapling) proofs to a PCZT locally.
/// Returns a PCZT-with-proofs, which must later be combined with the
/// signed PCZT returned by the hardware signer.
pub fn add_proofs_to_pczt(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    use pczt::roles::prover::Prover;

    let pczt = pczt::Pczt::parse(pczt_bytes)
        .map_err(|e| format!("Parse PCZT: {e:?}"))?;

    let mut prover = Prover::new(pczt);

    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(&orchard::circuit::ProvingKey::build())
            .map_err(|e| format!("Orchard proof: {e:?}"))?;
    }

    if prover.requires_sapling_proofs() {
        // Keystone wallets are Orchard-only, so this path shouldn't be hit.
        // If it ever is, the caller would need to supply Sapling params.
        return Err("PCZT unexpectedly requires Sapling proofs".into());
    }

    Ok(prover.finish().serialize())
}

/// Redact information from a PCZT that the signer role doesn't need
/// (witnesses, proprietary metadata). Produces the bytes to send to
/// the hardware wallet for signing.
pub fn redact_pczt_for_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    use pczt::roles::redactor::Redactor;

    let pczt = pczt::Pczt::parse(pczt_bytes)
        .map_err(|e| format!("Parse PCZT: {e:?}"))?;

    let redacted = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
            });
        })
        .redact_sapling_with(|mut r| {
            r.redact_spends(|mut sr| sr.clear_witness());
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .redact_transparent_with(|mut r| {
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .finish();

    Ok(redacted.serialize())
}

/// Combine a PCZT-with-proofs and a PCZT-with-signatures, extract the
/// final transaction, store it, and broadcast it via lightwalletd.
pub async fn extract_and_broadcast_pczt(
    db_path: &str, lightwalletd_url: &str, network: Network,
    pczt_with_proofs_bytes: &[u8],
    pczt_with_signatures_bytes: &[u8],
) -> Result<String, String> {
    use pczt::roles::combiner::Combiner;
    use zcash_client_backend::data_api::wallet::extract_and_store_transaction_from_pczt;

    let pczt_with_proofs = pczt::Pczt::parse(pczt_with_proofs_bytes)
        .map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
    let pczt_with_signatures = pczt::Pczt::parse(pczt_with_signatures_bytes)
        .map_err(|e| format!("Parse PCZT with signatures: {e:?}"))?;

    let pczt = Combiner::new(vec![pczt_with_proofs, pczt_with_signatures])
        .combine()
        .map_err(|e| format!("Combine PCZTs: {e:?}"))?;

    let mut db = open_wallet_db(db_path, network)?;

    let orchard_vk = orchard::circuit::VerifyingKey::build();

    let txid = extract_and_store_transaction_from_pczt::<_, zcash_client_sqlite::ReceivedNoteId>(
        &mut db,
        pczt,
        None, // sapling_vk — None for Orchard-only
        Some(&orchard_vk),
    ).map_err(|e| format!("Extract TX from PCZT: {e}"))?;

    // Broadcast
    let channel = tonic::transport::Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| format!("Invalid URL: {e}"))?
        .tls_config(tonic::transport::ClientTlsConfig::new().with_webpki_roots())
        .map_err(|e| format!("TLS: {e}"))?
        .connect()
        .await
        .map_err(|e| format!("gRPC connect: {e}"))?;

    let mut client = zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient::new(channel);

    let raw_tx = db.get_transaction(txid)
        .map_err(|e| format!("Get TX: {e}"))?
        .ok_or("Transaction not found after extraction")?;

    let tx_bytes = {
        let mut buf = Vec::new();
        raw_tx.write(&mut buf).map_err(|e| format!("Serialize TX: {e}"))?;
        buf
    };

    let resp = client.send_transaction(
        zcash_client_backend::proto::service::RawTransaction {
            data: tx_bytes,
            height: 0,
        }
    ).await.map_err(|e| format!("Broadcast: {e}"))?.into_inner();

    // zebra-lightwalletd returns the txid in `error_message` on success, so the
    // only reliable signal is `error_code`.
    if resp.error_code != 0 {
        return Err(format!(
            "Broadcast rejected: {} (code {})",
            resp.error_message, resp.error_code
        ));
    }

    Ok(txid.to_string())
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

// ======================== No-op Sapling Provers ========================
// Used for Orchard-only transactions where Sapling params are not available.
// The prover methods will never be called for Orchard-only TXs.

use sapling_crypto::{
    bundle::GrothProofBytes,
    circuit,
    keys::EphemeralSecretKey,
    prover::{OutputProver, SpendProver},
    value::{NoteValue, ValueCommitTrapdoor},
    Diversifier, MerklePath, PaymentAddress, ProofGenerationKey, Rseed,
};

const GROTH_PROOF_SIZE: usize = 192;

struct NoOpSpendProver;

impl SpendProver for NoOpSpendProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _proof_generation_key: ProofGenerationKey,
        _diversifier: Diversifier,
        _rseed: Rseed,
        _value: NoteValue,
        _alpha: jubjub::Fr,
        _rcv: ValueCommitTrapdoor,
        _anchor: bls12_381::Scalar,
        _merkle_path: MerklePath,
    ) -> Option<circuit::Spend> {
        log::error!("NoOpSpendProver::prepare_circuit called — proposal contains unexpected Sapling spend");
        None
    }

    fn create_proof<R: rand_core::RngCore>(
        &self, _circuit: circuit::Spend, _rng: &mut R,
    ) -> Self::Proof {
        log::error!("NoOpSpendProver::create_proof called — should never happen");
        [0u8; GROTH_PROOF_SIZE]
    }

    fn encode_proof(_proof: Self::Proof) -> GrothProofBytes {
        [0u8; GROTH_PROOF_SIZE]
    }
}

struct NoOpOutputProver;

impl OutputProver for NoOpOutputProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _esk: &EphemeralSecretKey,
        _payment_address: PaymentAddress,
        _rcm: jubjub::Fr,
        _value: NoteValue,
        _rcv: ValueCommitTrapdoor,
    ) -> circuit::Output {
        log::error!("NoOpOutputProver::prepare_circuit called — proposal contains unexpected Sapling output");
        circuit::Output {
            value_commitment_opening: None,
            payment_address: None,
            commitment_randomness: None,
            esk: None,
        }
    }

    fn create_proof<R: rand_core::RngCore>(
        &self, _circuit: circuit::Output, _rng: &mut R,
    ) -> Self::Proof {
        log::error!("NoOpOutputProver::create_proof called — should never happen");
        [0u8; GROTH_PROOF_SIZE]
    }

    fn encode_proof(_proof: Self::Proof) -> GrothProofBytes {
        [0u8; GROTH_PROOF_SIZE]
    }
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
    use tonic::transport::{ClientTlsConfig, Endpoint};
    use zcash_client_backend::proto::service::{
        compact_tx_streamer_client::CompactTxStreamerClient, TxFilter,
    };

    let channel = match Endpoint::from_shared(lightwalletd_url.to_string())
        .and_then(|e| e.tls_config(ClientTlsConfig::new().with_webpki_roots()))
    {
        Ok(e) => match e.connect().await {
            Ok(c) => c,
            Err(e) => { log::warn!("txtrack: gRPC connect failed: {e}"); return -1; }
        },
        Err(e) => { log::warn!("txtrack: endpoint error: {e}"); return -1; }
    };

    let mut client = CompactTxStreamerClient::new(channel);

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

fn zip317_helper<DbT: InputSource>(
    change_memo: Option<MemoBytes>,
) -> (MultiOutputChangeStrategy<StandardFeeRule, DbT>, GreedyInputSelector<DbT>) {
    (
        MultiOutputChangeStrategy::new(
            StandardFeeRule::Zip317, change_memo, ShieldedProtocol::Orchard,
            DustOutputPolicy::default(),
            SplitPolicy::with_min_output_value(NonZeroUsize::new(4).unwrap(), Zatoshis::const_from_u64(1000_0000)),
        ),
        GreedyInputSelector::new(),
    )
}
