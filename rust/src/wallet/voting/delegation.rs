use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

use prost::Message;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::data_api::{Account, WalletRead};
use zcash_protocol::consensus::{BlockHeight, BranchId, NetworkConstants, Parameters};

use crate::wallet::{
    keys::parse_account_uuid, network::WalletNetwork, sync::open_wallet_db_for_read,
};

use super::{
    bundle::{select_notes_with_lwd, validate_bundle_index, voting_power, SelectedNotes},
    hotkey::derive_hotkey_raw_orchard_address,
    progress::{ProofProgressBridge, VotingWorkCancellation},
    state::{ensure_voting_round, open_voting_db},
    workflow,
};

/// Internal progress phases for preparing a signed delegation payload.
#[derive(Clone, Debug, PartialEq)]
pub enum ProofEvent {
    SelectingNotes,
    BuildingPczt,
    BuildingProof,
    ProofProgress { progress: f64 },
    SigningPayload,
    PayloadReady,
}

/// Signed delegation payload ready for Dart-side submission.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedDelegationPayload {
    pub pczt_bytes: Vec<u8>,
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

/// Result of warming delegation PIR proofs and prepared PCZT material.
///
/// Counts report PIR rows reused from storage versus fetched during this call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationPirPrecomputeResult {
    pub cached_count: u32,
    pub fetched_count: u32,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct PreparedDelegationSessionKey {
    db_path: String,
    account_uuid: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct PreparedDelegationKey {
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    pczt_inputs: PreparedDelegationPcztInputs,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct PreparedDelegationPcztInputs {
    bundle_notes: Vec<PreparedDelegationNoteInput>,
    orchard_fvk_bytes: [u8; 96],
    hotkey_raw_address: Vec<u8>,
    branch_id: u32,
    coin_type: u32,
    seed_fingerprint: [u8; 32],
    account_index: u32,
    round_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct PreparedDelegationNoteInput {
    commitment: Vec<u8>,
    nullifier: Vec<u8>,
    value: u64,
    position: u64,
    diversifier: Vec<u8>,
    rho: Vec<u8>,
    rseed: Vec<u8>,
    scope: u32,
}

struct PreparedDelegationEntry {
    governance_pczt: zcash_voting::GovernancePczt,
    inserted_at: Instant,
}

struct PreparedDelegationSessionEpoch {
    epoch: u64,
    updated_at: Instant,
}

#[derive(Default)]
struct PreparedDelegationCache {
    entries: HashMap<PreparedDelegationKey, PreparedDelegationEntry>,
    session_epochs: HashMap<PreparedDelegationSessionKey, PreparedDelegationSessionEpoch>,
}

const PREPARED_DELEGATION_PCZT_TTL: Duration = Duration::from_secs(15 * 60);
const MAX_PREPARED_DELEGATION_PCZTS: usize = 16;
const MAX_PREPARED_DELEGATION_SESSIONS: usize = 32;

static PREPARED_DELEGATION_PCZTS: OnceLock<Mutex<PreparedDelegationCache>> = OnceLock::new();

/// Returns the process-local prepared delegation PCZT cache.
fn prepared_pczt_cache() -> &'static Mutex<PreparedDelegationCache> {
    PREPARED_DELEGATION_PCZTS.get_or_init(|| Mutex::new(PreparedDelegationCache::default()))
}

/// Builds the session key used for all account-scoped prepared PCZT state.
fn prepared_delegation_session_key(
    db_path: &str,
    account_uuid: &str,
) -> PreparedDelegationSessionKey {
    PreparedDelegationSessionKey {
        db_path: db_path.to_string(),
        account_uuid: account_uuid.to_string(),
    }
}

/// Builds the complete immutable input key for cached governance PCZT material.
///
/// The cache is process-local and short-lived, but reuse must still prove that
/// the precomputed PCZT was built from the same tuple that the live delegation
/// path would pass to `build_governance_pczt`.
fn prepared_delegation_key(
    db_path: &str,
    account_uuid: &str,
    round_id: &str,
    bundle_index: u32,
    bundle_note_infos: &[zcash_voting::NoteInfo],
    account: &DelegationAccount,
    hotkey_raw_address: &[u8],
    branch_id: u32,
    network: WalletNetwork,
    round_name: &str,
) -> PreparedDelegationKey {
    PreparedDelegationKey {
        db_path: db_path.to_string(),
        account_uuid: account_uuid.to_string(),
        round_id: round_id.to_string(),
        bundle_index,
        pczt_inputs: PreparedDelegationPcztInputs {
            bundle_notes: bundle_note_infos
                .iter()
                .map(|note| PreparedDelegationNoteInput {
                    commitment: note.commitment.clone(),
                    nullifier: note.nullifier.clone(),
                    value: note.value,
                    position: note.position,
                    diversifier: note.diversifier.clone(),
                    rho: note.rho.clone(),
                    rseed: note.rseed.clone(),
                    scope: note.scope,
                })
                .collect(),
            orchard_fvk_bytes: account.orchard_fvk_bytes,
            hotkey_raw_address: hotkey_raw_address.to_vec(),
            branch_id,
            coin_type: network.network_type().coin_type(),
            seed_fingerprint: account.seed_fingerprint,
            account_index: account.account_index,
            round_name: round_name.to_string(),
        },
    }
}

/// Returns the current reset epoch for a session while the cache lock is held.
fn current_prepared_pczt_epoch_locked(
    cache: &PreparedDelegationCache,
    session_key: &PreparedDelegationSessionKey,
) -> u64 {
    cache
        .session_epochs
        .get(session_key)
        .map(|session| session.epoch)
        .unwrap_or(0)
}

/// Enforces TTL and size bounds for prepared PCZT entries and reset epochs.
fn prune_prepared_pczt_cache_locked(cache: &mut PreparedDelegationCache, now: Instant) {
    cache
        .entries
        .retain(|_, entry| now.duration_since(entry.inserted_at) <= PREPARED_DELEGATION_PCZT_TTL);

    while cache.entries.len() > MAX_PREPARED_DELEGATION_PCZTS {
        let Some(oldest_key) = cache
            .entries
            .iter()
            .min_by_key(|(_, entry)| entry.inserted_at)
            .map(|(key, _)| key.clone())
        else {
            break;
        };
        cache.entries.remove(&oldest_key);
    }

    let sessions_with_entries = cache
        .entries
        .keys()
        .map(|key| prepared_delegation_session_key(&key.db_path, &key.account_uuid))
        .collect::<HashSet<_>>();

    cache.session_epochs.retain(|session_key, session| {
        now.duration_since(session.updated_at) <= PREPARED_DELEGATION_PCZT_TTL
            || sessions_with_entries.contains(session_key)
    });

    while cache.session_epochs.len() > MAX_PREPARED_DELEGATION_SESSIONS {
        let Some(oldest_key) = cache
            .session_epochs
            .iter()
            .filter(|(session_key, _)| !sessions_with_entries.contains(*session_key))
            .min_by_key(|(_, session)| session.updated_at)
            .map(|(key, _)| key.clone())
        else {
            break;
        };
        cache.session_epochs.remove(&oldest_key);
    }
}

/// Captures the session reset epoch before starting cancellable precompute work.
fn prepared_pczt_epoch(db_path: &str, account_uuid: &str) -> Result<u64, String> {
    let session_key = prepared_delegation_session_key(db_path, account_uuid);
    let mut cache = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?;
    prune_prepared_pczt_cache_locked(&mut cache, Instant::now());
    Ok(current_prepared_pczt_epoch_locked(&cache, &session_key))
}

/// Inserts prepared PCZT material only if the session has not been reset.
///
/// Returns `false` when the caller finished after a lock/account/session cleanup
/// advanced the epoch.
fn insert_prepared_pczt_if_current(
    key: PreparedDelegationKey,
    expected_epoch: u64,
    governance_pczt: zcash_voting::GovernancePczt,
) -> Result<bool, String> {
    let session_key = prepared_delegation_session_key(&key.db_path, &key.account_uuid);
    let now = Instant::now();
    let mut cache = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?;
    prune_prepared_pczt_cache_locked(&mut cache, now);
    if current_prepared_pczt_epoch_locked(&cache, &session_key) != expected_epoch {
        return Ok(false);
    }
    cache.entries.insert(
        key,
        PreparedDelegationEntry {
            governance_pczt,
            inserted_at: now,
        },
    );
    prune_prepared_pczt_cache_locked(&mut cache, now);
    Ok(true)
}

/// Removes one prepared PCZT from the cache.
///
/// This is consume-on-entry for the real delegation flow; replaying the same
/// precompute result requires running the precompute again.
fn take_prepared_pczt(
    key: &PreparedDelegationKey,
) -> Result<Option<zcash_voting::GovernancePczt>, String> {
    let mut cache = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?;
    prune_prepared_pczt_cache_locked(&mut cache, Instant::now());
    Ok(cache.entries.remove(key).map(|entry| entry.governance_pczt))
}

/// Clear prepared delegation PCZTs for one voting session.
///
/// When `round_id` is `Some(non_empty)`, only entries for that round are
/// removed. `None` or `Some("")` removes all prepared PCZTs for the session.
///
/// Resetting also advances a per-session epoch, so an in-flight background
/// precompute that finishes after the reset cannot reinsert stale PCZT state.
pub fn clear_prepared_delegation_pczt_cache(
    db_path: &str,
    account_uuid: &str,
    round_id: Option<&str>,
) -> Result<usize, String> {
    let session_key = prepared_delegation_session_key(db_path, account_uuid);
    let round_id = round_id.filter(|round_id| !round_id.is_empty());
    let mut cache = prepared_pczt_cache()
        .lock()
        .map_err(|e| format!("prepared delegation PCZT cache lock poisoned: {e}"))?;
    prune_prepared_pczt_cache_locked(&mut cache, Instant::now());
    let before = cache.entries.len();
    cache.entries.retain(|key, _| {
        key.db_path != db_path
            || key.account_uuid != account_uuid
            || round_id.is_some_and(|round_id| key.round_id != round_id)
    });
    let session =
        cache
            .session_epochs
            .entry(session_key)
            .or_insert(PreparedDelegationSessionEpoch {
                epoch: 0,
                updated_at: Instant::now(),
            });
    session.epoch = session.epoch.saturating_add(1);
    session.updated_at = Instant::now();
    Ok(before - cache.entries.len())
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
    cancellation: VotingWorkCancellation,
) -> Result<DelegationPirPrecomputeResult, String> {
    let started = std::time::Instant::now();
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
    validate_bundle_index(bundle_setup.bundle_count, bundle_index, "delegation")?;
    let bundle_note_infos = bundle_notes(&note_infos, bundle_index)?;

    generate_and_cache_bundle_witnesses(
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
    let governance_pczt = voting_db
        .build_governance_pczt(
            &round_id,
            bundle_index,
            &bundle_note_infos,
            &account.orchard_fvk_bytes,
            &hotkey_raw_address,
            branch_id,
            network.network_type().coin_type(),
            &account.seed_fingerprint,
            account.account_index,
            &round_context.round_name,
            0,
        )
        .map_err(|e| format!("build_governance_pczt failed: {e}"))?;

    let prepared_key = prepared_delegation_key(
        db_path,
        account_uuid,
        &round_id,
        bundle_index,
        &bundle_note_infos,
        &account,
        &hotkey_raw_address,
        branch_id,
        network,
        &round_context.round_name,
    );
    let prepared_epoch = prepared_pczt_epoch(db_path, account_uuid)?;
    cancellation.check()?;

    let proof_db_path = db_path.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = bundle_note_infos.clone();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_network_id = network.voting_id().into();
    let proof_cancellation = cancellation.clone();
    let precompute = tokio::task::spawn_blocking(move || {
        proof_cancellation.check()?;
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        proof_cancellation.check()?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        proof_cancellation.check()?;
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

    cancellation.check()?;
    if insert_prepared_pczt_if_current(prepared_key, prepared_epoch, governance_pczt)? {
        log::info!(
            "voting delegation: prepared PCZT cached \
             (round_id={}, account_uuid={}, bundle_index={})",
            round_id,
            account_uuid,
            bundle_index
        );
    } else {
        log::info!(
            "voting delegation: prepared PCZT discarded after session reset \
             (round_id={}, account_uuid={}, bundle_index={})",
            round_id,
            account_uuid,
            bundle_index
        );
    }

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

/// Build, prove, and sign one delegation payload.
///
/// Emits progress phases through `on_progress`. The returned value is a signed
/// delegation payload ready for Dart-side submission; `bundle_index` must identify an
/// eligible persisted bundle for this round.
///
/// # Errors
///
/// Returns an error if note/bundle validation, witness
/// generation, PCZT construction, PIR proof generation, or delegation signing
/// fails.
#[allow(clippy::too_many_arguments)]
pub async fn build_prove_and_sign_delegation_payload<F>(
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
    cancellation: VotingWorkCancellation,
) -> Result<SignedDelegationPayload, String>
where
    F: Fn(ProofEvent) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id.clone();

    cancellation.check()?;
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
    validate_bundle_index(bundle_setup.bundle_count, bundle_index, "delegation")?;
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

    generate_and_cache_bundle_witnesses(
        db_path,
        network,
        &voting_db,
        &round_id,
        bundle_index,
        &selected,
        &bundle_note_infos,
    )?;

    cancellation.check()?;
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
    let prepared_key = prepared_delegation_key(
        db_path,
        account_uuid,
        &round_id,
        bundle_index,
        &bundle_note_infos,
        &account,
        &hotkey_raw_address,
        branch_id,
        network,
        &round_context.round_name,
    );
    let prepared_governance_pczt = take_prepared_pczt(&prepared_key)?;
    let governance_pczt = if let Some(governance_pczt) = prepared_governance_pczt {
        log::info!(
            "voting delegation: using precomputed governance PCZT \
             (bundle_index={})",
            bundle_index
        );
        governance_pczt
    } else {
        voting_db
            .build_governance_pczt(
                &round_id,
                bundle_index,
                &bundle_note_infos,
                &account.orchard_fvk_bytes,
                &hotkey_raw_address,
                branch_id,
                network.network_type().coin_type(),
                &account.seed_fingerprint,
                account.account_index,
                &round_context.round_name,
                0,
            )
            .map_err(|e| format!("build_governance_pczt failed: {e}"))?
    };
    log::info!(
        "voting delegation: built governance PCZT \
         (bundle_index={}, action_index={}, pczt_bytes={})",
        bundle_index,
        governance_pczt.action_index,
        governance_pczt.pczt_bytes.len()
    );

    cancellation.check()?;
    on_progress(ProofEvent::BuildingProof);
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = bundle_note_infos.clone();
    let proof_hotkey_raw_address = hotkey_raw_address.clone();
    let proof_network_id = network.voting_id().into();
    let proof_cancellation = cancellation.clone();
    let proof_progress = on_progress.clone();
    log::info!(
        "voting delegation: starting proof task \
         (bundle_index={}, network_id={})",
        bundle_index,
        proof_network_id
    );
    tokio::task::spawn_blocking(move || {
        proof_cancellation.check()?;
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        proof_cancellation.check()?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        proof_cancellation.check()?;
        let reporter = ProofProgressBridge::new(proof_cancellation.clone(), move |progress| {
            proof_progress(ProofEvent::ProofProgress { progress });
        });
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
    cancellation.check()?;
    log::info!(
        "voting delegation: proof task completed \
         (bundle_index={})",
        bundle_index
    );

    on_progress(ProofEvent::SigningPayload);
    let submission = voting_db
        .get_delegation_submission(
            &round_id,
            bundle_index,
            seed.expose_secret(),
            network.voting_id().into(),
            account.account_index,
        )
        .map_err(|e| format!("get_delegation_submission failed: {e}"))?;

    on_progress(ProofEvent::PayloadReady);
    Ok(SignedDelegationPayload {
        pczt_bytes: governance_pczt.pczt_bytes,
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

/// Open the wallet source and ask `zcash_voting` to cache bundle witnesses.
///
/// Witness generation itself lives in the shared crate so SDKs enforce the same
/// snapshot-tree-state and bundle-cache invariants.
fn generate_and_cache_bundle_witnesses(
    db_path: &str,
    network: WalletNetwork,
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    selected: &SelectedNotes,
    notes: &[zcash_voting::NoteInfo],
) -> Result<(), String> {
    let wallet_db = open_wallet_db_for_read(db_path, network)?;
    zcash_voting::witness::store_tree_state_and_generate_note_witnesses(
        voting_db,
        round_id,
        bundle_index,
        &selected.anchor_tree_state.encode_to_vec(),
        notes,
        &wallet_db,
    )
    .map(|_| ())
    .map_err(|e| e.to_string())
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
    fn prepared_delegation_pczt_cache_is_consume_on_entry() {
        clear_prepared_delegation_pczt_cache("/tmp/voting-pczt.sqlite", ACCOUNT_UUID, None)
            .unwrap();
        let key = test_prepared_key("/tmp/voting-pczt.sqlite", ACCOUNT_UUID, ROUND_ID, 0);
        let epoch = prepared_pczt_epoch("/tmp/voting-pczt.sqlite", ACCOUNT_UUID).unwrap();

        assert!(
            insert_prepared_pczt_if_current(key.clone(), epoch, test_governance_pczt()).unwrap()
        );
        assert!(take_prepared_pczt(&key).unwrap().is_some());
        assert!(take_prepared_pczt(&key).unwrap().is_none());
    }

    #[test]
    fn prepared_delegation_pczt_cache_key_binds_full_pczt_inputs() {
        clear_prepared_delegation_pczt_cache("/tmp/voting-input-key.sqlite", ACCOUNT_UUID, None)
            .unwrap();
        let key = test_prepared_key("/tmp/voting-input-key.sqlite", ACCOUNT_UUID, ROUND_ID, 0);
        let epoch = prepared_pczt_epoch("/tmp/voting-input-key.sqlite", ACCOUNT_UUID).unwrap();
        insert_prepared_pczt_if_current(key.clone(), epoch, test_governance_pczt()).unwrap();

        let mut different_round_name = key.clone();
        different_round_name.pczt_inputs.round_name = "Different Round".to_string();
        assert!(take_prepared_pczt(&different_round_name).unwrap().is_none());

        let mut different_bundle_note = key.clone();
        different_bundle_note.pczt_inputs.bundle_notes[0].nullifier[0] ^= 0x01;
        assert!(take_prepared_pczt(&different_bundle_note)
            .unwrap()
            .is_none());

        let mut different_account = key.clone();
        different_account.pczt_inputs.seed_fingerprint[0] ^= 0x01;
        assert!(take_prepared_pczt(&different_account).unwrap().is_none());
        assert!(take_prepared_pczt(&key).unwrap().is_some());
    }

    #[test]
    fn prepared_delegation_pczt_reset_blocks_late_precompute_insert() {
        clear_prepared_delegation_pczt_cache("/tmp/voting-late.sqlite", ACCOUNT_UUID, None)
            .unwrap();
        let key = test_prepared_key("/tmp/voting-late.sqlite", ACCOUNT_UUID, ROUND_ID, 0);
        let stale_epoch = prepared_pczt_epoch("/tmp/voting-late.sqlite", ACCOUNT_UUID).unwrap();

        clear_prepared_delegation_pczt_cache("/tmp/voting-late.sqlite", ACCOUNT_UUID, None)
            .unwrap();

        assert!(
            !insert_prepared_pczt_if_current(key.clone(), stale_epoch, test_governance_pczt())
                .unwrap()
        );
        assert!(take_prepared_pczt(&key).unwrap().is_none());
    }

    #[test]
    fn clear_prepared_delegation_pczt_cache_can_target_round() {
        clear_prepared_delegation_pczt_cache("/tmp/voting-round-clear.sqlite", ACCOUNT_UUID, None)
            .unwrap();
        let first_key =
            test_prepared_key("/tmp/voting-round-clear.sqlite", ACCOUNT_UUID, ROUND_ID, 0);
        let second_round = "0000000000000000000000000000000000000000000000000000000000000002";
        let second_key = test_prepared_key(
            "/tmp/voting-round-clear.sqlite",
            ACCOUNT_UUID,
            second_round,
            0,
        );
        let epoch = prepared_pczt_epoch("/tmp/voting-round-clear.sqlite", ACCOUNT_UUID).unwrap();
        insert_prepared_pczt_if_current(first_key.clone(), epoch, test_governance_pczt()).unwrap();
        insert_prepared_pczt_if_current(second_key.clone(), epoch, test_governance_pczt()).unwrap();

        assert_eq!(
            clear_prepared_delegation_pczt_cache(
                "/tmp/voting-round-clear.sqlite",
                ACCOUNT_UUID,
                Some(ROUND_ID),
            )
            .unwrap(),
            1
        );

        assert!(take_prepared_pczt(&first_key).unwrap().is_none());
        assert!(take_prepared_pczt(&second_key).unwrap().is_some());
    }

    #[test]
    fn build_prove_and_sign_delegation_payload_rejects_invalid_round_params_before_progress() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let seed = SecretVec::new(vec![7; 32]);
        let events = Arc::new(Mutex::new(Vec::new()));
        let events_for_callback = events.clone();
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_prove_and_sign_delegation_payload(
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
                VotingWorkCancellation::start(
                    db_path.to_str().unwrap(),
                    ACCOUNT_UUID,
                    Some(ROUND_ID),
                )
                .unwrap(),
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

    fn test_prepared_key(
        db_path: &str,
        account_uuid: &str,
        round_id: &str,
        bundle_index: u32,
    ) -> PreparedDelegationKey {
        prepared_delegation_key(
            db_path,
            account_uuid,
            round_id,
            bundle_index,
            &[test_note_info(42)],
            &test_delegation_account(),
            &[7; 32],
            0x1234,
            WalletNetwork::Regtest,
            "Demo Round",
        )
    }

    fn test_delegation_account() -> DelegationAccount {
        DelegationAccount {
            account_index: 0,
            orchard_fvk_bytes: [8; 96],
            seed_fingerprint: [9; 32],
        }
    }

    fn test_governance_pczt() -> zcash_voting::GovernancePczt {
        zcash_voting::GovernancePczt {
            pczt_bytes: vec![1, 2, 3],
            rk: vec![0; 32],
            alpha: vec![0; 32],
            nf_signed: vec![0; 32],
            cmx_new: vec![0; 32],
            gov_nullifiers: vec![vec![0; 32]; 5],
            van: vec![0; 32],
            van_comm_rand: vec![0; 32],
            dummy_nullifiers: vec![vec![0; 32]; 5],
            rho_signed: vec![0; 32],
            padded_cmx: vec![vec![0; 32]; 5],
            rseed_signed: vec![0; 32],
            rseed_output: vec![0; 32],
            action_bytes: vec![0; 32],
            action_index: 0,
            padded_note_secrets: vec![(vec![0; 32], vec![0; 32]); 5],
            pczt_sighash: vec![0; 32],
        }
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
