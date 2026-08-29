//! Client-side APIs for Zcash shielded voting.
//!
//! Wallet SDKs should import [`prelude`] and follow the lifecycle:
//! create a round, bind eligible notes into bundles, precompute witness/PIR
//! data, build a delegation PCZT, prove delegation, sync the vote commitment
//! tree, cast votes with `vote::commit`, confirm chain submissions through
//! `confirmation`, then recover helper-share payloads through `share`. New
//! integrations should use `round`, `precompute`, `delegate`, `vote`,
//! `confirmation`, `share`, and `session` rather than writing storage rows
//! directly.

#[cfg(all(feature = "upstream", feature = "zakura"))]
compile_error!("features `upstream` and `zakura` cannot be enabled together");

#[cfg(not(any(feature = "upstream", feature = "zakura")))]
compile_error!("enable exactly one of the `upstream` or `zakura` features");

pub mod action;
mod backend;
pub mod config;
pub mod confirmation;
pub mod delegate;
pub mod delegation_capability;
pub mod error;
pub mod governance;
pub mod helper;
pub mod hotkey;
mod http_transport;
pub mod lwd;
pub mod note_bundling;
pub mod phases;
pub mod pir;
pub mod pir_snapshot;
pub mod precompute;
pub mod prelude;
pub mod recovery;
pub mod round;
pub mod round_auth;
pub mod selection;
pub mod session;
pub mod share;
pub mod share_policy;
mod shielded_protocol;
pub mod storage;
pub mod transport;
pub mod tree_sync;
pub mod tx1;
pub mod types;
pub mod vote;
pub mod vote_commitment;
pub mod wire;
mod wire_codec;
pub mod witness;
pub mod zkp1;
pub mod zkp2;

pub use helper::health::HelperHealth;
pub use http_transport::HyperTransport;
pub use pir::{
    connect_pir, connect_pir_blocking, negotiated_pir_layout, ImtProofData, NegotiatedPirLayout,
    PirClient, PirClientBlocking, Transport, TransportFuture, TransportResponse,
};

pub use delegation_capability::{
    export_delegation_capability, import_delegation_capability, DelegationCapabilityBundleV1,
    DelegationCapabilityDigest, DelegationCapabilityV1, ExportedDelegationCapability,
    ImportDelegationCapabilityParams, MAX_DELEGATION_CAPABILITY_BUNDLES,
    MAX_DELEGATION_CAPABILITY_JSON_BYTES,
};
pub use governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS};
pub use note_bundling::{
    minimum_voting_eligibility_and_plan_for_notes, minimum_voting_eligibility_for_notes,
    validate_minimum_voting_eligibility_for_notes, voting_power, voting_power_for_round,
    voting_power_with_policy, BundlePolicy, ChunkResult, MinimumVotingEligibility, PrivacyTrim,
    MINIMUM_VOTING_NOTE_COUNT, MINIMUM_VOTING_WEIGHT_ZATOSHI,
};
pub use round::validate_bundle_index;
pub use selection::{
    gather_delegation_wallet_inputs, select_notes_with_wallet_db, select_snapshot_notes,
    DelegationWalletInputs, GatherDelegationWalletParams,
};
pub use types::{
    validate_proposal_id, validate_round_params, validate_vote_decision, validate_vote_options,
    CastVoteSignature, DelegationAction, DelegationPirPrecomputeResult, DelegationProgressBridge,
    DelegationProgressReporter, DelegationProofResult, DelegationSubmissionData, EncryptedShare,
    GovernancePczt, Network, NoopProgressReporter, NoteInfo, NoteRef, PirCachePrecomputeResult,
    PirCacheValidationReport, PirProofCacheEntry, PirProofCacheStatus, ProgressReporter,
    RoundBoundVotingHotkeyTarget, SelectedNotes, ShareDelegationRecord, SharePayload,
    VoteCommitStageBridge, VoteCommitStageReporter, VoteCommitmentBundle, VotingError,
    VotingHotkey, VotingHotkeyTarget, VotingRoundParams, WireEncryptedShare, WitnessData,
    MAX_PROPOSAL_ID, MAX_VOTE_OPTIONS, MIN_PROPOSAL_ID, MIN_VOTE_OPTIONS,
};

/// Warms the process-lifetime ZKP #2 proving-key cache.
///
/// The warm-up runs on a large-stack thread and is safe to call repeatedly.
pub fn warm_zkp2_proving_cache() -> Result<(), VotingError> {
    const KEYGEN_STACK_BYTES: usize = 64 * 1024 * 1024;

    std::thread::Builder::new()
        .name("voting-vote-proof-cache-warmup".to_string())
        .stack_size(KEYGEN_STACK_BYTES)
        .spawn(|| {
            voting_circuits::vote_proof::warm_vote_proof_keys().map_err(|e| {
                VotingError::ProofFailed {
                    message: format!("ZKP2 proving cache warm-up failed: {e}"),
                }
            })
        })
        .map_err(|e| VotingError::Internal {
            message: format!("failed to spawn ZKP2 proving cache warm-up thread: {e}"),
        })?
        .join()
        .map_err(|_| VotingError::Internal {
            message: "ZKP2 proving cache warm-up thread panicked".to_string(),
        })?
}

/// Warm process-lifetime proving-key caches used by on-device voting proofs.
///
/// This is intentionally best-effort at the cache layer: callers should invoke
/// it from a background task before the first proof is needed.
pub fn warm_proving_caches() {
    const KEYGEN_STACK_BYTES: usize = 64 * 1024 * 1024;

    let handles = [
        std::thread::Builder::new()
            .name("voting-delegation-cache-warmup".to_string())
            .stack_size(KEYGEN_STACK_BYTES)
            .spawn(|| {
                let _ = voting_circuits::delegation::warm_delegation_keys();
            })
            .expect("spawn delegation proving cache warm-up thread"),
        std::thread::Builder::new()
            .name("voting-vote-proof-cache-warmup".to_string())
            .stack_size(KEYGEN_STACK_BYTES)
            .spawn(|| {
                let _ = voting_circuits::vote_proof::warm_vote_proof_keys();
            })
            .expect("spawn vote proof cache warm-up thread"),
    ];

    for handle in handles {
        handle
            .join()
            .expect("proving cache warm-up thread panicked");
    }
}
