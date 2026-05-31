use std::{panic, sync::Arc};

use crate::frb_generated::StreamSink;
use crate::wallet::{
    keys,
    network::WalletNetwork,
    voting::{delegation, delegation::DelegationProgress, hotkey, state},
};
use rand::{rngs::OsRng, RngCore};
use secrecy::ExposeSecret;
use zcash_voting::BundlePolicy;
use zeroize::Zeroizing;

pub use zcash_voting::vote::{DraftVote, SignedVoteCommitments};

#[derive(Clone, Debug, PartialEq)]
/// Progress event emitted while building, proving, and signing a delegation payload.
///
/// A terminal `"result"` event carries `signed_delegation_payload`; earlier
/// phase events only describe local preparation progress.
pub struct ApiDelegationProofEvent {
    pub phase: String,
    pub proof_progress: Option<f64>,
    pub signed_delegation_payload: Option<zcash_voting::wire::SignedDelegationPayloadView>,
}

#[derive(Clone, Debug, PartialEq)]
/// Progress event emitted while building ZKP2 vote commitments.
///
/// A terminal `"result"` event carries the completed commitment set; earlier
/// phase events include the active `(proposal_id, bundle_index)` pair.
pub struct ApiVoteCommitEvent {
    pub phase: String,
    pub proposal_id: Option<u32>,
    pub bundle_index: Option<u32>,
    pub proof_progress: Option<f64>,
    pub commitments: Option<zcash_voting::wire::SignedVoteCommitmentsView>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// One vote-chain event attribute from a confirmed transaction.
pub struct ApiTxEventAttribute {
    pub key: String,
    pub value: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// One vote-chain event from a confirmed transaction.
pub struct ApiTxEvent {
    pub event_type: String,
    pub attributes: Vec<ApiTxEventAttribute>,
}

fn bundle_policy(max_real_notes_per_bundle: Option<u32>) -> Result<BundlePolicy, String> {
    BundlePolicy::from_optional_max_real_notes_per_bundle(max_real_notes_per_bundle)
        .map_err(|e| e.to_string())
}

fn seed_from_mnemonic(mnemonic: String) -> Result<secrecy::SecretVec<u8>, String> {
    let mnemonic = Zeroizing::new(mnemonic.into_bytes());
    keys::mnemonic_bytes_to_seed(mnemonic.as_slice())
}

impl From<ApiTxEventAttribute> for zcash_voting::confirmation::TxEventAttribute {
    fn from(attribute: ApiTxEventAttribute) -> Self {
        Self {
            key: attribute.key,
            value: attribute.value,
        }
    }
}

impl From<ApiTxEvent> for zcash_voting::confirmation::TxEvent {
    fn from(event: ApiTxEvent) -> Self {
        Self {
            event_type: event.event_type,
            attributes: event.attributes.into_iter().map(Into::into).collect(),
        }
    }
}

/// Returns the vote-chain delegation submission body as validated wire JSON.
///
/// Binary fields are base64-encoded here so Dart does not duplicate protocol
/// field names or byte encoding rules.
pub fn delegation_submission_wire_json(
    submission: zcash_voting::wire::SignedDelegationPayloadView,
) -> Result<String, String> {
    catch(|| submission.submission.to_json().map_err(|e| e.to_string()))
}

/// Returns the vote-chain cast-vote submission body as validated wire JSON.
pub fn vote_commitment_wire_json(
    commitment: zcash_voting::wire::VoteCommitmentWire,
) -> Result<String, String> {
    catch(|| commitment.to_json().map_err(|e| e.to_string()))
}

/// Returns the helper-server encrypted-share submission body as wire JSON.
pub fn vote_share_wire_json(
    share: zcash_voting::wire::VoteShareWire,
    vc_tree_position: Option<u64>,
    submit_at: u64,
) -> Result<String, String> {
    catch(|| {
        share
            .with_late_bound(vc_tree_position, submit_at)
            .and_then(|share| share.to_json())
            .map_err(|e| e.to_string())
    })
}

/// Plan independent helper-share timing and randomized helper targets.
///
/// This mirrors the zcash-swift-wallet-sdk wrapper around
/// `zcash_voting::share_policy::plan_share_submissions`, with Rust drawing the
/// policy-sized entropy from the OS CSPRNG before returning FRB-safe plans.
pub fn plan_share_submissions(
    share_count: u32,
    server_urls: Vec<String>,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> Result<Vec<zcash_voting::wire::ShareSubmissionPlan>, String> {
    catch(|| {
        let share_count = usize::try_from(share_count)
            .map_err(|_| "share_count does not fit in usize".to_string())?;
        let required = zcash_voting::share_policy::share_submission_random_bytes_required(
            share_count,
            server_urls.len(),
            now_seconds,
            vote_end_time_seconds,
            last_moment_buffer_seconds,
            single_share,
        );
        let mut submit_at_random_bytes = vec![0u8; required.submit_at_random_bytes];
        let mut server_random_bytes = vec![0u8; required.server_random_bytes];
        OsRng
            .try_fill_bytes(&mut submit_at_random_bytes)
            .map_err(|e| format!("failed to draw submit_at entropy: {e}"))?;
        OsRng
            .try_fill_bytes(&mut server_random_bytes)
            .map_err(|e| format!("failed to draw share-server entropy: {e}"))?;

        let plans = zcash_voting::share_policy::plan_share_submissions(
            share_count,
            &server_urls,
            now_seconds,
            vote_end_time_seconds,
            last_moment_buffer_seconds,
            single_share,
            &submit_at_random_bytes,
            &server_random_bytes,
        )
        .map_err(|e| e.to_string())?;

        Ok(plans)
    })
}

/// Return helper-share resubmission order using `zcash_voting` policy.
///
/// The crate keeps untried helpers ahead of helpers that already accepted the
/// share, while randomizing each group with OS entropy.
pub fn share_resubmission_server_order(
    configured_server_urls: Vec<String>,
    sent_to_urls: Vec<String>,
) -> Result<Vec<String>, String> {
    catch(|| {
        let random_bytes_required =
            zcash_voting::share::policy::resubmission_server_order_random_bytes_required(
                &configured_server_urls,
                &sent_to_urls,
            );
        let mut random_bytes = vec![0u8; random_bytes_required];
        OsRng.fill_bytes(&mut random_bytes);
        zcash_voting::share::policy::resubmission_server_order(
            &configured_server_urls,
            &sent_to_urls,
            &random_bytes,
        )
        .map_err(|e| e.to_string())
    })
}

/// Return share-tracking action flags using `zcash_voting::share_policy`.
///
/// Bit 0 means the share is ready for status polling. Bit 1 means it is overdue
/// and should be retried using the crate resubmission order.
pub fn share_tracking_flags(
    share: zcash_voting::wire::ShareDelegationRecordView,
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
) -> Result<u32, String> {
    catch(|| {
        let share = share_tracking_record(&share);
        let policy = zcash_voting::share::ShareTimingPolicy::default();
        let mut flags = 0u32;
        if zcash_voting::share::policy::is_share_ready_for_status_check(&share, now_seconds, policy)
        {
            flags |= 1;
        }
        if vote_end_time_seconds
            .map(|vote_end_time_seconds| {
                zcash_voting::share::policy::should_resubmit_share(
                    &share,
                    now_seconds,
                    vote_end_time_seconds,
                    policy,
                )
            })
            .unwrap_or(false)
        {
            flags |= 2;
        }
        Ok(flags)
    })
}

/// Return the next share-tracking delay in seconds using crate policy.
pub fn next_share_tracking_delay_seconds(
    shares: Vec<zcash_voting::wire::ShareDelegationRecordView>,
    now_seconds: u64,
) -> Result<Option<u64>, String> {
    catch(|| {
        let shares = shares.iter().map(share_tracking_record).collect::<Vec<_>>();
        Ok(zcash_voting::share::policy::next_tracking_delay_seconds(
            &shares,
            now_seconds,
            zcash_voting::share::ShareTimingPolicy::default(),
        ))
    })
}

/// Extract and validate one helper-share payload from stored recovery JSON.
///
/// The stored recovery blob is hex-encoded and also contains local-only
/// recovery material. This helper emits only the public base64 wire shape that
/// helper servers accept.
pub fn recovered_vote_share_wire_json(
    commitment_bundle_json: String,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String, String> {
    catch(|| {
        zcash_voting::share::recover_wire_json(
            &commitment_bundle_json,
            proposal_id,
            share_index,
            vc_tree_position,
            submit_at,
        )
        .map_err(|e| e.to_string())
    })
}

/// Derive the opaque per-account, per-round voting hotkey bytes.
///
/// Rust derives the wallet seed from the account mnemonic, then derives scoped
/// hotkey seed material locally and returns bytes for secure storage.
/// The returned `Vec<u8>` is an unavoidable FRB copy boundary
pub fn derive_voting_hotkey(
    mnemonic: String,
    round_id: String,
    account_uuid: String,
    network: String,
) -> Result<Vec<u8>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = seed_from_mnemonic(mnemonic)?;
        hotkey::derive_hotkey(&seed, &round_id, &account_uuid, network).map(|hotkey| {
            // FRB returns owned bytes, so this copy cannot be zeroized by Rust
            // after Dart receives it.
            hotkey.expose_secret().to_vec()
        })
    })
}

/// Generate opaque voting hotkey bytes for a hardware account.
///
/// Hardware accounts cannot expose their wallet seed to derive the deterministic
/// software hotkey, so the app persists this random per-round hotkey in secure
/// storage and reuses it for vote commitment signing.
pub fn generate_voting_hotkey(network: String) -> Result<Vec<u8>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        hotkey::generate_random_hotkey(network).map(|hotkey| {
            // FRB returns owned bytes, so this copy cannot be zeroized by Rust
            // after Dart receives it.
            hotkey.expose_secret().to_vec()
        })
    })
}

