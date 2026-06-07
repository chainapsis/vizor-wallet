//! Durable ballot intent + resumable voting-session planner.
//!
//! `resume_plan` is pure and I/O-free over the wallet's voting DB: it reports
//! the ordered remaining work for a round, built on the per-artifact phase
//! APIs in `crate::phases`. The wallet executes each step with its own
//! network/proof/sign plumbing.

use rusqlite::named_params;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

use crate::phases::{DelegationPhase, SharePhase, VotePhase};
use crate::storage::{queries, VotingDb};
use crate::types::{
    validate_proposal_id, validate_vote_decision, validate_vote_options, VotingError,
};
use crate::vote::{validate_draft_vote, DraftVote};

/// The voter's terminal decision for one proposal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision {
    Choice(u32),
    Skipped,
}

impl VotingDb {
    /// Record (insert or replace) the voter's decision for one proposal.
    ///
    /// `num_options` must be the proposal's declared option count. Choice
    /// decisions are validated against it before any durable intent is written.
    /// Written on each selection, before any per-proposal vote artifact exists.
    pub fn set_ballot_intent(
        &self,
        round_id: &str,
        proposal_id: u32,
        decision: Decision,
        num_options: u32,
    ) -> Result<(), VotingError> {
        validate_proposal_id(proposal_id)?;
        validate_ballot_intent_decision(decision, num_options)?;

        self.write_ballot_intent(round_id, proposal_id, decision)
    }

    /// Record a choice intent from a fully validated draft vote.
    pub fn set_ballot_intent_for_draft_vote(
        &self,
        round_id: &str,
        draft: &DraftVote,
    ) -> Result<(), VotingError> {
        validate_draft_vote(draft)?;
        self.write_ballot_intent(round_id, draft.proposal_id, Decision::Choice(draft.choice))
    }

    fn write_ballot_intent(
        &self,
        round_id: &str,
        proposal_id: u32,
        decision: Decision,
    ) -> Result<(), VotingError> {
        let (skipped, choice): (i64, Option<i64>) = match decision {
            Decision::Choice(c) => (0, Some(c as i64)),
            Decision::Skipped => (1, None),
        };
        let now = now_secs();
        let mut conn = self.conn();
        let wallet_id = self.wallet_id();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("set_ballot_intent transaction failed: {e}"),
        })?;
        let skipped_bool = skipped != 0;
        let choice_u32 = choice.map(|c| c as u32);
        queries::ensure_no_submitted_vote_conflict_for_intent(
            &tx,
            round_id,
            &wallet_id,
            proposal_id,
            skipped_bool,
            choice_u32,
        )?;
        tx.execute(
            "INSERT INTO ballot_intent
                (round_id, wallet_id, proposal_id, skipped, choice, created_at, updated_at)
             VALUES (:round_id, :wallet_id, :proposal_id, :skipped, :choice, :now, :now)
             ON CONFLICT(round_id, wallet_id, proposal_id)
             DO UPDATE SET skipped = :skipped, choice = :choice, updated_at = :now",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
                ":skipped": skipped,
                ":choice": choice,
                ":now": now,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("set_ballot_intent failed: {e}"),
        })?;
        queries::clear_stale_share_delegations_for_intent(
            &tx,
            round_id,
            &wallet_id,
            proposal_id,
            skipped_bool,
            choice_u32,
        )?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("set_ballot_intent commit failed: {e}"),
        })?;
        Ok(())
    }

    /// Load the voter's decisions for a round, sorted by proposal id.
    pub fn ballot_intents(&self, round_id: &str) -> Result<Vec<(u32, Decision)>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let mut stmt = conn
            .prepare(
                "SELECT proposal_id, skipped, choice FROM ballot_intent
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                 ORDER BY proposal_id",
            )
            .map_err(|e| VotingError::Internal {
                message: format!("prepare ballot_intents: {e}"),
            })?;
        let rows = stmt
            .query_map(
                named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
                |row| {
                    let pid = row.get::<_, i64>(0)? as u32;
                    let skipped: i64 = row.get(1)?;
                    let choice: Option<i64> = row.get(2)?;
                    let decision = if skipped != 0 {
                        Decision::Skipped
                    } else {
                        Decision::Choice(choice.unwrap_or(0) as u32)
                    };
                    Ok((pid, decision))
                },
            )
            .map_err(|e| VotingError::Internal {
                message: format!("query ballot_intents: {e}"),
            })?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| VotingError::Internal {
                message: format!("collect ballot_intents: {e}"),
            })
    }
}

fn validate_ballot_intent_decision(
    decision: Decision,
    num_options: u32,
) -> Result<(), VotingError> {
    match decision {
        Decision::Choice(choice) => validate_vote_decision(choice, num_options),
        Decision::Skipped => validate_vote_options(num_options),
    }
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// One unit of remaining work for a round. Ordered deterministically within a
/// `RoundPlan`, so a restart yields the same sequence.
#[non_exhaustive]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum NextStep {
    Delegate {
        bundle_index: u32,
    },
    PollDelegation {
        bundle_index: u32,
    },
    /// Cast a vote using the recorded ballot intent choice.
    ///
    /// A changed choice is recoverable only until a cast-vote transaction has
    /// been submitted. Once submitted, the proposal authority for that bundle
    /// has moved on-chain and `resume_plan` reports the conflict as invalid
    /// state instead of returning a non-actionable recast step.
    CastVote {
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
    },
    /// Submit a previously committed vote using persisted recovery material.
    ///
    /// Wallets should reconstruct the cast-vote fields with `vote::submission`
    /// instead of rebuilding them from a caller-supplied draft. Submit those
    /// fields to the vote chain, persist the cast-vote tx hash with
    /// `vote::record_submission` while polling, then call
    /// `confirmation::confirm_vote_submission` after the transaction confirms.
    /// Call `vote::recover_commit` again after confirmation before submitting
    /// helper-share payloads, so they carry the confirmed vote commitment tree
    /// position.
    SubmitVote {
        bundle_index: u32,
        proposal_id: u32,
    },
    PollVote {
        bundle_index: u32,
        proposal_id: u32,
    },
    /// Submit helper shares for an already-confirmed vote.
    ///
    /// This covers the crash boundary after the cast-vote transaction confirms
    /// and before every helper-share row has been durably recorded. The
    /// `share_index` identifies the missing helper share to submit. Wallets
    /// should reconstruct the vote with `vote::recover_commit`, submit that
    /// recovered share payload to helper servers, then record each accepted
    /// share with `share::record`.
    SubmitShares {
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
    },
    ConfirmShare {
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
    },
}

impl NextStep {
    /// Returns the stable string discriminator used by FFI layers.
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Delegate { .. } => "delegate",
            Self::PollDelegation { .. } => "poll_delegation",
            Self::CastVote { .. } => "cast_vote",
            Self::SubmitVote { .. } => "submit_vote",
            Self::PollVote { .. } => "poll_vote",
            Self::SubmitShares { .. } => "submit_shares",
            Self::ConfirmShare { .. } => "confirm_share",
        }
    }
}

/// High-level work area a wallet should show or resume for a round.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum RoundPlanAction {
    /// No crate-owned recovery or submitted vote artifact is present.
    Idle,
    /// Delegation must be submitted or polled before fresh vote work can finish.
    Delegate,
    /// Cast-vote, vote-submission, vote-polling, or helper-share submission work remains.
    Vote,
    /// Only blocking helper-share confirmation work remains.
    SubmitShares,
    /// A vote artifact exists and no blocking recovery work remains.
    Done,
}

impl RoundPlanAction {
    /// Returns the stable string discriminator used by FFI layers.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Delegate => "delegate",
            Self::Vote => "vote",
            Self::SubmitShares => "submit_shares",
            Self::Done => "done",
        }
    }
}

