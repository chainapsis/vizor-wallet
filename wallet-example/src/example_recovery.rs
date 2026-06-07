use anyhow::{Context, Result};
use zcash_voting::prelude::{
    resume_plan, round_snapshot, CommittedVote, NextStep, RoundPlan, RoundRecoverySnapshot,
    VotingDb,
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
/// Wallet code can persist this result and drive retries by iterating
/// `context.plan.next_steps`. For `submit_vote` / `submit_shares`, recover the
/// committed vote payload once and submit network requests from that payload.
pub fn load_round_recovery_context(
    voting_db: &VotingDb,
    round_id: &str,
    proposal_ids: &[u32],
) -> Result<RoundRecoveryContext> {
    let (snapshot, plan) = snapshot_with_resume_plan(voting_db, round_id, proposal_ids)?;
    Ok(RoundRecoveryContext { snapshot, plan })
}

/// Reconstructs the committed vote payload for a resume step.
///
/// Use this for `NextStep::SubmitVote` and `NextStep::SubmitShares` to avoid
/// rebuilding proofs during recovery.
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

/// Reconstructs committed-vote payloads for all planner steps that require them.
///
/// The returned list is ordered exactly as `plan.next_steps`, so callers can
/// execute vote-chain and helper-server retries in the planner's order.
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
