use std::sync::Arc;

use ff::PrimeField;
use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zeroize::Zeroizing;
use zip32::{fingerprint::SeedFingerprint, AccountId};

use crate::wallet::sync::open_wallet_db_for_read;
use crate::wallet::voting::network::wallet_network;

use super::db::open_voting_db;

use zcash_voting::config::PirLayout;
pub use zcash_voting::delegate::DelegationProgress;
use zcash_voting::delegate::{
    DelegationSigningRequest, PrepareDelegationBundleParams, PreparedDelegationBundle,
};
use zcash_voting::selection::select_notes_with_lwd;
use zcash_voting::storage::VotingDb;
use zcash_voting::BundlePolicy;

const ZATOSHI_PER_ZEC: u64 = 100_000_000;
const WHALE_PROTECTION_BUNDLE_ADDITION_THRESHOLD_ZATOSHI: u64 = 25_000 * ZATOSHI_PER_ZEC;

/// Start a new bundle before adding a note would cross the whale threshold.
///
/// `zcash_voting` owns the final bundle planning. Vizor only supplies the
/// threshold used when deciding whether another note can join a bundle.
fn whale_protected_bundle_policy(bundle_policy: BundlePolicy) -> BundlePolicy {
    bundle_policy.with_bundle_addition_threshold(WHALE_PROTECTION_BUNDLE_ADDITION_THRESHOLD_ZATOSHI)
}

fn prepare_params_with_whale_protection<'a>(
    mut prepare_params: PrepareDelegationBundleParams<'a>,
) -> PrepareDelegationBundleParams<'a> {
    prepare_params.bundle_policy = whale_protected_bundle_policy(prepare_params.bundle_policy);
    prepare_params
}

fn normalize_pir_server_urls(pir_server_urls: &[String]) -> Result<Vec<String>, String> {
    let mut normalized = Vec::with_capacity(pir_server_urls.len());
    for raw_url in pir_server_urls {
        let url = raw_url.trim();
        if url.is_empty() {
            return Err("PIR server URLs must not contain an empty URL".to_string());
        }
        if !normalized.iter().any(|existing| existing == url) {
            normalized.push(url.to_string());
        }
    }
    if normalized.is_empty() {
        return Err("at least one PIR server URL is required".to_string());
    }
    Ok(normalized)
}

fn is_retryable_pir_query_error(error: &str) -> bool {
    let message = error.to_ascii_lowercase();
    let has_pir_context = message.contains("pir parallel fetch failed")
        || message.contains("connect to pir server failed")
        || message.contains("pir http request timed out");
    if !has_pir_context {
        return false;
    }
    if message.contains("pir http request timed out")
        || message.contains("send http request")
        || message.contains("read http response body")
    {
        return true;
    }

    ["http status ", "http "].iter().any(|prefix| {
        message.match_indices(prefix).any(|(index, prefix)| {
            let remainder = &message[index + prefix.len()..];
            let Some(digits) = remainder.get(..3) else {
                return false;
            };
            if remainder.as_bytes().get(3).is_some_and(u8::is_ascii_digit) {
                return false;
            }
            let Ok(status) = digits.parse::<u16>() else {
                return false;
            };
            status == 408 || status == 429 || (500..=599).contains(&status)
        })
    })
}

fn with_pir_endpoint_failover<T>(
    pir_server_urls: &[String],
    mut operation: impl FnMut(&str) -> Result<T, String>,
) -> Result<T, String> {
    for (attempt, url) in pir_server_urls.iter().enumerate() {
        match operation(url) {
            Ok(result) => return Ok(result),
            Err(error) => {
                let retryable = is_retryable_pir_query_error(&error);
                let has_failover = attempt + 1 < pir_server_urls.len();
                log::warn!(
                    "delegation PIR attempt failed endpoint={} attempt={}/{} retryable={} error={}",
                    url,
                    attempt + 1,
                    pir_server_urls.len(),
                    retryable,
                    error
                );
                if !retryable || !has_failover {
                    return Err(error);
                }
            }
        }
    }

    Err("delegation PIR failover exited without an endpoint attempt".to_string())
}

