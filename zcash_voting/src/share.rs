//! Stable helper-share planning and recovery API.
//!
//! This module wraps share nullifier computation, helper payload recovery, and
//! share-delegation persistence so wallets do not need direct access to
//! `share_delegations` SQL or recovery JSON internals.

#[allow(unused_imports)]
pub(crate) use crate::backend::pasta_curves;
use crate::{
    round::VotingDb,
    share_tracking::ShareSubmissionReport,
    types::{
        ct_option_to_result, ShareDelegationRecord, SharePayload, VotingError, WireEncryptedShare,
    },
    vote::{validate_recovery_bundle_vote_fields, VoteRecoveryBundle},
};

/// Inputs for durably recording one helper-share fan-out.
#[derive(Clone, Copy, Debug)]
pub(crate) struct ShareDeliveryRecordParams<'a> {
    /// Round that owns the share.
    pub round_id: &'a str,
    /// Vote bundle that owns the share.
    pub bundle_index: u32,
    /// Proposal that owns the share.
    pub proposal_id: u32,
    /// Share position within the proposal's commitment.
    pub share_index: u32,
    /// Definite and outcome-unknown helper attempts plus the placement target.
    pub submission: &'a ShareSubmissionReport,
    /// Unix seconds when helpers should submit the share, or zero for immediate.
    pub submit_at: u64,
}

/// Identity and policy needed to durably journal a helper POST.
#[derive(Clone, Copy, Debug)]
pub struct ShareDeliveryAttemptParams<'a> {
    /// Round that owns the share.
    pub round_id: &'a str,
    /// Index of the committed vote bundle that owns the share.
    pub bundle_index: u32,
    /// Proposal whose vote commitment contains the share.
    pub proposal_id: u32,
    /// Position of the share within that proposal's commitment.
    pub share_index: u32,
    /// Canonical base URL of the helper receiving the POST.
    pub server_url: &'a str,
    /// Desired number of definite helper placements.
    pub target_count: usize,
    /// Unix seconds when the helper should submit, or zero for immediate.
    pub submit_at: u64,
}

/// Whether a fresh durable helper reservation must respect the placement target.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ShareAttemptCapacityPolicy {
    /// Refuse a fresh reservation once accepted plus in-flight placements reach the target.
    EnforcePlacementTarget,
    /// Permit recovery to exceed the target when retry ordering or liveness requires it.
    AllowRecoveryBeyondPlacementTarget,
}

/// Wallet identity captured before an asynchronous helper-share operation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ShareOperationScope {
    wallet_id: String,
}

impl ShareOperationScope {
    pub(crate) fn capture(db: &VotingDb) -> Self {
        Self {
            wallet_id: db.wallet_id(),
        }
    }

    pub(crate) fn wallet_id(&self) -> &str {
        &self.wallet_id
    }
}

/// Exact persisted share generation that an asynchronous result may mutate.
#[derive(Clone, Copy, Debug)]
pub(crate) struct ShareGeneration<'a> {
    scope: &'a ShareOperationScope,
    nullifier: &'a [u8],
}

impl<'a> ShareGeneration<'a> {
    pub(crate) fn new(scope: &'a ShareOperationScope, nullifier: &'a [u8]) -> Self {
        Self { scope, nullifier }
    }

    pub(crate) fn scope(self) -> &'a ShareOperationScope {
        self.scope
    }

    pub(crate) fn nullifier(self) -> &'a [u8] {
        self.nullifier
    }
}

/// Definite state transition for a previously journaled helper POST.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShareDeliveryAttemptOutcome {
    /// The helper definitely acknowledged acceptance.
    Accepted,
    /// The request may have reached the helper, but no acknowledgement arrived.
    Ambiguous,
    /// The request definitely did not reach an accepted state.
    DefiniteFailure,
}

/// Canonical per-helper delivery state for one share.
///
/// A helper has exactly one state. Stronger evidence always wins:
/// accepted > outcome unknown > in flight. Each list retains the order in
/// which helpers first entered that state.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct ShareDeliveryState {
    accepted_urls: Vec<String>,
    outcome_unknown_urls: Vec<String>,
    in_flight_urls: Vec<String>,
}

impl ShareDeliveryState {
    pub(crate) fn from_url_lists(
        accepted_urls: &[String],
        outcome_unknown_urls: &[String],
        in_flight_urls: &[String],
    ) -> Result<Self, VotingError> {
        let mut state = Self::default();
        state.merge_persisted_report(accepted_urls, outcome_unknown_urls)?;
        for url in crate::helper::url::canonical_helper_url_list(in_flight_urls)? {
            if !state.contains(&url) {
                state.in_flight_urls.push(url);
            }
        }
        Ok(state)
    }

    /// Merges a persisted report without allowing weaker evidence to replace
    /// stronger evidence already held by the state.
    pub(crate) fn merge_persisted_report(
        &mut self,
        accepted_urls: &[String],
        outcome_unknown_urls: &[String],
    ) -> Result<(), VotingError> {
        for url in crate::helper::url::canonical_helper_url_list(accepted_urls)? {
            self.mark_accepted_canonical(url);
        }
        for url in crate::helper::url::canonical_helper_url_list(outcome_unknown_urls)? {
            self.mark_outcome_unknown_canonical(url);
        }
        Ok(())
    }

    /// Starts a new attempt unless this helper already has any delivery state.
    pub(crate) fn begin(&mut self, url: &str) -> Result<bool, VotingError> {
        let url = crate::helper::url::canonicalize_helper_base_url(url)?;
        if self.contains(&url) {
            return Ok(false);
        }
        self.in_flight_urls.push(url);
        Ok(true)
    }