/// Kind of delegation recovery work grouped from `NextStep`s.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum DelegationRecoveryWorkKind {
    /// Run the delegation flow for this bundle.
    Delegate,
    /// Poll an already-submitted delegation transaction.
    PollDelegation,
}

impl DelegationRecoveryWorkKind {
    /// Returns the stable string discriminator used by FFI layers.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Delegate => "delegate",
            Self::PollDelegation => "poll_delegation",
        }
    }
}

/// Grouped delegation recovery work for one bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationRecoveryWork {
    pub kind: DelegationRecoveryWorkKind,
    pub bundle_index: u32,
    pub phase: DelegationPhase,
    /// Present only when `kind == DelegationRecoveryWorkKind::PollDelegation`.
    pub tx_hash: Option<String>,
}

/// Durable delegation state for one eligible bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationStatus {
    pub bundle_index: u32,
    pub phase: DelegationPhase,
    pub tx_hash: Option<String>,
}

/// Kind of vote recovery work grouped from `NextStep`s.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum VoteRecoveryWorkKind {
    /// Submit a committed vote using persisted recovery material.
    SubmitVote,
    /// Poll an already-submitted vote transaction.
    PollVote,
    /// Submit one or more missing helper shares for a confirmed vote.
    SubmitShares,
}

impl VoteRecoveryWorkKind {
    /// Returns the stable string discriminator used by FFI layers.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SubmitVote => "submit_vote",
            Self::PollVote => "poll_vote",
            Self::SubmitShares => "submit_shares",
        }
    }
}

/// Grouped vote recovery work for one `(bundle_index, proposal_id)` key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteRecoveryWork {
    pub kind: VoteRecoveryWorkKind,
    pub bundle_index: u32,
    pub proposal_id: u32,
    /// Present only when `kind == VoteRecoveryWorkKind::PollVote`.
    pub tx_hash: Option<String>,
    /// Present only when `kind == VoteRecoveryWorkKind::SubmitShares`.
    pub vc_tree_position: Option<u64>,
    /// Empty unless `kind == VoteRecoveryWorkKind::SubmitShares`.
    pub share_indexes: Vec<u32>,
}

/// Display choice for one proposal in a completed round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompletedVoteChoice {
    pub proposal_id: u32,
    /// `None` when the proposal was skipped or bundles disagree.
    pub choice: Option<u32>,
}

/// Read-only display summary for a locally completed vote.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompletedVoteDisplay {
    pub choices: Vec<CompletedVoteChoice>,
    /// Latest helper-share delegation timestamp, in Unix seconds.
    pub voted_at: Option<u64>,
}

/// Derived resume state for one round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundPlan {
    pub round_id: String,
    /// True iff any recovery step remains (`!next_steps.is_empty()`).
    pub pending_recovery: bool,
    /// Ordered remaining recovery work.
    pub next_steps: Vec<NextStep>,
    /// Proposals with no terminal decision yet.
    ///
    /// `Decision::Skipped` is terminal for this plan, so skipped proposals are
    /// not returned here.
    pub open_proposals: Vec<u32>,
    /// Informational: every proposal is either a confirmed Choice or Skipped.
    pub all_decided: bool,
    /// Durable delegation status for every eligible bundle in the round.
    pub delegation_statuses: Vec<DelegationStatus>,
    /// True when the plan contains work that should keep the foreground vote flow open.
    ///
    /// Unconfirmed helper shares that were already accepted by at least one helper
    /// remain in `next_steps` as `ConfirmShare`, but they are non-blocking because
    /// background polling can complete them later.
    pub blocking_recovery: bool,
    /// True when an unconfirmed helper-share row has no accepted helper URL yet.
    pub blocking_share_work: bool,
    /// True once round artifacts require the same voting hotkey to be reused.
    pub hotkey_bound: bool,
    /// True once the local DB contains a vote or helper-share artifact for the round.
    pub completed_vote_artifact: bool,
    /// True when a vote artifact exists and no blocking recovery work remains.
    pub completed_for_display: bool,
    /// Display data for a completed vote, present only when `completed_for_display`.
    pub completed_vote_display: Option<CompletedVoteDisplay>,
    /// True when a wallet should collect or restore draft choices for open proposals.
    pub needs_draft_setup: bool,
    /// Primary work area derived from the crate-owned recovery state.
    pub primary_action: RoundPlanAction,
    /// Delegation recovery work grouped from `next_steps` for wallet orchestration.
    pub recovered_delegation_work: Vec<DelegationRecoveryWork>,
    /// Vote recovery work grouped from `next_steps` for wallet orchestration.
    pub recovered_vote_work: Vec<VoteRecoveryWork>,
}

fn step_rank(step: &NextStep) -> (u32, u32, u32, u32) {
    // Delegation is a prerequisite for fresh vote work, so keep it before
    // vote/share recovery. Vote work is proposal-primary so an interrupted
    // question finishes across all bundles before later questions resume.
    match step {
        NextStep::Delegate { bundle_index } => (0, 0, *bundle_index, 0),
        NextStep::PollDelegation { bundle_index } => (0, 0, *bundle_index, 0),
        NextStep::CastVote {
            bundle_index,
            proposal_id,
            choice: _,
        } => (1, *proposal_id, *bundle_index, 0),
        NextStep::SubmitVote {
            bundle_index,
            proposal_id,
        } => (1, *proposal_id, *bundle_index, 0),
        NextStep::PollVote {
            bundle_index,
            proposal_id,
        } => (1, *proposal_id, *bundle_index, 0),
        NextStep::SubmitShares {
            bundle_index,
            proposal_id,
            share_index,
        } => (1, *proposal_id, *bundle_index, *share_index),
        NextStep::ConfirmShare {
            bundle_index,
            proposal_id,
            share_index,
        } => (2, *proposal_id, *bundle_index, *share_index),
    }
}

fn missing_recovery_field(message: String) -> VotingError {
    VotingError::Internal { message }
}

fn delegation_statuses(
    db: &VotingDb,
    round_id: &str,
    delegation: &BTreeMap<u32, DelegationPhase>,
) -> Result<Vec<DelegationStatus>, VotingError> {
    delegation
        .iter()
        .map(|(&bundle_index, &phase)| {
            Ok(DelegationStatus {
                bundle_index,
                phase,
                tx_hash: db.get_delegation_tx_hash(round_id, bundle_index)?,
            })
        })
        .collect()
}

fn recovered_delegation_work_from_steps(
    db: &VotingDb,
    round_id: &str,
    delegation: &BTreeMap<u32, DelegationPhase>,
    steps: &[NextStep],
) -> Result<Vec<DelegationRecoveryWork>, VotingError> {
    let mut work = Vec::<DelegationRecoveryWork>::new();
    for step in steps {
        match *step {
            NextStep::Delegate { bundle_index } => {
                let phase = delegation.get(&bundle_index).copied().ok_or_else(|| {
                    missing_recovery_field(format!(
                        "delegate step missing phase for round={round_id}, bundle={bundle_index}"
                    ))
                })?;
                work.push(DelegationRecoveryWork {
                    kind: DelegationRecoveryWorkKind::Delegate,
                    bundle_index,
                    phase,
                    tx_hash: None,
                });
            }
            NextStep::PollDelegation { bundle_index } => {
                let phase = delegation.get(&bundle_index).copied().ok_or_else(|| {
                    missing_recovery_field(format!(
                        "poll delegation step missing phase for round={round_id}, bundle={bundle_index}"
                    ))
                })?;
                let tx_hash = db
                    .get_delegation_tx_hash(round_id, bundle_index)?
                    .ok_or_else(|| {
                        missing_recovery_field(format!(
                            "poll delegation step missing tx_hash for round={round_id}, bundle={bundle_index}"
                        ))
                    })?;
                work.push(DelegationRecoveryWork {
                    kind: DelegationRecoveryWorkKind::PollDelegation,
                    bundle_index,
                    phase,
                    tx_hash: Some(tx_hash),
                });
            }
            _ => {}
        }
    }
    Ok(work)
}

