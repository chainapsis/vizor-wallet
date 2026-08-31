use anyhow::{Context, Result};
use zcash_voting::prelude::{
    recover_atomic_vote_batch, resume_plan, round_snapshot, CommittedVote, NextStep, RoundPlan,
    RoundRecoverySnapshot, SignedVoteBatch, VotingDb,
};

/// One round-level recovery payload fetched in a single caller entrypoint.
pub struct RoundRecoveryContext {
    pub snapshot: RoundRecoverySnapshot,
    pub plan: RoundPlan,
}

/// Recovery material needed to execute one planner step without rebuilding proofs.
pub struct RecoveredVoteStep {
    pub step: NextStep,
    pub committed_vote: CommittedVote,
}

/// One recovered atomic batch keyed by its planner step.
pub struct RecoveredVoteBatchStep {
    pub step: NextStep,
    pub signed_batch: SignedVoteBatch,
}

/// Loads the typed recovery snapshot for one round.
pub fn load_round_recovery_snapshot(
    voting_db: &VotingDb,
    round_id: &str,
) -> Result<RoundRecoverySnapshot> {
    round_snapshot(voting_db, round_id).context("load round recovery snapshot")
}

/// Returns both the recovery snapshot and resumable step plan for one round.
pub fn snapshot_with_resume_plan(
    voting_db: &VotingDb,
    round_id: &str,
    proposal_ids: &[u32],
) -> Result<(RoundRecoverySnapshot, RoundPlan)> {
    let snapshot = load_round_recovery_snapshot(voting_db, round_id)?;
    let plan = resume_plan(voting_db, round_id, proposal_ids).context("build resume plan")?;
    Ok((snapshot, plan))
}

/// Loads round recovery data and planner steps in one wallet-facing call.
///
/// Wallet code drives retries by iterating `context.plan.next_steps`. Recover
/// singleton vote handles and helper-share
/// identities with `recover_committed_vote_for_step`, and atomic batches with
/// `recover_vote_batch_for_step`. Helper delivery must reuse the wallet's
/// SDK-persisted complete plan through
/// `example_vote::submit_committed_vote_shares`.
pub fn load_round_recovery_context(
    voting_db: &VotingDb,
    round_id: &str,
    proposal_ids: &[u32],
) -> Result<RoundRecoveryContext> {
    let (snapshot, plan) = snapshot_with_resume_plan(voting_db, round_id, proposal_ids)?;
    Ok(RoundRecoveryContext { snapshot, plan })
}

/// Reconstructs the committed vote handle for a resume step.
///
/// Use this for singleton `NextStep::SubmitVote` and per-vote
/// `NextStep::SubmitShares` work to avoid rebuilding proofs during recovery.
pub fn recover_committed_vote_for_step(
    voting_db: &VotingDb,
    round_id: &str,
    step: &NextStep,
) -> Result<Option<CommittedVote>> {
    match *step {
        NextStep::SubmitVote {
            bundle_index,
            proposal_id,
        }
        | NextStep::SubmitShares {
            bundle_index,
            proposal_id,
            ..
        } => CommittedVote::recover(voting_db, round_id, bundle_index, proposal_id)
            .map(Some)
            .context("recover committed vote for resume step"),
        _ => Ok(None),
    }
}

/// Reconstructs one complete atomic batch for a batch resume step.
///
/// Submit `batch_json` once for `NextStep::SubmitVoteBatch`. For either batch
/// step, retain `batch_digest` for `record_vote_batch_submission` and
/// `confirm_vote_batch_submission`.
pub fn recover_vote_batch_for_step(
    voting_db: &VotingDb,
    round_id: &str,
    step: &NextStep,
) -> Result<Option<SignedVoteBatch>> {
    match *step {
        NextStep::SubmitVoteBatch {
            bundle_index,
            proposal_id,
        }
        | NextStep::PollVoteBatch {
            bundle_index,
            proposal_id,
        } => recover_atomic_vote_batch(voting_db, round_id, bundle_index, proposal_id)
            .map(Some)
            .context("recover atomic vote batch for resume step"),
        _ => Ok(None),
    }
}

/// Reconstructs committed-vote handles for all planner steps that require them.
///
/// The returned list is ordered exactly as `plan.next_steps`, so callers can
/// execute vote-chain work in planner order and route `SubmitShares` through
/// the persisted full-batch plan and durable helper-submission API.
pub fn recover_committed_votes_for_plan(
    voting_db: &VotingDb,
    round_id: &str,
    plan: &RoundPlan,
) -> Result<Vec<RecoveredVoteStep>> {
    let mut recovered = Vec::new();
    for step in &plan.next_steps {
        if let Some(committed_vote) = recover_committed_vote_for_step(voting_db, round_id, step)? {
            recovered.push(RecoveredVoteStep {
                step: step.clone(),
                committed_vote,
            });
        }
    }
    Ok(recovered)
}

/// Reconstructs complete atomic batches for all batch planner steps.
pub fn recover_vote_batches_for_plan(
    voting_db: &VotingDb,
    round_id: &str,
    plan: &RoundPlan,
) -> Result<Vec<RecoveredVoteBatchStep>> {
    let mut recovered = Vec::new();
    for step in &plan.next_steps {
        if let Some(signed_batch) = recover_vote_batch_for_step(voting_db, round_id, step)? {
            recovered.push(RecoveredVoteBatchStep {
                step: step.clone(),
                signed_batch,
            });
        }
    }
    Ok(recovered)
}