    pub(crate) fn mark_accepted(&mut self, url: &str) -> Result<(), VotingError> {
        let url = crate::helper::url::canonicalize_helper_base_url(url)?;
        self.mark_accepted_canonical(url);
        Ok(())
    }

    pub(crate) fn mark_outcome_unknown(&mut self, url: &str) -> Result<(), VotingError> {
        let url = crate::helper::url::canonicalize_helper_base_url(url)?;
        self.mark_outcome_unknown_canonical(url);
        Ok(())
    }

    pub(crate) fn mark_definite_failure(&mut self, url: &str) -> Result<(), VotingError> {
        let url = crate::helper::url::canonicalize_helper_base_url(url)?;
        self.in_flight_urls.retain(|candidate| candidate != &url);
        Ok(())
    }

    pub(crate) fn accepted_urls(&self) -> &[String] {
        &self.accepted_urls
    }

    pub(crate) fn outcome_unknown_urls(&self) -> &[String] {
        &self.outcome_unknown_urls
    }

    pub(crate) fn in_flight_urls(&self) -> &[String] {
        &self.in_flight_urls
    }

    fn contains(&self, url: &str) -> bool {
        self.accepted_urls.iter().any(|candidate| candidate == url)
            || self
                .outcome_unknown_urls
                .iter()
                .any(|candidate| candidate == url)
            || self.in_flight_urls.iter().any(|candidate| candidate == url)
    }

    fn mark_accepted_canonical(&mut self, url: String) {
        self.outcome_unknown_urls
            .retain(|candidate| candidate != &url);
        self.in_flight_urls.retain(|candidate| candidate != &url);
        if !self.accepted_urls.contains(&url) {
            self.accepted_urls.push(url);
        }
    }

    fn mark_outcome_unknown_canonical(&mut self, url: String) {
        self.in_flight_urls.retain(|candidate| candidate != &url);
        if !self.accepted_urls.contains(&url) && !self.outcome_unknown_urls.contains(&url) {
            self.outcome_unknown_urls.push(url);
        }
    }
}
use pasta_curves::group::ff::PrimeField;
use pasta_curves::pallas;
use rusqlite::TransactionBehavior;

pub use crate::types::ShareDelegationRecord as ShareRecord;

/// One persisted round that still has unconfirmed helper shares.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PendingShareRound {
    /// Stable vote-round identifier.
    pub round_id: String,
    /// Opaque caller context stored when the round was first created.
    pub session_json: Option<String>,
}

/// Share scheduling and retry policy helpers.
pub mod policy {
    pub use crate::share_policy::{
        is_last_moment, is_share_ready_for_status_check, last_moment_buffer_seconds,
        last_moment_deadline_seconds, next_tracking_delay_seconds, overdue_threshold_seconds,
        plan_share_submission, plan_share_submission_from_order, plan_share_submissions,
        plan_share_submissions_with_preferred_servers, resubmission_server_order,
        resubmission_server_order_from_configured_order, resubmission_server_order_from_groups,
        resubmission_server_order_random_bytes_required, scheduled_share_submit_at_from_entropy,
        scheduled_share_submit_at_from_random_unit, select_share_submission_targets,
        select_share_submission_targets_from_order, share_recovery_base_time,
        share_server_order_random_bytes_required, share_server_selection_policy,
        share_submission_random_bytes_required, share_submission_target_count,
        share_submit_at_random_bytes_required, should_resubmit_share, shuffled_share_server_order,
        summarize_share_tracking, ImmediateShareKey, ShareServerSelectionPolicy,
        ShareSubmissionPlan, ShareSubmissionRandomBytesRequired, ShareTimingPolicy,
        ShareTrackingSummary, IMMEDIATE_SHARE_INDEX, LAST_MOMENT_BUFFER_FRACTION_DENOMINATOR,
        LAST_MOMENT_BUFFER_FRACTION_NUMERATOR, LAST_MOMENT_BUFFER_MAX_SECONDS,
        SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR, SHARE_HELPER_INITIAL_MAX_FRACTION_NUMERATOR,
        SHARE_HELPER_MAX_CONCURRENT_POSTS, SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER,
        SHARE_HELPER_POST_TIMEOUT_MILLISECONDS, SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS,
        SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS, SHARE_HELPER_TARGET_COUNT_CAP,
        SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS, SHARE_SUBMIT_AT_MAX_DELAY_SECONDS,
        VOTE_COMMITMENT_SHARE_COUNT,
    };
}

pub use policy::{
    ImmediateShareKey, ShareServerSelectionPolicy, ShareSubmissionPlan as SharePlan,
    ShareTimingPolicy, ShareTrackingSummary,
};

/// Computes the 32-byte share reveal nullifier.
pub fn compute_nullifier(
    vote_commitment: &[u8; 32],
    share_index: u32,
    primary_blind: &[u8; 32],
) -> Result<[u8; 32], VotingError> {
    if share_index > 15 {
        return Err(VotingError::InvalidInput {
            message: format!("share_index must be 0..15, got {share_index}"),
        });
    }

    let vc = ct_option_to_result(
        pallas::Base::from_repr(*vote_commitment),
        "invalid vote_commitment field element",
    )?;
    let blind = ct_option_to_result(
        pallas::Base::from_repr(*primary_blind),
        "invalid primary_blind field element",
    )?;
    let nullifier = voting_circuits::share_reveal::share_nullifier_hash(
        vc,
        pallas::Base::from(share_index as u64),
        blind,
    );
    Ok(nullifier.to_repr())
}

