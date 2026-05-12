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
    endpoint_validation,
    hotkey::derive_hotkey_raw_orchard_address,
    state::{ensure_voting_round, open_voting_db},
    workflow,
};

/// Internal progress phases for delegation PCZT build/prove/sign/broadcast.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProofEvent {
    SelectingNotes,
    BuildingPczt,
    BuildingProof,
    SigningPczt,
    Broadcasting,
    Done { txid_hex: String },
}

/// Completed delegation bundle plus broadcast/storage status.
#[derive(Clone, Debug, PartialEq, Eq)]
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

/// Result of preparing bundle rows for a voting round.
#[derive(Clone, Debug, PartialEq, Eq)]
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
    branch_id: u32,
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

/// Initializes the local voting database for delegation operations.
///
/// Opens or creates the voting DB scoped to `wallet_id`; returns an error if
/// the DB cannot be opened or migrated.
pub fn prepare_delegation(db_path: &str, wallet_id: &str) -> Result<(), String> {
    open_voting_db(db_path, wallet_id).map(|_| ())
}

/// Select notes and create/reuse delegation bundle rows for a round.
///
/// The selected notes are taken at the round snapshot height. Existing bundle
/// rows are reused only when they match the current eligible note set.
///
/// # Errors
///
/// Returns an error if round initialization, lightwalletd note selection, or
/// bundle setup/validation fails.
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