impl From<DelegationProgress> for ApiDelegationProofEvent {
    fn from(progress: DelegationProgress) -> Self {
        match progress {
            DelegationProgress::SelectingNotes => Self {
                phase: "selecting_notes".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            DelegationProgress::PcztBuilding | DelegationProgress::PcztBuilt => Self {
                phase: "building_pczt".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofStarting => Self {
                phase: "building_proof".to_string(),
                proof_progress: Some(0.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofProgress(value) => Self {
                phase: "proof_progress".to_string(),
                proof_progress: Some(value),
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofComplete => Self {
                phase: "proof_progress".to_string(),
                proof_progress: Some(1.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::SigningPayload => Self {
                phase: "signing_payload".to_string(),
                proof_progress: Some(1.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::PayloadReady => Self {
                phase: "payload_ready".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            _ => Self {
                phase: "delegation_progress".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
        }
    }
}

impl From<zcash_voting::vote::VoteCommitStage> for ApiVoteCommitEvent {
    fn from(event: zcash_voting::vote::VoteCommitStage) -> Self {
        match event {
            zcash_voting::vote::VoteCommitStage::ProofStarting {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "building_proof".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(0.0),
                commitments: None,
            },
            zcash_voting::vote::VoteCommitStage::ProofProgress {
                proposal_id,
                bundle_index,
                progress,
            } => Self {
                phase: "proof_progress".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(progress),
                commitments: None,
            },
            zcash_voting::vote::VoteCommitStage::SharePayloadsBuilding {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "building_share_payloads".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(1.0),
                commitments: None,
            },
            zcash_voting::vote::VoteCommitStage::Signing {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "signing".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: None,
                commitments: None,
            },
            _ => Self {
                phase: "vote_commit_stage".to_string(),
                proposal_id: None,
                bundle_index: None,
                proof_progress: None,
                commitments: None,
            },
        }
    }
}

fn share_tracking_record(
    share: &zcash_voting::wire::ShareDelegationRecordView,
) -> zcash_voting::ShareDelegationRecord {
    zcash_voting::ShareDelegationRecord {
        round_id: share.round_id.clone(),
        bundle_index: share.bundle_index,
        proposal_id: share.proposal_id,
        share_index: share.share_index,
        sent_to_urls: share.sent_to_urls.clone(),
        nullifier: share.nullifier.clone(),
        confirmed: share.confirmed,
        submit_at: share.submit_at,
        created_at: share.created_at,
    }
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

/// Select notes and persist bundle rows for the delegation pipeline.
///
/// Reuses existing bundle rows for the same round/wallet, so callers can safely
/// retry setup before proving a specific bundle.
pub async fn setup_delegation_bundles(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    max_real_notes_per_bundle: Option<u32>,
) -> Result<zcash_voting::wire::BundleLayout, String> {
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    let voting_db = state::open_voting_db(&db_path, &account_uuid)?;
    delegation::setup_delegation_bundles(
        &voting_db,
        &db_path,
        &lightwalletd_url,
        &network,
        round_params,
        &round_name,
        session_json.as_deref(),
        bundle_policy,
    )
    .await
    .map(zcash_voting::wire::BundleLayout::from)
}

#[allow(clippy::too_many_arguments)]
/// Build delegation PCZT material and prefetch/cache PIR-backed IMT proofs.
///
/// This is a background warm-up path. The normal proof path still fetches any
/// missing PIR proofs if this was not run or did not complete in time.
pub async fn precompute_delegation_pir(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    mnemonic: String,
    bundle_index: u32,
    max_real_notes_per_bundle: Option<u32>,
) -> Result<zcash_voting::wire::DelegationPirPrecomputeResultView, String> {
    let network = keys::parse_network(&network)?;
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    let seed = seed_from_mnemonic(mnemonic)?;
    delegation::precompute_delegation_pir(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params,
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed,
        bundle_index,
        bundle_policy,
    )
    .await
    .map(zcash_voting::wire::DelegationPirPrecomputeResultView::from)
}

#[allow(clippy::too_many_arguments)]
/// Streaming variant of `build_prove_and_sign_delegation_payload`.
///
/// Emits local preparation phase events while work progresses, then emits a
/// final `"result"` event containing `SignedDelegationPayloadView`. The function
/// returns `Ok(())` after the terminal event is queued.
pub async fn build_prove_and_sign_delegation_payload_with_progress(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    mnemonic: String,
    bundle_index: u32,
    max_real_notes_per_bundle: Option<u32>,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    let seed = seed_from_mnemonic(mnemonic)?;
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let signed_result = delegation::build_prove_and_sign_delegation_payload(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params,
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed,
        bundle_index,
        bundle_policy,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                log::warn!("voting delegation: StreamSink closed, progress not delivered");
            }
        },
    )
    .await
    .and_then(|bundle| {
        zcash_voting::wire::SignedDelegationPayloadView::try_from(bundle).map_err(|e| e.to_string())
    });
    let signed = match signed_result {
        Ok(signed) => signed,
        Err(error) => {
            if sink.add_error(error.clone()).is_err() {
                log::warn!("voting delegation: StreamSink closed before error delivery");
            }
            return Ok(());
        }
    };

    if sink
        .add(ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(signed),
        })
        .is_err()
    {
        log::warn!("voting delegation: StreamSink closed before final result");
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
/// Build and redact a voting PCZT that Keystone must sign for one bundle.
pub async fn build_keystone_delegation_request(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    hotkey_seed: Vec<u8>,
    bundle_index: u32,
    max_real_notes_per_bundle: Option<u32>,
) -> Result<zcash_voting::wire::KeystoneSigningRequest, String> {
    let network = keys::parse_network(&network)?;
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    let hotkey_secret = secrecy::SecretVec::new(hotkey_seed);
    delegation::build_keystone_delegation_request(
        &db_path,
        &lightwalletd_url,
        network,
        round_params,
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &hotkey_secret,
        bundle_index,
        bundle_policy,
    )
    .await
    .map(zcash_voting::wire::KeystoneSigningRequest::from)
}

/// Validate and persist a Keystone signed-PCZT response for one delegation bundle.
pub fn accept_keystone_signature(
    db_path: String,
    wallet_id: String,
    round_id: String,
    request: zcash_voting::wire::KeystoneSigningRequest,
    signed_pczt_bytes: Vec<u8>,
) -> Result<zcash_voting::wire::KeystoneSignatureRecord, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::delegate::accept_keystone_signature(
            &db,
            &round_id,
            &request,
            &signed_pczt_bytes,
        )
        .map_err(|e| format!("accept_keystone_signature failed: {e}"))
    })
}

/// Load persisted Keystone signatures for one voting round.
pub fn get_keystone_signatures(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<Vec<zcash_voting::wire::KeystoneSignatureRecord>, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.get_keystone_signatures(&round_id)
            .map_err(|e| format!("get_keystone_signatures failed: {e}"))
    })
}

#[allow(clippy::too_many_arguments)]
/// Streaming Keystone variant of `build_prove_and_sign_delegation_payload`.
pub async fn build_prove_delegation_payload_with_keystone_signature_with_progress(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    hotkey_seed: Vec<u8>,
    bundle_index: u32,
    keystone_sig: Vec<u8>,
    keystone_sighash: Vec<u8>,
    max_real_notes_per_bundle: Option<u32>,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    let hotkey_secret = secrecy::SecretVec::new(hotkey_seed);
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let signed_result = delegation::build_prove_delegation_payload_with_keystone_signature(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params,
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &hotkey_secret,
        bundle_index,
        &keystone_sig,
        &keystone_sighash,
        bundle_policy,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                log::warn!("voting delegation: StreamSink closed, progress not delivered");
            }
        },
    )
    .await
    .and_then(|bundle| {
        zcash_voting::wire::SignedDelegationPayloadView::try_from(bundle).map_err(|e| e.to_string())
    });
    let signed = match signed_result {
        Ok(signed) => signed,
        Err(error) => {
            if sink.add_error(error.clone()).is_err() {
                log::warn!("voting delegation: StreamSink closed before error delivery");
            }
            return Ok(());
        }
    };

    if sink
        .add(ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(signed),
        })
        .is_err()
    {
        log::warn!("voting delegation: StreamSink closed before final result");
    }
    Ok(())
}

pub fn mark_delegation_submitted(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.mark_delegation_submitted(&round_id, bundle_index, &tx_hash)
            .map_err(|e| e.to_string())
    })
}

/// Parse tx events and record a confirmed delegation submission.
pub fn confirm_delegation_submission(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
    events: Vec<ApiTxEvent>,
) -> Result<zcash_voting::wire::DelegationConfirmation, String> {
    catch(|| {
        let events: Vec<zcash_voting::confirmation::TxEvent> =
            events.into_iter().map(Into::into).collect();
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::confirmation::confirm_delegation_submission(
            &db,
            &round_id,
            bundle_index,
            &tx_hash,
            &events,
        )
        .map_err(|e| e.to_string())
    })
}

/// Delete bundle rows at or above `keep_count` for partial-bundle recovery.
///
/// Returns the number of deleted rows.
pub fn delete_skipped_bundles(
    db_path: String,
    wallet_id: String,
    round_id: String,
    keep_count: u32,
) -> Result<u32, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.delete_skipped_bundles(&round_id, keep_count)
            .and_then(|deleted| {
                u32::try_from(deleted).map_err(|_| zcash_voting::VotingError::Internal {
                    message: format!("deleted bundle count {deleted} does not fit in u32"),
                })
            })
            .map_err(|e| format!("delete_skipped_bundles failed: {e}"))
    })
}

