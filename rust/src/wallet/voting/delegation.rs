use std::sync::Arc;

use incrementalmerkletree::Position;
use prost::Message;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::{
    data_api::{Account, WalletRead},
    proto::service::TreeState,
};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_protocol::consensus::{BlockHeight, NetworkConstants, Parameters};

use crate::wallet::{
    db::with_wallet_db_write_lock,
    keys::parse_account_uuid,
    network::WalletNetwork,
    sync::{open_wallet_db, open_wallet_db_for_read},
};

use super::{
    bundle::{select_notes_with_lwd, voting_power, SelectedNotes},
    hotkey::derive_hotkey_raw_orchard_address,
    state::{ensure_voting_round, open_voting_db},
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProofEvent {
    SelectingNotes,
    BuildingPczt,
    BuildingProof,
    SigningPczt,
    Broadcasting,
    Done { txid_hex: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedDelegation {
    pub pczt_bytes: Vec<u8>,
    pub txid_hex: String,
    pub status: String,
    pub message: Option<String>,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BundleSetupResult {
    pub bundle_count: u32,
    pub eligible_weight_zatoshi: u64,
}

#[derive(Clone, Debug)]
struct RoundContext {
    snapshot_height: u64,
    round_name: String,
}

#[derive(Clone, Debug)]
struct DelegationBroadcastResult {
    txid_hex: String,
    status: String,
    message: Option<String>,
}

impl DelegationBroadcastResult {
    const BROADCASTED: &'static str = "broadcasted";
    const BROADCAST_UNKNOWN: &'static str = "broadcast_unknown";
    const BROADCASTED_STORAGE_FAILED: &'static str = "broadcasted_storage_failed";

    fn broadcasted(txid_hex: String) -> Self {
        Self {
            txid_hex,
            status: Self::BROADCASTED.to_string(),
            message: None,
        }
    }

    fn broadcast_unknown(txid_hex: String, message: String) -> Self {
        Self {
            txid_hex,
            status: Self::BROADCAST_UNKNOWN.to_string(),
            message: Some(message),
        }
    }

    fn broadcasted_storage_failed(txid_hex: String, message: String) -> Self {
        Self {
            txid_hex,
            status: Self::BROADCASTED_STORAGE_FAILED.to_string(),
            message: Some(message),
        }
    }
}

pub fn prepare_delegation(db_path: &str, wallet_id: &str) -> Result<(), String> {
    open_voting_db(db_path, wallet_id).map(|_| ())
}

#[allow(clippy::too_many_arguments)]
pub async fn setup_delegation_bundles(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    account_uuid: &str,
) -> Result<BundleSetupResult, String> {
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let selected = select_notes_with_lwd(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        round_context.snapshot_height,
    )
    .await?;
    let note_infos = selected.voting_note_infos();
    ensure_bundles(&voting_db, round_params.vote_round_id.as_str(), &note_infos)
}

#[allow(clippy::too_many_arguments)]
pub async fn build_and_prove_delegation_bundle<F>(
    db_path: &str,
    lightwalletd_url: &str,
    pir_server_url: &str,
    network: WalletNetwork,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    account_uuid: &str,
    seed_bytes: &[u8],
    bundle_index: u32,
    on_progress: F,
) -> Result<SignedDelegation, String>
where
    F: Fn(ProofEvent) + Send + Sync + 'static,
{
    let seed = SecretVec::new(seed_bytes.to_vec());
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id.as_str();

    on_progress(ProofEvent::SelectingNotes);
    let selected = select_notes_with_lwd(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        round_context.snapshot_height,
    )
    .await?;
    let note_infos = selected.voting_note_infos();
    let selected_weight_zatoshi = voting_power(&selected);

    let bundle_setup = ensure_bundles(&voting_db, round_id, &note_infos)?;
    if bundle_setup.bundle_count == 0 {
        return Err("No eligible voting bundles were created for delegation".to_string());
    }
    validate_bundle_index(bundle_setup.bundle_count, bundle_index)?;
    let bundle_note_infos = bundle_notes(&note_infos, bundle_index)?;
    let delegated_weight_zatoshi = bundle_weight_zatoshi(&bundle_note_infos)?;

    store_and_generate_witnesses(
        db_path,
        network,
        &voting_db,
        round_id,
        bundle_index,
        &selected,
        &bundle_note_infos,
    )?;

    on_progress(ProofEvent::BuildingPczt);
    let account = load_account_for_delegation(db_path, network, account_uuid)?;
    let hotkey_raw_address =
        derive_hotkey_raw_orchard_address(&seed, round_id, account_uuid, network)?;
    let governance_pczt = voting_db
        .build_governance_pczt(
            round_id,
            bundle_index,
            &bundle_note_infos,
            &account.orchard_fvk_bytes,
            &hotkey_raw_address,
            consensus_branch_id(network),
            network.network_type().coin_type(),
            &account.seed_fingerprint,
            account.account_index,
            &round_context.round_name,
            0,
        )
        .map_err(|e| format!("build_governance_pczt failed: {e}"))?;

    let pir_client = zcash_voting::PirClientBlocking::with_transport(
        pir_server_url,
        Arc::new(zcash_voting::HyperTransport::new()),
    )
    .map_err(|e| format!("connect to PIR server failed: {e}"))?;

    on_progress(ProofEvent::BuildingProof);
    let reporter = zcash_voting::NoopProgressReporter;
    voting_db
        .build_and_prove_delegation(
            round_id,
            bundle_index,
            &bundle_note_infos,
            &hotkey_raw_address,
            &pir_client,
            network.voting_id().into(),
            &reporter,
        )
        .map_err(|e| format!("build_and_prove_delegation failed: {e}"))?;

    let pczt_with_proofs = add_delegation_proof_to_pczt(&governance_pczt.pczt_bytes)?;

    on_progress(ProofEvent::SigningPczt);
    let signed_pczt = sign_delegation_pczt(
        &pczt_with_proofs,
        &seed,
        network,
        account.account_id,
        governance_pczt.action_index,
    )?;

    on_progress(ProofEvent::Broadcasting);
    let mut broadcast =
        extract_broadcast_store_delegation_pczt(db_path, lightwalletd_url, network, &signed_pczt)
            .await?;

    if broadcast.status == DelegationBroadcastResult::BROADCASTED
        || broadcast.status == DelegationBroadcastResult::BROADCASTED_STORAGE_FAILED
        || broadcast.status == DelegationBroadcastResult::BROADCAST_UNKNOWN
    {
        record_delegation_tx_hash(&voting_db, round_id, bundle_index, &mut broadcast);
    }

    on_progress(ProofEvent::Done {
        txid_hex: broadcast.txid_hex.clone(),
    });
    Ok(SignedDelegation {
        pczt_bytes: signed_pczt,
        txid_hex: broadcast.txid_hex,
        status: broadcast.status,
        message: broadcast.message,
        eligible_weight_zatoshi: bundle_setup
            .eligible_weight_zatoshi
            .min(selected_weight_zatoshi),
        delegated_weight_zatoshi,
        bundle_count: bundle_setup.bundle_count,
        bundle_index,
    })
}

fn ensure_round_initialized(
    voting_db: &zcash_voting::storage::VotingDb,
    round_params: &zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
) -> Result<RoundContext, String> {
    let state = ensure_voting_round(voting_db, round_params, session_json)?;
    let round_name = if round_name.is_empty() {
        round_params.vote_round_id.clone()
    } else {
        round_name.to_string()
    };
    Ok(RoundContext {
        snapshot_height: state.snapshot_height,
        round_name,
    })
}

fn ensure_bundles(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    notes: &[zcash_voting::NoteInfo],
) -> Result<BundleSetupResult, String> {
    match voting_db.get_bundle_count(round_id) {
        Ok(count) if count > 0 => {
            let chunks = zcash_voting::chunk_notes(notes);
            Ok(BundleSetupResult {
                bundle_count: count,
                eligible_weight_zatoshi: chunks.eligible_weight,
            })
        }
        _ => voting_db
            .setup_bundles(round_id, notes)
            .map(|(count, weight)| BundleSetupResult {
                bundle_count: count,
                eligible_weight_zatoshi: weight,
            })
            .map_err(|e| format!("setup_bundles failed: {e}")),
    }
}

fn validate_bundle_index(bundle_count: u32, bundle_index: u32) -> Result<(), String> {
    if bundle_index < bundle_count {
        Ok(())
    } else {
        Err(format!(
            "bundle_index {bundle_index} is out of range for {bundle_count} delegation bundles"
        ))
    }
}

fn bundle_notes(
    notes: &[zcash_voting::NoteInfo],
    bundle_index: u32,
) -> Result<Vec<zcash_voting::NoteInfo>, String> {
    let chunks = zcash_voting::chunk_notes(notes);
    chunks
        .bundles
        .get(bundle_index as usize)
        .cloned()
        .ok_or_else(|| format!("bundle_index {bundle_index} has no eligible note bundle"))
}

fn bundle_weight_zatoshi(notes: &[zcash_voting::NoteInfo]) -> Result<u64, String> {
    let total = notes.iter().try_fold(0u64, |acc, note| {
        acc.checked_add(note.value)
            .ok_or_else(|| "delegation bundle weight overflows u64".to_string())
    })?;
    Ok((total / zcash_voting::governance::BALLOT_DIVISOR)
        * zcash_voting::governance::BALLOT_DIVISOR)
}

pub fn get_bundle_count(db_path: &str, wallet_id: &str, round_id: &str) -> Result<u32, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))
}

pub fn delete_skipped_bundles(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    keep_count: u32,
) -> Result<u32, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .delete_skipped_bundles(round_id, keep_count)
        .and_then(|deleted| {
            u32::try_from(deleted).map_err(|_| zcash_voting::VotingError::Internal {
                message: format!("deleted bundle count {deleted} does not fit in u32"),
            })
        })
        .map_err(|e| format!("delete_skipped_bundles failed: {e}"))
}