/// Records a helper-share submission using nullifier material from recovery state.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when any entry in `sent_to_urls`
/// fails [`crate::helper::url::canonicalize_helper_base_url`]. Validate
/// helper URLs with that function before delivering a share over the
/// network, so an already-delivered share can always be recorded.
#[cfg(any(test, feature = "test-fixtures"))]
fn record_impl(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    submit_at: u64,
) -> Result<(), VotingError> {
    // Reserve the WAL writer before loading recovery identity. Otherwise a
    // concurrent recast can replace the recovery bundle after this read and
    // the old share nullifier can be recorded under the replacement vote key.
    let mut conn = db.conn();
    let wallet_id = db.wallet_id();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("begin recovered share transaction failed: {e}"),
        })?;
    let bundle =
        crate::vote::recovery_bundle_with_conn(&tx, &wallet_id, round_id, bundle_index, proposal_id)?
            .ok_or_else(|| VotingError::InvalidInput {
                message: format!(
                    "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
                ),
            })?;
    ensure_recovery_proposal(&bundle, proposal_id)?;
    let payload = recover_payload(&bundle, share_index)?;
    let primary_blind = array32("primary_blind", payload.primary_blind.clone())?;
    let nullifier = compute_nullifier(&bundle.vote_commitment, share_index, &primary_blind)?;
    crate::storage::queries::record_share_delegation(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        &[],
        0,
        &nullifier,
        submit_at,
    )?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit recovered share transaction failed: {e}"),
    })
}

/// Records a helper-share submission for integration-test fixture setup.
///
/// Production callers submit through
/// [`crate::vote::CommittedVote::submit_share_to_helpers`], which owns the
/// journal-before-dispatch lifecycle. This lower-level entry point exists only
/// for the `test-fixtures` feature so integration tests can seed durable state
/// without opening a network connection.
#[cfg(any(test, feature = "test-fixtures"))]
#[doc(hidden)]
pub fn record(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    submit_at: u64,
) -> Result<(), VotingError> {
    record_impl(
        db,
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        submit_at,
    )
}

/// Records definite and outcome-unknown helper submissions for later tracking.
///
/// `params.submission.target_count` is the number of definite placements the
/// tracker should maintain. Outcome-unknown helpers never count toward that
/// target because `pending` does not prove possession. Tracking excludes them
/// during early replenishment but may retry them during overdue duplicate-safe
/// recovery.
///
/// Returns the effective durable `submit_at`, preserving an existing schedule.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when the target does not fit the
/// persisted representation, the vote recovery bundle is missing or invalid,
/// or any reported URL fails
/// [`crate::helper::url::canonicalize_helper_base_url`] — validate helper
/// URLs before delivering over the network. Storage failures are returned
/// unchanged.
#[cfg(any(test, feature = "test-fixtures"))]
fn record_delivery_impl(
    db: &VotingDb,
    params: &ShareDeliveryRecordParams<'_>,
) -> Result<u64, VotingError> {
    let scope = ShareOperationScope::capture(db);
    record_delivery_for_scope(db, &scope, params).map(|(submit_at, _)| submit_at)
}

pub(crate) fn record_delivery_for_scope(
    db: &VotingDb,
    scope: &ShareOperationScope,
    params: &ShareDeliveryRecordParams<'_>,
) -> Result<(u64, [u8; 32]), VotingError> {
    let target_count = persisted_delivery_target_count(params)?;
    let nullifier = delivery_nullifier_for_scope(
        db,
        scope,
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
    )?;
    let submit_at = db.record_share_delivery_for_wallet(
        scope.wallet_id(),
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        &params.submission.accepted_urls,
        &params.submission.ambiguous_urls,
        target_count,
        &nullifier,
        params.submit_at,
    )?;
    Ok((submit_at, nullifier))
}

/// Records delivery while atomically requiring the recovery generation that
/// was validated before the share payload was built.
pub(crate) fn record_delivery_for_committed_vote(
    db: &VotingDb,
    scope: &ShareOperationScope,
    params: &ShareDeliveryRecordParams<'_>,
    expected_commitment_bundle_json: &str,
    expected_nullifier: &[u8; 32],
) -> Result<(u64, [u8; 32]), VotingError> {
    let target_count = persisted_delivery_target_count(params)?;
    let submit_at = db.record_share_delivery_for_vote_generation(
        scope.wallet_id(),
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        &params.submission.accepted_urls,
        &params.submission.ambiguous_urls,
        target_count,
        expected_nullifier,
        params.submit_at,
        expected_commitment_bundle_json,
    )?;
    Ok((submit_at, *expected_nullifier))
}

fn persisted_delivery_target_count(
    params: &ShareDeliveryRecordParams<'_>,
) -> Result<u32, VotingError> {
    u32::try_from(params.submission.target_count).map_err(|_| VotingError::InvalidInput {
        message: format!(
            "target_count {} does not fit u32",
            params.submission.target_count
        ),
    })
}

#[cfg(test)]
pub(crate) fn record_delivery(
    db: &VotingDb,
    params: &ShareDeliveryRecordParams<'_>,
) -> Result<u64, VotingError> {
    record_delivery_impl(db, params)
}