/// Sync vote commitment tree state for a voting round.
///
/// Returns the latest synced tree height. The underlying tree client is cached
/// per `(db_path, wallet_id)` so later VAN witness calls can reuse the synced
/// in-memory tree state.
pub fn sync_vote_tree(
    db_path: String,
    wallet_id: String,
    round_id: String,
    node_url: String,
) -> Result<u32, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::precompute::sync_vote_tree(&db, &round_id, &node_url)
            .map_err(|e| format!("sync_vote_tree failed: {e}"))
    })
}

/// Generate a Vote Authority Note Merkle witness for a delegation bundle.
///
/// `anchor_height` is the vote-tree height where the witness should be anchored;
/// callers must sync the same round before requesting the witness.
pub fn generate_van_witness(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<zcash_voting::wire::VanWitness, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        let bundle_count = db
            .get_bundle_count(&round_id)
            .map_err(|e| format!("get_bundle_count failed: {e}"))?;
        zcash_voting::validate_bundle_index(bundle_count, bundle_index, "voting")
            .map_err(|e| e.to_string())?;
        zcash_voting::precompute::van_witness(&db, &round_id, bundle_index, anchor_height)
            .map(zcash_voting::wire::VanWitness::from)
            .map_err(|e| format!("generate_van_witness failed: {e}"))
    })
}

/// Clear process-local voting state for a wallet or round.
///
/// Passing a non-empty round ID clears round-scoped caches only. Passing `None`
/// or an empty round ID also drops the cached vote-tree client for the wallet.
/// This does not abort in-flight proof or vote work already running on worker
/// threads.
pub fn reset_voting_session_state(
    db_path: String,
    wallet_id: String,
    round_id: Option<String>,
) -> Result<(), String> {
    catch(|| {
        let account_wide = round_id.as_deref().map(str::is_empty).unwrap_or(true);
        let tree_count = if account_wide {
            let db = state::open_voting_db(&db_path, &wallet_id)?;
            zcash_voting::precompute::reset_vote_tree(&db, "")
                .map_err(|e| format!("clear_tree_sync_session failed: {e}"))?;
            1
        } else {
            0
        };
        log::info!(
            "voting: reset process-local session state \
             (wallet_id={}, round_id={:?}, tree_entries={})",
            wallet_id,
            round_id,
            tree_count
        );
        Ok(())
    })
}

/// Recover a committed but unsubmitted vote from persisted local recovery data.
pub fn recover_vote_commitment(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<zcash_voting::wire::SignedVoteCommitmentsView, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::vote::recover_signed_commitments(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("vote commitment recovery failed: {e}"))
            .and_then(|commitments| {
                zcash_voting::wire::SignedVoteCommitmentsView::try_from(commitments)
                    .map_err(|e| e.to_string())
            })
    })
}