pub fn store_delegation_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .store_delegation_tx_hash(round_id, bundle_index, tx_hash)
        .map_err(|e| format!("store_delegation_tx_hash failed: {e}"))?;
    match voting_db
        .get_delegation_tx_hash(round_id, bundle_index)
        .map_err(|e| format!("get_delegation_tx_hash failed after store: {e}"))?
    {
        Some(stored) if stored == tx_hash => Ok(()),
        Some(stored) => Err(format!(
            "stored tx hash {stored} did not match requested tx hash {tx_hash}"
        )),
        None => Err(format!(
            "no delegation bundle row found for bundle_index {bundle_index}"
        )),
    }
}

pub fn get_delegation_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
) -> Result<Option<String>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_delegation_tx_hash(round_id, bundle_index)
        .map_err(|e| format!("get_delegation_tx_hash failed: {e}"))
}

fn record_delegation_tx_hash(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    broadcast: &mut DelegationBroadcastResult,
) {
    let storage_result = voting_db
        .store_delegation_tx_hash(round_id, bundle_index, &broadcast.txid_hex)
        .map_err(|e| e.to_string())
        .and_then(|_| {
            voting_db
                .get_delegation_tx_hash(round_id, bundle_index)
                .map_err(|e| e.to_string())
        })
        .and_then(|stored| match stored {
            Some(stored) if stored == broadcast.txid_hex => Ok(()),
            Some(stored) => Err(format!(
                "stored tx hash {stored} did not match broadcast txid {}",
                broadcast.txid_hex
            )),
            None => Err(format!(
                "no delegation bundle row found for bundle_index {bundle_index}"
            )),
        });

    if let Err(storage_err) = storage_result {
        let message = format!(
            "Delegation broadcast status={} for txid={} but VotingDb hash storage failed: {storage_err}. \
             Do not retry until sync or recovery confirms the transaction state.",
            broadcast.status, broadcast.txid_hex
        );
        log::error!("{message}");
        if broadcast.status == DelegationBroadcastResult::BROADCASTED {
            broadcast.status = DelegationBroadcastResult::BROADCASTED_STORAGE_FAILED.to_string();
        }
        broadcast.message = Some(match broadcast.message.take() {
            Some(existing) => format!("{existing} {message}"),
            None => message,
        });
    }
}

