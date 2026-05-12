use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

use incrementalmerkletree::Position;
use prost::Message;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::{
    data_api::{Account, WalletRead},
    proto::service::TreeState,
};
use zcash_protocol::consensus::{BlockHeight, BranchId, NetworkConstants, Parameters};

use crate::wallet::{
    keys::parse_account_uuid, network::WalletNetwork, sync::open_wallet_db_for_read,
};

use super::{
    bundle::{select_notes_with_lwd, voting_power, SelectedNotes},
    hotkey::derive_hotkey_raw_orchard_address,
    state::{ensure_voting_round, open_voting_db},
};

#[derive(Clone, Debug, PartialEq, Eq)]
/// Internal progress phases for delegation PCZT build/prove/sign/broadcast.
pub enum ProofEvent {
    SelectingNotes,
    BuildingPczt,
    BuildingProof,
    SigningPczt,
    Broadcasting,
    Done { txid_hex: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Completed delegation bundle plus broadcast/storage status.
pub struct SignedDelegation {
    pub pczt_bytes: Vec<u8>,
    pub txid_hex: String,
    pub status: String,
    pub message: Option<String>,
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub spend_auth_sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub vote_round_id: String,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Result of preparing bundle rows for a voting round.
pub struct BundleSetupResult {
    pub bundle_count: u32,
    pub eligible_weight_zatoshi: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationPirPrecomputeResult {
    pub cached_count: u32,
    pub fetched_count: u32,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct PreparedDelegationKey {
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    hotkey_raw_address: Vec<u8>,
}

static PREPARED_DELEGATION_PCZTS: OnceLock<
    Mutex<HashMap<PreparedDelegationKey, zcash_voting::GovernancePczt>>,
> = OnceLock::new();

fn prepared_pczt_cache(
) -> &'static Mutex<HashMap<PreparedDelegationKey, zcash_voting::GovernancePczt>> {
    PREPARED_DELEGATION_PCZTS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Clone, Debug)]
struct RoundContext {
    snapshot_height: u64,
    round_name: String,
}

fn short_hex(bytes: &[u8]) -> String {
    let prefix_len = bytes.len().min(8);
    let mut value = hex::encode(&bytes[..prefix_len]);
    if bytes.len() > prefix_len {
        value.push_str("...");
    }
    value
}

/// Initialize the local voting database for delegation operations.
pub fn prepare_delegation(db_path: &str, wallet_id: &str) -> Result<(), String> {
    open_voting_db(db_path, wallet_id).map(|_| ())
}

#[allow(clippy::too_many_arguments)]
/// Select notes and create/reuse delegation bundle rows for a round.
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
pub async fn precompute_delegation_pir(
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
) -> Result<DelegationPirPrecomputeResult, String> {
    let started = std::time::Instant::now();
    let seed = SecretVec::new(seed_bytes.to_vec());
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id.clone();

    let selected = select_notes_with_lwd(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        round_context.snapshot_height,
    )
    .await?;
    let note_infos = selected.voting_note_infos();
    let bundle_setup = ensure_bundles(&voting_db, &round_id, &note_infos)?;
    if bundle_setup.bundle_count == 0 {
        return Err("No eligible voting bundles were created for PIR precompute".to_string());
    }
    validate_bundle_index(bundle_setup.bundle_count, bundle_index)?;
    let bundle_note_infos = bundle_notes(&note_infos, bundle_index)?;

    store_and_generate_witnesses(
        db_path,
        network,
        &voting_db,
        &round_id,
        bundle_index,
        &selected,
        &bundle_note_infos,
    )?;

    let account = load_account_for_delegation(db_path, network, account_uuid)?;
    let hotkey_raw_address =
        derive_hotkey_raw_orchard_address(&seed, &round_id, account_uuid, network)?;
    let branch_height = current_chain_height(lightwalletd_url).await?;
    let branch_id = consensus_branch_id(network, branch_height)?;
    let governance_pczt = build_paired_governance_pczt(
        &voting_db,
        &round_id,
        account_uuid,
        bundle_index,
        &bundle_note_infos,
        &account,
        &hotkey_raw_address,
        branch_id,
        network,
        &round_context.round_name,
    )?;

    let prepared_key = PreparedDelegationKey {
        db_path: db_path.to_string(),
        account_uuid: account_uuid.to_string(),
        round_id: round_id.clone(),
        bundle_index,
        hotkey_raw_address: hotkey_raw_address.clone(),
    };
    prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?
        .insert(prepared_key, governance_pczt);

    let proof_db_path = db_path.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = bundle_note_infos.clone();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_network_id = network.voting_id().into();
    let precompute = tokio::task::spawn_blocking(move || {
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        proof_voting_db
            .precompute_delegation_pir(
                &proof_round_id,
                bundle_index,
                &proof_bundle_note_infos,
                &pir_client,
                proof_network_id,
            )
            .map_err(|e| format!("precompute_delegation_pir failed: {e}"))
    })
    .await
    .map_err(|e| format!("delegation PIR precompute task failed: {e}"))??;

    log::info!(
        "voting delegation: PIR precompute completed \
         (round_id={}, account_uuid={}, bundle_index={}, cached={}, fetched={}, elapsed={:.2}s)",
        round_id,
        account_uuid,
        bundle_index,
        precompute.cached_count,
        precompute.fetched_count,
        started.elapsed().as_secs_f64()
    );

    Ok(DelegationPirPrecomputeResult {
        cached_count: precompute.cached_count,
        fetched_count: precompute.fetched_count,
        bundle_count: bundle_setup.bundle_count,
        bundle_index,
    })
}

#[allow(clippy::too_many_arguments)]
/// Build, prove, sign, broadcast, and locally store one delegation bundle.
///
/// Broadcast is attempted before local transaction storage. If broadcast succeeds
/// but storage fails, the returned status tells callers not to retry the bundle.
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
    let round_id = round_params.vote_round_id.clone();

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

    let bundle_setup = ensure_bundles(&voting_db, &round_id, &note_infos)?;
    if bundle_setup.bundle_count == 0 {
        return Err("No eligible voting bundles were created for delegation".to_string());
    }
    validate_bundle_index(bundle_setup.bundle_count, bundle_index)?;
    let bundle_note_infos = bundle_notes(&note_infos, bundle_index)?;
    let delegated_weight_zatoshi = bundle_weight_zatoshi(&bundle_note_infos)?;
    let note_debug = bundle_note_infos
        .iter()
        .enumerate()
        .map(|(idx, note)| {
            format!(
                "#{idx}:pos={} value={} cmx={} nf={}",
                note.position,
                note.value,
                short_hex(&note.commitment),
                short_hex(&note.nullifier)
            )
        })
        .collect::<Vec<_>>()
        .join(", ");
    log::info!(
        "voting delegation: preparing bundle \
         (round_id={}, account_uuid={}, bundle_index={}, bundle_count={}, \
         note_count={}, delegated_weight_zatoshi={}, notes=[{}])",
        round_id,
        account_uuid,
        bundle_index,
        bundle_setup.bundle_count,
        bundle_note_infos.len(),
        delegated_weight_zatoshi,
        note_debug
    );

    store_and_generate_witnesses(
        db_path,
        network,
        &voting_db,
        &round_id,
        bundle_index,
        &selected,
        &bundle_note_infos,
    )?;

    on_progress(ProofEvent::BuildingPczt);
    let account = load_account_for_delegation(db_path, network, account_uuid)?;
    let hotkey_raw_address =
        derive_hotkey_raw_orchard_address(&seed, &round_id, account_uuid, network)?;
    let branch_height = current_chain_height(lightwalletd_url).await?;
    let branch_id = consensus_branch_id(network, branch_height)?;
    log::info!(
        "voting delegation: selected consensus branch \
         (network={:?}, branch_height={}, branch_id=0x{:08x})",
        network,
        branch_height,
        branch_id
    );
    let prepared_key = PreparedDelegationKey {
        db_path: db_path.to_string(),
        account_uuid: account_uuid.to_string(),
        round_id: round_id.clone(),
        bundle_index,
        hotkey_raw_address: hotkey_raw_address.clone(),
    };
    let prepared_governance_pczt = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?
        .remove(&prepared_key);
    let governance_pczt = if let Some(governance_pczt) = prepared_governance_pczt {
        log::info!(
            "voting delegation: using precomputed governance PCZT \
             (round_id={}, account_uuid={}, bundle_index={})",
            round_id,
            account_uuid,
            bundle_index
        );
        governance_pczt
    } else {
        build_paired_governance_pczt(
            &voting_db,
            &round_id,
            account_uuid,
            bundle_index,
            &bundle_note_infos,
            &account,
            &hotkey_raw_address,
            branch_id,
            network,
            &round_context.round_name,
        )?
    };
    log::info!(
        "voting delegation: built governance PCZT \
         (round_id={}, account_uuid={}, bundle_index={}, action_index={}, \
         pczt_bytes={}, sighash={}, nf_signed={}, cmx_new={}, rk={}, alpha={}, \
         rseed_signed={}, rseed_output={})",
        round_id,
        account_uuid,
        bundle_index,
        governance_pczt.action_index,
        governance_pczt.pczt_bytes.len(),
        short_hex(&governance_pczt.pczt_sighash),
        short_hex(&governance_pczt.nf_signed),
        short_hex(&governance_pczt.cmx_new),
        short_hex(&governance_pczt.rk),
        short_hex(&governance_pczt.alpha),
        short_hex(&governance_pczt.rseed_signed),
        short_hex(&governance_pczt.rseed_output)
    );

    on_progress(ProofEvent::BuildingProof);
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = bundle_note_infos.clone();
    let proof_hotkey_raw_address = hotkey_raw_address.clone();
    let proof_network_id = network.voting_id().into();
    log::info!(
        "voting delegation: starting proof task \
         (round_id={}, account_uuid={}, bundle_index={}, network_id={}, \
         hotkey_raw_address={}, expected_nf_signed={}, expected_cmx_new={})",
        round_id,
        account_uuid,
        bundle_index,
        proof_network_id,
        short_hex(&hotkey_raw_address),
        short_hex(&governance_pczt.nf_signed),
        short_hex(&governance_pczt.cmx_new)
    );
    tokio::task::spawn_blocking(move || {
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        let reporter = zcash_voting::NoopProgressReporter;
        proof_voting_db
            .build_and_prove_delegation(
                &proof_round_id,
                bundle_index,
                &proof_bundle_note_infos,
                &proof_hotkey_raw_address,
                &pir_client,
                proof_network_id,
                &reporter,
            )
            .map(|_| ())
            .map_err(|e| format!("build_and_prove_delegation failed: {e}"))
    })
    .await
    .map_err(|e| format!("delegation proof task failed: {e}"))??;
    log::info!(
        "voting delegation: proof task completed \
         (round_id={}, account_uuid={}, bundle_index={})",
        round_id,
        account_uuid,
        bundle_index
    );

    on_progress(ProofEvent::SigningPczt);
    let submission = voting_db
        .get_delegation_submission(
            &round_id,
            bundle_index,
            seed.expose_secret(),
            network.voting_id().into(),
            account.account_index,
        )
        .map_err(|e| format!("get_delegation_submission failed: {e}"))?;

    on_progress(ProofEvent::Done {
        txid_hex: String::new(),
    });
    Ok(SignedDelegation {
        pczt_bytes: governance_pczt.pczt_bytes,
        txid_hex: String::new(),
        status: "ready_for_submission".to_string(),
        message: None,
        proof: submission.proof,
        rk: submission.rk,
        spend_auth_sig: submission.spend_auth_sig,
        sighash: submission.sighash,
        nf_signed: submission.nf_signed,
        cmx_new: submission.cmx_new,
        gov_comm: submission.gov_comm,
        gov_nullifiers: submission.gov_nullifiers,
        vote_round_id: submission.vote_round_id,
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

fn governance_pczt_output_paired_with_signed_action(
    governance_pczt: &zcash_voting::GovernancePczt,
) -> Result<bool, String> {
    let pczt = pczt::Pczt::parse(&governance_pczt.pczt_bytes)
        .map_err(|e| format!("failed to parse governance PCZT: {e:?}"))?;
    let action = pczt
        .orchard()
        .actions()
        .get(governance_pczt.action_index)
        .ok_or_else(|| {
            format!(
                "governance PCZT action_index {} is out of range for {} actions",
                governance_pczt.action_index,
                pczt.orchard().actions().len()
            )
        })?;

    Ok(action.output().cmx().as_slice() == governance_pczt.cmx_new.as_slice())
}

#[allow(clippy::too_many_arguments)]
fn build_paired_governance_pczt(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    account_uuid: &str,
    bundle_index: u32,
    bundle_note_infos: &[zcash_voting::NoteInfo],
    account: &DelegationAccount,
    hotkey_raw_address: &[u8],
    branch_id: u32,
    network: WalletNetwork,
    round_name: &str,
) -> Result<zcash_voting::GovernancePczt, String> {
    let mut last_unpaired = None;
    for attempt in 1..=16 {
        let candidate = voting_db
            .build_governance_pczt(
                round_id,
                bundle_index,
                bundle_note_infos,
                &account.orchard_fvk_bytes,
                hotkey_raw_address,
                branch_id,
                network.network_type().coin_type(),
                &account.seed_fingerprint,
                account.account_index,
                round_name,
                0,
            )
            .map_err(|e| format!("build_governance_pczt failed: {e}"))?;
        if governance_pczt_output_paired_with_signed_action(&candidate)? {
            if attempt > 1 {
                log::info!(
                    "voting delegation: rebuilt governance PCZT after unpaired action layout \
                     (round_id={}, account_uuid={}, bundle_index={}, attempts={})",
                    round_id,
                    account_uuid,
                    bundle_index,
                    attempt
                );
            }
            return Ok(candidate);
        }
        last_unpaired = Some(candidate);
    }

    let action_index = last_unpaired
        .as_ref()
        .map(|pczt| pczt.action_index.to_string())
        .unwrap_or_else(|| "unknown".to_string());
    Err(format!(
        "build_governance_pczt produced unpaired governance output after 16 attempts \
         (last action_index={action_index})"
    ))
}

/// Return the stored bundle count for `round_id`.
pub fn get_bundle_count(db_path: &str, wallet_id: &str, round_id: &str) -> Result<u32, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))
}

/// Delete bundle rows at or above `keep_count`.
///
/// Used by partial-bundle recovery when the user elects not to delegate later
/// bundles. Returns the number of deleted rows.
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

/// Store and verify the transaction hash for one delegation bundle row.
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

/// Load the transaction hash for one delegation bundle row, if present.
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
        account_index: u32::from(derivation.account_index()),
        orchard_fvk_bytes: orchard_fvk.to_bytes(),
        seed_fingerprint: derivation.seed_fingerprint().to_bytes(),
    })
}

async fn current_chain_height(lightwalletd_url: &str) -> Result<u64, String> {
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let tip = crate::wallet::sync_engine::get_latest_block(&mut client)
        .await
        .map_err(|e| e.to_string())?;
    Ok(tip.height)
}

fn consensus_branch_id(network: WalletNetwork, height: u64) -> Result<u32, String> {
    let height = u32::try_from(height)
        .map(BlockHeight::from_u32)
        .map_err(|_| format!("chain height {height} does not fit in u32"))?;
    Ok(u32::from(BranchId::for_height(&network, height)))
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
    fn consensus_branch_id_follows_network_height() {
        assert_eq!(
            consensus_branch_id(WalletNetwork::Main, 3_146_399).unwrap(),
            0xC8E7_1055
        );
        assert_eq!(
            consensus_branch_id(WalletNetwork::Main, 3_146_400).unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            consensus_branch_id(WalletNetwork::Test, 3_536_500).unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            consensus_branch_id(WalletNetwork::Regtest, 1).unwrap(),
            0x4DEC_4DF0
        );
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