/// Seeds complete helper-delivery metadata for integration-test fixtures.
///
/// This bypasses network dispatch and is unavailable without the
/// `test-fixtures` feature. Production callers must use
/// [`crate::vote::CommittedVote::submit_share_to_helpers`].
#[cfg(feature = "test-fixtures")]
#[doc(hidden)]
#[allow(clippy::too_many_arguments)]
pub fn record_delivery_fixture(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    accepted_urls: &[String],
    ambiguous_urls: &[String],
    target_count: usize,
    submit_at: u64,
) -> Result<(), VotingError> {
    let submission = ShareSubmissionReport {
        accepted_urls: accepted_urls.to_vec(),
        ambiguous_urls: ambiguous_urls.to_vec(),
        target_count,
    };
    record_delivery_impl(
        db,
        &ShareDeliveryRecordParams {
            round_id,
            bundle_index,
            proposal_id,
            share_index,
            submission: &submission,
            submit_at,
        },
    )
    .map(|_| ())
}

/// Writes an `attempting` marker before a helper POST may be dispatched.
///
/// The helper must belong to `placement_server_urls`. A reservation starts
/// only while the number of accepted plus in-flight configured helpers is
/// below `params.target_count`; an existing helper state, a satisfied capacity,
/// or a stale generation is reported without writing a marker. The marker is
/// persisted before `Started` is returned, so dispatch can safely occur only
/// afterward.
pub(crate) fn begin_delivery_attempt_for_generation(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    generation: ShareGeneration<'_>,
    placement_server_urls: &[String],
) -> Result<crate::storage::queries::ShareAttemptReservation, VotingError> {
    db.add_attempting_server_for_generation(
        generation.scope().wallet_id(),
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        params.server_url,
        placement_server_urls,
        params.target_count,
        ShareAttemptCapacityPolicy::EnforcePlacementTarget,
        Some(generation.nullifier()),
    )
}

/// Journals a POST for a share record that recovery has already loaded.
///
/// Returns `false` if the helper already has delivery state or the configured
/// placement capacity is already satisfied.
#[cfg(test)]
pub(crate) fn begin_existing_delivery_attempt(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    placement_server_urls: &[String],
) -> Result<bool, VotingError> {
    db.add_attempting_server(
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        params.server_url,
        placement_server_urls,
        params.target_count,
    )
}

/// Journals a recovery POST under the caller-selected placement-capacity policy.
///
/// The durable target remains `params.target_count` even when overdue or
/// interrupted recovery is explicitly allowed to reserve beyond it.
pub(crate) fn begin_existing_delivery_attempt_for_generation(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    generation: ShareGeneration<'_>,
    placement_server_urls: &[String],
    capacity_policy: ShareAttemptCapacityPolicy,
) -> Result<crate::storage::queries::ShareAttemptReservation, VotingError> {
    db.add_attempting_server_for_generation(
        generation.scope().wallet_id(),
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        params.server_url,
        placement_server_urls,
        params.target_count,
        capacity_policy,
        Some(generation.nullifier()),
    )
}

/// Persists the observed result of a journaled helper POST.
///
/// Outcome-unknown state remains excluded from ordinary delivery. Overdue
/// recovery may explicitly retry it through the duplicate-safe helper path.
#[cfg(test)]
pub(crate) fn resolve_delivery_attempt(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    outcome: ShareDeliveryAttemptOutcome,
    reset_submit_at: bool,
) -> Result<(), VotingError> {
    let scope = ShareOperationScope::capture(db);
    let nullifier = delivery_nullifier_for_scope(
        db,
        &scope,
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
    )?;
    resolve_delivery_attempt_for_generation(
        db,
        params,
        ShareGeneration::new(&scope, &nullifier),
        outcome,
        reset_submit_at,
    )
    .map(|_| ())
}

pub(crate) fn resolve_delivery_attempt_for_generation(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    generation: ShareGeneration<'_>,
    outcome: ShareDeliveryAttemptOutcome,
    reset_submit_at: bool,
) -> Result<bool, VotingError> {
    let url = [params.server_url.to_string()];
    match outcome {
        ShareDeliveryAttemptOutcome::Accepted => db.add_sent_servers_for_generation(
            generation.scope().wallet_id(),
            params.round_id,
            params.bundle_index,
            params.proposal_id,
            params.share_index,
            &url,
            Some(generation.nullifier()),
            reset_submit_at,
        ),
        ShareDeliveryAttemptOutcome::Ambiguous => db.add_ambiguous_servers_for_generation(
            generation.scope().wallet_id(),
            params.round_id,
            params.bundle_index,
            params.proposal_id,
            params.share_index,
            &url,
            reset_submit_at,
            Some(generation.nullifier()),
        ),
        ShareDeliveryAttemptOutcome::DefiniteFailure => db.remove_attempting_server_for_generation(
            generation.scope().wallet_id(),
            params.round_id,
            params.bundle_index,
            params.proposal_id,
            params.share_index,
            params.server_url,
            Some(generation.nullifier()),
        ),
    }
}

#[cfg(any(test, feature = "test-fixtures"))]
fn delivery_nullifier(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<[u8; 32], VotingError> {
    let scope = ShareOperationScope::capture(db);
    delivery_nullifier_for_scope(db, &scope, round_id, bundle_index, proposal_id, share_index)
}

fn delivery_nullifier_for_scope(
    db: &VotingDb,
    scope: &ShareOperationScope,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<[u8; 32], VotingError> {
    let fields = db.get_commitment_bundle_recovery_fields_for_wallet(
        scope.wallet_id(),
        round_id,
        bundle_index,
        proposal_id,
    )?;
    let bundle = fields
        .and_then(|(json, _)| json)
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        })?;
    nullifier_from_recovery_json(&bundle, proposal_id, share_index)
}

