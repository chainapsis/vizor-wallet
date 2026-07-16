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

pub mod action;
pub mod config;
pub mod confirmation;
pub mod delegate;
pub mod error;
pub mod governance;
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
pub mod selection;
pub mod session;
pub mod share;
pub mod share_policy;
mod shielded_protocol;
pub mod storage;
pub mod transport;
pub mod tree_sync;
pub mod types;
pub mod vote;
pub mod vote_commitment;
pub mod wire;
mod wire_codec;
pub mod witness;
pub mod zkp1;
pub mod zkp2;

pub use http_transport::HyperTransport;
pub use pir_client::{
    ImtProofData, PirClient, PirClientBlocking, Transport, TransportFuture, TransportResponse,
};

pub use governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS};
pub use note_bundling::{
    minimum_voting_eligibility_for_notes, validate_minimum_voting_eligibility_for_notes,
    voting_power, voting_power_with_policy, BundlePolicy, MinimumVotingEligibility,
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
    GovernancePczt, Network, NoopProgressReporter, NoteInfo, NoteRef, ProgressReporter,
    SelectedNotes, ShareDelegationRecord, SharePayload, VoteCommitStageBridge,
    VoteCommitStageReporter, VoteCommitmentBundle, VotingError, VotingHotkey, VotingRoundParams,
    WireEncryptedShare, WitnessData, MAX_PROPOSAL_ID, MAX_VOTE_OPTIONS, MIN_PROPOSAL_ID,
    MIN_VOTE_OPTIONS,
};

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
