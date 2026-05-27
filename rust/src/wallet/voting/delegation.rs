use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
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
    bundle::{select_notes_with_lwd, validate_bundle_index, voting_power, SelectedNotes},
    hotkey::{derive_hotkey_raw_orchard_address, hotkey_raw_orchard_address_from_secret},
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

/// Voting PCZT request that must be signed by Keystone before delegation proof submission.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeystoneDelegationRequest {
    pub pczt_bytes: Vec<u8>,
    pub redacted_pczt_bytes: Vec<u8>,
    pub pczt_sighash: Vec<u8>,
    pub rk: Vec<u8>,
    pub action_index: u32,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

/// Persisted Keystone signature for one delegation bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeystoneSignatureRecord {
    pub bundle_index: u32,
    pub sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub rk: Vec<u8>,
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

struct DelegationBundleContext {
    voting_db: zcash_voting::storage::VotingDb,
    round_id: String,
    bundle_index: u32,
    bundle_setup: BundleSetupResult,
    selected_weight_zatoshi: u64,
    bundle_note_infos: Vec<zcash_voting::NoteInfo>,
    delegated_weight_zatoshi: u64,
    account: DelegationAccount,
    hotkey_raw_address: Vec<u8>,
    branch_id: u32,
    round_name: String,
}

impl DelegationBundleContext {
    fn prepared_key(
        &self,
        db_path: &str,
        account_uuid: &str,
        network: WalletNetwork,
    ) -> PreparedDelegationKey {
        prepared_delegation_key(
            db_path,
            account_uuid,
            &self.round_id,
            self.bundle_index,
            &self.bundle_note_infos,
            &self.account,
            &self.hotkey_raw_address,
            self.branch_id,
            network,
            &self.round_name,
        )
    }
}

/// Initializes the local voting database for delegation operations.
///
/// Opens or creates the voting DB scoped to `wallet_id`; returns an error if
/// the DB cannot be opened or migrated.
pub fn prepare_delegation(db_path: &str, wallet_id: &str) -> Result<(), String> {
    open_voting_db(db_path, wallet_id).map(|_| ())
}

#[allow(clippy::too_many_arguments)]
async fn prepare_delegation_bundle_context(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    account_uuid: &str,
    hotkey_raw_address: Vec<u8>,
    bundle_index: u32,
) -> Result<DelegationBundleContext, String> {
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;
    let round_id = round_params.vote_round_id;

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
    let branch_height = current_chain_height(lightwalletd_url).await?;
    let branch_id = consensus_branch_id(network, branch_height)?;
    log::info!(
        "voting delegation: selected consensus branch \
         (network={:?}, branch_height={}, branch_id=0x{:08x})",
        network,
        branch_height,
        branch_id
    );

    Ok(DelegationBundleContext {
        voting_db,
        round_id,
        bundle_index,
        bundle_setup,
        selected_weight_zatoshi,
        bundle_note_infos,
        delegated_weight_zatoshi,
        account,
        hotkey_raw_address,
        branch_id,
        round_name: round_context.round_name,
    })
}

fn build_governance_pczt_for_context(
    context: &DelegationBundleContext,
    network: WalletNetwork,
) -> Result<zcash_voting::GovernancePczt, String> {
    context
        .voting_db
        .build_governance_pczt(
            &context.round_id,
            context.bundle_index,
            &context.bundle_note_infos,
            &context.account.orchard_fvk_bytes,
            &context.hotkey_raw_address,
            context.branch_id,
            network.network_type().coin_type(),
            &context.account.seed_fingerprint,
            context.account.account_index,
            &context.round_name,
            0,
        )
        .map_err(|e| format!("build_governance_pczt failed: {e}"))
}

fn signed_payload_from_submission(
    submission: zcash_voting::DelegationSubmissionData,
    pczt_bytes: Vec<u8>,
    bundle_setup: &BundleSetupResult,
    selected_weight_zatoshi: u64,
    delegated_weight_zatoshi: u64,
    bundle_index: u32,
) -> SignedDelegationPayload {
    SignedDelegationPayload {
        pczt_bytes,
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
    }
}

