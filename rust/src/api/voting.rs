use std::{panic, sync::Arc};

#[cfg(test)]
use super::voting_helpers::bundle_policy;
use super::voting_helpers::{
    delegation_static_inputs, prepare_delegation_bundle_params, resolve_delegation_lwd_inputs,
    seed_from_mnemonic,
};
use crate::frb_generated::StreamSink;
use crate::wallet::{
    keys,
    voting::{db, delegation, delegation::DelegationProgress, hotkey, network::voting_network},
};
use rand::{rngs::OsRng, RngCore};
use secrecy::ExposeSecret;
use zcash_voting::config;
use zcash_voting::wire::{
    ConfigSwitchKind, ResolveVotingConfigOptions, ResolvedVotingConfig, ResolvedVotingConfigSummary,
};

pub use zcash_voting::vote::{DraftVote, SignedVoteCommitments};

// Shared phase labels emitted in streaming voting/delegation progress events.
const PHASE_SELECTING_NOTES: &str = "selecting_notes";
const PHASE_BUILDING_PCZT: &str = "building_pczt";
const PHASE_BUILDING_PROOF: &str = "building_proof";
const PHASE_PROOF_PROGRESS: &str = "proof_progress";
const PHASE_SIGNING_PAYLOAD: &str = "signing_payload";
const PHASE_PAYLOAD_READY: &str = "payload_ready";
const PHASE_RESULT: &str = "result";
const PHASE_DELEGATION_PROGRESS: &str = "delegation_progress";
const PHASE_BUILDING_SHARE_PAYLOADS: &str = "building_share_payloads";
const PHASE_SIGNING: &str = "signing";
const PHASE_VOTE_COMMIT_STAGE: &str = "vote_commit_stage";