fn store_and_generate_witnesses(
    db_path: &str,
    network: WalletNetwork,
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    selected: &SelectedNotes,
    notes: &[zcash_voting::NoteInfo],
) -> Result<(), String> {
    voting_db
        .store_tree_state(round_id, &selected.anchor_tree_state.encode_to_vec())
        .map_err(|e| format!("store_tree_state failed: {e}"))?;
    let witnesses = generate_note_witnesses(db_path, network, voting_db, round_id, notes)?;
    voting_db
        .store_witnesses(round_id, bundle_index, &witnesses)
        .map_err(|e| format!("store_witnesses failed: {e}"))
}

fn generate_note_witnesses(
    db_path: &str,
    network: WalletNetwork,
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    notes: &[zcash_voting::NoteInfo],
) -> Result<Vec<zcash_voting::WitnessData>, String> {
    let (tree_state_bytes, params) = {
        let wallet_id = voting_db.wallet_id();
        let conn = voting_db.conn();
        let tree_state_bytes =
            zcash_voting::storage::queries::load_tree_state(&conn, round_id, &wallet_id)
                .map_err(|e| format!("load_tree_state failed: {e}"))?;
        let params = zcash_voting::storage::queries::load_round_params(&conn, round_id, &wallet_id)
            .map_err(|e| format!("load_round_params failed: {e}"))?;
        (tree_state_bytes, params)
    };

    let tree_state = TreeState::decode(tree_state_bytes.as_slice())
        .map_err(|e| format!("failed to decode TreeState protobuf: {e}"))?;
    let orchard_ct = tree_state
        .orchard_tree()
        .map_err(|e| format!("failed to parse orchard tree from TreeState: {e}"))?;
    let frontier_root_bytes = orchard_ct.root().to_bytes();
    validate_cached_tree_state_for_round(&tree_state, &frontier_root_bytes[..], &params)?;
    let frontier = orchard_ct.to_frontier();
    let nonempty_frontier = frontier
        .take()
        .ok_or_else(|| "empty orchard frontier at snapshot height".to_string())?;

    let positions: Vec<Position> = notes
        .iter()
        .map(|note| Position::from(note.position))
        .collect();
    let snapshot_height = u32::try_from(params.snapshot_height).map_err(|_| {
        format!(
            "snapshot_height {} does not fit in u32",
            params.snapshot_height
        )
    })?;
    let wallet_db = open_wallet_db_for_read(db_path, network)?;
    let merkle_paths = wallet_db
        .generate_orchard_witnesses_at_historical_height(
            &positions,
            nonempty_frontier,
            BlockHeight::from_u32(snapshot_height),
        )
        .map_err(|e| format!("generate_orchard_witnesses_at_historical_height failed: {e}"))?;

    if merkle_paths.len() != notes.len() {
        return Err(format!(
            "generated {} Merkle paths for {} voting notes",
            merkle_paths.len(),
            notes.len()
        ));
    }

    let root = frontier_root_bytes.to_vec();
    Ok(merkle_paths
        .into_iter()
        .zip(notes.iter())
        .map(|(path, note)| zcash_voting::WitnessData {
            note_commitment: note.commitment.clone(),
            position: note.position,
            root: root.clone(),
            auth_path: path
                .path_elems()
                .iter()
                .map(|hash| hash.to_bytes().to_vec())
                .collect(),
        })
        .collect())
}