/// Warms PIR and governance-PCZT state for a single delegation bundle.
///
/// Validates the PIR endpoint against the round snapshot, persists witnesses,
/// caches a branch-specific governance PCZT, and precomputes delegation PIR
/// rows for `bundle_index`.
///
/// # Errors
///
/// Returns an error if the round, endpoint, note selection, bundle index,
/// witness generation, account data, consensus branch, PCZT build, or PIR
/// precompute step fails.
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
    seed: &SecretVec<u8>,
    bundle_index: u32,
) -> Result<DelegationPirPrecomputeResult, String> {
    let started = std::time::Instant::now();
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id.clone();
    let pir_server_url =
        endpoint_validation::validate_pir_endpoint(pir_server_url, network, &round_params).await?;

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
        derive_hotkey_raw_orchard_address(seed, &round_id, account_uuid, network)?;
    let branch_height = current_chain_height(lightwalletd_url).await?;
    let branch_id = consensus_branch_id(network, branch_height)?;
    let governance_pczt = build_paired_governance_pczt(
        &voting_db,
        &round_id,
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
        branch_id,
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
    let proof_pir_server_url = pir_server_url;
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
         (bundle_index={}, cached={}, fetched={}, elapsed={:.2}s)",
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

/// Build, prove, sign, broadcast, and locally store one delegation bundle.
///
/// Emits progress phases through `on_progress`. The returned value is a signed
/// delegation payload ready for submission; `bundle_index` must identify an
/// eligible persisted bundle for this round.
///
/// # Errors
///
/// Returns an error if endpoint validation, note/bundle validation, witness
/// generation, PCZT construction, PIR proof generation, or delegation signing
/// fails.
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
    seed: &SecretVec<u8>,
    bundle_index: u32,
    on_progress: F,
) -> Result<SignedDelegation, String>
where
    F: Fn(ProofEvent) + Send + Sync + 'static,
{
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id.clone();
    let pir_server_url =
        endpoint_validation::validate_pir_endpoint(pir_server_url, network, &round_params).await?;

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
    log::info!(
        "voting delegation: preparing bundle \
         (bundle_index={}, bundle_count={}, note_count={}, delegated_weight_zatoshi={})",
        bundle_index,
        bundle_setup.bundle_count,
        bundle_note_infos.len(),
        delegated_weight_zatoshi
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
        derive_hotkey_raw_orchard_address(seed, &round_id, account_uuid, network)?;
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
        branch_id,
        hotkey_raw_address: hotkey_raw_address.clone(),
    };
    let prepared_governance_pczt = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?
        .remove(&prepared_key);
    let governance_pczt = if let Some(governance_pczt) = prepared_governance_pczt {
        log::info!(
            "voting delegation: using precomputed governance PCZT \
             (bundle_index={})",
            bundle_index
        );
        governance_pczt
    } else {
        build_paired_governance_pczt(
            &voting_db,
            &round_id,
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
         (bundle_index={}, action_index={}, pczt_bytes={})",
        bundle_index,
        governance_pczt.action_index,
        governance_pczt.pczt_bytes.len()
    );

    on_progress(ProofEvent::BuildingProof);
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url;
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = bundle_note_infos.clone();
    let proof_hotkey_raw_address = hotkey_raw_address.clone();
    let proof_network_id = network.voting_id().into();
    log::info!(
        "voting delegation: starting proof task \
         (bundle_index={}, network_id={})",
        bundle_index,
        proof_network_id
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
         (bundle_index={})",
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

/// Ensures the round exists and resolves the display name used in PCZT metadata.
///
/// An empty `round_name` falls back to the round ID. Returns the persisted round
/// snapshot height used for note selection.
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

/// Creates bundle rows for eligible notes or validates existing rows.
///
/// Existing rows are accepted only when current chunking and stored note
/// identities match; this prevents recovery state from drifting from the live
/// note set.
fn ensure_bundles(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    notes: &[zcash_voting::NoteInfo],
) -> Result<BundleSetupResult, String> {
    let stored_count = voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))?;
    if stored_count > 0 {
        let chunks = zcash_voting::chunk_notes(notes);
        if chunks.bundles.len() != stored_count as usize {
            return Err(format!(
                "current note selection produces {} delegation bundles, but {stored_count} \
                 bundle rows are already persisted for round {round_id}",
                chunks.bundles.len()
            ));
        }
        validate_persisted_bundle_notes(voting_db, round_id, &chunks.bundles)?;
        return Ok(BundleSetupResult {
            bundle_count: stored_count,
            eligible_weight_zatoshi: chunks.eligible_weight,
        });
    }

    voting_db
        .setup_bundles(round_id, notes)
        .map(|(count, weight)| BundleSetupResult {
            bundle_count: count,
            eligible_weight_zatoshi: weight,
        })
        .map_err(|e| format!("setup_bundles failed: {e}"))
}

/// Verifies that persisted bundle rows match the current note chunks.
///
/// The check includes stored positions and note identity hashes where available.
fn validate_persisted_bundle_notes(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundles: &[Vec<zcash_voting::NoteInfo>],
) -> Result<(), String> {
    let wallet_id = voting_db.wallet_id();
    let conn = voting_db.conn();
    for (bundle_index, bundle_notes) in bundles.iter().enumerate() {
        zcash_voting::storage::queries::require_bundle_notes(
            &conn,
            round_id,
            &wallet_id,
            bundle_index as u32,
            bundle_notes,
        )
        .map_err(|e| format!("persisted bundle notes do not match current selection: {e}"))?;
    }
    Ok(())
}

/// Validates that `bundle_index` is in `[0, bundle_count)`.
fn validate_bundle_index(bundle_count: u32, bundle_index: u32) -> Result<(), String> {
    if bundle_index < bundle_count {
        Ok(())
    } else {
        Err(format!(
            "bundle_index {bundle_index} is out of range for {bundle_count} delegation bundles"
        ))
    }
}

/// Returns the eligible notes for one chunked delegation bundle.
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

/// Returns the bundle voting weight rounded down to the ballot divisor.
///
/// Fails if summing note values overflows `u64`.
fn bundle_weight_zatoshi(notes: &[zcash_voting::NoteInfo]) -> Result<u64, String> {
    let total = notes.iter().try_fold(0u64, |acc, note| {
        acc.checked_add(note.value)
            .ok_or_else(|| "delegation bundle weight overflows u64".to_string())
    })?;
    Ok((total / zcash_voting::governance::BALLOT_DIVISOR)
        * zcash_voting::governance::BALLOT_DIVISOR)
}

/// Checks whether the PCZT action index points at the governance output.
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

/// Builds a governance PCZT whose signed action is paired with its output.
///
/// Retries randomized PCZT construction to avoid an action/output layout that
/// would make downstream submission ambiguous.
#[allow(clippy::too_many_arguments)]
fn build_paired_governance_pczt(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
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
                     (bundle_index={}, attempts={})",
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

/// Returns the stored bundle count for `round_id`.
///
/// The count is scoped to `wallet_id`; missing rounds return zero through the
/// underlying voting DB query.
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
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, deletion fails, or the
/// deleted row count does not fit in `u32`.
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
///
/// Marks the bundle as submitted in the recovery workflow. The hash is scoped
/// by `(wallet_id, round_id, bundle_index)`.
pub fn store_delegation_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), String> {
    workflow::mark_delegation_submitted(db_path, wallet_id, round_id, bundle_index, tx_hash)
}

/// Load the transaction hash for one delegation bundle row, if present.
///
/// Returns `Ok(None)` when the bundle exists but has not been marked submitted.
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

/// Persists the selected anchor tree state and Merkle witnesses for a bundle.
///
/// The witnesses are generated at the voting round snapshot height.
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

/// Generates Orchard Merkle witnesses for the bundle notes at the round snapshot.
///
/// Validates the cached tree state against the round roots before querying the
/// wallet DB for historical witnesses.
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

/// Validates that cached lightwalletd tree state belongs to the voting round.
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

/// Loads the account metadata required for delegation PCZT construction.
///
/// The account must have ZIP-32 derivation metadata, a UFVK, and an Orchard
/// viewing key. Hardware/imported accounts without those fields are rejected.
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

/// Fetches the current lightwalletd chain height.
async fn current_chain_height(lightwalletd_url: &str) -> Result<u64, String> {
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let tip = crate::wallet::sync_engine::get_latest_block(&mut client)
        .await
        .map_err(|e| e.to_string())?;
    Ok(tip.height)
}

/// Resolves the consensus branch ID active at `height` for `network`.
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
        let seed = SecretVec::new(vec![7; 32]);
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
                &seed,
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
    fn ensure_bundles_creates_once_then_reuses_matching_bundle_rows() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let notes = vec![test_note_info(42)];

        let created = ensure_bundles(&voting_db, ROUND_ID, &notes).unwrap();
        let reused = ensure_bundles(&voting_db, ROUND_ID, &notes).unwrap();

        assert_eq!(created.bundle_count, 1);
        assert_eq!(
            created.eligible_weight_zatoshi,
            zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(reused.bundle_count, 1);
        assert_eq!(
            reused.eligible_weight_zatoshi,
            zcash_voting::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn ensure_bundles_rejects_current_note_selection_drift() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();

        ensure_bundles(&voting_db, ROUND_ID, &[test_note_info(42)]).unwrap();

        let shape_err = ensure_bundles(&voting_db, ROUND_ID, &[]).unwrap_err();
        assert!(shape_err.contains("bundle rows are already persisted"));

        let mut substituted = test_note_info(42);
        substituted.nullifier[0] ^= 0x01;
        let identity_err = ensure_bundles(&voting_db, ROUND_ID, &[substituted]).unwrap_err();
        assert!(identity_err.contains("persisted bundle notes do not match current selection"));
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
