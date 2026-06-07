//! Stable imports for wallet SDK integrations.
//!
//! Wallets should prefer this module over importing from internal modules. The
//! prelude intentionally contains the setup, precompute, and delegation types
//! needed by mobile SDK boundaries without exposing proof-circuit internals.

pub use crate::confirmation::{
    confirm_delegation_submission, confirm_vote_submission, DelegationConfirmation, TxEvent,
    TxEventAttribute, VoteConfirmation,
};
pub use crate::delegate::gather_delegation_lwd_inputs;
pub use crate::delegate::LightwalletdBranchIdProvider;
pub use crate::delegate::{
    branch_id_for_height, display_memo, load_account_keys, pczt_sighash, record_submission,
    record_van_position, setup as setup_delegation, signing_request as delegation_signing_request,
    spend_auth_signature, submission as delegation_submission, BranchIdProvider,
    DelegationAccountKeys, DelegationKeys, DelegationPhase, DelegationProgress, DelegationProof,
    DelegationSetup, DelegationSigner, DelegationSigningRequest, DelegationSubmission,
    KeystoneSigningRequest, PreparedDelegationReport, PreparedSigner, SignedDelegationBundle,
};
pub use crate::delegate::{
    prepare_delegation_bundle, PrepareDelegationBundleParams, PreparedDelegationBundle,
};
pub use crate::error::VotingError;
pub use crate::governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS};
pub use crate::hotkey::{
    generate_random_voting_hotkey, VOTING_HOTKEY_ACCOUNT_INDEX, VOTING_HOTKEY_ADDRESS_INDEX,
    VOTING_HOTKEY_STORED_SECRET_LEN,
};
pub use crate::note_bundling::{
    minimum_voting_eligibility_for_notes, validate_minimum_voting_eligibility_for_notes,
    voting_power, voting_power_with_policy, BundlePolicy, MinimumVotingEligibility,
    MINIMUM_VOTING_NOTE_COUNT, MINIMUM_VOTING_WEIGHT_ZATOSHI,
};
pub use crate::phases::{SharePhase, VotePhase, WorkflowPhase};
pub use crate::pir::{select_pir_endpoint, PirEndpoint};
pub use crate::precompute::{
    note_witnesses, stored_note_witnesses, verify_witness, PirPrecomputeReport,
};
pub use crate::recovery::{
    clear as clear_recovery, recoverable_commitment_bundle, round_snapshot, DelegationRecovery,
    RecoverableCommitmentBundle, RoundRecoverySnapshot, ShareWorkflow, VoteRecovery,
};
pub use crate::round::{
    bundle_notes_for_index, bundle_notes_for_index_with_policy, delegation_round_name,
    note_bundles, note_bundles_with_policy, quantized_bundle_set_weight, quantized_bundle_weight,
    raw_bundle_weight, validate_bundle_index, BundleLayout, RoundInfo, RoundParams, VotingDb,
};
pub use crate::selection::select_notes_with_lwd;
pub use crate::selection::{
    gather_delegation_wallet_inputs, select_notes_with_wallet_db, select_snapshot_note_infos,
    select_snapshot_notes, DelegationWalletInputs, GatherDelegationWalletParams,
};
pub use crate::session::{
    resume_plan, CompletedVoteChoice, CompletedVoteDisplay, Decision, DelegationRecoveryWork,
    DelegationRecoveryWorkKind, DelegationStatus, NextStep, RoundPlan, RoundPlanAction,
    VoteRecoveryWork, VoteRecoveryWorkKind,
};
pub use crate::share::{
    add_sent_servers, compute_nullifier, confirm as confirm_share, list as share_records,
    record as record_share, recover_payload, recover_wire_json, unconfirmed as unconfirmed_shares,
    SharePlan, ShareRecord, ShareTimingPolicy, ShareTrackingSummary,
};
pub use crate::types::{
    validate_proposal_id, validate_vote_decision, validate_vote_options, DelegationProgressBridge,
    DelegationProgressReporter, Network, NoopProgressReporter, NoteInfo, NoteRef, ProgressReporter,
    SelectedNotes, SharePayload, VoteCommitStageBridge, VoteCommitStageReporter, VotingHotkey,
    WitnessData, MAX_PROPOSAL_ID, MAX_VOTE_OPTIONS, MIN_PROPOSAL_ID, MIN_VOTE_OPTIONS,
};
pub use crate::vote::{
    commit as commit_vote, commit_batch, parse_recovery,
    record_submission as record_vote_submission, record_vc_position,
    recover_commit as recover_vote_commit, recover_signed_commitments, recovery_bundle,
    serialize_recovery, submission as vote_submission, validate_draft_vote, validate_draft_votes,
    CommittedVote, DraftVote, SignedVoteCommitment, SignedVoteCommitments, VanWitness, VoteCommit,
    VoteCommitStage, VoteRecoveryBundle, VoteSigner, VoteSubmission,
};
pub use crate::warm_proving_caches;
pub use crate::wire::{DelegationSubmissionWire, VoteCommitmentWire, VoteShareWire};

pub use crate::precompute::delegation_pir;

pub use crate::precompute::{
    reset_vote_tree, reset_voting_session_state, sync_vote_tree, van_witness,
};