fn validate_cached_tree_state_for_round(
    tree_state: &TreeState,
    orchard_root: &[u8],
    params: &zcash_voting::VotingRoundParams,
) -> Result<(), String> {
    if tree_state.height != params.snapshot_height {
        return Err(format!(
            "cached TreeState height {} does not match round snapshot_height {}",
            tree_state.height, params.snapshot_height
        ));
    }
    if orchard_root != params.nc_root.as_slice() {
        return Err("cached TreeState orchard root does not match round nc_root".to_string());
    }
    Ok(())
}

#[derive(Clone, Debug)]
struct DelegationAccount {
    account_id: zip32::AccountId,
    account_index: u32,
    orchard_fvk_bytes: [u8; 96],
    seed_fingerprint: [u8; 32],
}

fn load_account_for_delegation(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<DelegationAccount, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_uuid = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_uuid)
        .map_err(|e| format!("Failed to load voting account: {e}"))?
        .ok_or_else(|| "Voting account not found".to_string())?;
    let derivation = account
        .source()
        .key_derivation()
        .ok_or_else(|| "Voting account has no ZIP-32 derivation metadata".to_string())?;
    let ufvk = account
        .ufvk()
        .ok_or_else(|| "Voting account has no UFVK".to_string())?;
    let orchard_fvk = ufvk
        .orchard()
        .ok_or_else(|| "Voting account has no Orchard viewing key".to_string())?;
    Ok(DelegationAccount {
        account_id: derivation.account_index(),
        account_index: u32::from(derivation.account_index()),
        orchard_fvk_bytes: orchard_fvk.to_bytes(),
        seed_fingerprint: derivation.seed_fingerprint().to_bytes(),
    })
}

