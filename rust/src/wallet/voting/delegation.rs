use std::sync::Arc;

use ff::PrimeField;
use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zip32::{fingerprint::SeedFingerprint, AccountId};

use crate::wallet::sync::open_wallet_db_for_read;
use crate::wallet::voting::network::wallet_network;

use super::db::open_voting_db;

pub use zcash_voting::delegate::DelegationProgress;
use zcash_voting::delegate::{
    DelegationSigningRequest, PrepareDelegationBundleParams, PreparedDelegationBundle,
};
use zcash_voting::selection::select_notes_with_lwd;
use zcash_voting::storage::VotingDb;
use zcash_voting::BundlePolicy;

/// Completes the proof phase for a previously prepared delegation bundle.
///
/// Opens the voting database for `account_uuid`, connects to `pir_server_url`,
/// then runs bundle proving on a blocking worker thread while forwarding
/// `DelegationProgress` updates to `on_progress`.
///
/// # Errors
///
/// Returns an error if opening the voting database fails, connecting to the PIR
/// server fails, the underlying `PreparedDelegationBundle::prove` call fails, or
/// the spawned blocking task is cancelled or panics.
async fn prove_delegation_bundle<F>(
    db_path: &str,
    pir_server_url: &str,
    account_uuid: &str,
    prepared: &PreparedDelegationBundle,
    on_progress: Arc<F>,
) -> Result<(), String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let proof_db_path = db_path.to_string();
    let proof_pir_server_url = pir_server_url.to_string();
    let proof_account_uuid = account_uuid.to_string();
    let prepared = prepared.clone();
    let proof_progress = on_progress.clone();
    tokio::task::spawn_blocking(move || {
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &proof_pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        let reporter = zcash_voting::DelegationProgressBridge::new(move |progress| {
            proof_progress(progress);
        });
        prepared
            .prove(&proof_voting_db, &pir_client, &reporter)
            .map(|_| ())
            .map_err(|e| format!("delegate::prove failed: {e}"))
    })
    .await
    .map_err(|e| format!("delegation proof task failed: {e}"))??;
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
pub async fn setup_delegation_bundles(
    voting_db: &VotingDb,
    db_path: &str,
    lwd_params: zcash_voting::delegate::ResolveDelegationLwdParams<'_>,
    session_json: Option<&str>,
    bundle_policy: BundlePolicy,
) -> Result<zcash_voting::round::BundleLayout, String> {
    let zcash_voting::delegate::ResolveDelegationLwdParams {
        lightwalletd_url,
        network,
        round_params,
        round_name,
    } = lwd_params;
    let round_context = zcash_voting::delegate::ensure_round_context(
        voting_db,
        &round_params,
        round_name,
        session_json,
    )
    .map_err(|e| e.to_string())?;
    let selected = select_notes_with_lwd(
        voting_db,
        db_path,
        lightwalletd_url,
        network,
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
pub async fn precompute_delegation_pir(
    db_path: &str,
    pir_server_url: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
) -> Result<zcash_voting::delegate::PreparedDelegationReport, String> {
    let PrepareDelegationBundleParams {
        lwd,
        session_json,
        account_uuid,
        voting_hotkey,
        bundle_index,
        bundle_policy,
    } = prepare_params;

    let db_path = db_path.to_string();
    let pir_server_url = pir_server_url.to_string();
    let account_uuid = account_uuid.to_string();
    let session_json = session_json.map(str::to_string);
    let voting_hotkey = voting_hotkey.clone();

    tokio::task::spawn_blocking(move || {
        let voting_db = open_voting_db(&db_path, &account_uuid)?;
        let wallet_db = open_wallet_db_for_read(&db_path, wallet_network(voting_hotkey.network()))?;
        let prepared = zcash_voting::delegate::prepare_delegation_bundle(
            &voting_db,
            &wallet_db,
            PrepareDelegationBundleParams {
                lwd,
                session_json: session_json.as_deref(),
                account_uuid: &account_uuid,
                voting_hotkey: &voting_hotkey,
                bundle_index,
                bundle_policy,
            },
        )
        .map_err(|e| e.to_string())?;
        let pir_client = zcash_voting::PirClientBlocking::with_transport(
            &pir_server_url,
            Arc::new(zcash_voting::HyperTransport::new()),
        )
        .map_err(|e| format!("connect to PIR server failed: {e}"))?;
        prepared
            .precompute(&voting_db, &wallet_db, &pir_client)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("delegation PIR precompute task failed: {e}"))?
}

/// Build, prove, and sign one delegation payload.
///
/// Emits progress phases through `on_progress`. The returned value is a signed
/// delegation payload ready for Dart-side submission.
///
/// # Errors
///
/// Returns an error if note/bundle validation, witness
/// generation, PCZT construction, PIR proof generation, or delegation signing
/// fails.
pub async fn build_prove_and_sign_delegation_payload<F>(
    db_path: &str,
    pir_server_url: &str,
    seed: &SecretVec<u8>,
    prepare_params: PrepareDelegationBundleParams<'_>,
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);
    let account_uuid = prepare_params.account_uuid;

    zcash_voting::validate_round_params(&prepare_params.lwd.round_params)
        .map_err(|e| format!("Invalid voting round params: {e}"))?;
    on_progress(DelegationProgress::SelectingNotes);
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let wallet_db = open_wallet_db_for_read(
        db_path,
        wallet_network(prepare_params.voting_hotkey.network()),
    )?;

    let prepared_bundle =
        zcash_voting::delegate::prepare_delegation_bundle(&voting_db, &wallet_db, prepare_params)
            .map_err(|e| e.to_string())?;

    let pczt_progress = on_progress.clone();
    let setup_stages = zcash_voting::DelegationProgressBridge::new(move |progress| {
        pczt_progress(progress);
    });
    let delegation_setup = prepared_bundle
        .setup(&voting_db, &setup_stages)
        .map_err(|e| format!("delegate::setup failed: {e}"))?;

    prove_delegation_bundle(
        db_path,
        pir_server_url,
        account_uuid,
        &prepared_bundle,
        on_progress.clone(),
    )
    .await?;

    on_progress(DelegationProgress::SigningPayload);
    let signing_request = prepared_bundle
        .signing_request(&voting_db)
        .map_err(|e| format!("delegation signing request failed: {e}"))?;
    let (sig, sighash) = sign_delegation_request(seed, signing_request)
        .map_err(|e| format!("delegation signing failed: {e}"))?;
    let signer = zcash_voting::delegate::PreparedSigner::signature(sig, sighash);
    let signed_bundle = prepared_bundle
        .signed_bundle(&voting_db, delegation_setup.pczt_bytes, signer)
        .map_err(|e| format!("delegate::signed_bundle failed: {e}"))?;

    on_progress(DelegationProgress::PayloadReady);
    Ok(signed_bundle)
}

/// Signs a delegation request with the Orchard spend authorizing key derived from
/// the wallet seed and account in the request.
///
/// Returns the detached signature bytes plus the original sighash when the seed,
/// account index, and randomizer all validate.
fn sign_delegation_request(
    seed: &SecretVec<u8>,
    request: DelegationSigningRequest,
) -> Result<([u8; 64], [u8; 32]), String> {
    let seed = seed.expose_secret();
    // Bind the request to this exact wallet seed before deriving any keys.
    let seed_fingerprint = SeedFingerprint::from_seed(seed)
        .ok_or_else(|| "wallet seed length is not valid for ZIP-32".to_string())?;
    if seed_fingerprint.to_bytes() != request.seed_fingerprint {
        return Err(
            "wallet seed fingerprint does not match delegation signing request".to_string(),
        );
    }

    // Derive the account Orchard signing key specified by the request metadata.
    let account = AccountId::try_from(request.account_index)
        .map_err(|_| format!("invalid account_index {}", request.account_index))?;
    let usk = UnifiedSpendingKey::from_seed(&request.network, seed, account)
        .map_err(|e| format!("derive account unified spending key failed: {e}"))?;
    let sk = *usk.orchard();
    let ask = orchard::keys::SpendAuthorizingKey::from(&sk);
    // The alpha randomizer must decode as a canonical Pallas scalar.
    let alpha = Option::<pasta_curves::pallas::Scalar>::from(
        pasta_curves::pallas::Scalar::from_repr(request.alpha),
    )
    .ok_or_else(|| "delegation alpha is not a valid Pallas scalar".to_string())?;
    // Sign the request-specific sighash with the randomized spend auth key.
    let rsk = ask.randomize(&alpha);
    let rng = rand::rngs::OsRng;
    let sig = rsk.sign(rng, &request.sighash);
    Ok(((&sig).into(), request.sighash))
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
pub async fn build_keystone_delegation_request(
    db_path: &str,
    account_uuid: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
) -> Result<zcash_voting::delegate::KeystoneSigningRequest, String> {
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let wallet_db = open_wallet_db_for_read(
        db_path,
        wallet_network(prepare_params.voting_hotkey.network()),
    )?;
    let prepared =
        zcash_voting::delegate::prepare_delegation_bundle(&voting_db, &wallet_db, prepare_params)
            .map_err(|e| e.to_string())?;
    let noop_stages = zcash_voting::NoopProgressReporter;
    prepared
        .keystone_request(&voting_db, &noop_stages)
        .map_err(|e| format!("delegate::keystone_request failed: {e}"))
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
pub async fn build_prove_delegation_payload_with_keystone_signature<F>(
    db_path: &str,
    pir_server_url: &str,
    account_uuid: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
    keystone_sig: &[u8],
    keystone_sighash: &[u8],
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let on_progress = Arc::new(on_progress);

    on_progress(DelegationProgress::SelectingNotes);
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let wallet_db = open_wallet_db_for_read(
        db_path,
        wallet_network(prepare_params.voting_hotkey.network()),
    )?;
    let prepared_bundle =
        zcash_voting::delegate::prepare_delegation_bundle(&voting_db, &wallet_db, prepare_params)
            .map_err(|e| e.to_string())?;
    prove_delegation_bundle(
        db_path,
        pir_server_url,
        account_uuid,
        &prepared_bundle,
        on_progress.clone(),
    )
    .await?;

    on_progress(DelegationProgress::SigningPayload);
    let signer = zcash_voting::delegate::PreparedSigner::signature_from_bytes(
        keystone_sig,
        keystone_sighash,
    )
    .map_err(|e| format!("invalid Keystone signature fields: {e}"))?;
    let signed_bundle = prepared_bundle
        .signed_bundle(&voting_db, Vec::new(), signer)
        .map_err(|e| format!("delegate::signed_bundle failed: {e}"))?;
    on_progress(DelegationProgress::PayloadReady);

    Ok(signed_bundle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::test_support::{ROUND_ID, TEST_ACCOUNT_UUID};
    use ff::PrimeField;
    use orchard::{
        keys::SpendAuthorizingKey,
        primitives::redpallas::{Signature, SpendAuth, VerificationKey},
    };
    use secrecy::ExposeSecret;
    use std::sync::{Arc, Mutex};
    use zip32::{fingerprint::SeedFingerprint, AccountId};

    #[test]
    fn build_prove_and_sign_delegation_payload_rejects_invalid_round_params_before_progress() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let seed = SecretVec::new(vec![7; 32]);
        let events = Arc::new(Mutex::new(Vec::new()));
        let events_for_callback = events.clone();
        let round_params = zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        };
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_prove_and_sign_delegation_payload(
                db_path.to_str().unwrap(),
                "http://127.0.0.1:2",
                &seed,
                PrepareDelegationBundleParams {
                    lwd: zcash_voting::delegate::DelegationLwdInputs {
                        round_params,
                        resolved_round_name: "Demo".to_string(),
                        anchor_tree_state_bytes: Vec::new(),
                        branch_id_provider:
                            zcash_voting::delegate::LightwalletdBranchIdProvider::resolved(0),
                    },
                    session_json: None,
                    account_uuid: TEST_ACCOUNT_UUID,
                    voting_hotkey: &zcash_voting::VotingHotkey::from_stored_secret(
                        &[9; 32],
                        zcash_voting::Network::Regtest,
                    )
                    .unwrap(),
                    bundle_index: 0,
                    bundle_policy: BundlePolicy::default(),
                },
                move |event| events_for_callback.lock().unwrap().push(event),
            ))
            .unwrap_err();

        assert!(err.contains("Invalid voting round params"));
        assert!(events.lock().unwrap().is_empty());
    }

    #[test]
    fn sign_delegation_request_happy_path_signs_and_verifies() {
        let seed = SecretVec::new(vec![0x42; 32]);
        let account_index = 0u32;
        let account = AccountId::try_from(account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(
            &zcash_voting::Network::Testnet,
            seed.expose_secret(),
            account,
        )
        .unwrap();
        let ask = SpendAuthorizingKey::from(usk.orchard());
        let alpha = pasta_curves::pallas::Scalar::from(7);
        let sighash = [0xAB; 32];
        let request = DelegationSigningRequest {
            account_index,
            network: zcash_voting::Network::Testnet,
            seed_fingerprint: SeedFingerprint::from_seed(seed.expose_secret())
                .unwrap()
                .to_bytes(),
            sighash,
            alpha: alpha.to_repr(),
        };

        let (sig_bytes, returned_sighash) = sign_delegation_request(&seed, request).unwrap();

        let verification_key = VerificationKey::from(&ask.randomize(&alpha));
        verification_key
            .verify(&sighash, &Signature::<SpendAuth>::from(sig_bytes))
            .unwrap();
        assert_eq!(returned_sighash, sighash);
    }
}
