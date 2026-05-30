use std::sync::Arc;

use secrecy::{ExposeSecret, SecretVec};

use crate::wallet::{
    keys,
    network::WalletNetwork,
    sync::{get_sync_progress_from_db, open_wallet_db_for_read},
};

use super::{
    hotkey::{derive_voting_hotkey, voting_hotkey_from_secret},
    progress::VotingWorkCancellation,
    state::{ensure_voting_round, open_voting_db},
    voting_network,
};

pub use zcash_voting::delegate::DelegationProgress;
use zcash_voting::delegate::{
    DelegationBundleContext, PrepareDelegationBundleParams, ResolveDelegationLwdParams,
};
use zcash_voting::selection::select_notes_with_lwd;
use zcash_voting::storage::VotingDb;
use zcash_voting::BundlePolicy;

#[derive(Clone, Debug)]
struct RoundContext {
    snapshot_height: u64,
    round_name: String,
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
    voting_hotkey: zcash_voting::VotingHotkey,
    bundle_index: u32,
    bundle_policy: BundlePolicy,
) -> Result<DelegationBundleContext, String> {
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let round_context =
        ensure_round_initialized(&voting_db, &round_params, round_name, session_json)?;

    // 1. Resolve the round anchor and consensus branch id in one lightwalletd
    //    pass before any wallet-DB handle exists. This await happens before the
    //    wallet is opened so the non-Send handle never crosses an await point.
    let lwd = zcash_voting::delegate::gather_delegation_lwd_inputs(ResolveDelegationLwdParams {
        lightwalletd_url,
        network: voting_network(network),
        round_params,
        round_name,
        cancellation: &zcash_voting::NoopCancellation,
    })
    .await
    .map_err(|e| e.to_string())?;
    // 2. Open the wallet once and do all wallet-DB work synchronously: snapshot
    //    notes plus account keys, and (only on a cold cache) the witnesses.
    let wallet_db = open_wallet_db_for_read(db_path, network)?;
    let wallet_progress = get_sync_progress_from_db(&wallet_db)?;
    let prepared = zcash_voting::delegate::prepare_delegation_bundle(
        &voting_db,
        lwd,
        PrepareDelegationBundleParams {
            wallet_db: &wallet_db,
            account_uuid,
            voting_hotkey: &voting_hotkey,
            scanned_height: wallet_progress.scanned_height,
            bundle_index,
            bundle_policy,
        },
    )
    .map_err(|e| e.to_string())?;
    let delegated_weight_zatoshi =
        zcash_voting::round::quantized_bundle_weight(&prepared.bundle_note_infos)
            .map_err(|e| format!("quantized_bundle_weight failed: {e}"))?;

    // 3. Skip the expensive Orchard witness walk when a prior precompute pass
    //    already cached witnesses for this bundle. `store_witnesses`
    //    short-circuits, but `note_witnesses` would still regenerate first.
    if !voting_db
        .has_witnesses(&prepared.round_id, bundle_index)
        .map_err(|e| format!("has_witnesses failed: {e}"))?
    {
        zcash_voting::precompute::note_witnesses(
            &voting_db,
            &prepared.round_id,
            bundle_index,
            &prepared.anchor_tree_state_bytes,
            &prepared.bundle_note_infos,
            &wallet_db,
        )
        .map(|_| ())
        .map_err(|e| e.to_string())?;
    }

    Ok(DelegationBundleContext {
        voting_db,
        round_id: prepared.round_id,
        bundle_index,
        bundle_setup: prepared.layout.clone(),
        selected_weight_zatoshi: prepared.layout.eligible_weight,
        bundle_note_infos: prepared.bundle_note_infos,
        delegated_weight_zatoshi,
        delegation_keys: prepared.delegation_keys,
        branch_id_provider: prepared.branch_id_provider,
        round_name: round_context.round_name,
    })
}