async fn prove_delegation_for_context<F>(
    db_path: &str,
    pir_server_url: &str,
    account_uuid: &str,
    network: WalletNetwork,
    context: &DelegationBundleContext,
    on_progress: Arc<F>,
    cancellation: VotingWorkCancellation,
) -> Result<(), String>
where
    F: Fn(ProofEvent) + Send + Sync + 'static,
{
    cancellation.check()?;
    on_progress(ProofEvent::BuildingProof);
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = context.round_id.clone();
    let proof_bundle_index = context.bundle_index;
    let proof_bundle_note_infos = context.bundle_note_infos.clone();
    let proof_hotkey_raw_address = context.hotkey_raw_address.clone();
    let proof_network_id = network.voting_id().into();
    let proof_cancellation = cancellation.clone();
    let proof_progress = on_progress.clone();
    log::info!(
        "voting delegation: starting proof task \
         (bundle_index={}, network_id={})",
        proof_bundle_index,
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
                proof_bundle_index,
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
        context.bundle_index
    );
    Ok(())
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
    let round_id = round_params.vote_round_id.clone();
    let hotkey_raw_address =
        derive_hotkey_raw_orchard_address(seed, &round_id, account_uuid, network)?;
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        hotkey_raw_address,
        bundle_index,
    )
    .await?;
    let governance_pczt = build_governance_pczt_for_context(&context, network)?;

    let prepared_key = context.prepared_key(db_path, account_uuid, network);
    let prepared_epoch = prepared_pczt_epoch(db_path, account_uuid)?;
    cancellation.check()?;

    let proof_db_path = db_path.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = round_id.clone();
    let proof_bundle_note_infos = context.bundle_note_infos.clone();
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
        bundle_count: context.bundle_setup.bundle_count,
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
    let round_id = round_params.vote_round_id.clone();

    cancellation.check()?;
    on_progress(ProofEvent::SelectingNotes);
    let hotkey_raw_address =
        derive_hotkey_raw_orchard_address(seed, &round_id, account_uuid, network)?;
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        hotkey_raw_address,
        bundle_index,
    )
    .await?;
    log::info!(
        "voting delegation: preparing bundle \
         (bundle_index={}, bundle_count={}, note_count={}, delegated_weight_zatoshi={})",
        bundle_index,
        context.bundle_setup.bundle_count,
        context.bundle_note_infos.len(),
        context.delegated_weight_zatoshi
    );

    cancellation.check()?;
    on_progress(ProofEvent::BuildingPczt);
    let prepared_key = context.prepared_key(db_path, account_uuid, network);
    let prepared_governance_pczt = take_prepared_pczt(&prepared_key)?;
    let governance_pczt = if let Some(governance_pczt) = prepared_governance_pczt {
        log::info!(
            "voting delegation: using precomputed governance PCZT \
             (bundle_index={})",
            bundle_index
        );
        governance_pczt
    } else {
        build_governance_pczt_for_context(&context, network)?
    };
    log::info!(
        "voting delegation: built governance PCZT \
         (bundle_index={}, action_index={}, pczt_bytes={})",
        bundle_index,
        governance_pczt.action_index,
        governance_pczt.pczt_bytes.len()
    );

    prove_delegation_for_context(
        db_path,
        pir_server_url,
        account_uuid,
        network,
        &context,
        on_progress.clone(),
        cancellation.clone(),
    )
    .await?;

    on_progress(ProofEvent::SigningPayload);
    let submission = context
        .voting_db
        .get_delegation_submission(
            &round_id,
            bundle_index,
            seed.expose_secret(),
            network.voting_id().into(),
            context.account.account_index,
        )
        .map_err(|e| format!("get_delegation_submission failed: {e}"))?;

    on_progress(ProofEvent::PayloadReady);
    Ok(signed_payload_from_submission(
        submission,
        governance_pczt.pczt_bytes,
        &context.bundle_setup,
        context.selected_weight_zatoshi,
        context.delegated_weight_zatoshi,
        bundle_index,
    ))
}

/// Build one voting PCZT request for Keystone signing.
///
/// The full PCZT is persisted only in Rust-side voting state. `redacted_pczt_bytes`
/// is the payload that should be UR-encoded for Keystone.
///
/// # Errors
///
/// Returns an error if note selection, witness generation, account metadata,
/// PCZT construction, or redaction fails.
#[allow(clippy::too_many_arguments)]
pub async fn build_keystone_delegation_request(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    account_uuid: &str,
    hotkey_secret: &SecretVec<u8>,
    bundle_index: u32,
    cancellation: VotingWorkCancellation,
) -> Result<KeystoneDelegationRequest, String> {
    let hotkey_raw_address = hotkey_raw_orchard_address_from_secret(hotkey_secret, network)?;
    cancellation.check()?;
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        hotkey_raw_address,
        bundle_index,
    )
    .await?;
    cancellation.check()?;
    let governance_pczt = build_governance_pczt_for_context(&context, network)?;
    let redacted_pczt_bytes =
        crate::wallet::sync::redact_pczt_for_signer(&governance_pczt.pczt_bytes)?;
    let action_index = u32::try_from(governance_pczt.action_index)
        .map_err(|_| "governance PCZT action index does not fit in u32".to_string())?;

    Ok(KeystoneDelegationRequest {
        pczt_bytes: governance_pczt.pczt_bytes,
        redacted_pczt_bytes,
        pczt_sighash: governance_pczt.pczt_sighash,
        rk: governance_pczt.rk,
        action_index,
        eligible_weight_zatoshi: context
            .bundle_setup
            .eligible_weight_zatoshi
            .min(context.selected_weight_zatoshi),
        delegated_weight_zatoshi: context.delegated_weight_zatoshi,
        bundle_count: context.bundle_setup.bundle_count,
        bundle_index,
    })
}