pub(crate) fn nullifier_from_recovery_json(
    commitment_bundle_json: &str,
    proposal_id: u32,
    share_index: u32,
) -> Result<[u8; 32], VotingError> {
    let bundle = crate::vote::parse_recovery(commitment_bundle_json)?;
    ensure_recovery_proposal(&bundle, proposal_id)?;
    let payload = recover_payload(&bundle, share_index)?;
    let primary_blind = array32("primary_blind", payload.primary_blind.clone())?;
    compute_nullifier(&bundle.vote_commitment, share_index, &primary_blind)
}

fn ensure_recovery_proposal(
    bundle: &VoteRecoveryBundle,
    proposal_id: u32,
) -> Result<(), VotingError> {
    if bundle.proposal_id != proposal_id {
        return Err(VotingError::InvalidInput {
            message: format!(
                "recovery proposal_id {} does not match requested {proposal_id}",
                bundle.proposal_id
            ),
        });
    }
    Ok(())
}

/// Lists all helper-share records for a round.
pub fn list(db: &VotingDb, round_id: &str) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    db.get_share_delegations(round_id)
}

pub(crate) fn list_for_scope(
    db: &VotingDb,
    scope: &ShareOperationScope,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    db.get_share_delegations_for_wallet(round_id, scope.wallet_id())
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn get_delegation_for_scope(
    db: &VotingDb,
    scope: &ShareOperationScope,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<Option<ShareDelegationRecord>, VotingError> {
    db.get_share_delegation_for_wallet(
        round_id,
        scope.wallet_id(),
        bundle_index,
        proposal_id,
        share_index,
    )
}

/// Lists unconfirmed helper-share records for retry and polling.
pub fn unconfirmed(
    db: &VotingDb,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    db.get_unconfirmed_delegations(round_id)
}

pub(crate) fn unconfirmed_for_scope(
    db: &VotingDb,
    scope: &ShareOperationScope,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    db.get_unconfirmed_delegations_for_wallet(round_id, scope.wallet_id())
}

/// Lists rounds with at least one unconfirmed helper share.
///
/// Each round is returned once in newest-first order. The persisted
/// `session_json` lets wallet integrations restore caller-owned round timing
/// without reading the voting database schema directly.
pub fn pending_rounds(db: &VotingDb) -> Result<Vec<PendingShareRound>, VotingError> {
    db.pending_share_rounds().map(|rounds| {
        rounds
            .into_iter()
            .map(|(round_id, session_json)| PendingShareRound {
                round_id,
                session_json,
            })
            .collect()
    })
}

/// Re-reads whether one helper-share record is durably confirmed.
pub(crate) fn is_confirmed_for_generation(
    db: &VotingDb,
    params: &ShareDeliveryAttemptParams<'_>,
    generation: ShareGeneration<'_>,
) -> Result<Option<bool>, VotingError> {
    db.share_is_confirmed_for_generation(
        generation.scope().wallet_id(),
        params.round_id,
        params.bundle_index,
        params.proposal_id,
        params.share_index,
        Some(generation.nullifier()),
    )
}

/// Re-reads whether the exact helper-share generation still owns its durable key.
pub(crate) fn is_current_generation(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    generation: ShareGeneration<'_>,
) -> Result<bool, VotingError> {
    db.share_is_confirmed_for_generation(
        generation.scope().wallet_id(),
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        Some(generation.nullifier()),
    )
    .map(|confirmed| confirmed.is_some())
}

/// Marks one helper-share record confirmed.
#[cfg(test)]
pub(crate) fn confirm(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), VotingError> {
    db.mark_share_confirmed(round_id, bundle_index, proposal_id, share_index)
}

pub(crate) fn confirm_for_generation(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    generation: ShareGeneration<'_>,
) -> Result<bool, VotingError> {
    db.mark_share_confirmed_for_generation(
        generation.scope().wallet_id(),
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        Some(generation.nullifier()),
    )
}

/// Adds helper URLs after immediate resubmission and clears a delayed schedule.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when any entry in `new_urls` fails
/// [`crate::helper::url::canonicalize_helper_base_url`]; validate helper URLs
/// before delivering over the network.
#[cfg(test)]
pub(crate) fn add_sent_servers(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), VotingError> {
    db.add_sent_servers(round_id, bundle_index, proposal_id, share_index, new_urls)
}

/// Reconstructs one helper-server payload from a persisted vote recovery bundle.
pub fn recover_payload(
    bundle: &VoteRecoveryBundle,
    share_index: u32,
) -> Result<SharePayload, VotingError> {
    recover_payloads(bundle)?
        .into_iter()
        .find(|payload| payload.enc_share.share_index == share_index)
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!("share_index {share_index} not found in vote recovery bundle"),
        })
}

/// Reconstructs all helper-server payloads from a persisted vote recovery bundle.
pub fn recover_payloads(bundle: &VoteRecoveryBundle) -> Result<Vec<SharePayload>, VotingError> {
    validate_recovery_bundle_vote_fields(bundle)?;

    let all_enc_shares = bundle
        .encrypted_shares
        .iter()
        .map(WireEncryptedShare::from)
        .collect::<Vec<_>>();
    let iter_shares: &[WireEncryptedShare] = if bundle.single_share {
        &all_enc_shares[..1.min(all_enc_shares.len())]
    } else {
        &all_enc_shares
    };
    iter_shares
        .iter()
        .enumerate()
        .map(|(idx, share)| {
            let primary_blind =
                bundle
                    .share_blinds
                    .get(idx)
                    .ok_or_else(|| VotingError::InvalidInput {
                        message: format!("missing primary blind for encrypted share index {idx}"),
                    })?;
            Ok(SharePayload {
                vote_round_id: bundle.vote_round_id.clone(),
                shares_hash: bundle.shares_hash.to_vec(),
                proposal_id: bundle.proposal_id,
                vote_decision: bundle.vote_decision,
                enc_share: share.clone(),
                tree_position: bundle.vc_tree_position,
                all_enc_shares: all_enc_shares.clone(),
                share_comms: bundle
                    .share_comms
                    .iter()
                    .map(|comm| comm.to_vec())
                    .collect(),
                primary_blind: primary_blind.to_vec(),
            })
        })
        .collect()
}