fn recovered_vote_work_from_steps(
    db: &VotingDb,
    round_id: &str,
    blocking_confirm_share_keys: &BTreeSet<(u32, u32, u32)>,
    steps: &[NextStep],
) -> Result<Vec<VoteRecoveryWork>, VotingError> {
    let mut work = Vec::<VoteRecoveryWork>::new();
    let pending_vote_confirmation_keys = steps
        .iter()
        .filter_map(|step| match step {
            NextStep::PollVote {
                bundle_index,
                proposal_id,
            } => Some((*bundle_index, *proposal_id)),
            _ => None,
        })
        .collect::<BTreeSet<_>>();
    for step in steps {
        match *step {
            NextStep::SubmitVote {
                bundle_index,
                proposal_id,
            } => work.push(VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::SubmitVote,
                bundle_index,
                proposal_id,
                tx_hash: None,
                vc_tree_position: None,
                share_indexes: Vec::new(),
            }),
            NextStep::PollVote {
                bundle_index,
                proposal_id,
            } => {
                let tx_hash = db
                    .get_vote_tx_hash(round_id, bundle_index, proposal_id)?
                    .ok_or_else(|| {
                        missing_recovery_field(format!(
                            "poll vote step missing tx_hash for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
                        ))
                    })?;
                work.push(VoteRecoveryWork {
                    kind: VoteRecoveryWorkKind::PollVote,
                    bundle_index,
                    proposal_id,
                    tx_hash: Some(tx_hash),
                    vc_tree_position: None,
                    share_indexes: Vec::new(),
                });
            }
            NextStep::SubmitShares {
                bundle_index,
                proposal_id,
                share_index,
            } => push_submit_share_work(
                db,
                round_id,
                &mut work,
                bundle_index,
                proposal_id,
                share_index,
            )?,
            NextStep::ConfirmShare {
                bundle_index,
                proposal_id,
                share_index,
            } if blocking_confirm_share_keys.contains(&(
                bundle_index,
                proposal_id,
                share_index,
            )) && !pending_vote_confirmation_keys.contains(&(bundle_index, proposal_id)) =>
            {
                push_submit_share_work(
                    db,
                    round_id,
                    &mut work,
                    bundle_index,
                    proposal_id,
                    share_index,
                )?;
            }
            _ => {}
        }
    }
    Ok(work)
}

