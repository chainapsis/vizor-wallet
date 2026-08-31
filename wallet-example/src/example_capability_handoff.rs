//! Role-separated delegation capability handoff.
//!
//! This module connects the lower-level wallet examples into the sequence an
//! integrator implements across the voter and funds controller applications:
//!
//! 1. The voter calls [`voter_create_target`] and sends the resulting JSON.
//! 2. The funds controller calls [`controller_validate_target`], then passes
//!    that target through
//!    [`crate::example_delegation::prepare_delegation_bundle_for_public_target`],
//!    [`crate::example_delegation::precompute_delegation_bundle`], and its
//!    selected software or external-signer helper in
//!    [`crate::example_delegation`]. Its chain adapter turns each resulting
//!    submission into the exact signed transaction bytes it will broadcast.
//! 3. The funds controller calls [`controller_export_capability`] with those
//!    bytes. It durably stores `canonical_json()` and `digest()`, then delivers
//!    the exact JSON. Broadcasting the signed delegation transactions may
//!    happen concurrently.
//! 4. The voter calls [`voter_import_capability`] and returns the resulting
//!    digest as a delivery acknowledgement. The funds controller compares it
//!    with the stored digest and redelivers the same bytes after a mismatch or
//!    missing acknowledgement.
//! 5. After broadcast, the voter calls [`voter_confirm_delegation`] for every
//!    bundle with its confirmed transaction event. Imported capability rounds
//!    cannot create votes until every bundle has a public VAN position.
//! 6. The voter calls [`voter_build_signed_vote`], submits the vote-chain
//!    payload, asks the SDK to prepare the complete helper-share plan, records
//!    its confirmed tree position, then submits the prepared plan through
//!    [`crate::example_vote`].
//!
//! Authenticated transport, durable controller outbox storage, chain
//! submission, event monitoring, helper transport routing, cancellation, and
//! tracking timers remain owned by the integrating applications. Helper plan
//! persistence is SDK-owned.

use anyhow::{Context, Result};
use zcash_voting::prelude::{
    confirm_delegation_submission, CommittedVote, DelegationCapabilityDigest,
    DelegationConfirmation, DraftVote, ExportedDelegationCapability, Network,
    RoundBoundVotingHotkeyTarget, TxEvent, VotingDb, VotingHotkey,
};
use zcash_voting::VotingRoundParams;

use crate::example_delegation::{
    encode_public_voting_target, export_delegation_capability_package,
    import_delegation_capability_package, validate_public_voting_target,
};
use crate::example_vote::{
    commit_vote_bundle, derive_vote_van_witness, WalletVanWitnessRequest, WalletVoteCommitRequest,
};

/// Voter step: creates the public hotkey target sent to the funds controller.
pub fn voter_create_target(
    voting_hotkey: &VotingHotkey,
    vote_chain_id: &str,
    round_params: &VotingRoundParams,
) -> Result<Vec<u8>> {
    encode_public_voting_target(voting_hotkey, vote_chain_id, round_params)
        .context("create voter public target")
}

/// Funds controller step: validates received target bytes against local context.
pub fn controller_validate_target(
    target_json: &[u8],
    expected_chain_id: &str,
    expected_network: Network,
    expected_round_params: &VotingRoundParams,
) -> Result<RoundBoundVotingHotkeyTarget> {
    validate_public_voting_target(
        target_json,
        expected_chain_id,
        expected_network,
        expected_round_params,
    )
    .context("validate voter public target")
}

/// Funds controller step: binds canonical package bytes to their acknowledgement digest.
pub fn controller_export_capability(
    voting_db: &VotingDb,
    voting_target: &RoundBoundVotingHotkeyTarget,
    signed_delegation_txs: &[Vec<u8>],
) -> Result<ExportedDelegationCapability> {
    export_delegation_capability_package(voting_db, voting_target, signed_delegation_txs)
        .context("export controller delegation capability")
}

/// Voter step: validates and durably imports the exact delivered package bytes.
pub fn voter_import_capability(
    voting_db: &VotingDb,
    capability_json: &[u8],
    voting_hotkey: &VotingHotkey,
    expected_chain_id: &str,
    expected_network: Network,
    expected_round_params: &VotingRoundParams,
    session_json: Option<&str>,
) -> Result<DelegationCapabilityDigest> {
    import_delegation_capability_package(
        voting_db,
        capability_json,
        voting_hotkey,
        expected_chain_id,
        expected_network,
        expected_round_params,
        session_json,
    )
    .context("import voter delegation capability")
}

/// Voter step: records the confirmed delegation transaction and VAN position.
pub fn voter_confirm_delegation(
    voting_db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    delegation_tx_hash: &str,
    events: &[TxEvent],
) -> Result<DelegationConfirmation> {
    confirm_delegation_submission(
        voting_db,
        round_id,
        bundle_index,
        delegation_tx_hash,
        events,
    )
    .context("record voter delegation confirmation")
}

/// Voter step: syncs the confirmed VAN, builds ZKP2, and signs one vote.
///
/// Submit the chain payload from
/// [`crate::example_vote::committed_vote_submission`], then persist its hash
/// and confirmed tree position with
/// [`crate::example_vote::record_committed_vote_execution`]. Ask the SDK to
/// create and persist one complete helper plan with
/// [`crate::example_vote::prepare_committed_vote_shares`] before calling
/// [`crate::example_vote::submit_committed_vote_shares`]. After restart,
/// recover the vote and call the same preparation API to load the exact plan;
/// pass the complete current helper fleet to submission.
pub fn voter_build_signed_vote(
    voting_db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    vote_node_url: &str,
    draft: &DraftVote,
    voting_hotkey: &VotingHotkey,
) -> Result<CommittedVote> {
    let van_witness = derive_vote_van_witness(
        voting_db,
        WalletVanWitnessRequest {
            round_id,
            bundle_index,
            vote_node_url,
        },
    )
    .context("derive confirmed VAN witness")?;

    commit_vote_bundle(
        voting_db,
        WalletVoteCommitRequest {
            round_id,
            bundle_index,
            draft,
            van_witness: &van_witness,
            voting_hotkey,
        },
    )
    .context("build signed voter commitment")
}