/// Reconstructs one helper-server payload from persisted recovery JSON and
/// serializes it as helper wire JSON.
pub fn recover_wire_json(
    commitment_bundle_json: &str,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String, VotingError> {
    let bundle = crate::vote::parse_recovery(commitment_bundle_json)?;
    ensure_recovery_proposal(&bundle, proposal_id)?;
    let payload = recover_payload(&bundle, share_index)?;
    payload.to_wire_json(Some(vc_tree_position), submit_at)
}

fn array32(label: &str, value: Vec<u8>) -> Result<[u8; 32], VotingError> {
    value
        .try_into()
        .map_err(|value: Vec<u8>| VotingError::Internal {
            message: format!("{label} must be 32 bytes, got {}", value.len()),
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        round::RoundParams,
        storage::{queries, VotingDb},
        types::{EncryptedShare, NoteInfo},
        vote::{serialize_recovery, VoteRecoveryBundle},
    };
    use pasta_curves::group::{Group, GroupEncoding};
    use std::sync::atomic::{AtomicBool, Ordering};

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const WALLET_ID: &str = "wallet";
    static SQLITE_BUSY_OBSERVED: AtomicBool = AtomicBool::new(false);

    fn signal_sqlite_busy(_attempt: i32) -> bool {
        SQLITE_BUSY_OBSERVED.store(true, Ordering::SeqCst);
        std::thread::sleep(std::time::Duration::from_millis(1));
        true
    }

    fn db_with_vote_recovery() -> VotingDb {
        db_with_vote_recovery_and_session(None)
    }

    fn db_with_vote_recovery_and_session(session_json: Option<&str>) -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(), session_json)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 0, 1, 2, &[0xCA; 32]).unwrap();
        let json = serialize_recovery(&recovery_bundle_fixture()).unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::named_params! {
                    ":json": json,
                    ":pos": 456i64,
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
        db
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn recovery_bundle_fixture() -> VoteRecoveryBundle {
        VoteRecoveryBundle {
            vote_round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            proposal_id: 1,
            vote_decision: 2,
            anchor_height: 123,
            vc_tree_position: 456,
            single_share: false,
            num_options: 3,
            van_nullifier: [0x10; 32],
            vote_authority_note_new: [0x11; 32],
            vote_commitment: [0x12; 32],
            proof: vec![0x13; 96],
            shares_hash: field_bytes(5),
            r_vpk: [0x15; 32],
            alpha_v: [0x16; 32],
            vote_auth_sig: [0x17; 64],
            encrypted_shares: vec![
                EncryptedShare {
                    c1: point_bytes(1),
                    c2: point_bytes(2),
                    share_index: 0,
                    plaintext_value: 5,
                    randomness: vec![0x23; 32],
                },
                EncryptedShare {
                    c1: point_bytes(3),
                    c2: point_bytes(4),
                    share_index: 1,
                    plaintext_value: 6,
                    randomness: vec![0x33; 32],
                },
            ],
            share_blinds: vec![field_bytes(1), field_bytes(2)],
            share_comms: (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
                .map(|index| field_bytes(index as u8 + 10))
                .collect(),
            batch: None,
        }
    }

    #[test]
    fn share_recovery_payload_and_nullifier_happy_path() {
        let bundle = recovery_bundle_fixture();

        let payloads = recover_payloads(&bundle).unwrap();
        let payload = recover_payload(&bundle, 1).unwrap();
        let nullifier = compute_nullifier(&bundle.vote_commitment, 1, &field_bytes(2)).unwrap();

        assert_eq!(payloads.len(), 2);
        assert_eq!(payload.vote_round_id, ROUND_ID);
        assert_eq!(payload.enc_share.share_index, 1);
        assert_eq!(payload.all_enc_shares.len(), 2);
        assert_eq!(payload.share_comms[1], field_bytes(11));
        assert_eq!(payload.primary_blind, field_bytes(2).to_vec());
        assert_eq!(nullifier.len(), 32);
    }

    #[test]
    fn recover_wire_json_uses_recovery_bundle_payload() {
        let bundle = recovery_bundle_fixture();
        let json = crate::vote::serialize_recovery(&bundle).unwrap();
        let wire_json = recover_wire_json(&json, 1, 1, 999, 123).unwrap();
        let value: serde_json::Value = serde_json::from_str(&wire_json).unwrap();
        assert_eq!(value["proposal_id"].as_u64().unwrap(), 1);
        assert_eq!(value["share_index"].as_u64().unwrap(), 1);
        assert_eq!(value["tree_position"].as_u64().unwrap(), 999);
        assert_eq!(value["submit_at"].as_u64().unwrap(), 123);
        assert_eq!(value["vote_round_id"].as_str().unwrap(), ROUND_ID);
        assert_eq!(value["enc_share"]["share_index"].as_u64().unwrap(), 1);
        assert!(
            value.get("all_enc_shares").is_none(),
            "recovered helper wire JSON does not include all_enc_shares"
        );
    }

    #[test]
    fn share_recovery_payloads_reject_invalid_vote_bounds() {
        let mut bundle = recovery_bundle_fixture();
        bundle.num_options = 1;
        assert!(recover_payloads(&bundle).is_err());

        let mut bundle = recovery_bundle_fixture();
        bundle.vote_decision = bundle.num_options;
        assert!(recover_payloads(&bundle).is_err());

        let mut bundle = recovery_bundle_fixture();
        bundle.vote_round_id = "AA".repeat(32);
        assert!(recover_payloads(&bundle).is_err());
    }

    #[test]
    fn share_tracking_apis_happy_path() {
        let db = db_with_vote_recovery();
        let initial_urls = vec!["https://helper-1.example".to_string()];
        record(&db, ROUND_ID, 0, 1, 1, &initial_urls, 99).unwrap();

        let records = list(&db, ROUND_ID).unwrap();
        let unconfirmed_records = unconfirmed(&db, ROUND_ID).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(unconfirmed_records.len(), 1);
        assert_eq!(records[0].share_index, 1);
        assert_eq!(records[0].sent_to_urls, initial_urls);
        assert!(!records[0].confirmed);

        add_sent_servers(
            &db,
            ROUND_ID,
            0,
            1,
            1,
            &["https://helper-2.example".to_string()],
        )
        .unwrap();
        let records = list(&db, ROUND_ID).unwrap();
        assert_eq!(records[0].sent_to_urls.len(), 2);
        assert_eq!(records[0].submit_at, 0);

        db.conn()
            .execute(
                "UPDATE share_delegations SET nullifier = :nullifier
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1
                   AND share_index = 1",
                rusqlite::named_params! {
                    ":nullifier": vec![0xFF_u8; 32],
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
        let err = record(&db, ROUND_ID, 0, 1, 1, &initial_urls, 99).unwrap_err();
        assert!(
            err.to_string().contains("share nullifier conflict"),
            "unexpected error: {err}"
        );

        confirm(&db, ROUND_ID, 0, 1, 1).unwrap();
        assert!(unconfirmed(&db, ROUND_ID).unwrap().is_empty());
        assert_eq!(list(&db, ROUND_ID).unwrap()[0].confirmed, true);
    }

    #[test]
    fn record_rejects_recovery_for_a_different_proposal() {
        let db = db_with_vote_recovery();
        let mut mismatched = recovery_bundle_fixture();
        mismatched.proposal_id = 2;
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = ?1
                 WHERE round_id = ?2 AND wallet_id = ?3
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::params![
                    serialize_recovery(&mismatched).unwrap(),
                    ROUND_ID,
                    WALLET_ID
                ],
            )
            .unwrap();

        let error = record(
            &db,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper.example".to_string()],
            99,
        )
        .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("recovery proposal_id 2 does not match requested 1"),
            "unexpected error: {error}"
        );
        assert!(list(&db, ROUND_ID).unwrap().is_empty());
    }

    #[test]
    fn record_derives_share_identity_after_reserving_wal_writer() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "zcash-voting-share-recovery-identity-{}-{unique}.sqlite",
            std::process::id()
        ));
        let path_string = path.to_string_lossy().into_owned();
        let db_a = VotingDb::open(&path_string).unwrap();
        db_a.set_wallet_id(WALLET_ID);
        db_a.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        db_a.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
        queries::store_vote(&db_a.conn(), ROUND_ID, WALLET_ID, 0, 1, 2, &[0xCA; 32]).unwrap();
        db_a.set_ballot_intent(ROUND_ID, 1, crate::session::Decision::Choice(2), 3)
            .unwrap();

        let initial = recovery_bundle_fixture();
        db_a.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = ?1, vc_tree_position = 456
                 WHERE round_id = ?2 AND wallet_id = ?3
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::params![serialize_recovery(&initial).unwrap(), ROUND_ID, WALLET_ID],
            )
            .unwrap();

        let mut replacement = initial.clone();
        replacement.vote_decision = 1;
        replacement.vote_commitment = field_bytes(20);
        replacement.share_blinds[1] = field_bytes(3);
        let expected_payload = recover_payload(&replacement, 1).unwrap();
        let expected_nullifier = compute_nullifier(
            &replacement.vote_commitment,
            1,
            &array32("primary_blind", expected_payload.primary_blind).unwrap(),
        )
        .unwrap();
        let initial_payload = recover_payload(&initial, 1).unwrap();
        let initial_nullifier = compute_nullifier(
            &initial.vote_commitment,
            1,
            &array32("primary_blind", initial_payload.primary_blind).unwrap(),
        )
        .unwrap();
        assert_ne!(initial_nullifier, expected_nullifier);

        let db_b = VotingDb::open(&path_string).unwrap();
        db_b.set_wallet_id(WALLET_ID);
        db_a.conn().busy_handler(Some(signal_sqlite_busy)).unwrap();

        SQLITE_BUSY_OBSERVED.store(false, Ordering::SeqCst);
        let mut writer_conn = db_b.conn();
        let writer_tx = writer_conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .unwrap();
        writer_tx
            .execute(
                "UPDATE votes SET choice = 1, commitment_bundle_json = ?1
                 WHERE round_id = ?2 AND wallet_id = ?3
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::params![
                    serialize_recovery(&replacement).unwrap(),
                    ROUND_ID,
                    WALLET_ID
                ],
            )
            .unwrap();
        writer_tx
            .execute(
                "UPDATE ballot_intent SET skipped = 0, choice = 1
                 WHERE round_id = ?1 AND wallet_id = ?2 AND proposal_id = 1",
                rusqlite::params![ROUND_ID, WALLET_ID],
            )
            .unwrap();

        let (result_tx, result_rx) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            scope.spawn(|| {
                result_tx
                    .send(record(
                        &db_a,
                        ROUND_ID,
                        0,
                        1,
                        1,
                        &["https://helper.example".to_string()],
                        99,
                    ))
                    .unwrap();
            });

            let contention_deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
            while !SQLITE_BUSY_OBSERVED.load(Ordering::SeqCst) {
                if let Ok(result) = result_rx.try_recv() {
                    drop(writer_tx);
                    panic!("share recording completed before SQLite contention: {result:?}");
                }
                if std::time::Instant::now() >= contention_deadline {
                    drop(writer_tx);
                    panic!("share recording never reached SQLite contention");
                }
                std::thread::sleep(std::time::Duration::from_millis(1));
            }

            writer_tx.commit().unwrap();
            result_rx
                .recv_timeout(std::time::Duration::from_secs(2))
                .unwrap()
                .unwrap();
        });

        let records = list(&db_a, ROUND_ID).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].nullifier, expected_nullifier);
        assert_ne!(records[0].nullifier, initial_nullifier);

        drop(writer_conn);
        drop(db_b);
        drop(db_a);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{path_string}-shm"));
        let _ = std::fs::remove_file(format!("{path_string}-wal"));
    }

    #[test]
    fn pending_rounds_return_session_context_until_all_shares_confirm() {
        let session_json = r#"{"vote_end_time":4102444800}"#;
        let db = db_with_vote_recovery_and_session(Some(session_json));
        let urls = vec!["https://helper.example".to_string()];

        record(&db, ROUND_ID, 0, 1, 0, &urls, 99).unwrap();
        record(&db, ROUND_ID, 0, 1, 1, &urls, 100).unwrap();

        assert_eq!(
            pending_rounds(&db).unwrap(),
            vec![PendingShareRound {
                round_id: ROUND_ID.to_string(),
                session_json: Some(session_json.to_string()),
            }]
        );

        db.set_wallet_id("another-wallet");
        assert!(pending_rounds(&db).unwrap().is_empty());
        db.set_wallet_id(WALLET_ID);

        confirm(&db, ROUND_ID, 0, 1, 0).unwrap();
        assert_eq!(pending_rounds(&db).unwrap().len(), 1);

        confirm(&db, ROUND_ID, 0, 1, 1).unwrap();
        assert!(pending_rounds(&db).unwrap().is_empty());
    }

    #[test]
    fn delivery_state_preserves_order_and_strongest_evidence() {
        let accepted = vec![
            "https://accepted-1.example".to_string(),
            "HTTPS://ACCEPTED-1.EXAMPLE:443/".to_string(),
        ];
        let outcome_unknown = vec![
            "https://unknown-1.example".to_string(),
            "https://accepted-1.example".to_string(),
        ];
        let in_flight = vec![
            "https://flight-1.example".to_string(),
            "https://unknown-1.example".to_string(),
            "https://accepted-1.example".to_string(),
        ];
        let mut state =
            ShareDeliveryState::from_url_lists(&accepted, &outcome_unknown, &in_flight).unwrap();

        assert_eq!(state.accepted_urls(), &["https://accepted-1.example"]);
        assert_eq!(state.outcome_unknown_urls(), &["https://unknown-1.example"]);
        assert_eq!(state.in_flight_urls(), &["https://flight-1.example"]);
        assert!(!state.begin("https://unknown-1.example/").unwrap());
        assert!(state.begin("https://flight-2.example").unwrap());

        state
            .mark_outcome_unknown("https://flight-2.example")
            .unwrap();
        state.mark_accepted("https://unknown-1.example").unwrap();
        state
            .mark_definite_failure("https://flight-1.example")
            .unwrap();
        state
            .merge_persisted_report(
                &["https://accepted-2.example".to_string()],
                &[
                    "https://accepted-1.example".to_string(),
                    "https://unknown-2.example".to_string(),
                ],
            )
            .unwrap();

        assert_eq!(
            state.accepted_urls(),
            &[
                "https://accepted-1.example",
                "https://unknown-1.example",
                "https://accepted-2.example",
            ]
        );
        assert_eq!(
            state.outcome_unknown_urls(),
            &["https://flight-2.example", "https://unknown-2.example",]
        );
        assert!(state.in_flight_urls().is_empty());
    }

    #[test]
    fn share_policy_re_exports_are_callable() {
        assert_eq!(policy::share_submission_target_count(3), 2);
        assert_eq!(policy::SHARE_HELPER_TARGET_COUNT_CAP, 10);
        assert_eq!(policy::SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, 12);
        assert_eq!(policy::SHARE_HELPER_INITIAL_MAX_FRACTION_NUMERATOR, 3);
        assert_eq!(policy::SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR, 4);
        assert_eq!(policy::SHARE_SUBMIT_AT_MAX_DELAY_SECONDS, 100 * 60 * 60);
        assert_eq!(
            policy::scheduled_share_submit_at_from_random_unit(10, 100, Some(10), false, 0.0)
                .unwrap(),
            10
        );
    }

    fn field_bytes(value: u8) -> [u8; 32] {
        let mut bytes = [0u8; 32];
        bytes[0] = value;
        bytes
    }

    fn point_bytes(multiplier: u64) -> Vec<u8> {
        (pallas::Point::generator() * pallas::Scalar::from(multiplier))
            .to_bytes()
            .to_vec()
    }
}