/// Return the shared last-moment helper-share buffer, in Unix seconds.
#[flutter_rust_bridge::frb(sync)]
pub fn last_moment_buffer_seconds(
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> Option<u64> {
    zcash_voting::share::policy::last_moment_buffer_seconds(
        ceremony_start_seconds,
        vote_end_time_seconds,
    )
}

/// Return true when `now_seconds` is inside the active round's last-moment window.
#[flutter_rust_bridge::frb(sync)]
pub fn is_last_moment(
    now_seconds: u64,
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> bool {
    zcash_voting::share::policy::is_last_moment(
        now_seconds,
        ceremony_start_seconds,
        vote_end_time_seconds,
    )
}

// Fixed-width Keystone payload fields.
const KEYSTONE_SIG_LEN: usize = 64;
const KEYSTONE_SIGHASH_LEN: usize = 32;
const KEYSTONE_RK_LEN: usize = 32;

// Bit flags attached to share-tracking status records.
const SHARE_TRACKING_FLAG_READY: u32 = 1;
const SHARE_TRACKING_FLAG_OVERDUE: u32 = 1 << 1;
#[cfg(test)]
const MAX_SAFE_JSON_INTEGER: u64 = 0x1f_ffff_ffff_ffff;

// Log-friendly stream labels and sink-drop diagnostics.
const DELEGATION_STREAM_CONTEXT: &str = "voting delegation";
const VOTE_STREAM_CONTEXT: &str = "voting vote";
const SINK_PROGRESS_NOT_DELIVERED: &str = "StreamSink closed, progress not delivered";
const SINK_ERROR_NOT_DELIVERED: &str = "StreamSink closed before error delivery";
const SINK_RESULT_NOT_DELIVERED: &str = "StreamSink closed before final result";

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

#[derive(Clone, Debug, PartialEq)]
/// Shared delegation/voting round context passed across the FRB boundary.
///
/// This bundles the reusable round and wallet scope required by delegation setup,
/// proving, and keystone request flows.
pub struct ApiVotingRoundContext {
    pub db_path: String,
    pub lightwalletd_url: String,
    pub network: String,
    pub round_params: zcash_voting::wire::VotingRoundParams,
    pub round_name: String,
    pub session_json: Option<String>,
    pub account_uuid: String,
    pub max_real_notes_per_bundle: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Parsed fields from a Keystone-signed voting PCZT.
pub struct ParsedSignedVotingPczt {
    /// ZIP-244 sighash extracted from the signed PCZT.
    pub sighash: Vec<u8>,
    /// Orchard SpendAuth signature extracted from the signed PCZT.
    pub spend_auth_sig: Vec<u8>,
}

/// Returns the vote-chain delegation submission body as validated wire JSON.
///
/// Binary fields are base64-encoded here so Dart does not duplicate protocol
/// field names or byte encoding rules.
pub fn delegation_submission_wire_json(
    submission: zcash_voting::wire::SignedDelegationPayloadView,
) -> Result<String, String> {
    catch(|| {
        // Serialize validated delegation payload into chain wire JSON.
        submission.submission.to_json().map_err(|e| e.to_string())
    })
}

/// Returns the vote-chain cast-vote submission body as validated wire JSON.
pub fn vote_commitment_wire_json(
    commitment: zcash_voting::wire::VoteCommitmentWire,
) -> Result<String, String> {
    catch(|| {
        // Serialize validated cast-vote commitment into chain wire JSON.
        commitment.to_json().map_err(|e| e.to_string())
    })
}

/// Returns the helper-server encrypted-share submission body as wire JSON.
pub fn vote_share_wire_json(
    share: zcash_voting::wire::VoteShareWire,
    vc_tree_position: Option<u64>,
    submit_at: u64,
) -> Result<String, String> {
    catch(|| {
        // Bind late fields before emitting helper wire JSON.
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
///
/// # Errors
///
/// Returns an error if `share_count` does not fit `usize`, entropy generation
/// fails, or crate policy rejects the supplied timing/server inputs.
pub fn plan_share_submissions(
    share_count: u32,
    server_urls: Vec<String>,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> Result<Vec<zcash_voting::wire::ShareSubmissionPlan>, String> {
    catch(|| {
        // Convert to usize once for policy sizing and planner inputs.
        let share_count = usize::try_from(share_count)
            .map_err(|_| "share_count does not fit in usize".to_string())?;

        // Ask crate policy how much CSPRNG entropy is required.
        let required = zcash_voting::share_policy::share_submission_random_bytes_required(
            share_count,
            server_urls.len(),
            now_seconds,
            vote_end_time_seconds,
            last_moment_buffer_seconds,
            single_share,
        );

        // Draw independent entropy streams for schedule and helper selection.
        let mut submit_at_random_bytes = vec![0u8; required.submit_at_random_bytes];
        let mut server_random_bytes = vec![0u8; required.server_random_bytes];
        OsRng
            .try_fill_bytes(&mut submit_at_random_bytes)
            .map_err(|e| format!("failed to draw submit_at entropy: {e}"))?;
        OsRng
            .try_fill_bytes(&mut server_random_bytes)
            .map_err(|e| format!("failed to draw share-server entropy: {e}"))?;

        // Build FRB-safe plans with fully materialized random inputs.
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

/// Build round params from server metadata while binding trusted `ea_pk`.
///
/// Trust model for the per-round parameters:
///
/// - `ea_pk` (the encryption-authority key votes are encrypted to) is the only
///   field that cannot be independently re-derived by the wallet, so it is
///   always sourced from the authenticated dynamic config and never from the
///   vote server's round response. This call ignores any server-supplied
///   `ea_pk` and substitutes the authenticated value for `round_id`.
/// - `snapshot_height` and `nc_root` are accepted from the server here but are
///   re-verified downstream against the wallet's own lightwalletd-synced
///   Orchard commitment tree: `zcash_voting`'s witness generation
///   (`validate_cached_tree_state_for_round`) requires the synced frontier
///   height and root to match these exactly, so a wrong value fails closed
///   before any vote material is produced.
/// - `nullifier_imt_root` is accepted from the server here but is used
///   downstream as the expected root that PIR nullifier proofs are verified
///   against; a wrong root makes proof verification fail closed rather than
///   enabling a forged non-membership claim.
///
/// In other words, every server-supplied field other than `ea_pk` is
/// cross-checked against an independent source (lightwalletd or PIR proofs)
/// downstream, and `ea_pk` is pinned to authenticated config here. A
/// compromised or stale endpoint therefore cannot steer voting to the wrong
/// authority or roots without being rejected.
pub fn trusted_voting_round_params_from_config(
    resolved_config: zcash_voting::config::ResolvedVotingConfig,
    round_id: String,
    snapshot_height: u64,
    nc_root: Vec<u8>,
    nullifier_imt_root: Vec<u8>,
) -> Result<zcash_voting::wire::VotingRoundParams, String> {
    catch(|| {
        resolved_config
            .trusted_voting_round_params(round_id, snapshot_height, nc_root, nullifier_imt_root)
            .map_err(|e| e.to_string())
    })
}

fn share_record(
    share: zcash_voting::wire::ShareDelegationRecordView,
) -> zcash_voting::ShareDelegationRecord {
    // Convert API view type into core share-tracking record shape.
    zcash_voting::ShareDelegationRecord {
        round_id: share.round_id,
        bundle_index: share.bundle_index,
        proposal_id: share.proposal_id,
        share_index: share.share_index,
        sent_to_urls: share.sent_to_urls,
        nullifier: share.nullifier,
        confirmed: share.confirmed,
        submit_at: share.submit_at,
        created_at: share.created_at,
    }
}

/// Return share-tracking action flags using `zcash_voting::share_policy`.
///
/// [`SHARE_TRACKING_FLAG_READY`] means the share is ready for status polling.
/// [`SHARE_TRACKING_FLAG_OVERDUE`] means it is overdue and should be retried
/// against helpers that missed the initial submission.
pub fn share_tracking_flags(
    share: zcash_voting::wire::ShareDelegationRecordView,
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
) -> Result<u32, String> {
    catch(|| {
        let share = share_record(share);
        let policy = zcash_voting::share::ShareTimingPolicy::default();
        let mut flags = 0u32;

        // Flag shares that are ready for helper status checks.
        if zcash_voting::share::policy::is_share_ready_for_status_check(&share, now_seconds, policy)
        {
            flags |= SHARE_TRACKING_FLAG_READY;
        }

        // Flag shares that are overdue and should be retried.
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
            flags |= SHARE_TRACKING_FLAG_OVERDUE;
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
        // Convert wire views into core records consumed by share policy.
        let shares = shares.into_iter().map(share_record).collect::<Vec<_>>();
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

/// Generate opaque voting hotkey bytes for a local voting account.
///
/// Vizor v2 uses the same random app-owned hotkey model for software and
/// Keystone accounts. The app persists this random per-round hotkey in secure
/// storage and reuses it for delegation setup and vote commitment signing.
pub fn generate_voting_hotkey(network: String) -> Result<Vec<u8>, String> {
    catch(|| {
        // Voting hotkeys are app-owned random secrets, not wallet-seed-derived.
        let network = keys::parse_network(&network)?;
        zcash_voting::hotkey::generate_random_voting_hotkey(voting_network(network))
            .map_err(|e| format!("Voting hotkey generation failed: {e}"))
            .map(|hotkey| {
                // FRB returns owned bytes, so this copy cannot be zeroized by Rust
                // after Dart receives it.
                hotkey.stored_secret().to_vec()
            })
    })
}

impl From<DelegationProgress> for ApiDelegationProofEvent {
    fn from(progress: DelegationProgress) -> Self {
        // Normalize crate-specific progress into stable FRB phase labels.
        match progress {
            DelegationProgress::SelectingNotes => Self {
                phase: PHASE_SELECTING_NOTES.to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            DelegationProgress::PcztBuilding | DelegationProgress::PcztBuilt => Self {
                phase: PHASE_BUILDING_PCZT.to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofStarting => Self {
                phase: PHASE_BUILDING_PROOF.to_string(),
                proof_progress: Some(0.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofProgress(value) => Self {
                phase: PHASE_PROOF_PROGRESS.to_string(),
                proof_progress: Some(value),
                signed_delegation_payload: None,
            },
            DelegationProgress::ProofComplete => Self {
                phase: PHASE_PROOF_PROGRESS.to_string(),
                proof_progress: Some(1.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::SigningPayload => Self {
                phase: PHASE_SIGNING_PAYLOAD.to_string(),
                proof_progress: Some(1.0),
                signed_delegation_payload: None,
            },
            DelegationProgress::PayloadReady => Self {
                phase: PHASE_PAYLOAD_READY.to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            _ => Self {
                phase: PHASE_DELEGATION_PROGRESS.to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
        }
    }
}

impl From<zcash_voting::vote::VoteCommitStage> for ApiVoteCommitEvent {
    fn from(event: zcash_voting::vote::VoteCommitStage) -> Self {
        // Normalize vote commit stage details into API progress events.
        match event {
            zcash_voting::vote::VoteCommitStage::ProofStarting {
                proposal_id,
                bundle_index,
            } => Self {
                phase: PHASE_BUILDING_PROOF.to_string(),
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
                phase: PHASE_PROOF_PROGRESS.to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(progress),
                commitments: None,
            },
            zcash_voting::vote::VoteCommitStage::SharePayloadsBuilding {
                proposal_id,
                bundle_index,
            } => Self {
                phase: PHASE_BUILDING_SHARE_PAYLOADS.to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(1.0),
                commitments: None,
            },
            zcash_voting::vote::VoteCommitStage::Signing {
                proposal_id,
                bundle_index,
            } => Self {
                phase: PHASE_SIGNING.to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: None,
                commitments: None,
            },
            _ => Self {
                phase: PHASE_VOTE_COMMIT_STAGE.to_string(),
                proposal_id: None,
                bundle_index: None,
                proof_progress: None,
                commitments: None,
            },
        }
    }
}

/// Executes an API helper and converts Rust panics into string errors.
///
/// This preserves the existing `Result<T, String>` contract used by FRB entry
/// points so callers receive a normal error instead of an unwind crossing FFI.
fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    // Convert unwind payloads into stable string errors for FFI callers.
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

/// Validates that `bytes` has exactly `expected` length.
///
/// Returns an error naming `field` when the provided length differs.
fn require_len(bytes: &[u8], expected: usize, field: &str) -> Result<(), String> {
    // Keep fixed-size cryptographic fields strict at API boundaries.
    if bytes.len() == expected {
        Ok(())
    } else {
        Err(format!(
            "{field} must be exactly {expected} bytes, got {}",
            bytes.len()
        ))
    }
}

// Helper function to log when a sink is closed.
// Log sink closure is non-fatal. Log so dropped listeners are visible in debug.
fn log_sink_closed(context: &str, detail: &str) {
    log::warn!("{context}: {detail}");
}

/// Emits the terminal `"result"` delegation event to a progress sink.
///
/// If signing failed, this forwards the error through `sink.add_error` and
/// returns `Ok(())` so closed sinks do not fail the outer task.
fn emit_signed_delegation_result(
    sink: &StreamSink<ApiDelegationProofEvent>,
    signed_result: Result<zcash_voting::wire::SignedDelegationPayloadView, String>,
) -> Result<(), String> {
    // Surface computation/signing errors through stream errors.
    let signed = match signed_result {
        Ok(signed) => signed,
        Err(error) => {
            if sink.add_error(error.clone()).is_err() {
                log_sink_closed(DELEGATION_STREAM_CONTEXT, SINK_ERROR_NOT_DELIVERED);
            }
            return Ok(());
        }
    };

    // Emit the terminal result event when a payload is available.
    if sink
        .add(ApiDelegationProofEvent {
            phase: PHASE_RESULT.to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(signed),
        })
        .is_err()
    {
        log_sink_closed(DELEGATION_STREAM_CONTEXT, SINK_RESULT_NOT_DELIVERED);
    }
    Ok(())
}

fn emit_signed_vote_result(
    sink: &StreamSink<ApiVoteCommitEvent>,
    signed_result: Result<zcash_voting::wire::SignedVoteCommitmentsView, String>,
) -> Result<(), String> {
    // Surface computation/signing errors through stream errors.
    let commitments = match signed_result {
        Ok(commitments) => commitments,
        Err(error) => {
            if sink.add_error(error.clone()).is_err() {
                log_sink_closed(VOTE_STREAM_CONTEXT, SINK_ERROR_NOT_DELIVERED);
            }
            return Ok(());
        }
    };

    // Emit the terminal result event when commitments are available.
    if sink
        .add(ApiVoteCommitEvent {
            phase: PHASE_RESULT.to_string(),
            proposal_id: None,
            bundle_index: Some(commitments.bundle_index),
            proof_progress: None,
            commitments: Some(commitments),
        })
        .is_err()
    {
        log_sink_closed(VOTE_STREAM_CONTEXT, SINK_RESULT_NOT_DELIVERED);
    }
    Ok(())
}

/// Select notes and persist bundle rows for the delegation pipeline.
///
/// Reuses existing bundle rows for the same round/wallet, so callers can safely
/// retry setup before proving a specific bundle.
///
/// # Errors
///
/// Returns an error if bundle policy parsing, opening the sidecar DB, round
/// initialization, note selection, or bundle layout persistence fails.
pub async fn setup_delegation_bundles(
    ctx: ApiVotingRoundContext,
) -> Result<zcash_voting::wire::BundleLayout, String> {
    // Resolve static network + bundle policy inputs and open the sidecar DB.
    let (voting_network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;
    let voting_db = db::open_voting_db(&ctx.db_path, &ctx.account_uuid)?;

    // Select and persist reusable delegation bundles for this round/account.
    delegation::setup_delegation_bundles(
        &voting_db,
        &ctx.db_path,
        zcash_voting::delegate::ResolveDelegationLwdParams {
            lightwalletd_url: &ctx.lightwalletd_url,
            network: voting_network,
            round_params: ctx.round_params,
            round_name: &ctx.round_name,
        },
        ctx.session_json.as_deref(),
        bundle_policy,
    )
    .await
}

/// Build delegation PCZT material and prefetch/cache PIR-backed IMT proofs.
///
/// This is a background warm-up path. The normal proof path still fetches any
/// missing PIR proofs if this was not run or did not complete in time.
///
/// # Errors
///
/// Returns an error if round input resolution, hotkey validation, bundle
/// preparation, or PIR precompute fails.
pub async fn precompute_delegation_pir(
    ctx: ApiVotingRoundContext,
    pir_server_url: String,
    stored_hotkey_secret: Vec<u8>,
    bundle_index: u32,
) -> Result<zcash_voting::wire::DelegationPirPrecomputeResultView, String> {
    // Resolve static network and bundling policy inputs from round context.
    let (voting_network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;

    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, voting_network)?;

    // Fetch lightwalletd-backed round inputs used for delegation bundle prep.
    let lwd = resolve_delegation_lwd_inputs(
        &ctx.lightwalletd_url,
        ctx.round_params,
        &ctx.round_name,
        voting_network,
    )
    .await?;

    // Assemble bundle preparation parameters for PIR precompute.
    let prepare_params = prepare_delegation_bundle_params(
        lwd,
        ctx.session_json.as_deref(),
        &ctx.account_uuid,
        &voting_hotkey,
        bundle_index,
        bundle_policy,
    );

    // Warm the PIR path by precomputing/caching delegation bundle artifacts.
    delegation::precompute_delegation_pir(&ctx.db_path, &pir_server_url, prepare_params)
        .await
        .map(zcash_voting::wire::DelegationPirPrecomputeResultView::from)
}

/// Streaming variant of `build_prove_and_sign_delegation_payload`.
///
/// Emits local preparation phase events while work progresses, then emits a
/// final `"result"` event containing `SignedDelegationPayloadView`. The function
/// returns `Ok(())` after the terminal event is queued.
///
/// # Errors
///
/// Returns an error if round input resolution fails before the stream work
/// starts. Runtime delegation/proving errors are forwarded into the sink as
/// stream errors.
pub async fn build_prove_and_sign_delegation_payload_with_progress(
    ctx: ApiVotingRoundContext,
    pir_server_url: String,
    mnemonic: String,
    stored_hotkey_secret: Vec<u8>,
    bundle_index: u32,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    // Resolve static delegation inputs and validate the app-owned stored hotkey.
    let (voting_network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;
    let seed = seed_from_mnemonic(mnemonic)?;
    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, voting_network)?;

    // Resolve lightwalletd inputs and assemble delegation prepare parameters.
    let lwd = resolve_delegation_lwd_inputs(
        &ctx.lightwalletd_url,
        ctx.round_params,
        &ctx.round_name,
        voting_network,
    )
    .await?;
    let prepare_params = prepare_delegation_bundle_params(
        lwd,
        ctx.session_json.as_deref(),
        &ctx.account_uuid,
        &voting_hotkey,
        bundle_index,
        bundle_policy,
    );

    // Stream local progress events and emit one final result/error event.
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let signed_result = delegation::build_prove_and_sign_delegation_payload(
        &ctx.db_path,
        &pir_server_url,
        &seed,
        prepare_params,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                log_sink_closed(DELEGATION_STREAM_CONTEXT, SINK_PROGRESS_NOT_DELIVERED);
            }
        },
    )
    .await
    .and_then(|bundle| {
        zcash_voting::wire::SignedDelegationPayloadView::try_from(bundle).map_err(|e| e.to_string())
    });
    emit_signed_delegation_result(sink.as_ref(), signed_result)
}

/// Build and redact a voting PCZT that Keystone must sign for one bundle.
///
/// # Errors
///
/// Returns an error if round input resolution fails or if PCZT construction and
/// redaction for the requested bundle fails.
pub async fn build_keystone_delegation_request(
    ctx: ApiVotingRoundContext,
    stored_hotkey_secret: Vec<u8>,
    bundle_index: u32,
) -> Result<zcash_voting::wire::KeystoneSigningRequest, String> {
    // Resolve static round inputs and validate Keystone-provided hotkey bytes.
    let (voting_network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;
    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, voting_network)?;

    // Resolve lightwalletd-backed round inputs and build request parameters.
    let lwd = resolve_delegation_lwd_inputs(
        &ctx.lightwalletd_url,
        ctx.round_params,
        &ctx.round_name,
        voting_network,
    )
    .await?;
    let prepare_params = prepare_delegation_bundle_params(
        lwd,
        ctx.session_json.as_deref(),
        &ctx.account_uuid,
        &voting_hotkey,
        bundle_index,
        bundle_policy,
    );

    // Build and redact the PCZT request that Keystone signs out of process.
    delegation::build_keystone_delegation_request(&ctx.db_path, &ctx.account_uuid, prepare_params)
        .await
}

/// Parse the fields Dart needs from a Keystone-signed voting PCZT.
///
/// # Errors
///
/// Returns an error if the signed PCZT cannot be decoded, does not contain a
/// spend authorization sighash, or does not contain a SpendAuth signature for
/// the expected action.
pub fn parse_signed_voting_pczt(
    signed_pczt_bytes: Vec<u8>,
    action_index: u32,
) -> Result<ParsedSignedVotingPczt, String> {
    catch(|| {
        let action_index =
            usize::try_from(action_index).map_err(|_| "action_index does not fit in usize")?;
        let sighash = zcash_voting::delegate::pczt_sighash(&signed_pczt_bytes)
            .map_err(|e| format!("extract_pczt_sighash failed: {e}"))?;
        let spend_auth_sig =
            zcash_voting::delegate::spend_auth_signature(&signed_pczt_bytes, action_index)
                .map_err(|e| format!("extract_spend_auth_sig failed: {e}"))?;
        Ok(ParsedSignedVotingPczt {
            sighash: sighash.to_vec(),
            spend_auth_sig: spend_auth_sig.to_vec(),
        })
    })
}

/// Persist a Keystone signature for one delegation bundle.
///
/// # Errors
///
/// Returns an error if signature lengths are invalid, opening the voting DB
/// fails, or persisting the signature record fails.
pub fn store_keystone_signature(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    sig: Vec<u8>,
    sighash: Vec<u8>,
    rk: Vec<u8>,
) -> Result<(), String> {
    catch(|| {
        // Validate fixed-size fields before persisting the signature tuple.
        require_len(&sig, KEYSTONE_SIG_LEN, "sig")?;
        require_len(&sighash, KEYSTONE_SIGHASH_LEN, "sighash")?;
        require_len(&rk, KEYSTONE_RK_LEN, "rk")?;
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.store_keystone_signature(&round_id, bundle_index, &sig, &sighash, &rk)
            .map_err(|e| format!("store_keystone_signature failed: {e}"))
    })
}

/// Load persisted Keystone signatures for one voting round.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or signature rows cannot be
/// loaded.
pub fn get_keystone_signatures(
    db_path: String,
    account_uuid: String,
    round_id: String,
) -> Result<Vec<zcash_voting::wire::KeystoneSignatureRecord>, String> {
    catch(|| {
        // Load all persisted Keystone signatures for this round.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.get_keystone_signatures(&round_id)
            .map_err(|e| format!("get_keystone_signatures failed: {e}"))
    })
}

/// Streaming Keystone variant of `build_prove_and_sign_delegation_payload`.
///
/// # Errors
///
/// Returns an error if round input resolution fails before stream work starts.
/// Runtime proving/signature errors are emitted through the sink.
pub async fn build_prove_delegation_payload_with_keystone_signature_with_progress(
    ctx: ApiVotingRoundContext,
    pir_server_url: String,
    stored_hotkey_secret: Vec<u8>,
    bundle_index: u32,
    keystone_sig: Vec<u8>,
    keystone_sighash: Vec<u8>,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    // Resolve static inputs and validate the persisted Keystone hotkey seed.
    let (voting_network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;
    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, voting_network)?;

    // Resolve round inputs and build delegation preparation parameters.
    let lwd = resolve_delegation_lwd_inputs(
        &ctx.lightwalletd_url,
        ctx.round_params,
        &ctx.round_name,
        voting_network,
    )
    .await?;
    let prepare_params = prepare_delegation_bundle_params(
        lwd,
        ctx.session_json.as_deref(),
        &ctx.account_uuid,
        &voting_hotkey,
        bundle_index,
        bundle_policy,
    );

    // Stream local progress and emit the terminal signed payload or error.
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let signed_result = delegation::build_prove_delegation_payload_with_keystone_signature(
        &ctx.db_path,
        &pir_server_url,
        &ctx.account_uuid,
        prepare_params,
        &keystone_sig,
        &keystone_sighash,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                log_sink_closed(DELEGATION_STREAM_CONTEXT, SINK_PROGRESS_NOT_DELIVERED);
            }
        },
    )
    .await
    .and_then(|bundle| {
        zcash_voting::wire::SignedDelegationPayloadView::try_from(bundle).map_err(|e| e.to_string())
    });
    emit_signed_delegation_result(sink.as_ref(), signed_result)
}

/// Record a submitted delegation transaction hash for one bundle.
///
/// Repeated calls are idempotent only for the same transaction hash.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the bundle key is missing,
/// or the stored hash conflicts with `tx_hash`.
pub fn mark_delegation_submitted(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        // Persist submission hash for this round/bundle key.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.mark_delegation_submitted(&round_id, bundle_index, &tx_hash)
            .map_err(|e| e.to_string())
    })
}

/// Parse tx events and record a confirmed delegation submission.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the event payload does not
/// match the expected round/type shape, or confirmation state cannot be stored.
pub fn confirm_delegation_submission(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
    events_json: String,
) -> Result<zcash_voting::wire::DelegationConfirmation, String> {
    catch(|| {
        let events = parse_tx_events_json(&events_json)?;
        // Parse tx events and persist confirmation details for this bundle.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
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
    account_uuid: String,
    round_id: String,
    keep_count: u32,
) -> Result<u32, String> {
    catch(|| {
        // Delete skipped bundle rows and downcast deleted count for FRB.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
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
/// per `(db_path, account_uuid)` so later VAN witness calls can reuse the synced
/// in-memory tree state.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or tree sync against
/// `node_url` fails for `round_id`.
pub fn sync_vote_tree(
    db_path: String,
    account_uuid: String,
    round_id: String,
    node_url: String,
) -> Result<u32, String> {
    catch(|| {
        // Sync and cache vote tree state for this wallet/round.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        zcash_voting::precompute::sync_vote_tree(&db, &round_id, &node_url)
            .map_err(|e| format!("sync_vote_tree failed: {e}"))
    })
}

/// Generate a Vote Authority Note Merkle witness for a delegation bundle.
///
/// `anchor_height` is the vote-tree height where the witness should be anchored;
/// callers must sync the same round before requesting the witness.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, `bundle_index` is out of
/// range for the round, or witness generation fails.
pub fn generate_van_witness(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<zcash_voting::wire::VanWitness, String> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        // Validate bundle index against persisted bundle count first.
        let bundle_count = db
            .get_bundle_count(&round_id)
            .map_err(|e| format!("get_bundle_count failed: {e}"))?;
        zcash_voting::validate_bundle_index(bundle_count, bundle_index, "voting")
            .map_err(|e| e.to_string())?;
        zcash_voting::precompute::van_witness(&db, &round_id, bundle_index, anchor_height)
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
    account_uuid: String,
    round_id: Option<String>,
) -> Result<(), String> {
    catch(|| {
        // Empty/None round_id means clear account-wide cached vote tree state.
        let account_wide = round_id.as_deref().map(str::is_empty).unwrap_or(true);
        let tree_count = if account_wide {
            let db = db::open_voting_db(&db_path, &account_uuid)?;
            zcash_voting::precompute::reset_vote_tree(&db, "")
                .map_err(|e| format!("clear_tree_sync_session failed: {e}"))?;
            1
        } else {
            0
        };
        log::info!(
            "voting: reset process-local session state \
             (account_uuid={}, round_id={:?}, tree_entries={})",
            account_uuid,
            round_id,
            tree_count
        );
        Ok(())
    })
}

/// Recover a committed but unsubmitted vote from persisted local recovery data.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, no matching commitment is
/// recoverable, or wire conversion fails.
pub fn recover_vote_commitment(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<zcash_voting::wire::SignedVoteCommitmentsView, String> {
    catch(|| {
        // Recover persisted commitments and convert to public wire view.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        zcash_voting::vote::recover_signed_commitments(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("vote commitment recovery failed: {e}"))
            .and_then(|commitments| {
                zcash_voting::wire::SignedVoteCommitmentsView::try_from(commitments)
                    .map_err(|e| e.to_string())
            })
    })
}

#[allow(clippy::too_many_arguments)]
async fn build_vote_commitments_result<F>(
    db_path: String,
    account_uuid: String,
    network: String,
    round_id: String,
    bundle_index: u32,
    stored_hotkey_secret: Vec<u8>,
    van_witness: zcash_voting::wire::VanWitness,
    draft_votes: Vec<zcash_voting::wire::DraftVote>,
    on_stage: F,
) -> Result<zcash_voting::wire::SignedVoteCommitmentsView, String>
where
    F: Fn(zcash_voting::vote::VoteCommitStage) + Send + Sync + 'static,
{
    // Parse network once and keep hotkey bytes in a secrecy wrapper.
    let network = keys::parse_network(&network)?;
    let stored_hotkey_secret = secrecy::SecretVec::new(stored_hotkey_secret);

    // Commit/prove work is CPU-heavy; run it on a blocking worker thread.
    let commitment_result = tokio::task::spawn_blocking(move || {
        let reporter = zcash_voting::VoteCommitStageBridge::new(on_stage);
        let voting_db = db::open_voting_db(&db_path, &account_uuid)?;
        let voting_hotkey = zcash_voting::VotingHotkey::from_stored_secret(
            stored_hotkey_secret.expose_secret(),
            voting_network(network),
        )
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;

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
    let commitments = commitment_result?;

    // Convert internal commitment type into the FRB wire view.
    zcash_voting::wire::SignedVoteCommitmentsView::try_from(commitments).map_err(|e| e.to_string())
}

#[allow(clippy::too_many_arguments)]
/// Streaming variant of `build_vote_commitments`.
///
/// Emits per-proposal progress events, then a terminal `"result"` event carrying
/// `SignedVoteCommitmentsView`.
pub async fn build_vote_commitments_with_progress(
    db_path: String,
    account_uuid: String,
    network: String,
    round_id: String,
    bundle_index: u32,
    stored_hotkey_secret: Vec<u8>,
    van_witness: zcash_voting::wire::VanWitness,
    draft_votes: Vec<zcash_voting::wire::DraftVote>,
    sink: StreamSink<ApiVoteCommitEvent>,
) -> Result<(), String> {
    // Bridge stage callbacks into stream events for UI progress updates.
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let commitments = build_vote_commitments_result(
        db_path,
        account_uuid,
        network,
        round_id,
        bundle_index,
        stored_hotkey_secret,
        van_witness,
        draft_votes,
        move |stage| {
            if progress_sink.add(stage.into()).is_err() {
                log_sink_closed(VOTE_STREAM_CONTEXT, SINK_PROGRESS_NOT_DELIVERED);
            }
        },
    )
    .await;

    emit_signed_vote_result(sink.as_ref(), commitments)
}

/// Load the full recovery/share-tracking summary for one voting round.
pub fn get_round_recovery_state(
    db_path: String,
    account_uuid: String,
    round_id: String,
) -> Result<zcash_voting::wire::RoundRecoveryStateView, String> {
    catch(|| {
        // Load persisted round snapshot and expose wire-safe view fields.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        zcash_voting::recovery::round_snapshot(&db, &round_id)
            .map(zcash_voting::wire::RoundRecoveryStateView::from)
            .map_err(|e| format!("round_snapshot failed: {e}"))
    })
}

/// Record a submitted cast-vote transaction hash for one bundle/proposal key.
///
/// Repeated calls are idempotent only for the same transaction hash.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the vote key is missing, or
/// the stored hash conflicts with `tx_hash`.
pub fn mark_vote_submitted(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        // Persist submission hash for this round/bundle/proposal key.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.mark_vote_submitted(&round_id, bundle_index, proposal_id, &tx_hash)
            .map_err(|e| e.to_string())
    })
}

/// Parse tx events and record a confirmed vote submission.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the event payload does not
/// match the expected round/type shape, or confirmation state cannot be stored.
pub fn confirm_vote_submission(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
    events_json: String,
) -> Result<zcash_voting::wire::VoteConfirmation, String> {
    catch(|| {
        let events = parse_tx_events_json(&events_json)?;
        // Parse tx events and persist vote confirmation fields.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
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

fn parse_tx_events_json(events_json: &str) -> Result<Vec<zcash_voting::prelude::TxEvent>, String> {
    let events: Vec<zcash_voting::prelude::TxEvent> =
        serde_json::from_str(events_json).map_err(|e| format!("invalid tx events JSON: {e}"))?;
    Ok(events)
}

#[allow(clippy::too_many_arguments)]
/// Record helper-server submission state for one encrypted vote share.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the vote cannot be
/// recovered, or the share record cannot be persisted.
pub fn record_share_delegation(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: Vec<String>,
    submit_at: u64,
) -> Result<(), String> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        // Recover vote context first, then persist helper submission metadata.
        zcash_voting::vote::CommittedVote::recover(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("recover committed vote failed: {e}"))?
            .record_share(&db, share_index, &sent_to_urls, submit_at)
            .map_err(|e| format!("record_share_delegation failed: {e}"))?;
        Ok(())
    })
}

/// Mark one delegated share as confirmed on-chain.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails, the vote cannot be
/// recovered, or share confirmation cannot be persisted.
pub fn mark_share_confirmed(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        // Recover vote context first, then mark the specific share as confirmed.
        zcash_voting::vote::CommittedVote::recover(&db, &round_id, bundle_index, proposal_id)
            .map_err(|e| format!("recover committed vote failed: {e}"))?
            .confirm_share(&db, share_index)
            .map_err(|e| format!("mark_share_confirmed failed: {e}"))?;
        Ok(())
    })
}

/// Merge additional helper-server URLs into one share delegation record.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or the share record cannot
/// be updated.
pub fn add_sent_servers(
    db_path: String,
    account_uuid: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: Vec<String>,
) -> Result<(), String> {
    catch(|| {
        // Merge additional helper URLs into persisted share delivery state.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
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
    account_uuid: String,
    round_id: String,
) -> Result<(), String> {
    catch(|| {
        // Clear persisted recovery/share-tracking state for this round.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        zcash_voting::recovery::clear(&db, &round_id)
            .map_err(|e| format!("clear_recovery_state failed: {e}"))
    })
}

/// Compute the resumable voting-session plan for a round. The plan reports the
/// ordered remaining work (`next_steps`) and which proposals are still open.
pub fn get_round_plan(
    db_path: String,
    account_uuid: String,
    round_id: String,
    proposal_ids: Vec<u32>,
) -> Result<zcash_voting::wire::RoundPlanView, String> {
    catch(|| {
        // Derive resumable next steps and convert to wire view.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        let plan = zcash_voting::session::resume_plan(&db, &round_id, &proposal_ids)
            .map_err(|e| format!("resume_plan failed: {e}"))?;
        zcash_voting::wire::RoundPlanView::try_from(plan).map_err(|e| e.to_string())
    })
}

/// Persist (insert or replace) the voter's ballot intent for one proposal.
/// Pass `skipped: true` for `Decision::Skipped`; otherwise `choice` must be set.
/// `num_options` is the proposal's declared option count.
pub fn set_ballot_intent(
    db_path: String,
    account_uuid: String,
    round_id: String,
    proposal_id: u32,
    num_options: u32,
    skipped: bool,
    choice: Option<u32>,
) -> Result<(), String> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        // `skipped` takes precedence; otherwise a concrete choice is required.
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingConfigResolution {
    pub config: ResolvedVotingConfig,
    pub switch_kind: ConfigSwitchKind,
}

/// Authenticate the static voting config bytes and surface the dynamic URL.
///
/// The wallet fetches the static trust anchor with its own transport and passes
/// the bytes here. Rust verifies the hash pin and decodes the static config,
/// returning the `dynamic_config_url` the wallet must fetch next before calling
/// [`resolve_voting_config`]. Config errors are returned as a flat string.
pub fn resolve_static_voting_config(
    source: String,
    static_bytes: Vec<u8>,
) -> Result<String, String> {
    config::resolve_static_voting_config(&source, &static_bytes)
        .map(|resolved| resolved.dynamic_config_url)
        .map_err(|error| error.to_string())
}

/// Resolve and authenticate voting config from wallet-fetched bytes.
///
/// The wallet owns transport: it fetches the static bytes, calls
/// [`resolve_static_voting_config`] to learn the dynamic URL, fetches the
/// dynamic bytes, then passes both blobs here. Rust authenticates them and
/// computes the config-switch classification against `previous`. Config errors
/// are returned as a flat string; transport failures never reach this layer.
pub fn resolve_voting_config(
    source: String,
    static_bytes: Vec<u8>,
    dynamic_bytes: Vec<u8>,
    previous: Option<ResolvedVotingConfig>,
) -> Result<VotingConfigResolution, String> {
    let resolved_static = config::resolve_static_voting_config(&source, &static_bytes)
        .map_err(|error| error.to_string())?;
    let next = config::resolve_dynamic_voting_config(
        resolved_static,
        &dynamic_bytes,
        ResolveVotingConfigOptions::default(),
    )
    .map_err(|error| error.to_string())?;

    let switch_kind = config::decide_config_switch(
        previous.as_ref().map(ResolvedVotingConfigSummary::from),
        ResolvedVotingConfigSummary::from(&next),
    )
    .kind;

    Ok(VotingConfigResolution {
        config: next,
        switch_kind,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::test_support::{
        test_api_round_params, test_note_info, ROUND_ID, TEST_ACCOUNT_UUID,
    };
    use base64::Engine as _;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use zcash_client_backend::proto::service::TreeState;
    use zcash_voting::prelude::{TxEvent, TxEventAttribute};
    use zcash_voting::BundlePolicy;

    fn b64(bytes: impl AsRef<[u8]>) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    fn tx_events_json(events: Vec<TxEvent>) -> String {
        serde_json::to_string(&events).unwrap()
    }

    fn delegate_event(round_id: &str, leaf_index: u32) -> TxEvent {
        TxEvent {
            event_type: "delegate_vote".to_string(),
            attributes: vec![
                TxEventAttribute {
                    key: "vote_round_id".to_string(),
                    value: round_id.to_string(),
                },
                TxEventAttribute {
                    key: "leaf_index".to_string(),
                    value: leaf_index.to_string(),
                },
            ],
        }
    }

    fn cast_vote_event(round_id: &str, van_position: u32, vc_tree_position: u64) -> TxEvent {
        TxEvent {
            event_type: "cast_vote".to_string(),
            attributes: vec![
                TxEventAttribute {
                    key: "vote_round_id".to_string(),
                    value: round_id.to_string(),
                },
                TxEventAttribute {
                    key: "leaf_index".to_string(),
                    value: format!("{van_position},{vc_tree_position}"),
                },
            ],
        }
    }

    fn test_round_context(
        db_path: &std::path::Path,
        network: &str,
        account_uuid: &str,
    ) -> ApiVotingRoundContext {
        ApiVotingRoundContext {
            db_path: db_path.to_str().unwrap().to_string(),
            lightwalletd_url: "http://127.0.0.1:1".to_string(),
            network: network.to_string(),
            round_params: test_api_round_params(),
            round_name: "Demo".to_string(),
            session_json: None,
            account_uuid: account_uuid.to_string(),
            max_real_notes_per_bundle: None,
        }
    }

    #[test]
    fn generate_voting_hotkey_happy_path_returns_valid_distinct_seeds() {
        let hotkey_a = generate_voting_hotkey("regtest".to_string()).unwrap();
        let hotkey_b = generate_voting_hotkey("regtest".to_string()).unwrap();
        assert_eq!(hotkey_a.len(), 64);
        assert_eq!(hotkey_b.len(), 64);
        assert_ne!(hotkey_a, hotkey_b);
    }

    #[test]
    fn bundle_policy_happy_path_maps_optional_limit() {
        assert_eq!(
            bundle_policy(None).unwrap(),
            BundlePolicy::from_optional_max_real_notes_per_bundle(None).unwrap()
        );
        assert_eq!(
            bundle_policy(Some(2)).unwrap(),
            BundlePolicy::from_optional_max_real_notes_per_bundle(Some(2)).unwrap()
        );
    }

    #[test]
    fn api_round_params_convert_to_core_round_params() {
        let api = test_api_round_params();

        let core: zcash_voting::VotingRoundParams = api.clone();

        assert_eq!(core.vote_round_id, api.vote_round_id);
        assert_eq!(core.snapshot_height, api.snapshot_height);
        assert_eq!(core.ea_pk, api.ea_pk);
        assert_eq!(core.nc_root, api.nc_root);
        assert_eq!(core.nullifier_imt_root, api.nullifier_imt_root);
    }

    #[test]
    fn trusted_round_params_use_config_ea_pk() {
        let trusted_ea_pk = vec![7u8; 32];
        let config = zcash_voting::config::ResolvedVotingConfig {
            source_fingerprint: "source".to_string(),
            trusted_key_fingerprint: "keys".to_string(),
            dynamic_config_fingerprint: "dynamic".to_string(),
            vote_servers: vec![],
            pir_endpoints: vec![],
            supported_versions: zcash_voting::config::SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
            authenticated_rounds: vec![zcash_voting::config::AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: trusted_ea_pk.clone(),
            }],
            skipped_round_ids: vec![],
            conditions: vec![],
        };

        let params = trusted_voting_round_params_from_config(
            config,
            ROUND_ID.to_string(),
            123,
            vec![2u8; 32],
            vec![3u8; 32],
        )
        .unwrap();

        assert_eq!(params.vote_round_id, ROUND_ID);
        assert_eq!(params.snapshot_height, 123);
        assert_eq!(params.ea_pk, trusted_ea_pk);
        assert_eq!(params.nc_root, vec![2u8; 32]);
        assert_eq!(params.nullifier_imt_root, vec![3u8; 32]);
    }

    #[test]
    fn api_bundle_setup_result_preserves_core_fields() {
        let api = zcash_voting::wire::BundleLayout {
            bundle_count: 2,
            eligible_weight: 50,
            dropped_count: 0,
        };

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
        assert_eq!(api.submission.proof, b64(vec![4]));
        assert_eq!(api.submission.vote_round_id, b64([0, 1, 2, 3]));
        assert_eq!(api.eligible_weight_zatoshi, 20);
        assert_eq!(api.delegated_weight_zatoshi, 10);
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn api_keystone_delegation_request_preserves_display_memo() {
        let api = zcash_voting::wire::KeystoneSigningRequest {
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
        };

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
                    proof: b64(vec![8; 96]),
                    rk: b64(vec![1; 32]),
                    spend_auth_sig: b64(vec![2; 64]),
                    sighash: b64(vec![3; 32]),
                    nf_signed: b64(vec![4; 32]),
                    cmx_new: b64(vec![5; 32]),
                    gov_comm: b64(vec![6; 32]),
                    gov_nullifiers: vec![b64(vec![7; 32]); zcash_voting::BUNDLE_NOTE_SLOTS],
                    vote_round_id: b64([0, 1, 2, 3]),
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
            van_nullifier: b64(vec![1; 32]),
            vote_authority_note_new: b64(vec![2; 32]),
            vote_commitment: b64(vec![3; 32]),
            proposal_id: 7,
            proof: b64(vec![4; 96]),
            vote_round_id: b64(vec![0, 1, 2, 3]),
            anchor_height: 77,
            r_vpk: b64(vec![5; 32]),
            vote_auth_sig: b64(vec![6; 64]),
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
            // JSON numbers are constrained to the IEEE-754 safe-integer range.
            Some(MAX_SAFE_JSON_INTEGER + 1),
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
    fn plan_share_submissions_happy_path_returns_helper_targets() {
        let server_urls = vec![
            "https://helper-a.example".to_string(),
            "https://helper-b.example".to_string(),
        ];
        let plans =
            plan_share_submissions(3, server_urls.clone(), 100, 600, Some(120), false).unwrap();

        assert_eq!(plans.len(), 3);
        for plan in plans {
            assert!(plan.submit_at >= 100);
            assert!(!plan.target_servers.is_empty());
            assert!(plan.target_servers.len() <= plan.target_count as usize);
            assert!(plan
                .target_servers
                .iter()
                .all(|url| server_urls.contains(url)));
        }
    }

    #[test]
    fn api_van_witness_preserves_core_fields() {
        let mut witness = vec![vec![0u8; 32]; zcash_voting::vote::VAN_AUTH_PATH_LEN];
        witness[0] = vec![1; 32];
        witness[1] = vec![2; 32];
        let api = zcash_voting::wire::VanWitness {
            auth_path: witness,
            position: 7,
            anchor_height: 123,
        };

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
        assert_eq!(api.commitments[0].shares[0].primary_blind, b64(vec![9; 32]));
        assert_eq!(api.commitments[0].wire.vote_auth_sig, b64(vec![9; 64]));
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
        let db = db::open_voting_db(db_path.to_str().unwrap(), "wallet-api-bundles").unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
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
        let db = db::open_voting_db(db_path.to_str().unwrap(), "wallet-api-witness").unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
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
        assert_eq!(
            witness.auth_path.len(),
            zcash_voting::vote::VAN_AUTH_PATH_LEN
        );
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[test]
    fn reset_voting_session_state_with_round_preserves_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-round-reset";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();

        let witness = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
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
        let account_uuid = "wallet-api-account-reset";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            None,
        )
        .unwrap();

        let err = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap_err();
        assert!(!err.is_empty());
    }

    #[test]
    fn recover_vote_commitment_happy_path_returns_wire_commitment() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        seed_recovery_vote(&db, TEST_ACCOUNT_UUID, 0, 7, 1, 88);

        let recovered = recover_vote_commitment(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            7,
        )
        .unwrap();

        assert_eq!(recovered.bundle_index, 0);
        assert_eq!(recovered.commitments.len(), 1);
        assert_eq!(recovered.commitments[0].proposal_id, 7);
    }

    #[test]
    fn recovery_api_preserves_round_summary_and_share_records() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-recovery";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(
            &conn,
            ROUND_ID,
            account_uuid,
            1,
            2,
            1,
            b"vote-1",
        )
        .unwrap();
        drop(conn);
        mark_vote_submitted(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
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
                    ":wallet_id": account_uuid,
                    ":bundle_index": 1i64,
                    ":proposal_id": 2i64,
                },
            )
            .unwrap();
        }
        record_share_delegation(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
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
            account_uuid.to_string(),
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
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            0,
        )
        .unwrap();
        let confirmed_state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(confirmed_state.unconfirmed_share_delegations.is_empty());

        clear_recovery_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        let cleared_state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(cleared_state.share_delegations.is_empty());
    }

    #[test]
    fn keystone_signature_round_trip_and_length_validation() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();

        store_keystone_signature(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            vec![7; KEYSTONE_SIG_LEN],
            vec![8; KEYSTONE_SIGHASH_LEN],
            vec![9; KEYSTONE_RK_LEN],
        )
        .unwrap();
        let records = get_keystone_signatures(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(records.len(), 1);
        assert_eq!(records[0].bundle_index, 0);
        assert_eq!(records[0].sig, vec![7; KEYSTONE_SIG_LEN]);

        let err = store_keystone_signature(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            vec![7; KEYSTONE_SIG_LEN - 1],
            vec![8; KEYSTONE_SIGHASH_LEN],
            vec![9; KEYSTONE_RK_LEN],
        )
        .unwrap_err();
        assert!(err.contains("sig must be exactly"));
    }

    #[test]
    fn set_ballot_intent_persists_choice_and_skipped() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();

        set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            1,
            3,
            false,
            Some(2),
        )
        .unwrap();
        set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            2,
            3,
            true,
            None,
        )
        .unwrap();

        let err = set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            3,
            3,
            false,
            None,
        )
        .unwrap_err();
        assert!(err.contains("choice must be Some"));
    }

    #[test]
    fn round_plan_happy_path_returns_round_and_open_proposals() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();

        let plan = get_round_plan(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![1, 2],
        )
        .unwrap();

        assert_eq!(plan.round_id, ROUND_ID);
        assert_eq!(plan.open_proposals, vec![1, 2]);
    }

    #[test]
    fn mark_delegation_submitted_updates_recovery_snapshot() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();

        mark_delegation_submitted(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            "delegation-submitted-tx".to_string(),
        )
        .unwrap();

        let snapshot = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert_eq!(snapshot.delegation.len(), 1);
        assert_eq!(
            snapshot.delegation[0].tx_hash.as_deref(),
            Some("delegation-submitted-tx")
        );
    }

    #[test]
    fn confirm_submission_apis_record_expected_confirmation_fields() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(&test_api_round_params(), None).unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        seed_recovery_vote(&db, TEST_ACCOUNT_UUID, 0, 7, 1, 88);

        let delegation = confirm_delegation_submission(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            "delegate-confirmed-tx".to_string(),
            tx_events_json(vec![delegate_event(ROUND_ID, 42)]),
        )
        .unwrap();
        assert_eq!(delegation.tx_hash, "delegate-confirmed-tx");
        assert_eq!(delegation.van_leaf_position, 42);

        let vote = confirm_vote_submission(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            0,
            7,
            "vote-confirmed-tx".to_string(),
            tx_events_json(vec![cast_vote_event(ROUND_ID, 42, 88)]),
        )
        .unwrap();
        assert_eq!(vote.tx_hash, "vote-confirmed-tx");
        assert_eq!(vote.vc_tree_position, 88);
    }

    #[test]
    fn setup_delegation_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(setup_delegation_bundles(test_round_context(
                &db_path, "bogus", "wallet-1",
            )))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn precompute_delegation_pir_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_delegation_pir(
                test_round_context(&db_path, "bogus", "wallet-1"),
                "http://127.0.0.1:2".to_string(),
                vec![9; 64],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn precompute_delegation_pir_rejects_invalid_hotkey_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_delegation_pir(
                test_round_context(&db_path, "regtest", "wallet-1"),
                "http://127.0.0.1:2".to_string(),
                vec![9; 1],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Voting hotkey reconstruction failed"));
    }

    #[test]
    fn build_keystone_delegation_request_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_request(
                test_round_context(&db_path, "bogus", "wallet-1"),
                vec![9; 64],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn build_keystone_delegation_request_rejects_invalid_hotkey_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_request(
                test_round_context(&db_path, "regtest", "wallet-1"),
                vec![9; 1],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Voting hotkey reconstruction failed"));
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

    fn seed_recovery_vote(
        db: &zcash_voting::storage::VotingDb,
        account_uuid: &str,
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
        vc_tree_position: u64,
    ) {
        let recovery_json =
            test_vote_recovery_json(bundle_index, proposal_id, vote_decision, vc_tree_position);
        let recovery = zcash_voting::vote::parse_recovery(&recovery_json).unwrap();
        let commitment_bytes = serde_json::to_vec(&serde_json::json!({
            "van_nullifier": hex::encode(recovery.van_nullifier),
            "vote_authority_note_new": hex::encode(recovery.vote_authority_note_new),
            "vote_commitment": hex::encode(recovery.vote_commitment),
            "proof": hex::encode(recovery.proof),
        }))
        .unwrap();
        zcash_voting::storage::queries::store_vote(
            &db.conn(),
            ROUND_ID,
            account_uuid,
            bundle_index,
            proposal_id,
            vote_decision,
            &commitment_bytes,
        )
        .unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":json": recovery_json,
                    ":round_id": ROUND_ID,
                    ":wallet_id": account_uuid,
                    ":bundle_index": i64::from(bundle_index),
                    ":proposal_id": i64::from(proposal_id),
                },
            )
            .unwrap();
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
}