/// Completes the proof phase for a previously prepared delegation bundle.
///
/// Opens the voting database for `account_uuid`, then runs bundle proving on a
/// blocking worker thread while forwarding `DelegationProgress` updates to
/// `on_progress`. Retryable PIR transport failures rotate through the remaining
/// exact-snapshot endpoints while reusing the same prepared bundle.
///
/// # Errors
///
/// Returns an error if opening the voting database fails, connecting to the PIR
/// server fails, the underlying `PreparedDelegationBundle::prove` call fails, or
/// the spawned blocking task is cancelled or panics.
async fn prove_delegation_bundle<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    account_uuid: &str,
    prepared: &PreparedDelegationBundle,
    on_progress: Arc<F>,
) -> Result<(), String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let proof_db_path = db_path.to_string();
    let proof_pir_server_urls = pir_server_urls.to_vec();
    let proof_account_uuid = account_uuid.to_string();
    let prepared = prepared.clone();
    let proof_progress = on_progress.clone();
    tokio::task::spawn_blocking(move || {
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let reporter = zcash_voting::DelegationProgressBridge::new(move |progress| {
            proof_progress(progress);
        });
        with_pir_endpoint_failover(&proof_pir_server_urls, |pir_server_url| {
            let pir_client = zcash_voting::connect_pir_blocking(
                pir_layout,
                pir_server_url,
                Arc::new(zcash_voting::HyperTransport::new()),
            )
            .map_err(|e| format!("connect to PIR server failed: {e}"))?;
            prepared
                .prove(&proof_voting_db, &pir_client, &reporter)
                .map(|_| ())
                .map_err(|e| format!("delegate::prove failed: {e}"))
        })
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
        network,
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
    let bundle_policy = whale_protected_bundle_policy(bundle_policy);
    voting_db
        .ensure_bundles_with_skipped_suffix_with_policy(
            round_params.vote_round_id.as_str(),
            &note_infos,
            bundle_policy,
        )
        .map_err(|e| format!("ensure_bundles_with_skipped_suffix failed: {e}"))
}

/// Minimum voting eligibility plus the note value the privacy trim withholds.
///
/// Both come from one bundle plan. The withheld value is raw note value, not
/// bundle-quantized voting weight, and it is reported separately from
/// `dropped_count` (sub-ballot notes, already worth zero ballots).
///
/// This narrows the plan to the one field the API layer needs so bundle
/// contents do not leak into the FRB boundary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingEligibilityReport {
    pub eligibility: zcash_voting::MinimumVotingEligibility,
    pub privacy_trim_dropped_value_zatoshi: u64,
}

/// Reports eligibility and the privacy-trim loss for an already-selected note set.
///
/// Split out from [`check_voting_eligibility`] so the planning behavior can be
/// tested without lightwalletd note selection.
///
/// `seed_policy` is only what an unplanned round would be planned with. Once a
/// round has a plan, its stored policy is authoritative, so the policy is
/// resolved from round state rather than assumed from the seed -- otherwise the
/// preview describes a plan the round would not actually derive.
///
/// # Errors
///
/// Returns an error if the round policy cannot be resolved or if any selected
/// note row is malformed.
fn voting_eligibility_report(
    voting_db: &VotingDb,
    round_id: &str,
    note_infos: &[zcash_voting::types::NoteInfo],
    seed_policy: BundlePolicy,
) -> Result<VotingEligibilityReport, String> {
    let bundle_policy = voting_db
        .effective_bundle_policy(round_id, seed_policy)
        .map_err(|e| e.to_string())?;
    // One plan, so the reported weight and the reported loss cannot describe
    // different bundle sets. This also applies the canonical duplicate-nullifier
    // collapse rather than repeating it here.
    let (eligibility, plan) =
        zcash_voting::minimum_voting_eligibility_and_plan_for_notes(note_infos, bundle_policy)
            .map_err(|e| e.to_string())?;
    Ok(VotingEligibilityReport {
        eligibility,
        privacy_trim_dropped_value_zatoshi: plan.privacy_trim.dropped_value,
    })
}