fn push_submit_share_work(
    db: &VotingDb,
    round_id: &str,
    work: &mut Vec<VoteRecoveryWork>,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), VotingError> {
    if let Some(existing) = work.iter_mut().find(|item| {
        item.kind == VoteRecoveryWorkKind::SubmitShares
            && item.bundle_index == bundle_index
            && item.proposal_id == proposal_id
    }) {
        existing.share_indexes.push(share_index);
        existing.share_indexes.sort_unstable();
        existing.share_indexes.dedup();
        return Ok(());
    }

    let vc_tree_position = db
        .get_commitment_bundle(round_id, bundle_index, proposal_id)?
        .map(|(_, position)| position)
        .ok_or_else(|| {
            missing_recovery_field(format!(
                "submit shares step missing vc_tree_position for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ))
        })?;
    work.push(VoteRecoveryWork {
        kind: VoteRecoveryWorkKind::SubmitShares,
        bundle_index,
        proposal_id,
        tx_hash: None,
        vc_tree_position: Some(vc_tree_position),
        share_indexes: vec![share_index],
    });
    Ok(())
}

fn select_primary_action(
    steps: &[NextStep],
    blocking_recovery: bool,
    blocking_share_work: bool,
    completed_for_display: bool,
) -> RoundPlanAction {
    if completed_for_display {
        return RoundPlanAction::Done;
    }
    if !blocking_recovery {
        return RoundPlanAction::Idle;
    }
    if steps.iter().any(|step| {
        matches!(
            step,
            NextStep::Delegate { .. } | NextStep::PollDelegation { .. }
        )
    }) {
        return RoundPlanAction::Delegate;
    }
    if steps.iter().any(|step| {
        matches!(
            step,
            NextStep::CastVote { .. }
                | NextStep::SubmitVote { .. }
                | NextStep::PollVote { .. }
                | NextStep::SubmitShares { .. }
        )
    }) {
        return RoundPlanAction::Vote;
    }
    if blocking_share_work {
        RoundPlanAction::SubmitShares
    } else {
        RoundPlanAction::Idle
    }
}

fn completed_vote_display(
    proposal_ids: &[u32],
    intents: &BTreeMap<u32, Decision>,
    vote_choices: &BTreeMap<(u32, u32), u32>,
    stale_vote_keys: &BTreeSet<(u32, u32)>,
    voted_at: Option<u64>,
) -> CompletedVoteDisplay {
    let choices = proposal_ids
        .iter()
        .map(|&proposal_id| {
            let proposal_choices = vote_choices
                .iter()
                .filter_map(|(&(bundle_index, vote_proposal_id), &choice)| {
                    (vote_proposal_id == proposal_id
                        && !stale_vote_keys.contains(&(bundle_index, vote_proposal_id)))
                    .then_some(choice)
                })
                .collect::<BTreeSet<_>>();
            let choice = match intents.get(&proposal_id) {
                Some(Decision::Skipped) => None,
                Some(Decision::Choice(_)) if proposal_choices.len() == 1 => {
                    proposal_choices.first().copied()
                }
                _ => None,
            };
            CompletedVoteChoice {
                proposal_id,
                choice,
            }
        })
        .collect();

    CompletedVoteDisplay { choices, voted_at }
}

/// Build the resume plan for `round_id`.
///
/// `proposal_ids` is the round's full set of proposal ids (from the wallet's
/// round config); the crate cannot enumerate "never decided" proposals on its
/// own. The plan is a best-effort snapshot over the durable phase tables.
/// Wallets should execute one returned step, persist that step's result, then
/// call `resume_plan` again; later steps may depend on earlier on-chain
/// confirmations.
pub fn resume_plan(
    db: &VotingDb,
    round_id: &str,
    proposal_ids: &[u32],
) -> Result<RoundPlan, VotingError> {
    for &proposal_id in proposal_ids {
        validate_proposal_id(proposal_id)?;
    }

    let delegation: BTreeMap<u32, DelegationPhase> =
        db.delegation_phases(round_id)?.into_iter().collect();
    let votes: BTreeMap<(u32, u32), VotePhase> = db
        .vote_phases(round_id)?
        .into_iter()
        .map(|(b, p, ph)| ((b, p), ph))
        .collect();
    let vote_choices: BTreeMap<(u32, u32), u32> = db
        .get_votes(round_id)?
        .into_iter()
        .map(|vote| ((vote.bundle_index, vote.proposal_id), vote.choice))
        .collect();
    let share_phase_rows = db.share_phases(round_id)?;
    let share_delegations = db.get_share_delegations(round_id)?;
    let share_indexes_by_vote = share_phase_rows.iter().fold(
        BTreeMap::<(u32, u32), BTreeSet<u32>>::new(),
        |mut acc, (bundle_index, proposal_id, share_index, _)| {
            acc.entry((*bundle_index, *proposal_id))
                .or_default()
                .insert(*share_index);
            acc
        },
    );
    let intents: BTreeMap<u32, Decision> = db.ballot_intents(round_id)?.into_iter().collect();

    let bundles: Vec<u32> = delegation.keys().copied().collect();

    let mut choice_proposals: Vec<u32> = Vec::new();
    let mut open_proposals: Vec<u32> = Vec::new();
    for &pid in proposal_ids {
        match intents.get(&pid) {
            Some(Decision::Choice(_)) => choice_proposals.push(pid),
            Some(Decision::Skipped) => {}
            None => open_proposals.push(pid),
        }
    }
    choice_proposals.sort_unstable();
    open_proposals.sort_unstable();

    if !choice_proposals.is_empty() && bundles.is_empty() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "round {round_id} has ballot choice intent but no eligible bundle rows"
            ),
        });
    }

    let mut steps: Vec<NextStep> = Vec::new();
    let mut bundles_needing_delegation: BTreeSet<u32> = BTreeSet::new();
    let stale_vote_keys: BTreeSet<(u32, u32)> = vote_choices
        .iter()
        .filter_map(|(&(bundle_index, proposal_id), &stored_choice)| {
            match intents.get(&proposal_id) {
                Some(Decision::Choice(intent_choice)) if *intent_choice != stored_choice => {
                    Some((bundle_index, proposal_id))
                }
                Some(Decision::Skipped) => Some((bundle_index, proposal_id)),
                _ => None,
            }
        })
        .collect();

    for &(bundle_index, proposal_id) in &stale_vote_keys {
        if matches!(
            votes.get(&(bundle_index, proposal_id)),
            Some(VotePhase::Submitted | VotePhase::Confirmed)
        ) {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "round {round_id} bundle {bundle_index} proposal {proposal_id} has a submitted vote that conflicts with ballot intent"
                ),
            });
        }
    }

    // Vote steps for answered proposals.
    for &pid in &choice_proposals {
        let intent_choice = match intents.get(&pid) {
            Some(Decision::Choice(choice)) => *choice,
            _ => continue,
        };
        for &b in &bundles {
            let vote_key = (b, pid);
            if stale_vote_keys.contains(&vote_key)
                || vote_choices.get(&vote_key) != Some(&intent_choice)
            {
                steps.push(NextStep::CastVote {
                    bundle_index: b,
                    proposal_id: pid,
                    choice: intent_choice,
                });
                bundles_needing_delegation.insert(b);
                continue;
            }
            match votes.get(&vote_key) {
                Some(VotePhase::Confirmed) => {
                    for share_index in missing_share_indexes_for_confirmed_vote(
                        db,
                        round_id,
                        b,
                        pid,
                        share_indexes_by_vote
                            .get(&vote_key)
                            .cloned()
                            .unwrap_or_default(),
                    )? {
                        steps.push(NextStep::SubmitShares {
                            bundle_index: b,
                            proposal_id: pid,
                            share_index,
                        });
                    }
                }
                Some(VotePhase::Committed) => {
                    steps.push(NextStep::SubmitVote {
                        bundle_index: b,
                        proposal_id: pid,
                    });
                }
                Some(VotePhase::Submitted) => {
                    if !vote_has_recovery_bundle(db, round_id, b, pid)? {
                        return Err(VotingError::InvalidInput {
                            message: format!(
                                "round {round_id} bundle {b} proposal {pid} has a submitted vote without recovery material"
                            ),
                        });
                    }
                    steps.push(NextStep::PollVote {
                        bundle_index: b,
                        proposal_id: pid,
                    });
                }
                // Prepared or no row yet -> still needs casting.
                _ => {
                    steps.push(NextStep::CastVote {
                        bundle_index: b,
                        proposal_id: pid,
                        choice: intent_choice,
                    });
                    bundles_needing_delegation.insert(b);
                }
            }
        }
    }

    // Delegation steps: resume any mid-flight delegation; otherwise only the
    // prerequisite for a bundle that still has a vote to cast.
    for &b in &bundles {
        match delegation.get(&b) {
            Some(DelegationPhase::Confirmed) => {}
            Some(DelegationPhase::Submitted) => {
                steps.push(NextStep::PollDelegation { bundle_index: b });
            }
            // Prepared / PcztBuilt / Proved: still needs the delegate flow.
            _ => {
                if bundles_needing_delegation.contains(&b) {
                    steps.push(NextStep::Delegate { bundle_index: b });
                }
            }
        }
    }

    // Confirm already-submitted helper shares.
    for &(b, p, s, phase) in &share_phase_rows {
        if stale_vote_keys.contains(&(b, p)) {
            continue;
        }
        match phase {
            SharePhase::Submitted => {
                steps.push(NextStep::ConfirmShare {
                    bundle_index: b,
                    proposal_id: p,
                    share_index: s,
                });
            }
            SharePhase::Confirmed => {}
        }
    }

    steps.sort_by_key(step_rank);

    let confirm_share_step_keys = steps
        .iter()
        .filter_map(|step| match step {
            NextStep::ConfirmShare {
                bundle_index,
                proposal_id,
                share_index,
            } => Some((*bundle_index, *proposal_id, *share_index)),
            _ => None,
        })
        .collect::<BTreeSet<_>>();
    let blocking_confirm_share_keys = db
        .get_unconfirmed_delegations(round_id)?
        .into_iter()
        .filter(|share| share.sent_to_urls.is_empty())
        .filter(|share| {
            confirm_share_step_keys.contains(&(
                share.bundle_index,
                share.proposal_id,
                share.share_index,
            ))
        })
        .map(|share| (share.bundle_index, share.proposal_id, share.share_index))
        .collect::<BTreeSet<_>>();
    let blocking_share_work = !blocking_confirm_share_keys.is_empty();
    let blocking_recovery = steps.iter().any(|step| match step {
        NextStep::ConfirmShare {
            bundle_index,
            proposal_id,
            share_index,
        } => blocking_confirm_share_keys.contains(&(*bundle_index, *proposal_id, *share_index)),
        _ => true,
    });

    let delegation_statuses = delegation_statuses(db, round_id, &delegation)?;
    let hotkey_bound = delegation
        .values()
        .any(|phase| *phase != DelegationPhase::Prepared)
        || !votes.is_empty()
        || !share_phase_rows.is_empty();
    let all_decided = proposal_ids.iter().all(|&pid| match intents.get(&pid) {
        Some(Decision::Skipped) => true,
        Some(Decision::Choice(choice)) => {
            !bundles.is_empty()
                && bundles.iter().all(|&b| {
                    let vote_key = (b, pid);
                    vote_choices.get(&vote_key) == Some(choice)
                        && votes.get(&vote_key) == Some(&VotePhase::Confirmed)
                })
        }
        None => false,
    });
    let completed_vote_artifact =
        vote_choices
            .iter()
            .any(|(&(bundle_index, proposal_id), &stored_choice)| {
                !stale_vote_keys.contains(&(bundle_index, proposal_id))
                    && matches!(
                        intents.get(&proposal_id),
                        Some(Decision::Choice(intent_choice)) if *intent_choice == stored_choice
                    )
            })
            || share_phase_rows
                .iter()
                .any(|(bundle_index, proposal_id, _, _)| {
                    !stale_vote_keys.contains(&(*bundle_index, *proposal_id))
                        && matches!(intents.get(proposal_id), Some(Decision::Choice(_)))
                });
    let completed_for_display = completed_vote_artifact && !blocking_recovery;
    let voted_at = share_delegations
        .iter()
        .map(|share| share.created_at)
        .filter(|created_at| *created_at > 0)
        .max();
    let completed_vote_display = completed_for_display.then(|| {
        completed_vote_display(
            proposal_ids,
            &intents,
            &vote_choices,
            &stale_vote_keys,
            voted_at,
        )
    });
    let pending_recovery = !steps.is_empty();
    let needs_draft_setup = !blocking_recovery && !all_decided && !open_proposals.is_empty();
    let primary_action = select_primary_action(
        &steps,
        blocking_recovery,
        blocking_share_work,
        completed_for_display,
    );
    let recovered_delegation_work =
        recovered_delegation_work_from_steps(db, round_id, &delegation, &steps)?;
    let recovered_vote_work =
        recovered_vote_work_from_steps(db, round_id, &blocking_confirm_share_keys, &steps)?;

    Ok(RoundPlan {
        round_id: round_id.to_string(),
        pending_recovery,
        next_steps: steps,
        open_proposals,
        all_decided,
        delegation_statuses,
        blocking_recovery,
        blocking_share_work,
        hotkey_bound,
        completed_vote_artifact,
        completed_for_display,
        completed_vote_display,
        needs_draft_setup,
        primary_action,
        recovered_delegation_work,
        recovered_vote_work,
    })
}