fn add_delegation_proof_to_pczt(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    use pczt::roles::prover::Prover;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    let mut prover = Prover::new(pczt);
    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(&orchard::circuit::ProvingKey::build())
            .map_err(|e| format!("Orchard proof: {e:?}"))?;
    }
    if prover.requires_sapling_proofs() {
        return Err("Delegation PCZT unexpectedly requires Sapling proofs".to_string());
    }
    Ok(prover.finish().serialize())
}

fn sign_delegation_pczt(
    pczt_bytes: &[u8],
    seed: &SecretVec<u8>,
    network: WalletNetwork,
    account_id: zip32::AccountId,
    action_index: usize,
) -> Result<Vec<u8>, String> {
    use pczt::roles::signer::Signer;

    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), account_id)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;
    let ask = orchard::keys::SpendAuthorizingKey::from(usk.orchard());
    let mut signer = Signer::new(
        pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT for signing: {e:?}"))?,
    )
    .map_err(|e| format!("Create PCZT signer: {e:?}"))?;
    signer
        .sign_orchard(action_index, &ask)
        .map_err(|e| format!("Sign delegation PCZT Orchard action: {e:?}"))?;
    Ok(signer.finish().serialize())
}

async fn extract_broadcast_store_delegation_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    signed_pczt_bytes: &[u8],
) -> Result<DelegationBroadcastResult, String> {
    let (tx, tx_bytes, txid) = extract_transaction_from_signed_delegation_pczt(signed_pczt_bytes)?;
    let store_locally =
        || store_delegation_pczt_locally(db_path, network, signed_pczt_bytes, &tx, &txid);

    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let resp = match crate::wallet::sync_engine::send_transaction_with_status(
        &mut client,
        &tx_bytes,
    )
    .await
    {
        Ok(resp) => resp,
        Err(status) if status.code() == tonic::Code::DeadlineExceeded => {
            let mut message = format!(
                "Delegation broadcast response timed out for txid={txid}. The transaction may \
                 already be on the network. Do not retry until sync or an explorer confirms it."
            );
            if let Err(storage_err) = store_locally() {
                message.push_str(&format!(" Local tracking also failed: {storage_err}."));
            }
            return Ok(DelegationBroadcastResult::broadcast_unknown(
                txid.to_string(),
                message,
            ));
        }
        Err(status) => return Err(format!("Broadcast delegation transaction: {status}")),
    };

    if resp.error_code != 0 {
        return Err(format!(
            "Delegation broadcast rejected: {} (code {})",
            resp.error_message, resp.error_code
        ));
    }

    if let Err(storage_err) = store_locally() {
        log::error!(
            "voting delegation: broadcast succeeded but local storage failed \
             (txid={txid}): {storage_err}"
        );
        return Ok(DelegationBroadcastResult::broadcasted_storage_failed(
            txid.to_string(),
            format!(
                "Delegation broadcast succeeded (txid={txid}) but local storage failed. \
                 {storage_err}. The transaction is on the network; do not retry until sync \
                 reconciles wallet state."
            ),
        ));
    }

    Ok(DelegationBroadcastResult::broadcasted(txid.to_string()))
}

fn extract_transaction_from_signed_delegation_pczt(
    signed_pczt_bytes: &[u8],
) -> Result<
    (
        zcash_primitives::transaction::Transaction,
        Vec<u8>,
        zcash_primitives::transaction::TxId,
    ),
    String,
> {
    use pczt::roles::spend_finalizer::SpendFinalizer;
    use pczt::roles::tx_extractor::TransactionExtractor;

    let orchard_vk = orchard::circuit::VerifyingKey::build();
    let finalized = SpendFinalizer::new(
        pczt::Pczt::parse(signed_pczt_bytes)
            .map_err(|e| format!("Parse signed delegation PCZT: {e:?}"))?,
    )
    .finalize_spends()
    .map_err(|e| format!("Finalize delegation PCZT spends: {e:?}"))?;
    let tx = TransactionExtractor::new(finalized)
        .with_orchard(&orchard_vk)
        .extract()
        .map_err(|e| format!("Extract delegation transaction from PCZT: {e:?}"))?;
    let txid = tx.txid();
    let mut tx_bytes = Vec::new();
    tx.write(&mut tx_bytes)
        .map_err(|e| format!("Serialize delegation transaction: {e}"))?;
    Ok((tx, tx_bytes, txid))
}