/// Select notes and check whether a wallet can vote without persisting bundles.
///
/// The selected notes are taken at the round snapshot height. The result uses
/// the same smart bundle quantization that delegation setup uses, but this path
/// does not initialize round rows or create bundle rows in the sidecar DB.
///
/// # Errors
///
/// Returns an error if lightwalletd note selection fails, the round policy
/// cannot be resolved, or any selected note row is malformed.
pub async fn check_voting_eligibility(
    voting_db: &VotingDb,
    db_path: &str,
    lightwalletd_url: &str,
    network: zcash_voting::Network,
    round_id: &str,
    snapshot_height: u64,
    bundle_policy: BundlePolicy,
) -> Result<VotingEligibilityReport, String> {
    let selected = select_notes_with_lwd(
        voting_db,
        db_path,
        lightwalletd_url,
        network,
        snapshot_height,
    )
    .await
    .map_err(|e| e.to_string())?;
    let note_infos = selected.voting_note_infos();
    let seed_policy = whale_protected_bundle_policy(bundle_policy);
    voting_eligibility_report(voting_db, round_id, &note_infos, seed_policy)
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
    pir_layout: PirLayout,
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
    let network = voting_hotkey.network();
    let stored_hotkey_secret = Zeroizing::new(voting_hotkey.stored_secret().to_vec());

    tokio::task::spawn_blocking(move || {
        let voting_hotkey = zcash_voting::VotingHotkey::from_stored_secret(
            stored_hotkey_secret.as_slice(),
            network,
        )
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;
        let voting_db = open_voting_db(&db_path, &account_uuid)?;
        let wallet_db = open_wallet_db_for_read(&db_path, wallet_network(voting_hotkey.network()))?;
        let prepare_params = PrepareDelegationBundleParams {
            lwd,
            session_json: session_json.as_deref(),
            account_uuid: &account_uuid,
            voting_hotkey: &voting_hotkey,
            bundle_index,
            bundle_policy,
        };
        let prepare_params = prepare_params_with_whale_protection(prepare_params);
        let prepared = zcash_voting::delegate::prepare_delegation_bundle(
            &voting_db,
            &wallet_db,
            prepare_params,
        )
        .map_err(|e| e.to_string())?;
        let pir_client = zcash_voting::connect_pir_blocking(
            pir_layout,
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
/// delegation payload ready for Dart-side submission. PIR endpoints are tried
/// in order only for retryable transport failures, reusing one prepared bundle.
///
/// # Errors
///
/// Returns an error if note/bundle validation, witness
/// generation, PCZT construction, PIR proof generation, or delegation signing
/// fails.
pub async fn build_prove_and_sign_delegation_payload<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    seed: &SecretVec<u8>,
    prepare_params: PrepareDelegationBundleParams<'_>,
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let pir_server_urls = normalize_pir_server_urls(pir_server_urls)?;
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
    let prepare_params = prepare_params_with_whale_protection(prepare_params);

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
        &pir_server_urls,
        pir_layout,
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
    let rng = voting_crypto_deps::rand::rngs::OsRng;
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
    let prepare_params = prepare_params_with_whale_protection(prepare_params);
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
/// Retryable PIR transport failures rotate through `pir_server_urls` without
/// rebuilding that request.
///
/// # Errors
///
/// Returns an error if proof generation fails, the Keystone signature does not
/// match the stored PCZT sighash, or submission payload reconstruction fails.
pub async fn build_prove_delegation_payload_with_keystone_signature<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    account_uuid: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
    keystone_sig: &[u8],
    keystone_sighash: &[u8],
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let pir_server_urls = normalize_pir_server_urls(pir_server_urls)?;
    let on_progress = Arc::new(on_progress);

    on_progress(DelegationProgress::SelectingNotes);
    let voting_db = open_voting_db(db_path, account_uuid)?;
    let wallet_db = open_wallet_db_for_read(
        db_path,
        wallet_network(prepare_params.voting_hotkey.network()),
    )?;
    let prepare_params = prepare_params_with_whale_protection(prepare_params);
    let prepared_bundle =
        zcash_voting::delegate::prepare_delegation_bundle(&voting_db, &wallet_db, prepare_params)
            .map_err(|e| e.to_string())?;
    prove_delegation_bundle(
        db_path,
        &pir_server_urls,
        pir_layout,
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

    fn note_with_value(position: u64, value: u64) -> zcash_voting::NoteInfo {
        let tag = position as u8;
        zcash_voting::NoteInfo {
            commitment: vec![tag; 32],
            nullifier: vec![tag.wrapping_add(1); 32],
            value,
            position,
            diversifier: vec![tag; 11],
            rho: vec![tag; 32],
            rseed: vec![tag; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }

    #[test]
    fn pir_endpoint_failover_rotates_after_retryable_transport_error() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let result = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            if url.contains("primary") {
                Err(
                    "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request"
                        .to_string(),
                )
            } else {
                Ok("proof")
            }
        })
        .unwrap();

        assert_eq!(result, "proof");
        assert_eq!(attempts, urls);
    }

    #[test]
    fn pir_endpoint_failover_stops_on_validation_error() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let error = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            Err::<(), _>(
                "delegate::prove failed: connected PIR circuit root does not match".to_string(),
            )
        })
        .unwrap_err();

        assert!(error.contains("circuit root"));
        assert_eq!(attempts, vec![urls[0].clone()]);
    }

    #[test]
    fn pir_endpoint_failover_returns_last_error_after_exhaustion() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let error = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            Err::<(), _>(format!(
                "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request to {url}"
            ))
        })
        .unwrap_err();

        assert!(error.contains(&urls[1]));
        assert_eq!(attempts, urls);
    }

    #[test]
    fn pir_query_retry_classifier_is_transport_only() {
        for error in [
            "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request",
            "connect to PIR server failed: PIR HTTP request timed out",
            "PIR parallel fetch failed: read HTTP response body: connection closed",
            "PIR parallel fetch failed: tier1 query failed: HTTP 503",
            "PIR parallel fetch failed: tier1 query failed: HTTP status 521",
        ] {
            assert!(is_retryable_pir_query_error(error), "{error}");
        }
        for error in [
            "delegate::prove failed: connected PIR circuit root does not match",
            "PIR parallel fetch failed: invalid proof encoding",
            "PIR parallel fetch failed: tier1 query failed: HTTP 400",
            "PIR parallel fetch failed: tier1 query failed: HTTP 5000",
            "network: gRPC connect failed: send HTTP request",
        ] {
            assert!(!is_retryable_pir_query_error(error), "{error}");
        }
    }

    #[test]
    fn pir_server_url_normalization_rejects_empty_and_deduplicates() {
        let normalized = normalize_pir_server_urls(&[
            " https://pir.example ".to_string(),
            "https://pir.example".to_string(),
            "https://pir-backup.example".to_string(),
        ])
        .unwrap();
        assert_eq!(
            normalized,
            vec![
                "https://pir.example".to_string(),
                "https://pir-backup.example".to_string(),
            ]
        );
        assert!(normalize_pir_server_urls(&[]).is_err());
        assert!(normalize_pir_server_urls(&[" ".to_string()]).is_err());
    }

    #[test]
    fn whale_protection_starts_new_bundle_when_addition_would_cross_threshold() {
        let notes = vec![
            note_with_value(1, 10_000 * ZATOSHI_PER_ZEC),
            note_with_value(2, 10_000 * ZATOSHI_PER_ZEC),
            note_with_value(3, 5_000 * ZATOSHI_PER_ZEC),
            note_with_value(4, ZATOSHI_PER_ZEC),
        ];
        let default_plan =
            zcash_voting::round::note_bundles_with_policy(&notes, BundlePolicy::default()).unwrap();
        assert_eq!(default_plan[0].len(), 4);

        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        let protected_plan = zcash_voting::round::note_bundles_with_policy(&notes, policy).unwrap();
        let protected_positions: Vec<Vec<u64>> = protected_plan
            .iter()
            .map(|bundle| bundle.iter().map(|note| note.position).collect())
            .collect();

        assert_eq!(protected_plan.len(), 2);
        assert!(protected_positions.contains(&vec![1, 2, 3]));
        assert!(protected_positions.contains(&vec![4]));

        // The whale threshold and the privacy trim pull in opposite directions.
        // They compose because a 1% / 1000 ZEC drop budget can never pay for a
        // bundle sized near the 25,000 ZEC threshold, so splitting a whale never
        // costs it the bundle the split just created.
        let trim =
            zcash_voting::note_bundling::chunk_notes_with_policy(&notes, policy).privacy_trim;
        assert!(trim.is_empty());
    }

    /// Opens a fresh sidecar DB with the round row the report path looks up.
    fn test_voting_db(temp_dir: &tempfile::TempDir) -> VotingDb {
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &zcash_voting::VotingRoundParams {
                vote_round_id: ROUND_ID.to_string(),
                snapshot_height: 100,
                ea_pk: vec![1],
                nc_root: vec![2; 32],
                nullifier_imt_root: vec![3; 32],
            },
            None,
        )
        .unwrap();
        db
    }

    /// Two 500 ZEC notes plus a 15-note 1 ZEC tail: the shape the trim exists for.
    ///
    /// Bundles pack five notes each, so this plans as 1003 / 5 / 5 / 2 ZEC.
    fn whale_with_dust_tail_notes() -> Vec<zcash_voting::NoteInfo> {
        let mut notes = vec![
            note_with_value(1, 500 * ZATOSHI_PER_ZEC),
            note_with_value(2, 500 * ZATOSHI_PER_ZEC),
        ];
        notes.extend((3..18).map(|position| note_with_value(position, ZATOSHI_PER_ZEC)));
        notes
    }

    #[test]
    fn voting_eligibility_report_surfaces_the_privacy_trim_for_a_dust_tail() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Budget is 1% of 1015 ZEC, which pays for the 2 ZEC and 5 ZEC tail
        // bundles and then hits the 2-bundle target.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            7 * ZATOSHI_PER_ZEC
        );
        assert!(report.eligibility.is_eligible());
        assert_eq!(
            report.eligibility.eligible_weight,
            1008 * ZATOSHI_PER_ZEC,
            "the reported weight must be the post-trim weight"
        );
    }

    #[test]
    fn voting_eligibility_report_withholds_nothing_from_uniform_notes() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        // No single tail bundle fits the budget, so a uniform holder cannot be
        // trimmed at all. This is a documented no-op case upstream; pin it so a
        // policy change cannot start quietly costing these voters weight.
        let notes: Vec<_> = (1..=20)
            .map(|position| note_with_value(position, 50 * ZATOSHI_PER_ZEC))
            .collect();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        assert_eq!(report.privacy_trim_dropped_value_zatoshi, 0);
        assert_eq!(report.eligibility.eligible_weight, 1000 * ZATOSHI_PER_ZEC);
    }

    #[test]
    fn voting_eligibility_report_matches_what_a_planned_round_actually_withheld() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        let layout = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        assert!(layout.privacy_trim_dropped_value_zatoshi > 0);

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // The round stored a trimming policy, so the preview must agree with
        // the plan storage holds. Deriving this from the bundle count alone
        // would report zero for a round that genuinely withheld value.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            layout.privacy_trim_dropped_value_zatoshi
        );
        assert_eq!(report.eligibility.eligible_weight, layout.eligible_weight);
    }

    #[test]
    fn voting_eligibility_report_withholds_nothing_for_a_round_migrated_from_launch() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy.with_max_privacy_bundles(None))
            .unwrap();
        // A round carried across the in-place schema upgrade has bundle rows
        // but no stored policy, and re-derives without the trim.
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = NULL WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
            )
            .unwrap();

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Warning these voters about weight they are not losing is the worse
        // failure, so the preview must stay silent for them.
        assert_eq!(report.privacy_trim_dropped_value_zatoshi, 0);
        assert_eq!(report.eligibility.eligible_weight, 1015 * ZATOSHI_PER_ZEC);
    }

    #[test]
    fn voting_eligibility_report_ignores_duplicate_nullifiers() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let mut notes = whale_with_dust_tail_notes();
        notes.extend(whale_with_dust_tail_notes());
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Duplicates must collapse before planning, or the trim preview would
        // describe a different note set than the eligibility weight beside it.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            7 * ZATOSHI_PER_ZEC
        );
        assert_eq!(report.eligibility.eligible_weight, 1008 * ZATOSHI_PER_ZEC);
    }

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
        let pir_server_urls = vec!["http://127.0.0.1:2".to_string()];
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_prove_and_sign_delegation_payload(
                db_path.to_str().unwrap(),
                &pir_server_urls,
                PirLayout {
                    pir_depth: 19,
                    tier0_layers: 12,
                    tier1_layers: 7,
                    poly_len: 4096,
                },
                &seed,
                PrepareDelegationBundleParams {
                    lwd: zcash_voting::delegate::DelegationLwdInputs {
                        network: zcash_voting::Network::Regtest,
                        round_params,
                        resolved_round_name: "Demo".to_string(),
                        anchor_tree_state_bytes: Vec::new(),
                        branch_id_provider:
                            zcash_voting::delegate::LightwalletdBranchIdProvider::resolved(0),
                    },
                    session_json: None,
                    account_uuid: TEST_ACCOUNT_UUID,
                    voting_hotkey: &zcash_voting::VotingHotkey::from_stored_secret(
                        &[9; 64],
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