fn signed_payload_from_submission(
    submission: zcash_voting::delegate::DelegationSubmission,
    pczt_bytes: Vec<u8>,
    bundle_setup: &zcash_voting::round::BundleLayout,
    selected_weight_zatoshi: u64,
    delegated_weight_zatoshi: u64,
    bundle_index: u32,
) -> zcash_voting::delegate::SignedDelegationBundle {
    zcash_voting::delegate::SignedDelegationBundle {
        submission,
        pczt_bytes,
        eligible_weight_zatoshi: bundle_setup.eligible_weight.min(selected_weight_zatoshi),
        delegated_weight_zatoshi,
        bundle_count: bundle_setup.bundle_count,
        bundle_index,
    }
}

async fn prove_delegation_for_context<F>(
    db_path: &str,
    pir_server_url: &str,
    account_uuid: &str,
    context: &DelegationBundleContext,
    on_progress: Arc<F>,
    cancellation: VotingWorkCancellation,
) -> Result<(), String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    cancellation.check()?;
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let proof_round_id = context.round_id.clone();
    let proof_bundle_index = context.bundle_index;
    let proof_bundle_note_infos = context.bundle_note_infos.clone();
    let proof_keys = context.delegation_keys.clone();
    let proof_cancellation = cancellation.clone();
    let proof_progress = on_progress.clone();
    tokio::task::spawn_blocking(move || {
        proof_cancellation.check()?;
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        let reporter = zcash_voting::DelegationProgressBridge::new(move |progress| {
            proof_progress(progress);
        });
        proof_cancellation.check()?;
        zcash_voting::delegate::prove(
            &proof_voting_db,
            &proof_round_id,
            proof_bundle_index,
            &proof_bundle_note_infos,
            &proof_keys,
            &pir_client,
            &reporter,
        )
        .map(|_| ())
        .map_err(|e| format!("delegate::prove failed: {e}"))
    })
    .await
    .map_err(|e| format!("delegation proof task failed: {e}"))??;
    cancellation.check()?;
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
    voting_db: &VotingDb,
    db_path: &str,
    lightwalletd_url: &str,
    network: &str,
    round_params: zcash_voting::VotingRoundParams,
    round_name: &str,
    session_json: Option<&str>,
    bundle_policy: BundlePolicy,
) -> Result<zcash_voting::round::BundleLayout, String> {
    let network = keys::parse_network(network)?;
    let round_context =
        ensure_round_initialized(voting_db, &round_params, round_name, session_json)?;
    let selected = select_notes_with_lwd(
        voting_db,
        db_path,
        lightwalletd_url,
        voting_network(network),
        round_context.snapshot_height,
    )
    .await
    .map_err(|e| e.to_string())?;
    let note_infos = selected.voting_note_infos();
    voting_db
        .ensure_bundles_with_skipped_suffix_with_policy(
            round_params.vote_round_id.as_str(),
            &note_infos,
            bundle_policy,
        )
        .map_err(|e| format!("ensure_bundles_with_skipped_suffix failed: {e}"))
}