fn store_delegation_pczt_locally(
    db_path: &str,
    network: WalletNetwork,
    signed_pczt_bytes: &[u8],
    tx: &zcash_primitives::transaction::Transaction,
    txid: &zcash_primitives::transaction::TxId,
) -> Result<(), String> {
    use zcash_client_backend::data_api::wallet::{
        decrypt_and_store_transaction, extract_and_store_transaction_from_pczt,
    };

    let orchard_vk = orchard::circuit::VerifyingKey::build();
    with_wallet_db_write_lock("voting.delegation.store_pczt", || {
        let mut db = open_wallet_db(db_path, network)?;
        match extract_and_store_transaction_from_pczt::<_, zcash_client_sqlite::ReceivedNoteId>(
            &mut db,
            pczt::Pczt::parse(signed_pczt_bytes)
                .map_err(|e| format!("Parse signed delegation PCZT for storage: {e:?}"))?,
            None,
            Some(&orchard_vk),
        ) {
            Ok(_) => Ok(()),
            Err(primary_err) => {
                log::warn!(
                    "voting delegation: PCZT-aware storage failed (txid={txid}): \
                     {primary_err}. Falling back to decrypt_and_store_transaction."
                );
                decrypt_and_store_transaction(&network, &mut db, tx, None).map_err(|fallback_err| {
                    format!("Primary: {primary_err}. Fallback: {fallback_err}")
                })
            }
        }
    })
}