/// Build a delegation proof and assemble the submission using a Keystone signature.
///
/// This path intentionally does not rebuild the governance PCZT. The signed PCZT
/// request already persisted the sighash and delegation fields; rebuilding here
/// would overwrite that state with a fresh PCZT that the device did not sign.
///
/// # Errors
///
/// Returns an error if proof generation fails, the Keystone signature does not
/// match the stored PCZT sighash, or submission payload reconstruction fails.
#[allow(clippy::too_many_arguments)]
pub async fn build_prove_delegation_payload_with_keystone_signature<F>(
    db_path: &str,
    lightwalletd_url: &str,
    pir_server_url: &str,
    network: WalletNetwork,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    account_uuid: &str,
    hotkey_secret: &SecretVec<u8>,
    bundle_index: u32,
    keystone_sig: &[u8],
    keystone_sighash: &[u8],
    on_progress: F,
    cancellation: VotingWorkCancellation,
) -> Result<SignedDelegationPayload, String>
where
    F: Fn(ProofEvent) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);
    let round_id = round_params.vote_round_id.clone();
    let hotkey_raw_address = hotkey_raw_orchard_address_from_secret(hotkey_secret, network)?;

    cancellation.check()?;
    on_progress(ProofEvent::SelectingNotes);
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        hotkey_raw_address,
        bundle_index,
    )
    .await?;

    prove_delegation_for_context(
        db_path,
        pir_server_url,
        account_uuid,
        network,
        &context,
        on_progress.clone(),
        cancellation.clone(),
    )
    .await?;

    on_progress(ProofEvent::SigningPayload);
    let submission = context
        .voting_db
        .get_delegation_submission_with_keystone_sig(
            &round_id,
            bundle_index,
            keystone_sig,
            keystone_sighash,
        )
        .map_err(|e| format!("get_delegation_submission_with_keystone_sig failed: {e}"))?;
    on_progress(ProofEvent::PayloadReady);

    Ok(signed_payload_from_submission(
        submission,
        Vec::new(),
        &context.bundle_setup,
        context.selected_weight_zatoshi,
        context.delegated_weight_zatoshi,
        bundle_index,
    ))
}

/// Extract the ZIP-244 shielded sighash from PCZT bytes.
pub fn extract_pczt_sighash(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    zcash_voting::action::extract_pczt_sighash(pczt_bytes)
        .map(|sighash| sighash.to_vec())
        .map_err(|e| format!("extract_pczt_sighash failed: {e}"))
}

/// Extract the SpendAuth signature from a Keystone-signed voting PCZT.
pub fn extract_spend_auth_signature_from_signed_pczt(
    signed_pczt_bytes: &[u8],
    action_index: u32,
) -> Result<Vec<u8>, String> {
    zcash_voting::action::extract_spend_auth_sig(signed_pczt_bytes, action_index as usize)
        .map(|sig| sig.to_vec())
        .map_err(|e| format!("extract_spend_auth_sig failed: {e}"))
}

/// Persist a Keystone signature for one delegation bundle.
pub fn store_keystone_signature(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    sig: &[u8],
    sighash: &[u8],
    rk: &[u8],
) -> Result<(), String> {
    require_len(sig, 64, "sig")?;
    require_len(sighash, 32, "sighash")?;
    require_len(rk, 32, "rk")?;
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .store_keystone_signature(round_id, bundle_index, sig, sighash, rk)
        .map_err(|e| format!("store_keystone_signature failed: {e}"))
}

/// Load persisted Keystone signatures for a voting round.
pub fn get_keystone_signatures(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<KeystoneSignatureRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_keystone_signatures(round_id)
        .map(|records| {
            records
                .into_iter()
                .map(|record| KeystoneSignatureRecord {
                    bundle_index: record.bundle_index,
                    sig: record.sig,
                    sighash: record.sighash,
                    rk: record.rk,
                })
                .collect()
        })
        .map_err(|e| format!("get_keystone_signatures failed: {e}"))
}

fn require_len(bytes: &[u8], expected: usize, field: &str) -> Result<(), String> {
    if bytes.len() == expected {
        Ok(())
    } else {
        Err(format!(
            "{field} must be exactly {expected} bytes, got {}",
            bytes.len()
        ))
    }
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