/// Warms PIR state for a single delegation bundle.
///
/// Validates the PIR endpoint against the round snapshot, persists witnesses,
/// initializes padded-note secrets, and precomputes delegation PIR rows for
/// `bundle_index`.
///
/// # Errors
///
/// Returns an error if the round, endpoint, note selection, bundle index,
/// witness generation, padded-secret initialization, or PIR precompute step
/// fails.
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
    bundle_policy: BundlePolicy,
    cancellation: VotingWorkCancellation,
) -> Result<zcash_voting::delegate::PreparedDelegationReport, String> {
    cancellation.check()?;
    let round_id = round_params.vote_round_id.clone();
    let voting_hotkey = derive_voting_hotkey(seed, &round_id, account_uuid, network)?;
    let lwd = zcash_voting::delegate::gather_delegation_lwd_inputs(ResolveDelegationLwdParams {
        lightwalletd_url,
        network: voting_network(network),
        round_params,
        round_name,
        cancellation: &cancellation,
    })
    .await
    .map_err(|e| e.to_string())?;
    cancellation.check()?;
    let db_path = db_path.to_string();
    let pir_server_url = pir_server_url.to_string();
    let account_uuid = account_uuid.to_string();
    let session_json = session_json.map(str::to_string);

    tokio::task::spawn_blocking(move || {
        cancellation.check()?;
        let voting_db = open_voting_db(&db_path, &account_uuid)?;
        ensure_round_initialized(
            &voting_db,
            &lwd.round_params,
            &lwd.resolved_round_name,
            session_json.as_deref(),
        )?;
        let wallet_db = open_wallet_db_for_read(&db_path, network)?;
        let wallet_progress = get_sync_progress_from_db(&wallet_db)?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        let prepared = zcash_voting::delegate::prepare_delegation_bundle(
            &voting_db,
            lwd,
            PrepareDelegationBundleParams {
                wallet_db: &wallet_db,
                account_uuid: &account_uuid,
                voting_hotkey: &voting_hotkey,
                scanned_height: wallet_progress.scanned_height,
                bundle_index,
                bundle_policy,
            },
        )
        .map_err(|e| e.to_string())?;
        prepared
            .precompute(&voting_db, &wallet_db, &pir_client, &cancellation)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("delegation PIR precompute task failed: {e}"))?
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
    bundle_policy: BundlePolicy,
    on_progress: F,
    cancellation: VotingWorkCancellation,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);
    let round_id = round_params.vote_round_id.clone();

    cancellation.check()?;
    zcash_voting::validate_round_params(&round_params)
        .map_err(|e| format!("Invalid voting round params: {e}"))?;
    on_progress(DelegationProgress::SelectingNotes);
    let voting_hotkey = derive_voting_hotkey(seed, &round_id, account_uuid, network)?;
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        voting_hotkey,
        bundle_index,
        bundle_policy,
    )
    .await?;

    let pczt_progress = on_progress.clone();
    let setup_stages = zcash_voting::DelegationProgressBridge::new(move |progress| {
        pczt_progress(progress);
    });
    let delegation_setup = zcash_voting::delegate::setup(
        &context.voting_db,
        &round_id,
        bundle_index,
        &context.bundle_note_infos,
        &context.delegation_keys,
        &context.branch_id_provider,
        &setup_stages,
    )
    .map_err(|e| format!("delegate::setup failed: {e}"))?;

    prove_delegation_for_context(
        db_path,
        pir_server_url,
        account_uuid,
        &context,
        on_progress.clone(),
        cancellation.clone(),
    )
    .await?;

    on_progress(DelegationProgress::SigningPayload);
    let submission = zcash_voting::delegate::submission(
        &context.voting_db,
        &round_id,
        bundle_index,
        zcash_voting::delegate::DelegationSigner::seed(
            seed.expose_secret(),
            &context.delegation_keys,
        ),
    )
    .map_err(|e| format!("delegate::submission failed: {e}"))?;

    on_progress(DelegationProgress::PayloadReady);
    Ok(signed_payload_from_submission(
        submission,
        delegation_setup.pczt_bytes,
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
    bundle_policy: BundlePolicy,
    cancellation: VotingWorkCancellation,
) -> Result<zcash_voting::delegate::KeystoneSigningRequest, String> {
    let voting_hotkey = voting_hotkey_from_secret(hotkey_secret, network)?;
    cancellation.check()?;
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        voting_hotkey,
        bundle_index,
        bundle_policy,
    )
    .await?;
    let noop_stages = zcash_voting::NoopProgressReporter;
    let delegation_setup = zcash_voting::delegate::setup(
        &context.voting_db,
        &context.round_id,
        context.bundle_index,
        &context.bundle_note_infos,
        &context.delegation_keys,
        &context.branch_id_provider,
        &noop_stages,
    )
    .map_err(|e| format!("delegate::setup failed: {e}"))?;
    let redacted_pczt_bytes =
        zcash_voting::delegate::redact_for_signer(&delegation_setup.pczt_bytes)
            .map_err(|e| format!("redact_for_signer failed: {e}"))?;
    let display_memo = zcash_voting::delegate::display_memo(
        &context.round_name,
        zcash_voting::round::raw_bundle_weight(&context.bundle_note_infos)
            .map_err(|e| format!("raw_bundle_weight failed: {e}"))?,
    );

    Ok(zcash_voting::delegate::KeystoneSigningRequest {
        setup: delegation_setup,
        redacted_pczt_bytes,
        display_memo,
        eligible_weight_zatoshi: context
            .bundle_setup
            .eligible_weight
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
    bundle_policy: BundlePolicy,
    on_progress: F,
    cancellation: VotingWorkCancellation,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);
    let round_id = round_params.vote_round_id.clone();
    let voting_hotkey = voting_hotkey_from_secret(hotkey_secret, network)?;

    cancellation.check()?;
    on_progress(DelegationProgress::SelectingNotes);
    let context = prepare_delegation_bundle_context(
        db_path,
        lightwalletd_url,
        network,
        round_params,
        round_name,
        session_json,
        account_uuid,
        voting_hotkey,
        bundle_index,
        bundle_policy,
    )
    .await?;

    prove_delegation_for_context(
        db_path,
        pir_server_url,
        account_uuid,
        &context,
        on_progress.clone(),
        cancellation.clone(),
    )
    .await?;

    on_progress(DelegationProgress::SigningPayload);
    let submission = zcash_voting::delegate::submission(
        &context.voting_db,
        &round_id,
        bundle_index,
        zcash_voting::delegate::DelegationSigner::keystone_from_bytes(
            keystone_sig,
            keystone_sighash,
        )
        .map_err(|e| format!("invalid Keystone signature fields: {e}"))?,
    )
    .map_err(|e| format!("delegate::submission failed: {e}"))?;
    on_progress(DelegationProgress::PayloadReady);

    Ok(signed_payload_from_submission(
        submission,
        Vec::new(),
        &context.bundle_setup,
        context.selected_weight_zatoshi,
        context.delegated_weight_zatoshi,
        bundle_index,
    ))
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
    Ok(RoundContext {
        snapshot_height: state.snapshot_height,
        round_name: zcash_voting::round::delegation_round_name(round_params, round_name),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;
    use std::sync::{Arc, Mutex};

    const ACCOUNT_UUID: &str = "550e8400-e29b-41d4-a716-446655440000";
    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

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
                BundlePolicy::default(),
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

        let created = voting_db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();
        let reused = voting_db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();

        assert_eq!(created.bundle_count, 1);
        assert_eq!(
            created.eligible_weight,
            zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(reused.bundle_count, 1);
        assert_eq!(
            reused.eligible_weight,
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

        voting_db
            .ensure_bundles(ROUND_ID, &[test_note_info(42)])
            .unwrap();

        let shape_err = voting_db
            .ensure_bundles(ROUND_ID, &[])
            .unwrap_err()
            .to_string();
        assert!(
            shape_err.contains("notes must not be empty")
                || shape_err.contains("no eligible notes")
                || shape_err.contains("current note selection produces")
        );

        let mut substituted = test_note_info(42);
        substituted.nullifier[0] ^= 0x01;
        let identity_err = voting_db
            .ensure_bundles(ROUND_ID, &[substituted])
            .unwrap_err()
            .to_string();
        assert!(identity_err.contains("note identity mismatch"));
    }

    #[test]
    fn ensure_bundles_preserves_multi_bundle_shape() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();

        let setup = voting_db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();

        assert_eq!(setup.bundle_count, 2);
        assert_eq!(
            setup.eligible_weight,
            6 * zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(voting_db.get_bundle_count(ROUND_ID).unwrap(), 2);
        assert_eq!(
            zcash_voting::round::quantized_bundle_weight(
                &zcash_voting::round::note_bundles(&notes).unwrap()[0]
            )
            .unwrap(),
            5 * zcash_voting::governance::BALLOT_DIVISOR
        );
        assert_eq!(
            zcash_voting::round::quantized_bundle_weight(
                &zcash_voting::round::note_bundles(&notes).unwrap()[1]
            )
            .unwrap(),
            zcash_voting::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn ensure_bundles_accepts_truncated_prefix_after_skipping_bundles() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let voting_db = open_voting_db(db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        voting_db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();
        voting_db.delete_skipped_bundles(ROUND_ID, 1).unwrap();

        let reused = voting_db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();

        assert_eq!(reused.bundle_count, 1);
        assert_eq!(
            reused.eligible_weight,
            5 * zcash_voting::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn bundle_notes_returns_only_requested_bundle() {
        let notes: Vec<_> = (0..6).map(test_note_info).collect();

        let bundles = zcash_voting::round::note_bundles(&notes).unwrap();
        let first = bundles[0].clone();
        let second = bundles[1].clone();

        assert_eq!(first.len(), 5);
        assert_eq!(second.len(), 1);
        assert_eq!(
            zcash_voting::round::quantized_bundle_weight(&first).unwrap(),
            5 * zcash_voting::BALLOT_DIVISOR
        );
        assert_eq!(
            zcash_voting::round::quantized_bundle_weight(&second).unwrap(),
            zcash_voting::BALLOT_DIVISOR
        );
        assert!(bundles.get(2).is_none());
    }

    #[test]
    fn delegation_display_memo_uses_raw_bundle_weight() {
        let mut note = test_note_info(0);
        note.value = 123_456_789;

        let raw_weight = zcash_voting::round::raw_bundle_weight(&[note.clone()]).unwrap();
        let quantized_weight = zcash_voting::round::quantized_bundle_weight(&[note]).unwrap();

        assert_eq!(raw_weight, 123_456_789);
        assert_ne!(raw_weight, quantized_weight);
        assert_eq!(
            zcash_voting::delegate::display_memo("Poll", raw_weight),
            "I am authorizing this hotkey managed by my wallet to vote on Poll with 1.23456789 ZEC."
        );
    }

    #[test]
    fn generate_and_cache_bundle_witnesses_rejects_invalid_cached_tree_state() {
        use zcash_client_backend::proto::service::TreeState;

        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let voting_db = open_voting_db(wallet_db_path.to_str().unwrap(), ACCOUNT_UUID).unwrap();
        let params = test_round_params();
        ensure_voting_round(&voting_db, &params, None).unwrap();
        voting_db
            .ensure_bundles(ROUND_ID, &[test_note_info(42)])
            .unwrap();
        let wallet_db =
            open_wallet_db_for_read(wallet_db_path.to_str().unwrap(), WalletNetwork::Regtest)
                .unwrap();
        let tree_state = TreeState {
            network: "regtest".to_string(),
            height: params.snapshot_height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        };

        let err = zcash_voting::precompute::note_witnesses(
            &voting_db,
            ROUND_ID,
            0,
            &tree_state.encode_to_vec(),
            &[test_note_info(42)],
            &wallet_db,
        )
        .unwrap_err();

        let err = err.to_string();
        assert!(err.contains("orchard") || err.contains("TreeState"));
    }

    #[test]
    fn load_account_keys_rejects_uninitialized_wallet_db() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.sqlite");

        let wallet_db =
            open_wallet_db_for_read(db_path.to_str().unwrap(), WalletNetwork::Regtest).unwrap();
        let err = zcash_voting::delegate::load_account_keys(&wallet_db, ACCOUNT_UUID).unwrap_err();

        assert!(
            err.to_string().contains("failed to load voting account")
                || err.to_string().contains("voting account not found")
        );
    }

    #[test]
    fn library_branch_id_for_height_follows_network_height() {
        assert_eq!(
            zcash_voting::delegate::branch_id_for_height(zcash_voting::Network::Mainnet, 3_146_399)
                .unwrap(),
            0xC8E7_1055
        );
        assert_eq!(
            zcash_voting::delegate::branch_id_for_height(zcash_voting::Network::Mainnet, 3_146_400)
                .unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            zcash_voting::delegate::branch_id_for_height(zcash_voting::Network::Testnet, 3_536_500)
                .unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            zcash_voting::delegate::branch_id_for_height(zcash_voting::Network::Regtest, 1)
                .unwrap(),
            0x4DEC_4DF0
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