fn consensus_branch_id(network: WalletNetwork) -> u32 {
    network
        .activation_height(zcash_protocol::consensus::NetworkUpgrade::Nu6)
        .map(|_| 0xC8E7_1055)
        .unwrap_or(0xC8E7_1055)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    const ACCOUNT_UUID: &str = "550e8400-e29b-41d4-a716-446655440000";
    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn prepare_delegation_initializes_voting_db_schema() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");

        prepare_delegation(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();

        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        assert!(voting_db.list_rounds().unwrap().is_empty());
    }

    #[test]
    fn build_and_prove_delegation_bundle_rejects_invalid_round_params_before_progress() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let events = Arc::new(Mutex::new(Vec::new()));
        let events_for_callback = events.clone();
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_and_prove_delegation_bundle(
                db_path.to_str().unwrap(),
                "http://127.0.0.1:1",
                "http://127.0.0.1:2",
                WalletNetwork::Regtest,
                zcash_voting::VotingRoundParams {
                    vote_round_id: ROUND_ID.to_string(),
                    snapshot_height: 100,
                    ea_pk: vec![1],
                    nc_root: vec![2; 32],
                    nullifier_imt_root: vec![3; 32],
                },
                "Demo",
                None,
                ACCOUNT_UUID,
                &[7; 32],
                0,
                move |event| events_for_callback.lock().unwrap().push(event),
            ))
            .unwrap_err();

        assert!(err.contains("Invalid voting round params"));
        assert!(events.lock().unwrap().is_empty());
    }

    #[test]
    fn ensure_round_initialized_uses_voting_db_and_round_name_fallback() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();

        let named = ensure_round_initialized(&voting_db, &params, "Demo Round", Some("{}"))
            .expect("round initializes");
        assert_eq!(named.snapshot_height, params.snapshot_height);
        assert_eq!(named.round_name, "Demo Round");

        let existing =
            ensure_round_initialized(&voting_db, &params, "", None).expect("existing round loads");
        assert_eq!(existing.snapshot_height, params.snapshot_height);
        assert_eq!(existing.round_name, ROUND_ID);
        assert_eq!(voting_db.list_rounds().unwrap().len(), 1);
    }

    #[test]
    fn ensure_bundles_creates_once_then_reuses_existing_bundle_count() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();

        let created = ensure_bundles(&voting_db, ROUND_ID, &[test_note_info(42)]).unwrap();
        let reused = ensure_bundles(&voting_db, ROUND_ID, &[]).unwrap();

        assert_eq!(created.bundle_count, 1);
        assert_eq!(
            created.eligible_weight_zatoshi,
            zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(reused.bundle_count, 1);
        assert_eq!(reused.eligible_weight_zatoshi, 0);
    }

    #[test]
    fn ensure_bundles_preserves_multi_bundle_shape() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();

        let setup = ensure_bundles(&voting_db, ROUND_ID, &notes).unwrap();

        assert_eq!(setup.bundle_count, 2);
        assert_eq!(
            setup.eligible_weight_zatoshi,
            6 * zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(voting_db.get_bundle_count(ROUND_ID).unwrap(), 2);
        assert_eq!(
            bundle_weight_zatoshi(&bundle_notes(&notes, 0).unwrap()).unwrap(),
            5 * zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(
            bundle_weight_zatoshi(&bundle_notes(&notes, 1).unwrap()).unwrap(),
            zcash_voting::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn validate_bundle_index_rejects_out_of_range_before_work() {
        assert!(validate_bundle_index(2, 0).is_ok());
        assert!(validate_bundle_index(2, 1).is_ok());
        assert!(validate_bundle_index(2, 2)
            .unwrap_err()
            .contains("out of range"));
    }

    #[test]
    fn bundle_notes_returns_only_requested_bundle() {
        let notes: Vec<_> = (0..6).map(test_note_info).collect();

        let first = bundle_notes(&notes, 0).unwrap();
        let second = bundle_notes(&notes, 1).unwrap();

        assert_eq!(first.len(), 5);
        assert_eq!(second.len(), 1);
        assert_eq!(
            bundle_weight_zatoshi(&first).unwrap(),
            5 * zcash_voting::BALLOT_DIVISOR
        );
        assert_eq!(
            bundle_weight_zatoshi(&second).unwrap(),
            zcash_voting::BALLOT_DIVISOR
        );
        assert!(bundle_notes(&notes, 2).is_err());
    }

    #[test]
    fn record_delegation_tx_hash_persists_successful_broadcast_hash() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        ensure_bundles(&voting_db, ROUND_ID, &[test_note_info(42)]).unwrap();
        let mut broadcast = DelegationBroadcastResult::broadcasted("txid-1".to_string());

        record_delegation_tx_hash(&voting_db, ROUND_ID, 0, &mut broadcast);

        assert_eq!(broadcast.status, DelegationBroadcastResult::BROADCASTED);
        assert!(broadcast.message.is_none());
        assert_eq!(
            voting_db
                .get_delegation_tx_hash(ROUND_ID, 0)
                .unwrap()
                .as_deref(),
            Some("txid-1")
        );
    }

    #[test]
    fn record_delegation_tx_hash_uses_requested_bundle_index() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        ensure_bundles(&voting_db, ROUND_ID, &notes).unwrap();
        let mut broadcast = DelegationBroadcastResult::broadcasted("txid-2".to_string());

        record_delegation_tx_hash(&voting_db, ROUND_ID, 1, &mut broadcast);

        assert_eq!(broadcast.status, DelegationBroadcastResult::BROADCASTED);
        assert_eq!(
            voting_db
                .get_delegation_tx_hash(ROUND_ID, 1)
                .unwrap()
                .as_deref(),
            Some("txid-2")
        );
        assert_eq!(voting_db.get_delegation_tx_hash(ROUND_ID, 0).unwrap(), None);
    }

    #[test]
    fn record_delegation_tx_hash_preserves_non_retry_semantics_on_storage_failure() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let mut broadcast = DelegationBroadcastResult::broadcasted("txid-1".to_string());

        record_delegation_tx_hash(&voting_db, ROUND_ID, 0, &mut broadcast);

        assert_eq!(
            broadcast.status,
            DelegationBroadcastResult::BROADCASTED_STORAGE_FAILED
        );
        assert!(broadcast
            .message
            .as_deref()
            .unwrap()
            .contains("Do not retry"));
    }

    #[test]
    fn delegation_broadcast_result_constructors_set_status_and_message() {
        let accepted = DelegationBroadcastResult::broadcasted("txid-a".to_string());
        assert_eq!(accepted.txid_hex, "txid-a");
        assert_eq!(accepted.status, DelegationBroadcastResult::BROADCASTED);
        assert!(accepted.message.is_none());

        let unknown =
            DelegationBroadcastResult::broadcast_unknown("txid-b".to_string(), "timeout".into());
        assert_eq!(unknown.status, DelegationBroadcastResult::BROADCAST_UNKNOWN);
        assert_eq!(unknown.message.as_deref(), Some("timeout"));

        let storage_failed = DelegationBroadcastResult::broadcasted_storage_failed(
            "txid-c".to_string(),
            "storage failed".into(),
        );
        assert_eq!(
            storage_failed.status,
            DelegationBroadcastResult::BROADCASTED_STORAGE_FAILED
        );
        assert_eq!(storage_failed.message.as_deref(), Some("storage failed"));
    }

    #[test]
    fn store_and_generate_witnesses_rejects_invalid_cached_tree_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let voting_db = open_voting_db(wallet_db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        ensure_bundles(&voting_db, ROUND_ID, &[test_note_info(42)]).unwrap();
        let selected = SelectedNotes {
            notes: Vec::new(),
            snapshot_height: params.snapshot_height,
            anchor_tree_state: TreeState {
                network: "regtest".to_string(),
                height: params.snapshot_height,
                hash: String::new(),
                time: 0,
                sapling_tree: String::new(),
                orchard_tree: String::new(),
            },
        };

        let err = store_and_generate_witnesses(
            wallet_db_path.to_str().unwrap(),
            WalletNetwork::Regtest,
            &voting_db,
            ROUND_ID,
            0,
            &selected,
            &[test_note_info(42)],
        )
        .unwrap_err();

        assert!(err.contains("orchard") || err.contains("TreeState"));
    }

    #[test]
    fn pczt_helpers_reject_invalid_bytes_without_side_effects() {
        let seed = SecretVec::new(vec![7; 32]);

        assert!(add_delegation_proof_to_pczt(b"not a pczt")
            .unwrap_err()
            .contains("Parse PCZT"));
        assert!(sign_delegation_pczt(
            b"not a pczt",
            &seed,
            WalletNetwork::Regtest,
            zip32::AccountId::ZERO,
            0,
        )
        .unwrap_err()
        .contains("Parse PCZT for signing"));
        assert!(
            extract_transaction_from_signed_delegation_pczt(b"not a pczt")
                .unwrap_err()
                .contains("Parse signed delegation PCZT")
        );
    }

    #[test]
    fn broadcast_helper_rejects_invalid_pczt_before_network_or_storage() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(extract_broadcast_store_delegation_pczt(
                db_path.to_str().unwrap(),
                "http://127.0.0.1:1",
                WalletNetwork::Regtest,
                b"not a pczt",
            ))
            .unwrap_err();

        assert!(err.contains("Parse signed delegation PCZT"));
    }

    #[test]
    fn load_account_for_delegation_rejects_uninitialized_wallet_db() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.sqlite");

        let err = load_account_for_delegation(
            db_path.to_str().unwrap(),
            WalletNetwork::Regtest,
            ACCOUNT_UUID,
        )
        .unwrap_err();

        assert!(
            err.contains("Failed to load voting account")
                || err.contains("Voting account not found")
        );
    }

    #[test]
    fn consensus_branch_id_is_nu6_for_supported_networks() {
        assert_eq!(consensus_branch_id(WalletNetwork::Main), 0xC8E7_1055);
        assert_eq!(consensus_branch_id(WalletNetwork::Test), 0xC8E7_1055);
        assert_eq!(consensus_branch_id(WalletNetwork::Regtest), 0xC8E7_1055);
    }

    #[test]
    fn validate_cached_tree_state_checks_height_and_root() {
        let params = zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![0; 32],
            nc_root: vec![7; 32],
            nullifier_imt_root: vec![8; 32],
        };
        let tree_state = TreeState {
            network: "test".to_string(),
            height: 100,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        };

        assert!(validate_cached_tree_state_for_round(&tree_state, &[7; 32], &params).is_ok());
        assert!(
            validate_cached_tree_state_for_round(&tree_state, &[9; 32], &params)
                .unwrap_err()
                .contains("orchard root")
        );

        let stale = TreeState {
            height: 99,
            ..tree_state
        };
        assert!(
            validate_cached_tree_state_for_round(&stale, &[7; 32], &params)
                .unwrap_err()
                .contains("snapshot_height")
        );
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: zcash_voting::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