#[allow(clippy::too_many_arguments)]
/// Streaming variant of `build_vote_commitments`.
///
/// Emits per-proposal progress events, then a terminal `"result"` event carrying
/// `SignedVoteCommitmentsView`.
pub async fn build_vote_commitments_with_progress(
    db_path: String,
    wallet_id: String,
    network: String,
    round_id: String,
    bundle_index: u32,
    hotkey_seed: Vec<u8>,
    van_witness: zcash_voting::wire::VanWitness,
    draft_votes: Vec<zcash_voting::wire::DraftVote>,
    sink: StreamSink<ApiVoteCommitEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let hotkey_seed = secrecy::SecretVec::new(hotkey_seed);
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let commitment_result = tokio::task::spawn_blocking(move || {
        let reporter = zcash_voting::VoteCommitStageBridge::new(move |stage| {
            if progress_sink.add(stage.into()).is_err() {
                log::warn!("voting vote: StreamSink closed, progress not delivered");
            }
        });
        let voting_db = state::open_voting_db(&db_path, &wallet_id)?;
        let voting_hotkey = hotkey::voting_hotkey_from_secret(&hotkey_seed, network)?;

        zcash_voting::vote::commit_batch(
            &voting_db,
            &round_id,
            bundle_index,
            &draft_votes,
            &van_witness,
            zcash_voting::vote::VoteSigner::hotkey(&voting_hotkey),
            &reporter,
        )
        .map_err(|e| format!("vote commit batch failed: {e}"))
    })
    .await
    .map_err(|e| format!("vote commitment task failed: {e}"))
    .and_then(|result| result);
    let commitments = match commitment_result {
        Ok(commitments) => {
            match zcash_voting::wire::SignedVoteCommitmentsView::try_from(commitments)
                .map_err(|e| e.to_string())
            {
                Ok(commitments) => commitments,
                Err(error) => {
                    if sink.add_error(error.clone()).is_err() {
                        log::warn!("voting vote: StreamSink closed before error delivery");
                    }
                    return Ok(());
                }
            }
        }
        Err(error) => {
            if sink.add_error(error.clone()).is_err() {
                log::warn!("voting vote: StreamSink closed before error delivery");
            }
            return Ok(());
        }
    };

    if sink
        .add(ApiVoteCommitEvent {
            phase: "done".to_string(),
            proposal_id: None,
            bundle_index: None,
            proof_progress: None,
            commitments: None,
        })
        .is_err()
    {
        log::warn!("voting vote: StreamSink closed before done event");
    }

    if sink
        .add(ApiVoteCommitEvent {
            phase: "result".to_string(),
            proposal_id: None,
            bundle_index: Some(commitments.bundle_index),
            proof_progress: None,
            commitments: Some(commitments),
        })
        .is_err()
    {
        log::warn!("voting vote: StreamSink closed before final result");
    }
    Ok(())
}

/// Load the full recovery/share-tracking summary for one voting round.
pub fn get_round_recovery_state(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<zcash_voting::wire::RoundRecoveryStateView, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::recovery::round_snapshot(&db, &round_id)
            .map(zcash_voting::wire::RoundRecoveryStateView::from)
            .map_err(|e| format!("round_snapshot failed: {e}"))
    })
}

pub fn mark_vote_submitted(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.mark_vote_submitted(&round_id, bundle_index, proposal_id, &tx_hash)
            .map_err(|e| e.to_string())
    })
}

/// Parse tx events and record a confirmed vote submission.
pub fn confirm_vote_submission(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
    events: Vec<ApiTxEvent>,
) -> Result<zcash_voting::wire::VoteConfirmation, String> {
    catch(|| {
        let events: Vec<zcash_voting::confirmation::TxEvent> =
            events.into_iter().map(Into::into).collect();
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::confirmation::confirm_vote_submission(
            &db,
            &round_id,
            bundle_index,
            proposal_id,
            &tx_hash,
            &events,
        )
        .map_err(|e| e.to_string())
    })
}

#[allow(clippy::too_many_arguments)]
/// Record helper-server submission state for one encrypted vote share.
pub fn record_share_delegation(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: Vec<String>,
    submit_at: u64,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::vote::CommittedVote::recover(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("recover committed vote failed: {e}"))?
            .record_share(&db, share_index, &sent_to_urls, submit_at)
            .map_err(|e| format!("record_share_delegation failed: {e}"))?;
        Ok(())
    })
}

/// Mark one delegated share as confirmed on-chain.
pub fn mark_share_confirmed(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::vote::CommittedVote::recover(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("recover committed vote failed: {e}"))?
            .confirm_share(&db, share_index)
            .map_err(|e| format!("mark_share_confirmed failed: {e}"))?;
        Ok(())
    })
}

/// Merge additional helper-server URLs into one share delegation record.
pub fn add_sent_servers(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: Vec<String>,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::share::add_sent_servers(
            &db,
            &round_id,
            bundle_index,
            proposal_id,
            share_index,
            &new_urls,
        )
        .map_err(|e| format!("add_sent_servers failed: {e}"))
    })
}

/// Clear vote/delegation recovery columns and share-tracking rows for a round.
///
/// This is an explicit reset for finalized or abandoned rounds, not a normal
/// retry step.
pub fn clear_recovery_state(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::recovery::clear(&db, &round_id)
            .map_err(|e| format!("clear_recovery_state failed: {e}"))
    })
}

/// Compute the resumable voting-session plan for a round. The plan reports the
/// ordered remaining work (`next_steps`) and which proposals are still open.
pub fn get_round_plan(
    db_path: String,
    wallet_id: String,
    round_id: String,
    proposal_ids: Vec<u32>,
) -> Result<zcash_voting::wire::RoundPlanView, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        let plan = zcash_voting::session::resume_plan(&db, &round_id, &proposal_ids)
            .map_err(|e| format!("resume_plan failed: {e}"))?;
        zcash_voting::wire::RoundPlanView::try_from(plan).map_err(|e| e.to_string())
    })
}

/// Compute delegation submission work for every eligible bundle in the round.
pub fn get_delegation_bundle_plan(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<zcash_voting::wire::DelegationBundlePlanView, String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        zcash_voting::session::delegation_bundle_plan(&db, &round_id)
            .map(zcash_voting::wire::DelegationBundlePlanView::from)
            .map_err(|e| format!("delegation_bundle_plan failed: {e}"))
    })
}

/// Persist (insert or replace) the voter's ballot intent for one proposal.
/// Pass `skipped: true` for `Decision::Skipped`; otherwise `choice` must be set.
/// `num_options` is the proposal's declared option count.
pub fn set_ballot_intent(
    db_path: String,
    wallet_id: String,
    round_id: String,
    proposal_id: u32,
    num_options: u32,
    skipped: bool,
    choice: Option<u32>,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        let decision = if skipped {
            zcash_voting::session::Decision::Skipped
        } else {
            let c = choice.ok_or_else(|| {
                "set_ballot_intent: choice must be Some when skipped is false".to_string()
            })?;
            zcash_voting::session::Decision::Choice(c)
        };
        db.set_ballot_intent(&round_id, proposal_id, decision, num_options)
            .map_err(|e| format!("set_ballot_intent failed: {e}"))
    })
}

pub(crate) fn voting_network(network: WalletNetwork) -> zcash_voting::Network {
    match network {
        WalletNetwork::Main => zcash_voting::Network::Mainnet,
        WalletNetwork::Test => zcash_voting::Network::Testnet,
        WalletNetwork::Regtest => zcash_voting::Network::Regtest,
    }
}