fn vote_has_recovery_bundle(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<bool, VotingError> {
    Ok(matches!(
        db.get_commitment_bundle_recovery_fields(round_id, bundle_index, proposal_id)?,
        Some((Some(_), _))
    ))
}

fn missing_share_indexes_for_confirmed_vote(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    recorded_share_indexes: BTreeSet<u32>,
) -> Result<Vec<u32>, VotingError> {
    let Some(recovery) = crate::vote::recovery_bundle(db, round_id, bundle_index, proposal_id)?
    else {
        return Err(VotingError::InvalidInput {
            message: format!(
                "confirmed vote for round {round_id} bundle {bundle_index} proposal {proposal_id} is missing recovery material for helper-share submission"
            ),
        });
    };
    let expected_share_indexes = crate::share::recover_payloads(&recovery)?
        .iter()
        .map(|payload| payload.enc_share.share_index)
        .collect::<BTreeSet<_>>();
    if expected_share_indexes.is_empty() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "confirmed vote for round {round_id} bundle {bundle_index} proposal {proposal_id} has no recoverable helper shares"
            ),
        });
    }

    Ok(expected_share_indexes
        .difference(&recorded_share_indexes)
        .copied()
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::round::RoundParams;
    use crate::types::{EncryptedShare, NoteInfo};
    use crate::vote::{DraftVote, VoteRecoveryBundle};

    const ROUND: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const W: &str = "wallet";

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND.to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![position as u8 + 0x02; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn db_with_bundle() -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(W);
        db.create_round(&round_params(), None).unwrap();
        db.ensure_bundles(ROUND, &[note(0)]).unwrap();
        db
    }

    fn store_vote_recovery_fixture(
        db: &VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
        vc_tree_position: Option<u64>,
    ) {
        let recovery = recovery_bundle_fixture(
            bundle_index,
            proposal_id,
            choice,
            vc_tree_position.unwrap_or(0),
        );
        store_recovery_bundle_fixture(db, &recovery, vc_tree_position);
    }

    fn store_recovery_bundle_fixture(
        db: &VotingDb,
        recovery: &VoteRecoveryBundle,
        vc_tree_position: Option<u64>,
    ) {
        let conn = db.conn();
        let rows = conn
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index
                   AND proposal_id = :proposal_id",
                named_params! {
                    ":json": crate::vote::serialize_recovery(&recovery).unwrap(),
                    ":pos": vc_tree_position.map(|position| position as i64),
                    ":round_id": ROUND,
                    ":wallet_id": W,
                    ":bundle_index": recovery.bundle_index as i64,
                    ":proposal_id": recovery.proposal_id as i64,
                },
            )
            .unwrap();
        assert_eq!(rows, 1);
    }

    fn confirm_vote_fixture(db: &VotingDb, bundle_index: u32, proposal_id: u32, choice: u32) {
        crate::storage::queries::store_vote(
            &db.conn(),
            ROUND,
            W,
            bundle_index,
            proposal_id,
            choice,
            &[0xCC; 16],
        )
        .unwrap();
        store_vote_recovery_fixture(db, bundle_index, proposal_id, choice, Some(42));
        db.record_vote_submission(ROUND, bundle_index, proposal_id, "tx")
            .unwrap();
    }

    fn recovery_bundle_fixture(
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
        vc_tree_position: u64,
    ) -> VoteRecoveryBundle {
        VoteRecoveryBundle {
            vote_round_id: ROUND.to_string(),
            bundle_index,
            proposal_id,
            vote_decision: choice,
            anchor_height: 123,
            vc_tree_position,
            single_share: false,
            num_options: 3,
            van_nullifier: [0x10; 32],
            vote_authority_note_new: [0x11; 32],
            vote_commitment: [0x12; 32],
            proof: vec![0x13; 96],
            shares_hash: [0x14; 32],
            r_vpk: [0x15; 32],
            alpha_v: [0x16; 32],
            vote_auth_sig: [0x17; 64],
            encrypted_shares: vec![
                EncryptedShare {
                    c1: vec![0x21; 32],
                    c2: vec![0x22; 32],
                    share_index: 0,
                    plaintext_value: 5,
                    randomness: vec![0x23; 32],
                },
                EncryptedShare {
                    c1: vec![0x31; 32],
                    c2: vec![0x32; 32],
                    share_index: 1,
                    plaintext_value: 6,
                    randomness: vec![0x33; 32],
                },
            ],
            share_blinds: vec![[0x41; 32], [0x42; 32]],
            share_comms: vec![[0x51; 32], [0x52; 32]],
        }
    }

    fn record_confirmed_share_fixture(
        db: &VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
    ) {
        let nullifier = vec![share_index as u8; 32];
        db.record_share_delegation(
            ROUND,
            bundle_index,
            proposal_id,
            share_index,
            &["https://helper.example".to_string()],
            &nullifier,
            0,
        )
        .unwrap();
        db.mark_share_confirmed(ROUND, bundle_index, proposal_id, share_index)
            .unwrap();
    }

    fn record_submitted_share_fixture(
        db: &VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
        sent_to_urls: &[String],
    ) {
        let nullifier = vec![share_index as u8; 32];
        db.record_share_delegation(
            ROUND,
            bundle_index,
            proposal_id,
            share_index,
            sent_to_urls,
            &nullifier,
            0,
        )
        .unwrap();
    }

    fn record_all_confirmed_share_fixtures(db: &VotingDb, bundle_index: u32, proposal_id: u32) {
        record_confirmed_share_fixture(db, bundle_index, proposal_id, 0);
        record_confirmed_share_fixture(db, bundle_index, proposal_id, 1);
    }

    #[test]
    fn ballot_intent_round_trip() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 1, Decision::Choice(0), 3)
            .unwrap();
        db.set_ballot_intent(ROUND, 2, Decision::Skipped, 3)
            .unwrap();
        db.set_ballot_intent(ROUND, 1, Decision::Choice(3), 4)
            .unwrap(); // upsert

        let intents = db.ballot_intents(ROUND).unwrap();
        assert_eq!(
            intents,
            vec![(1, Decision::Choice(3)), (2, Decision::Skipped)]
        );
    }

    #[test]
    fn ballot_intent_rejects_invalid_proposal_id() {
        let db = db_with_bundle();

        assert!(db
            .set_ballot_intent(ROUND, 0, Decision::Choice(0), 3)
            .is_err());
        assert!(db
            .set_ballot_intent(ROUND, 16, Decision::Skipped, 3)
            .is_err());
    }

    #[test]
    fn ballot_intent_rejects_choice_outside_proposal_option_count() {
        let db = db_with_bundle();

        db.set_ballot_intent(ROUND, 1, Decision::Choice(1), 2)
            .unwrap();
        assert!(db
            .set_ballot_intent(ROUND, 1, Decision::Choice(2), 2)
            .is_err());
        assert!(db
            .set_ballot_intent(ROUND, 1, Decision::Choice(0), 1)
            .is_err());
    }

    #[test]
    fn ballot_intent_for_draft_vote_validates_choice_and_options() {
        let db = db_with_bundle();
        let draft = DraftVote {
            proposal_id: 1,
            choice: 1,
            num_options: 2,
            single_share: false,
            vc_tree_position: 0,
        };

        db.set_ballot_intent_for_draft_vote(ROUND, &draft).unwrap();
        assert_eq!(
            db.ballot_intents(ROUND).unwrap(),
            vec![(1, Decision::Choice(1))]
        );

        assert!(db
            .set_ballot_intent_for_draft_vote(
                ROUND,
                &DraftVote {
                    choice: 2,
                    ..draft.clone()
                },
            )
            .is_err());
        assert!(db
            .set_ballot_intent_for_draft_vote(
                ROUND,
                &DraftVote {
                    num_options: 9,
                    ..draft
                },
            )
            .is_err());
    }

    #[test]
    fn resume_plan_rejects_invalid_proposal_ids() {
        let db = db_with_bundle();

        assert!(resume_plan(&db, ROUND, &[1, 0]).is_err());
        assert!(resume_plan(&db, ROUND, &[1, 16]).is_err());
    }

    #[test]
    fn fresh_round_with_no_choices_has_no_recovery() {
        let db = db_with_bundle();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert!(!plan.pending_recovery);
        assert!(plan.next_steps.is_empty());
        assert_eq!(plan.open_proposals, vec![1, 2, 3]);
        assert!(!plan.all_decided);
        assert_eq!(
            plan.delegation_statuses,
            vec![DelegationStatus {
                bundle_index: 0,
                phase: DelegationPhase::Prepared,
                tx_hash: None,
            }]
        );
        assert!(!plan.blocking_recovery);
        assert!(!plan.hotkey_bound);
        assert!(!plan.completed_vote_artifact);
        assert!(!plan.completed_for_display);
        assert_eq!(plan.completed_vote_display, None);
        assert!(plan.needs_draft_setup);
        assert_eq!(plan.primary_action, RoundPlanAction::Idle);
        assert!(plan.recovered_delegation_work.is_empty());
        assert!(plan.recovered_vote_work.is_empty());
    }

    #[test]
    fn answered_but_uncast_proposal_yields_cast_then_delegate_prereq() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert!(plan.pending_recovery);
        // Bundle 0 is only Prepared, and proposal 2 needs casting on it, so the
        // delegate prerequisite is emitted, ordered before the cast.
        assert_eq!(
            plan.next_steps,
            vec![
                NextStep::Delegate { bundle_index: 0 },
                NextStep::CastVote {
                    bundle_index: 0,
                    proposal_id: 2,
                    choice: 1,
                },
            ]
        );
        assert_eq!(plan.open_proposals, vec![1, 3]);
        assert_eq!(
            plan.recovered_delegation_work,
            vec![DelegationRecoveryWork {
                kind: DelegationRecoveryWorkKind::Delegate,
                bundle_index: 0,
                phase: DelegationPhase::Prepared,
                tx_hash: None,
            }]
        );
    }

    #[test]
    fn submitted_but_unconfirmed_vote_yields_poll() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 1, &[0xCC; 16]).unwrap();
        store_vote_recovery_fixture(&db, 0, 2, 1, None);
        db.record_vote_submission(ROUND, 0, 2, "vtx").unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert_eq!(
            plan.next_steps,
            vec![NextStep::PollVote {
                bundle_index: 0,
                proposal_id: 2
            }]
        );
        assert_eq!(
            plan.recovered_vote_work,
            vec![VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::PollVote,
                bundle_index: 0,
                proposal_id: 2,
                tx_hash: Some("vtx".to_string()),
                vc_tree_position: None,
                share_indexes: Vec::new(),
            }]
        );
    }

    #[test]
    fn submitted_vote_without_recovery_bundle_is_invalid() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 1, &[0xCC; 16]).unwrap();
        db.record_vote_submission(ROUND, 0, 2, "vtx").unwrap();

        let err = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap_err();

        assert!(
            err.to_string()
                .contains("submitted vote without recovery material"),
            "{err}"
        );
    }

    #[test]
    fn blocking_share_retry_waits_for_submitted_vote_confirmation() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 1, &[0xCC; 16]).unwrap();
        store_vote_recovery_fixture(&db, 0, 2, 1, None);
        db.record_vote_submission(ROUND, 0, 2, "vtx").unwrap();
        record_submitted_share_fixture(&db, 0, 2, 0, &[]);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![
                NextStep::PollVote {
                    bundle_index: 0,
                    proposal_id: 2,
                },
                NextStep::ConfirmShare {
                    bundle_index: 0,
                    proposal_id: 2,
                    share_index: 0,
                },
            ]
        );
        assert!(plan.blocking_recovery);
        assert!(plan.blocking_share_work);
        assert_eq!(plan.primary_action, RoundPlanAction::Vote);
        assert_eq!(
            plan.recovered_vote_work,
            vec![VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::PollVote,
                bundle_index: 0,
                proposal_id: 2,
                tx_hash: Some("vtx".to_string()),
                vc_tree_position: None,
                share_indexes: Vec::new(),
            }]
        );
    }

    #[test]
    fn committed_vote_yields_submit_not_rebuild() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 1, &[0xCC; 16]).unwrap();
        store_vote_recovery_fixture(&db, 0, 2, 1, None);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![NextStep::SubmitVote {
                bundle_index: 0,
                proposal_id: 2
            }]
        );
        assert!(plan.blocking_recovery);
        assert_eq!(plan.primary_action, RoundPlanAction::Vote);
        assert_eq!(
            plan.recovered_vote_work,
            vec![VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::SubmitVote,
                bundle_index: 0,
                proposal_id: 2,
                tx_hash: None,
                vc_tree_position: None,
                share_indexes: Vec::new(),
            }]
        );
    }

    #[test]
    fn changed_choice_after_submission_is_invalid_recovery_state() {
        let db = db_with_bundle();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();

        confirm_vote_fixture(&db, 0, 2, 0);
        db.conn()
            .execute(
                "INSERT INTO ballot_intent
                    (round_id, wallet_id, proposal_id, skipped, choice, created_at, updated_at)
                 VALUES (:round_id, :wallet_id, :proposal_id, 0, 1, 1, 1)",
                named_params! {
                    ":round_id": ROUND,
                    ":wallet_id": W,
                    ":proposal_id": 2_i64,
                },
            )
            .unwrap();

        let err = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap_err();

        assert!(
            err.to_string()
                .contains("submitted vote that conflicts with ballot intent"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn conflicting_intent_after_submission_is_rejected_before_share_cleanup() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(0), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        confirm_vote_fixture(&db, 0, 2, 0);
        record_all_confirmed_share_fixtures(&db, 0, 2);

        for decision in [Decision::Choice(1), Decision::Skipped] {
            let err = db.set_ballot_intent(ROUND, 2, decision, 3).unwrap_err();
            assert!(
                err.to_string()
                    .contains("submitted vote that conflicts with ballot intent"),
                "unexpected error for {decision:?}: {err}"
            );
            assert_eq!(
                db.ballot_intents(ROUND).unwrap(),
                vec![(2, Decision::Choice(0))]
            );
            let shares = db.get_share_delegations(ROUND).unwrap();
            assert_eq!(shares.len(), 2);
            let share_indexes = shares
                .iter()
                .map(|share| share.share_index)
                .collect::<BTreeSet<_>>();
            assert_eq!(share_indexes, BTreeSet::from([0, 1]));
            assert!(shares.iter().all(|share| {
                share.bundle_index == 0 && share.proposal_id == 2 && share.confirmed
            }));
        }
    }

    #[test]
    fn stale_vote_submission_after_choice_change_is_rejected() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(0), 3)
            .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 0, &[0xCC; 16]).unwrap();

        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        let err = db
            .record_vote_submission(ROUND, 0, 2, "old-vtx")
            .unwrap_err();

        assert!(
            err.to_string()
                .contains("vote submission conflicts with ballot intent"),
            "unexpected error: {err}"
        );
        assert_eq!(db.get_vote_tx_hash(ROUND, 0, 2).unwrap(), None);
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert_eq!(
            plan.next_steps,
            vec![NextStep::CastVote {
                bundle_index: 0,
                proposal_id: 2,
                choice: 1,
            }]
        );
    }

    #[test]
    fn stale_vote_submission_after_skip_is_rejected() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(0), 3)
            .unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 0, &[0xCC; 16]).unwrap();

        db.set_ballot_intent(ROUND, 2, Decision::Skipped, 3)
            .unwrap();
        let err = db
            .record_vote_submission(ROUND, 0, 2, "old-vtx")
            .unwrap_err();

        assert!(
            err.to_string()
                .contains("cannot record vote submission for skipped proposal"),
            "unexpected error: {err}"
        );
        assert_eq!(db.get_vote_tx_hash(ROUND, 0, 2).unwrap(), None);
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert!(!plan.pending_recovery);
        assert_eq!(plan.open_proposals, vec![1, 3]);
        assert!(!plan.completed_vote_artifact);
        assert!(!plan.completed_for_display);
        assert_eq!(plan.primary_action, RoundPlanAction::Idle);
    }

    #[test]
    fn changed_choice_ignores_stale_share_confirmations() {
        let db = db_with_bundle();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();

        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 0, &[0xCC; 16]).unwrap();
        db.record_share_delegation(
            ROUND,
            0,
            2,
            0,
            &["https://helper.example".to_string()],
            &[0x44; 32],
            0,
        )
        .unwrap();

        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![NextStep::CastVote {
                bundle_index: 0,
                proposal_id: 2,
                choice: 1,
            }]
        );
    }

    #[test]
    fn recast_choice_keeps_old_share_confirmations_suppressed() {
        let db = db_with_bundle();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();

        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 0, &[0xCC; 16]).unwrap();
        db.record_share_delegation(
            ROUND,
            0,
            2,
            0,
            &["https://helper.example".to_string()],
            &[0x44; 32],
            0,
        )
        .unwrap();

        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 1, &[0xDD; 16]).unwrap();

        assert!(
            db.get_share_delegations(ROUND).unwrap().is_empty(),
            "recasting must clear helper-share rows for the old vote"
        );

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert_eq!(
            plan.next_steps,
            vec![NextStep::CastVote {
                bundle_index: 0,
                proposal_id: 2,
                choice: 1,
            }]
        );
    }

    #[test]
    fn skipped_intent_clears_and_blocks_stale_share_rows() {
        let db = db_with_bundle();
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 0, 2, 0, &[0xCC; 16]).unwrap();
        db.record_share_delegation(
            ROUND,
            0,
            2,
            0,
            &["https://helper.example".to_string()],
            &[0x44; 32],
            0,
        )
        .unwrap();

        db.set_ballot_intent(ROUND, 2, Decision::Skipped, 3)
            .unwrap();

        assert!(db.get_share_delegations(ROUND).unwrap().is_empty());
        let err = db
            .record_share_delegation(
                ROUND,
                0,
                2,
                0,
                &["https://helper.example".to_string()],
                &[0x44; 32],
                0,
            )
            .unwrap_err();
        assert!(
            err.to_string()
                .contains("cannot record share delegation for skipped proposal"),
            "{err}"
        );
    }

    #[test]
    fn skipped_proposal_is_terminal_not_recovery() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 1, Decision::Skipped, 3)
            .unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();
        assert!(!plan.pending_recovery);
        assert_eq!(plan.open_proposals, vec![2, 3]);
    }

    #[test]
    fn choice_intent_without_bundles_is_invalid() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(W);
        db.create_round(&round_params(), None).unwrap();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();

        let err = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap_err();
        assert!(
            err.to_string().contains("no eligible bundle rows"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn midflight_delegation_is_recovery_without_votes() {
        let db = db_with_bundle();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap(); // Submitted, no VAN
        let plan = resume_plan(&db, ROUND, &[1]).unwrap();
        assert_eq!(
            plan.next_steps,
            vec![NextStep::PollDelegation { bundle_index: 0 }]
        );
        assert!(plan.hotkey_bound);
        assert_eq!(
            plan.recovered_delegation_work,
            vec![DelegationRecoveryWork {
                kind: DelegationRecoveryWorkKind::PollDelegation,
                bundle_index: 0,
                phase: DelegationPhase::Submitted,
                tx_hash: Some("dtx".to_string()),
            }]
        );
    }

    #[test]
    fn confirmed_delegation_without_votes_still_binds_hotkey() {
        let db = db_with_bundle();
        db.store_delegation_tx_hash(ROUND, 0, "dtx").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert!(!plan.pending_recovery);
        assert!(plan.next_steps.is_empty());
        assert!(plan.hotkey_bound);
        assert!(!plan.completed_vote_artifact);
        assert!(plan.needs_draft_setup);
        assert_eq!(
            plan.delegation_statuses,
            vec![DelegationStatus {
                bundle_index: 0,
                phase: DelegationPhase::Confirmed,
                tx_hash: Some("dtx".to_string()),
            }]
        );
        assert!(plan.recovered_delegation_work.is_empty());
    }

    #[test]
    fn multi_bundle_orders_vote_steps_by_proposal() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(W);
        db.create_round(&round_params(), None).unwrap();
        db.ensure_bundles(
            ROUND,
            &[note(0), note(1), note(2), note(3), note(4), note(5)],
        )
        .unwrap();

        // Verify the actual bundle count before asserting; 6 notes with
        // BALLOT_DIVISOR value each should produce 2 bundles (indices 0 and 1).
        let phases = db.delegation_phases(ROUND).unwrap();
        let bundle_count = phases.len();
        assert_eq!(
            bundle_count,
            2,
            "expected 6 notes → 2 bundles, got {bundle_count}; adjust this test if bundling rules changed"
        );

        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        // Delegation prerequisites come first, then vote work is ordered by
        // proposal before bundle.
        assert_eq!(
            plan.next_steps,
            vec![
                NextStep::Delegate { bundle_index: 0 },
                NextStep::Delegate { bundle_index: 1 },
                NextStep::CastVote {
                    bundle_index: 0,
                    proposal_id: 2,
                    choice: 1,
                },
                NextStep::CastVote {
                    bundle_index: 1,
                    proposal_id: 2,
                    choice: 1,
                },
            ]
        );
    }

    #[test]
    fn interrupted_second_bundle_vote_stays_before_later_proposals() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(W);
        db.create_round(&round_params(), None).unwrap();
        db.ensure_bundles(
            ROUND,
            &[note(0), note(1), note(2), note(3), note(4), note(5)],
        )
        .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx-0").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        db.store_delegation_tx_hash(ROUND, 1, "dtx-1").unwrap();
        db.store_van_position(ROUND, 1, 8).unwrap();

        for (proposal_id, choice) in [(1, 0), (2, 1), (3, 0)] {
            db.set_ballot_intent(ROUND, proposal_id, Decision::Choice(choice), 3)
                .unwrap();
        }
        confirm_vote_fixture(&db, 0, 1, 0);
        record_all_confirmed_share_fixtures(&db, 0, 1);
        crate::storage::queries::store_vote(&db.conn(), ROUND, W, 1, 1, 0, &[0xCC; 16]).unwrap();
        store_vote_recovery_fixture(&db, 1, 1, 0, None);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![
                NextStep::SubmitVote {
                    bundle_index: 1,
                    proposal_id: 1,
                },
                NextStep::CastVote {
                    bundle_index: 0,
                    proposal_id: 2,
                    choice: 1,
                },
                NextStep::CastVote {
                    bundle_index: 1,
                    proposal_id: 2,
                    choice: 1,
                },
                NextStep::CastVote {
                    bundle_index: 0,
                    proposal_id: 3,
                    choice: 0,
                },
                NextStep::CastVote {
                    bundle_index: 1,
                    proposal_id: 3,
                    choice: 0,
                },
            ]
        );
    }

    #[test]
    fn confirmed_vote_without_recorded_shares_yields_submit_shares() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(W);
        db.create_round(&round_params(), None).unwrap();
        db.ensure_bundles(
            ROUND,
            &[note(0), note(1), note(2), note(3), note(4), note(5)],
        )
        .unwrap();
        db.store_delegation_tx_hash(ROUND, 0, "dtx-0").unwrap();
        db.store_van_position(ROUND, 0, 7).unwrap();
        db.store_delegation_tx_hash(ROUND, 1, "dtx-1").unwrap();
        db.store_van_position(ROUND, 1, 8).unwrap();

        for (proposal_id, choice) in [(1, 0), (2, 1)] {
            db.set_ballot_intent(ROUND, proposal_id, Decision::Choice(choice), 3)
                .unwrap();
        }
        confirm_vote_fixture(&db, 0, 1, 0);
        record_all_confirmed_share_fixtures(&db, 0, 1);
        confirm_vote_fixture(&db, 1, 1, 0);

        let plan = resume_plan(&db, ROUND, &[1, 2]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![
                NextStep::SubmitShares {
                    bundle_index: 1,
                    proposal_id: 1,
                    share_index: 0,
                },
                NextStep::SubmitShares {
                    bundle_index: 1,
                    proposal_id: 1,
                    share_index: 1,
                },
                NextStep::CastVote {
                    bundle_index: 0,
                    proposal_id: 2,
                    choice: 1,
                },
                NextStep::CastVote {
                    bundle_index: 1,
                    proposal_id: 2,
                    choice: 1,
                },
            ]
        );
        assert_eq!(
            plan.recovered_vote_work,
            vec![VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::SubmitShares,
                bundle_index: 1,
                proposal_id: 1,
                tx_hash: None,
                vc_tree_position: Some(42),
                share_indexes: vec![0, 1],
            }]
        );
    }

    #[test]
    fn confirmed_vote_with_partial_recorded_shares_yields_submit_shares() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        confirm_vote_fixture(&db, 0, 2, 1);
        record_confirmed_share_fixture(&db, 0, 2, 0);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![NextStep::SubmitShares {
                bundle_index: 0,
                proposal_id: 2,
                share_index: 1,
            }]
        );
    }

    #[test]
    fn confirmed_vote_with_all_recorded_shares_has_no_share_submission_step() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        confirm_vote_fixture(&db, 0, 2, 1);
        record_all_confirmed_share_fixtures(&db, 0, 2);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert!(plan.next_steps.is_empty(), "got {:?}", plan.next_steps);
        assert!(plan.completed_vote_artifact);
        assert!(plan.completed_for_display);
        assert_eq!(
            plan.completed_vote_display
                .as_ref()
                .map(|display| &display.choices),
            Some(&vec![
                CompletedVoteChoice {
                    proposal_id: 1,
                    choice: None,
                },
                CompletedVoteChoice {
                    proposal_id: 2,
                    choice: Some(1),
                },
                CompletedVoteChoice {
                    proposal_id: 3,
                    choice: None,
                },
            ])
        );
        assert!(plan
            .completed_vote_display
            .as_ref()
            .and_then(|display| display.voted_at)
            .is_some());
        assert!(plan.needs_draft_setup);
        assert_eq!(plan.primary_action, RoundPlanAction::Done);
        assert!(plan.recovered_vote_work.is_empty());
    }

    #[test]
    fn confirmed_single_share_vote_with_recorded_payload_has_no_share_submission_step() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        confirm_vote_fixture(&db, 0, 2, 1);
        let mut recovery = recovery_bundle_fixture(0, 2, 1, 42);
        recovery.single_share = true;
        store_recovery_bundle_fixture(&db, &recovery, Some(42));
        record_confirmed_share_fixture(&db, 0, 2, 0);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert!(plan.next_steps.is_empty(), "got {:?}", plan.next_steps);
    }

    #[test]
    fn delegate_suppressed_when_vote_confirmed() {
        let db = db_with_bundle();
        confirm_vote_fixture(&db, 0, 2, 1);
        record_all_confirmed_share_fixtures(&db, 0, 2);

        // Bundle 0 delegation is still only Prepared — but the vote is Confirmed,
        // so no Delegate step should appear and the plan has no work left.
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert!(
            plan.next_steps.is_empty(),
            "expected no steps, got: {:?}",
            plan.next_steps
        );
        assert!(!plan.pending_recovery);
    }

    #[test]
    fn confirm_share_emitted_for_unconfirmed_share() {
        let db = db_with_bundle();
        db.record_share_delegation(
            ROUND,
            0,
            2,
            0,
            &["https://helper.example".to_string()],
            &[0x44; 32],
            0,
        )
        .unwrap();

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert!(
            plan.next_steps.contains(&NextStep::ConfirmShare {
                bundle_index: 0,
                proposal_id: 2,
                share_index: 0
            }),
            "expected ConfirmShare in steps, got: {:?}",
            plan.next_steps
        );
    }

    #[test]
    fn accepted_helper_share_confirmation_is_nonblocking_display_work() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        confirm_vote_fixture(&db, 0, 2, 1);
        let mut recovery = recovery_bundle_fixture(0, 2, 1, 42);
        recovery.single_share = true;
        store_recovery_bundle_fixture(&db, &recovery, Some(42));
        record_submitted_share_fixture(&db, 0, 2, 0, &["https://helper.example".to_string()]);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![NextStep::ConfirmShare {
                bundle_index: 0,
                proposal_id: 2,
                share_index: 0
            }]
        );
        assert!(plan.pending_recovery);
        assert!(!plan.blocking_recovery);
        assert!(!plan.blocking_share_work);
        assert!(plan.completed_vote_artifact);
        assert!(plan.completed_for_display);
        assert!(plan.needs_draft_setup);
        assert_eq!(plan.primary_action, RoundPlanAction::Done);
    }

    #[test]
    fn unaccepted_helper_share_confirmation_blocks_foreground_recovery() {
        let db = db_with_bundle();
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();
        confirm_vote_fixture(&db, 0, 2, 1);
        let mut recovery = recovery_bundle_fixture(0, 2, 1, 42);
        recovery.single_share = true;
        store_recovery_bundle_fixture(&db, &recovery, Some(42));
        record_submitted_share_fixture(&db, 0, 2, 0, &[]);

        let plan = resume_plan(&db, ROUND, &[1, 2, 3]).unwrap();

        assert_eq!(
            plan.next_steps,
            vec![NextStep::ConfirmShare {
                bundle_index: 0,
                proposal_id: 2,
                share_index: 0
            }]
        );
        assert!(plan.pending_recovery);
        assert!(plan.blocking_recovery);
        assert!(plan.blocking_share_work);
        assert!(plan.completed_vote_artifact);
        assert!(!plan.completed_for_display);
        assert!(!plan.needs_draft_setup);
        assert_eq!(plan.primary_action, RoundPlanAction::SubmitShares);
        assert_eq!(
            plan.recovered_vote_work,
            vec![VoteRecoveryWork {
                kind: VoteRecoveryWorkKind::SubmitShares,
                bundle_index: 0,
                proposal_id: 2,
                tx_hash: None,
                vc_tree_position: Some(42),
                share_indexes: vec![0],
            }]
        );
    }

    #[test]
    fn all_decided_true_with_confirmed_choice_and_skip() {
        let db = db_with_bundle();

        // Proposal 2: drive to Confirmed.
        confirm_vote_fixture(&db, 0, 2, 1);
        record_all_confirmed_share_fixtures(&db, 0, 2);
        db.set_ballot_intent(ROUND, 2, Decision::Choice(1), 3)
            .unwrap();

        // Proposal 1: skipped.
        db.set_ballot_intent(ROUND, 1, Decision::Skipped, 3)
            .unwrap();

        let plan = resume_plan(&db, ROUND, &[1, 2]).unwrap();

        assert!(plan.all_decided, "expected all_decided == true");
        assert!(!plan.pending_recovery, "expected pending_recovery == false");
    }
}
