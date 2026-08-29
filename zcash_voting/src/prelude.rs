//! Stable imports for wallet SDK integrations.
//!
//! Wallets should prefer this module over importing from internal modules. The
//! prelude intentionally contains the setup, precompute, and delegation types
//! needed by mobile SDK boundaries without exposing proof-circuit internals.

pub use crate::confirmation::{
    confirm_delegation_submission, confirm_vote_batch_submission, confirm_vote_submission,
    DelegationConfirmation, TxEvent, TxEventAttribute, VoteBatchConfirmation, VoteConfirmation,
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
    prepare_delegation_bundle, prepare_delegation_bundle_for_target,
    PrepareDelegationBundleForTargetParams, PrepareDelegationBundleParams,
    PreparedDelegationBundle,
};
pub use crate::delegation_capability::{
    export_delegation_capability, import_delegation_capability, DelegationCapabilityBundleV1,
    DelegationCapabilityDigest, DelegationCapabilityV1, ExportedDelegationCapability,
    ImportDelegationCapabilityParams, MAX_DELEGATION_CAPABILITY_BUNDLES,
    MAX_DELEGATION_CAPABILITY_JSON_BYTES,
};
pub use crate::error::VotingError;
pub use crate::governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS};
pub use crate::helper::health::{HelperHealth, HELPER_COOLDOWN_SECONDS, HELPER_FAILURE_THRESHOLD};
pub use crate::hotkey::{
    generate_random_voting_hotkey, VOTING_HOTKEY_ACCOUNT_INDEX, VOTING_HOTKEY_ADDRESS_INDEX,
    VOTING_HOTKEY_STORED_SECRET_LEN,
};
pub use crate::note_bundling::{
    minimum_voting_eligibility_and_plan_for_notes, minimum_voting_eligibility_for_notes,
    validate_minimum_voting_eligibility_for_notes, voting_power, voting_power_for_round,
    voting_power_with_policy, BundlePolicy, ChunkResult, MinimumVotingEligibility, PrivacyTrim,
    MINIMUM_VOTING_NOTE_COUNT, MINIMUM_VOTING_WEIGHT_ZATOSHI,
};
pub use crate::phases::{SharePhase, VotePhase, WorkflowPhase};
pub use crate::pir::{
    connect_pir, connect_pir_blocking, negotiated_pir_layout, select_pir_endpoint, PirEndpoint,
};
pub use crate::precompute::{
    note_witnesses, precompute_pir_proofs, precompute_snapshot_bundles, stored_note_witnesses,
    validate_cached_pir_proofs, verify_witness, PirPrecomputeReport,
    SnapshotBundlePrecomputeReport,
};
pub use crate::recovery::{
    clear as clear_recovery, recoverable_commitment_bundle, round_snapshot, DelegationRecovery,
    RecoverableCommitmentBundle, RoundRecoverySnapshot, ShareWorkflow, VoteRecovery,
};
pub use crate::round::{
    bundle_notes_for_index_for_round, bundle_notes_for_index_with_policy, delegation_round_name,
    note_bundles, note_bundles_for_round, note_bundles_with_policy, quantized_bundle_set_weight,
    quantized_bundle_weight, raw_bundle_weight, validate_bundle_index, BundleLayout, RoundInfo,
    RoundParams, VotingDb,
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
    SharePlan, ShareRecord, ShareServerSelectionPolicy, ShareTimingPolicy, ShareTrackingSummary,
};
pub use crate::types::{
    validate_proposal_id, validate_vote_decision, validate_vote_options, DelegationProgressBridge,
    DelegationProgressReporter, Network, NoopProgressReporter, NoteInfo, NoteRef,
    PirCachePrecomputeResult, PirCacheValidationReport, PirProofCacheEntry, PirProofCacheStatus,
    ProgressReporter, RoundBoundVotingHotkeyTarget, SelectedNotes, SharePayload,
    VoteCommitStageBridge, VoteCommitStageReporter, VotingHotkey, VotingHotkeyTarget, WitnessData,
    MAX_PROPOSAL_ID, MAX_VOTE_OPTIONS, MIN_PROPOSAL_ID, MIN_VOTE_OPTIONS,
};
pub use crate::vote::{
    commit as commit_vote, commit_atomic_vote_batch, commit_batch, parse_recovery,
    persist_prepared_atomic_vote_batch, persist_prepared_commit, persist_prepared_commit_batch,
    prepare_atomic_vote_batch, prepare_commit, prepare_commit_batch,
    record_batch_submission as record_vote_batch_submission,
    record_submission as record_vote_submission, record_vc_position, recover_atomic_vote_batch,
    recover_commit as recover_vote_commit, recover_signed_commitments, recovery_bundle,
    serialize_recovery, submission as vote_submission, validate_draft_vote, validate_draft_votes,
    AtomicVoteBatch, CommittedVote, DraftVote, PreparedAtomicVoteBatch, PreparedVoteCommit,
    PreparedVoteCommitments, SignedVoteBatch, SignedVoteCommitment, SignedVoteCommitments,
    VanWitness, VoteBatchRecovery, VoteCommit, VoteCommitBatch, VoteCommitStage,
    VoteRecoveryBundle, VoteSigner, VoteSubmission, DEFAULT_BATCH_PROOF_CONCURRENCY,
    MAX_VOTE_BATCH_ACTIONS,
};
pub use crate::wire::{
    DelegationSubmissionWire, SignedVoteBatchView, VoteCommitmentBatchWire, VoteCommitmentWire,
    VoteShareWire, VotingHotkeyTargetV1,
};
pub use crate::{warm_proving_caches, warm_zkp2_proving_cache};

pub use crate::precompute::delegation_pir;

pub use crate::precompute::{
    reset_vote_tree, reset_voting_session_state, sync_vote_tree, van_witness,
};