#[cfg(test)]
fn wallet_network(network: zcash_voting::Network) -> WalletNetwork {
    match network {
        zcash_voting::Network::Mainnet => WalletNetwork::Main,
        zcash_voting::Network::Testnet => WalletNetwork::Test,
        zcash_voting::Network::Regtest => WalletNetwork::Regtest,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine as _;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use zcash_client_backend::proto::service::TreeState;

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn converts_wallet_network_to_voting_network() {
        assert_eq!(
            voting_network(WalletNetwork::Main),
            zcash_voting::Network::Mainnet
        );
        assert_eq!(
            voting_network(WalletNetwork::Test),
            zcash_voting::Network::Testnet
        );
        assert_eq!(
            voting_network(WalletNetwork::Regtest),
            zcash_voting::Network::Regtest
        );
    }

    #[test]
    fn converts_voting_network_to_wallet_network() {
        assert_eq!(
            wallet_network(zcash_voting::Network::Mainnet),
            WalletNetwork::Main
        );
        assert_eq!(
            wallet_network(zcash_voting::Network::Testnet),
            WalletNetwork::Test
        );
        assert_eq!(
            wallet_network(zcash_voting::Network::Regtest),
            WalletNetwork::Regtest
        );
    }

    #[test]
    fn api_round_params_convert_to_core_round_params() {
        let api = test_api_round_params();

        let core: zcash_voting::VotingRoundParams = api.clone().into();

        assert_eq!(core.vote_round_id, api.vote_round_id);
        assert_eq!(core.snapshot_height, api.snapshot_height);
        assert_eq!(core.ea_pk, api.ea_pk);
        assert_eq!(core.nc_root, api.nc_root);
        assert_eq!(core.nullifier_imt_root, api.nullifier_imt_root);
    }

    #[test]
    fn api_bundle_setup_result_preserves_core_fields() {
        let api = zcash_voting::wire::BundleLayout::from(zcash_voting::round::BundleLayout {
            bundle_count: 2,
            eligible_weight: 50,
            dropped_count: 0,
        });

        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.eligible_weight, 50);
    }

    #[test]
    fn api_signed_delegation_payload_preserves_core_fields() {
        let api = zcash_voting::wire::SignedDelegationPayloadView::try_from(
            zcash_voting::delegate::SignedDelegationBundle {
                submission: zcash_voting::delegate::DelegationSubmission {
                    proof: vec![4],
                    rk: [5; 32],
                    nf_signed: [8; 32],
                    cmx_new: [9; 32],
                    gov_comm: [10; 32],
                    gov_nullifiers: [[11; 32]; 5],
                    alpha: [12; 32],
                    vote_round_id: "00010203".to_string(),
                    spend_auth_sig: [6; 64],
                    sighash: [7; 32],
                },
                pczt_bytes: vec![1, 2, 3],
                eligible_weight_zatoshi: 20,
                delegated_weight_zatoshi: 10,
                bundle_count: 2,
                bundle_index: 1,
            },
        )
        .unwrap();

        assert_eq!(api.pczt_bytes, vec![1, 2, 3]);
        assert_eq!(api.status, "ready_for_submission");
        assert_eq!(api.message, None);
        assert_eq!(
            api.submission.proof,
            base64::engine::general_purpose::STANDARD.encode(vec![4])
        );
        assert_eq!(
            api.submission.vote_round_id,
            base64::engine::general_purpose::STANDARD.encode([0, 1, 2, 3])
        );
        assert_eq!(api.eligible_weight_zatoshi, 20);
        assert_eq!(api.delegated_weight_zatoshi, 10);
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn api_keystone_delegation_request_preserves_display_memo() {
        let api = zcash_voting::wire::KeystoneSigningRequest::from(
            zcash_voting::delegate::KeystoneSigningRequest {
                pczt_bytes: vec![1],
                redacted_pczt_bytes: vec![2],
                pczt_sighash: vec![3; 32],
                rk: vec![4; 32],
                action_index: 5,
                display_memo: "I am authorizing this hotkey.".to_string(),
                eligible_weight_zatoshi: 20,
                delegated_weight_zatoshi: 10,
                bundle_count: 2,
                bundle_index: 1,
            },
        );

        assert_eq!(api.display_memo, "I am authorizing this hotkey.");
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn delegation_wire_json_matches_vote_chain_shape() {
        let wire =
            delegation_submission_wire_json(zcash_voting::wire::SignedDelegationPayloadView {
                pczt_bytes: vec![],
                status: "ready".to_string(),
                message: None,
                submission: zcash_voting::wire::DelegationSubmissionWire {
                    proof: base64::engine::general_purpose::STANDARD.encode(vec![8; 96]),
                    rk: base64::engine::general_purpose::STANDARD.encode(vec![1; 32]),
                    spend_auth_sig: base64::engine::general_purpose::STANDARD.encode(vec![2; 64]),
                    sighash: base64::engine::general_purpose::STANDARD.encode(vec![3; 32]),
                    nf_signed: base64::engine::general_purpose::STANDARD.encode(vec![4; 32]),
                    cmx_new: base64::engine::general_purpose::STANDARD.encode(vec![5; 32]),
                    gov_comm: base64::engine::general_purpose::STANDARD.encode(vec![6; 32]),
                    gov_nullifiers: vec![
                        base64::engine::general_purpose::STANDARD
                            .encode(vec![7; 32]);
                        zcash_voting::BUNDLE_NOTE_SLOTS
                    ],
                    vote_round_id: base64::engine::general_purpose::STANDARD.encode([0, 1, 2, 3]),
                },
                eligible_weight_zatoshi: 0,
                delegated_weight_zatoshi: 0,
                bundle_count: 1,
                bundle_index: 0,
            })
            .unwrap();

        let wire: serde_json::Value = serde_json::from_str(&wire).unwrap();
        assert!(wire.get("signed_note_nullifier").is_some());
        assert!(wire.get("van_cmx").is_some());
        assert_eq!(
            wire["gov_nullifiers"].as_array().unwrap().len(),
            zcash_voting::BUNDLE_NOTE_SLOTS
        );
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(wire["vote_round_id"].as_str().unwrap())
                .unwrap(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn cast_vote_wire_json_matches_vote_chain_shape() {
        let wire = vote_commitment_wire_json(zcash_voting::wire::VoteCommitmentWire {
            van_nullifier: base64::engine::general_purpose::STANDARD.encode(vec![1; 32]),
            vote_authority_note_new: base64::engine::general_purpose::STANDARD.encode(vec![2; 32]),
            vote_commitment: base64::engine::general_purpose::STANDARD.encode(vec![3; 32]),
            proposal_id: 7,
            proof: base64::engine::general_purpose::STANDARD.encode(vec![4; 96]),
            vote_round_id: base64::engine::general_purpose::STANDARD.encode(vec![0, 1, 2, 3]),
            anchor_height: 77,
            r_vpk: base64::engine::general_purpose::STANDARD.encode(vec![5; 32]),
            vote_auth_sig: base64::engine::general_purpose::STANDARD.encode(vec![6; 64]),
        })
        .unwrap();

        let wire: serde_json::Value = serde_json::from_str(&wire).unwrap();
        assert_eq!(wire["proposal_id"], 7);
        assert_eq!(wire["vote_comm_tree_anchor_height"], 77);
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(wire["vote_round_id"].as_str().unwrap())
                .unwrap(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn share_wire_json_matches_helper_shape_for_live_and_recovery_payloads() {
        let live = vote_share_wire_json(
            zcash_voting::wire::VoteShareWire {
                shares_hash: "AQ==".to_string(),
                proposal_id: 7,
                vote_decision: 2,
                encrypted_share: zcash_voting::wire::WireEncryptedShare {
                    c1: vec![3],
                    c2: vec![4],
                    share_index: 1,
                },
                share_index: 1,
                vc_tree_position: 55,
                all_encrypted_shares: vec![
                    zcash_voting::wire::WireEncryptedShare {
                        c1: vec![3],
                        c2: vec![4],
                        share_index: 1,
                    },
                    zcash_voting::wire::WireEncryptedShare {
                        c1: vec![5],
                        c2: vec![6],
                        share_index: 2,
                    },
                ],
                share_comms: vec!["Bw==".to_string(), "CA==".to_string()],
                primary_blind: "CQ==".to_string(),
                submit_at: 0,
            },
            Some(99),
            123,
        )
        .unwrap();
        let expected = serde_json::json!({
            "all_enc_shares": [
                {"c1":"Aw==","c2":"BA==","share_index":1},
                {"c1":"BQ==","c2":"Bg==","share_index":2}
            ],
            "enc_share": {"c1":"Aw==","c2":"BA==","share_index":1},
            "primary_blind":"CQ==",
            "proposal_id":7,
            "share_comms":["Bw==","CA=="],
            "share_index":1,
            "shares_hash":"AQ==",
            "submit_at":123,
            "tree_position":99,
            "vote_decision":2
        });
        let live: serde_json::Value = serde_json::from_str(&live).unwrap();
        assert_eq!(live, expected);

        let recovery_json =
            zcash_voting::vote::serialize_recovery(&zcash_voting::vote::VoteRecoveryBundle {
                vote_round_id: "00".repeat(32),
                bundle_index: 0,
                proposal_id: 7,
                vote_decision: 2,
                anchor_height: 10,
                vc_tree_position: 55,
                single_share: false,
                num_options: 3,
                van_nullifier: [0; 32],
                vote_authority_note_new: [0; 32],
                vote_commitment: [0; 32],
                proof: vec![0],
                shares_hash: [1; 32],
                r_vpk: [0; 32],
                alpha_v: [0; 32],
                vote_auth_sig: [0; 64],
                encrypted_shares: vec![
                    zcash_voting::EncryptedShare {
                        c1: vec![3],
                        c2: vec![4],
                        share_index: 1,
                        plaintext_value: 1,
                        randomness: vec![0],
                    },
                    zcash_voting::EncryptedShare {
                        c1: vec![5],
                        c2: vec![6],
                        share_index: 2,
                        plaintext_value: 2,
                        randomness: vec![0],
                    },
                ],
                share_blinds: vec![[9; 32], [10; 32]],
                share_comms: vec![[7; 32], [8; 32]],
            })
            .unwrap();
        let recovered = recovered_vote_share_wire_json(recovery_json, 7, 1, 99, 0).unwrap();
        let recovered: serde_json::Value = serde_json::from_str(&recovered).unwrap();
        assert_eq!(recovered["proposal_id"], 7);
        assert_eq!(recovered["vote_decision"], 2);
        assert_eq!(recovered["share_index"], 1);
        assert_eq!(recovered["tree_position"], 99);
        assert_eq!(recovered["submit_at"], 0);
        assert_eq!(recovered["enc_share"]["c1"], "Aw==");
        assert_eq!(recovered["all_enc_shares"].as_array().unwrap().len(), 2);
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(recovered["shares_hash"].as_str().unwrap())
                .unwrap(),
            vec![1; 32]
        );
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(recovered["primary_blind"].as_str().unwrap())
                .unwrap(),
            vec![9; 32]
        );
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(recovered["share_comms"][0].as_str().unwrap())
                .unwrap(),
            vec![7; 32]
        );
    }

    #[test]
    fn share_wire_json_rejects_json_unsafe_integer_fields() {
        let err = vote_share_wire_json(
            zcash_voting::wire::VoteShareWire {
                shares_hash: "AQ==".to_string(),
                proposal_id: 7,
                vote_decision: 2,
                encrypted_share: zcash_voting::wire::WireEncryptedShare {
                    c1: vec![3],
                    c2: vec![4],
                    share_index: 1,
                },
                share_index: 1,
                vc_tree_position: 0,
                all_encrypted_shares: vec![],
                share_comms: vec![],
                primary_blind: "CQ==".to_string(),
                submit_at: 0,
            },
            Some(0x1f_ffff_ffff_ffff + 1),
            123,
        )
        .unwrap_err();
        assert!(err.contains("tree_position"));
    }

    #[test]
    fn share_tracking_flags_use_crate_policy() {
        let share = zcash_voting::wire::ShareDelegationRecordView {
            round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            proposal_id: 7,
            share_index: 0,
            sent_to_urls: vec!["https://helper.example".to_string()],
            nullifier: vec![1; 32],
            phase: "submitted_share".to_string(),
            confirmed: false,
            submit_at: 100,
            created_at: 50,
        };

        assert_eq!(
            share_tracking_flags(share.clone(), 109, Some(500)).unwrap(),
            0
        );
        assert_eq!(
            share_tracking_flags(share.clone(), 110, Some(500)).unwrap(),
            1
        );
        assert_eq!(share_tracking_flags(share, 200, Some(500)).unwrap(), 3);
    }

    #[test]
    fn next_share_tracking_delay_uses_crate_ready_interval() {
        let ready = zcash_voting::wire::ShareDelegationRecordView {
            round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            proposal_id: 7,
            share_index: 0,
            sent_to_urls: vec!["https://helper.example".to_string()],
            nullifier: vec![1; 32],
            phase: "submitted_share".to_string(),
            confirmed: false,
            submit_at: 100,
            created_at: 50,
        };
        let future = zcash_voting::wire::ShareDelegationRecordView {
            submit_at: 140,
            ..ready.clone()
        };

        assert_eq!(
            next_share_tracking_delay_seconds(vec![ready], 130).unwrap(),
            Some(15)
        );
        assert_eq!(
            next_share_tracking_delay_seconds(vec![future], 120).unwrap(),
            Some(30)
        );
    }

    #[test]
    fn api_van_witness_preserves_core_fields() {
        let mut witness = vec![vec![0u8; 32]; zcash_voting::vote::VAN_AUTH_PATH_LEN];
        witness[0] = vec![1; 32];
        witness[1] = vec![2; 32];
        let api = zcash_voting::wire::VanWitness::from(zcash_voting::vote::VanWitness {
            auth_path: witness,
            position: 7,
            anchor_height: 123,
        });

        assert_eq!(api.auth_path[0], vec![1; 32]);
        assert_eq!(api.auth_path[1], vec![2; 32]);
        assert_eq!(api.position, 7);
        assert_eq!(api.anchor_height, 123);
    }

    #[test]
    fn api_delegation_proof_event_uses_stable_phase_names() {
        assert_eq!(
            ApiDelegationProofEvent::from(DelegationProgress::SelectingNotes).phase,
            "selecting_notes"
        );
        assert_eq!(
            ApiDelegationProofEvent::from(DelegationProgress::SigningPayload).phase,
            "signing_payload"
        );
        let ready = ApiDelegationProofEvent::from(DelegationProgress::PayloadReady);
        assert_eq!(ready.phase, "payload_ready");
        assert_eq!(ready.proof_progress, None);
        assert!(ready.signed_delegation_payload.is_none());

        let proof = ApiDelegationProofEvent::from(DelegationProgress::ProofProgress(0.5));
        assert_eq!(proof.phase, "proof_progress");
        assert_eq!(proof.proof_progress, Some(0.5));

        let result = ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(zcash_voting::wire::SignedDelegationPayloadView {
                pczt_bytes: vec![1],
                status: "ready_for_submission".to_string(),
                message: None,
                submission: zcash_voting::wire::DelegationSubmissionWire {
                    rk: "rk".to_string(),
                    spend_auth_sig: "sig".to_string(),
                    sighash: "sighash".to_string(),
                    nf_signed: "nf".to_string(),
                    cmx_new: "cmx".to_string(),
                    gov_comm: "gov".to_string(),
                    gov_nullifiers: vec!["nullifier".to_string()],
                    proof: "proof".to_string(),
                    vote_round_id: "round".to_string(),
                },
                eligible_weight_zatoshi: 10,
                delegated_weight_zatoshi: 10,
                bundle_count: 1,
                bundle_index: 0,
            }),
        };
        assert_eq!(result.phase, "result");
        assert_eq!(
            result.signed_delegation_payload.as_ref().unwrap().status,
            "ready_for_submission"
        );
    }

    #[test]
    fn api_vote_commit_event_uses_stable_phase_names() {
        let event = ApiVoteCommitEvent::from(zcash_voting::vote::VoteCommitStage::ProofStarting {
            proposal_id: 1,
            bundle_index: 2,
        });

        assert_eq!(event.phase, "building_proof");
        assert_eq!(event.proposal_id, Some(1));
        assert_eq!(event.bundle_index, Some(2));
        assert_eq!(event.proof_progress, Some(0.0));
        let proof = ApiVoteCommitEvent::from(zcash_voting::vote::VoteCommitStage::ProofProgress {
            proposal_id: 1,
            bundle_index: 2,
            progress: 0.5,
        });
        assert_eq!(proof.phase, "proof_progress");
        assert_eq!(proof.proof_progress, Some(0.5));

        let result = ApiVoteCommitEvent {
            phase: "result".to_string(),
            proposal_id: None,
            bundle_index: Some(2),
            proof_progress: None,
            commitments: Some(zcash_voting::wire::SignedVoteCommitmentsView {
                bundle_index: 2,
                commitments: vec![],
            }),
        };
        assert_eq!(result.phase, "result");
        assert_eq!(result.commitments.as_ref().unwrap().bundle_index, 2);
    }

    #[test]
    fn api_signed_vote_commitments_preserve_public_wire_fields() {
        let api = zcash_voting::wire::SignedVoteCommitmentsView::try_from(
            zcash_voting::vote::SignedVoteCommitments {
                bundle_index: 1,
                commitments: vec![zcash_voting::vote::SignedVoteCommitment {
                    proposal_id: 2,
                    choice: 1,
                    vote_round_id: ROUND_ID.to_string(),
                    van_nullifier: [1; 32],
                    vote_authority_note_new: [2; 32],
                    vote_commitment: [3; 32],
                    proof: vec![4; 10],
                    encrypted_shares: vec![zcash_voting::WireEncryptedShare {
                        c1: vec![5; 32],
                        c2: vec![6; 32],
                        share_index: 0,
                    }],
                    share_payloads: vec![zcash_voting::SharePayload {
                        shares_hash: vec![7; 32],
                        proposal_id: 2,
                        vote_decision: 1,
                        enc_share: zcash_voting::WireEncryptedShare {
                            c1: vec![5; 32],
                            c2: vec![6; 32],
                            share_index: 0,
                        },
                        tree_position: 9,
                        all_enc_shares: vec![],
                        share_comms: vec![vec![8; 32]],
                        primary_blind: vec![9; 32],
                    }],
                    anchor_height: 100,
                    shares_hash: [7; 32],
                    share_comms: vec![[8; 32]],
                    r_vpk: [10; 32],
                    vote_auth_sig: [9; 64],
                    commitment_bundle_json: "{\"proposal_id\":2}".to_string(),
                }],
            },
        )
        .unwrap();

        assert_eq!(api.bundle_index, 1);
        assert_eq!(api.commitments[0].proposal_id, 2);
        assert_eq!(api.commitments[0].wire.proposal_id, 2);
        assert_eq!(api.commitments[0].shares[0].encrypted_share.c1, vec![5; 32]);
        assert_eq!(
            api.commitments[0].shares[0].primary_blind,
            base64::engine::general_purpose::STANDARD.encode(vec![9; 32])
        );
        assert_eq!(
            api.commitments[0].wire.vote_auth_sig,
            base64::engine::general_purpose::STANDARD.encode(vec![9; 64])
        );
    }

    #[test]
    fn api_note_selection_result_preserves_core_fields() {
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let selected = zcash_voting::SelectedNotes {
            notes: vec![
                test_note_ref(divisor / 2, divisor / 2, 3),
                test_note_ref(divisor / 2, divisor / 2, 7),
            ],
            snapshot_height: 100,
            anchor_tree_state: test_tree_state(100),
        };

        let api = zcash_voting::wire::VotingNoteSelectionResultView::from_selected(
            selected,
            BundlePolicy::default(),
        )
        .unwrap();

        assert_eq!(api.note_count, 2);
        assert_eq!(api.eligible_weight_zatoshi, divisor);
        assert_eq!(api.snapshot_height, 100);
        assert_eq!(api.anchor_height, 100);
        assert_eq!(api.notes[0].commitment_tree_position, 3);
        assert_eq!(api.notes[1].value_zatoshi, divisor / 2);
        assert_eq!(api.notes[1].voting_weight_zatoshi, divisor / 2);
    }

    #[test]
    fn delete_skipped_bundles_api_is_bundle_indexed() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-api-bundles").unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(
            delete_skipped_bundles(
                db_path.to_str().unwrap().to_string(),
                "wallet-api-bundles".to_string(),
                ROUND_ID.to_string(),
                1,
            )
            .unwrap(),
            1
        );
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
    }

    #[test]
    fn sync_vote_tree_api_happy_path_accepts_empty_tree() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let server = start_tree_server(0, vec![], 1);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-empty-sync".to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        assert_eq!(height, 0);
    }

    #[test]
    fn generate_van_witness_api_happy_path_after_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-api-witness").unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-witness".to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();
        let witness = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-witness".to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap();

        assert_eq!(witness.position, 0);
        assert_eq!(witness.anchor_height, 1);
        assert_eq!(witness.auth_path.len(), 24);
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[test]
    fn reset_voting_session_state_with_round_preserves_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-round-reset";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();

        let witness = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap();
        assert_eq!(witness.position, 0);
    }

    #[test]
    fn reset_voting_session_state_without_round_drops_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-account-reset";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            None,
        )
        .unwrap();

        let err = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap_err();
        assert!(!err.is_empty());
    }

    #[test]
    fn recovery_api_preserves_round_summary_and_share_records() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-recovery";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(&conn, ROUND_ID, wallet_id, 1, 2, 1, b"vote-1")
            .unwrap();
        drop(conn);
        mark_vote_submitted(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            "vote-tx-1-2".to_string(),
        )
        .unwrap();
        {
            let conn = db.conn();
            conn.execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":json": test_vote_recovery_json(1, 2, 1, 99),
                    ":pos": 99i64,
                    ":round_id": ROUND_ID,
                    ":wallet_id": wallet_id,
                    ":bundle_index": 1i64,
                    ":proposal_id": 2i64,
                },
            )
            .unwrap();
        }
        record_share_delegation(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            0,
            vec!["https://helper.example".to_string()],
            123,
        )
        .unwrap();

        let state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(state.bundle_count, 2);
        assert_eq!(
            state.delegation[0].tx_hash.as_deref(),
            Some("delegation-tx-0")
        );
        assert_eq!(state.votes[0].proposal_id, 2);
        assert_eq!(state.votes[0].tx_hash.as_deref(), Some("vote-tx-1-2"));
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 99);
        assert_eq!(state.share_delegations[0].sent_to_urls.len(), 1);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);

        mark_share_confirmed(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            0,
        )
        .unwrap();
        let confirmed_state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(confirmed_state.unconfirmed_share_delegations.is_empty());

        clear_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        let cleared_state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(cleared_state.share_delegations.is_empty());
    }

    #[test]
    fn delegation_bundle_plan_reports_pending_and_submitted_bundles() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-delegation-plan";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        db.init_round(&test_api_round_params().into(), None)
            .unwrap();
        let notes: Vec<_> = (0..11).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 1, "submitted-tx")
            .unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 2, "confirmed-tx")
            .unwrap();
        db.store_van_position(ROUND_ID, 2, 9).unwrap();

        let plan = get_delegation_bundle_plan(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(plan.bundle_count, 3);
        assert_eq!(plan.pending_bundle_indexes, vec![0]);
        assert_eq!(plan.submitted_bundle_indexes, vec![1]);
    }

    #[test]
    fn setup_delegation_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(setup_delegation_bundles(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "bogus".to_string(),
                test_api_round_params(),
                "Demo".to_string(),
                None,
                "wallet-1".to_string(),
                None,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    fn test_api_round_params() -> zcash_voting::wire::VotingRoundParams {
        zcash_voting::wire::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_vote_recovery_json(
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
        vc_tree_position: u64,
    ) -> String {
        zcash_voting::vote::serialize_recovery(&zcash_voting::vote::VoteRecoveryBundle {
            vote_round_id: ROUND_ID.to_string(),
            bundle_index,
            proposal_id,
            vote_decision,
            anchor_height: 100,
            vc_tree_position,
            single_share: false,
            num_options: 2,
            van_nullifier: [1u8; 32],
            vote_authority_note_new: [2u8; 32],
            vote_commitment: [3u8; 32],
            proof: vec![4u8; 8],
            shares_hash: [5u8; 32],
            r_vpk: [6u8; 32],
            alpha_v: [7u8; 32],
            vote_auth_sig: [8u8; 64],
            encrypted_shares: vec![zcash_voting::EncryptedShare {
                c1: vec![9u8; 32],
                c2: vec![10u8; 32],
                share_index: 0,
                plaintext_value: 1,
                randomness: vec![11u8; 32],
            }],
            share_blinds: vec![[12u8; 32]],
            share_comms: vec![[13u8; 32]],
        })
        .unwrap()
    }

    fn test_tree_state(height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        }
    }

    fn test_note_ref(
        value_zatoshi: u64,
        voting_weight_zatoshi: u64,
        commitment_tree_position: u64,
    ) -> zcash_voting::NoteRef {
        zcash_voting::NoteRef {
            pool: "orchard".to_string(),
            txid_hex: hex::encode([commitment_tree_position as u8; 32]),
            output_index: commitment_tree_position as u32,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position,
            mined_height: 1,
            anchor_height: 100,
        }
    }

    struct MockTreeBlock {
        height: u32,
        start_index: usize,
        leaf: String,
        root: String,
    }

    fn start_tree_server(height: u32, leaves: Vec<String>, expected_requests: usize) -> String {
        let (latest_root, blocks) = mock_tree_blocks(&leaves);
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            for _ in 0..expected_requests {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0u8; 2048];
                let len = stream.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..len]);
                let path = request
                    .lines()
                    .next()
                    .and_then(|line| line.split_whitespace().nth(1))
                    .unwrap_or("/");
                let body = tree_response_body(path, height, latest_root.as_deref(), &blocks);
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        url
    }

    fn tree_response_body(
        path: &str,
        height: u32,
        latest_root: Option<&str>,
        blocks: &[MockTreeBlock],
    ) -> String {
        if path.ends_with("/latest") {
            match latest_root {
                Some(root) => format!(
                    r#"{{"tree":{{"next_index":{},"root":"{}","height":{}}}}}"#,
                    blocks.len(),
                    root,
                    height
                ),
                None => format!(
                    r#"{{"tree":{{"next_index":{},"height":{}}}}}"#,
                    blocks.len(),
                    height
                ),
            }
        } else if path.contains("/leaves?") {
            if height == 0 || blocks.is_empty() {
                r#"{"blocks":[]}"#.to_string()
            } else {
                let from_height = query_u32(path, "from_height").unwrap_or(0);
                let to_height = query_u32(path, "to_height").unwrap_or(height);
                let Some(block) = blocks
                    .iter()
                    .find(|block| block.height >= from_height && block.height <= to_height)
                else {
                    return r#"{"blocks":[],"next_from_height":0}"#.to_string();
                };
                let next_from_height = blocks
                    .iter()
                    .find(|next| next.height > block.height && next.height <= to_height)
                    .map(|next| format!(r#","next_from_height":{}"#, next.height))
                    .unwrap_or_default();
                format!(
                    r#"{{"blocks":[{{"height":{},"start_index":{},"leaves":["{}"],"root":"{}"}}]{}}}"#,
                    block.height, block.start_index, block.leaf, block.root, next_from_height
                )
            }
        } else {
            r#"{"tree":null}"#.to_string()
        }
    }

    fn mock_tree_blocks(leaves: &[String]) -> (Option<String>, Vec<MockTreeBlock>) {
        let mut server = vote_commitment_tree::MemoryTreeServer::empty();
        let mut blocks = Vec::new();

        for (idx, leaf_b64) in leaves.iter().enumerate() {
            let leaf_bytes = base64::engine::general_purpose::STANDARD
                .decode(leaf_b64)
                .unwrap();
            let leaf_bytes: [u8; 32] = leaf_bytes.try_into().unwrap();
            let leaf = vote_commitment_tree::MerkleHashVote::from_bytes(&leaf_bytes).unwrap();
            let height = (idx + 1) as u32;
            server.append(leaf.inner()).unwrap();
            server.checkpoint(height).unwrap();
            let root = vote_commitment_tree::MerkleHashVote::from_fp(server.root());
            blocks.push(MockTreeBlock {
                height,
                start_index: idx,
                leaf: leaf_b64.clone(),
                root: base64::engine::general_purpose::STANDARD.encode(root.to_bytes()),
            });
        }

        let latest_root = blocks.last().map(|block| block.root.clone());
        (latest_root, blocks)
    }

    fn query_u32(path: &str, key: &str) -> Option<u32> {
        path.split('?').nth(1)?.split('&').find_map(|pair| {
            let (name, value) = pair.split_once('=')?;
            (name == key).then(|| value.parse().ok()).flatten()
        })
    }

    fn fp_one_base64() -> String {
        "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".to_string()
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
