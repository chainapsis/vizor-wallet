//! Helper-share confirmation and recovery loop.
//!
//! [`share_policy`](crate::share_policy) decides *when* a share should be
//! checked or retried, and [`share`](crate::share) stores the result. This
//! module is the part in between: it asks helpers what they know, decides what
//! their answers mean, and drives the durable state forward.
//!
//! Wallets should call [`track_pending_shares`] on a timer and keep only the
//! lifecycle concerns — the timer itself, app lock, and round expiry — on their
//! side, surfaced through the `cancel` callback.
//!
//! # Trust model
//!
//! Helper responses are authenticated only by the host transport's connection
//! to configured endpoints. They are not chain proofs. This module requires
//! matching `confirmed` replies from two distinct currently configured helpers
//! before persisting confirmation when the fleet has at least two members. A
//! one-helper fleet necessarily uses its only configured helper. The configured
//! fleet is therefore the trusted quorum for the share nullifier's global
//! on-chain state.

use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock, Mutex, Weak},
    time::{Duration, Instant},
};

use crate::{
    helper::client::HelperClient,
    round::VotingDb,
    share,
    share_policy::{
        effective_share_submission_target_count, is_share_ready_for_status_check,
        is_share_resubmission_window_open, next_tracking_delay_seconds, should_resubmit_share,
        ShareSubmissionPlan, ShareTimingPolicy,
    },
    types::{ShareDelegationRecord, VotingError},
};

/// Maximum helper status requests in flight for one share.
pub const SHARE_STATUS_MAX_CONCURRENT_POLLS: usize = 4;
/// Maximum wall-clock time one share may consume while seeking confirmation.
pub const SHARE_STATUS_POLL_BUDGET_MILLISECONDS: u64 = 10_000;
/// Interval for observing caller cancellation while helper tasks are pending.
const SHARE_STATUS_CANCEL_CHECK_MILLISECONDS: u64 = 50;
/// Interval for observing caller cancellation while waiting for a share lock.
const SHARE_OPERATION_LOCK_CANCEL_CHECK_MILLISECONDS: u64 = 50;

const _: () = assert!(SHARE_STATUS_MAX_CONCURRENT_POLLS > 0);
const _: () = assert!(SHARE_STATUS_POLL_BUDGET_MILLISECONDS > 0);
const _: () = assert!(SHARE_STATUS_CANCEL_CHECK_MILLISECONDS > 0);
const _: () = assert!(SHARE_OPERATION_LOCK_CANCEL_CHECK_MILLISECONDS > 0);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct ShareOperationLockKey {
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
}

static SHARE_OPERATION_LOCKS: LazyLock<
    Mutex<HashMap<ShareOperationLockKey, Weak<tokio::sync::Mutex<()>>>>,
> = LazyLock::new(|| Mutex::new(HashMap::new()));

async fn lock_share_operation(
    scope: &share::ShareOperationScope,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<tokio::sync::OwnedMutexGuard<()>, VotingError> {
    let key = ShareOperationLockKey {
        wallet_id: scope.wallet_id().to_string(),
        round_id: round_id.to_string(),
        bundle_index,
        proposal_id,
        share_index,
    };
    let lock = {
        let mut locks = SHARE_OPERATION_LOCKS
            .lock()
            .map_err(|e| VotingError::Internal {
                message: format!("helper-share operation lock registry poisoned: {e}"),
            })?;
        locks.retain(|_, lock| lock.strong_count() > 0);
        if let Some(lock) = locks.get(&key).and_then(Weak::upgrade) {
            lock
        } else {
            let lock = Arc::new(tokio::sync::Mutex::new(()));
            locks.insert(key, Arc::downgrade(&lock));
            lock
        }
    };
    Ok(lock.lock_owned().await)
}

async fn lock_share_operation_or_cancel(
    scope: &share::ShareOperationScope,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<Option<tokio::sync::OwnedMutexGuard<()>>, VotingError> {
    let lock = lock_share_operation(scope, round_id, bundle_index, proposal_id, share_index);
    tokio::pin!(lock);

    loop {
        if cancel() {
            return Ok(None);
        }
        tokio::select! {
            biased;
            result = &mut lock => return result.map(Some),
            _ = tokio::time::sleep(Duration::from_millis(
                SHARE_OPERATION_LOCK_CANCEL_CHECK_MILLISECONDS,
            )) => {}
        }
    }
}

/// Identifies one helper share within a round.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ShareKey {
    /// Index of the committed vote bundle that owns the share.
    pub bundle_index: u32,
    /// Proposal whose vote commitment contains the share.
    pub proposal_id: u32,
    /// Position of the share within that proposal's commitment.
    pub share_index: u32,
}

impl ShareKey {
    fn of(share: &ShareDelegationRecord) -> Self {
        Self {
            bundle_index: share.bundle_index,
            proposal_id: share.proposal_id,
            share_index: share.share_index,
        }
    }
}

/// What the timing policy says should happen to a share right now.
///
/// This replaces the historical bitmask, which forced every wallet to hardcode
/// `flags & 1` / `flags & 2` against constants it could not see.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct ShareTrackingFlags {
    /// Enough time has passed since submission to ask helpers about the share.
    pub ready_for_status_check: bool,
    /// The share has gone unconfirmed long enough to warrant another helper.
    pub overdue_for_retry: bool,
}

impl ShareTrackingFlags {
    /// Returns true when this share needs no work in the current pass.
    pub fn is_idle(&self) -> bool {
        !self.ready_for_status_check && !self.overdue_for_retry
    }
}

/// Returns the tracking flags for one share.
///
/// `vote_end_time_seconds` is optional because some rounds have no usable end
/// time yet. Without it a share can still be status-checked but is never
/// treated as overdue: the overdue threshold is a fraction of the remaining
/// vote window, so with no window there is nothing to measure against, and
/// guessing would resubmit shares that are merely young.
pub fn share_tracking_flags(
    share: &ShareDelegationRecord,
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
    policy: ShareTimingPolicy,
) -> ShareTrackingFlags {
    ShareTrackingFlags {
        ready_for_status_check: is_share_ready_for_status_check(share, now_seconds, policy),
        overdue_for_retry: vote_end_time_seconds
            .is_some_and(|vote_end| should_resubmit_share(share, now_seconds, vote_end, policy)),
    }
}

/// One helper contacted during recovery and the share it accepted or may have
/// accepted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResubmittedShare {
    /// Durable identity of the recovered share.
    pub share: ShareKey,
    /// Canonical URL of the helper contacted by recovery.
    pub server_url: String,
}

/// Results of an initial fan-out across helper servers.
///
/// [`submit_share_to_helpers`] journals every attempt and outcome before this
/// report is returned, so callers must not treat it as pending persistence.
/// Outcome-unknown attempts do not count toward `target_count` because the
/// current status endpoint reports confirmation evidence, not possession. A
/// completed ambiguous attempt remains overdue-only; a process-interrupted
/// attempt may be retried once per pass through the duplicate-safe endpoint.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShareSubmissionReport {
    /// Helpers that definitively accepted the share.
    pub accepted_urls: Vec<String>,
    /// Helpers that may have accepted the share, including attempts interrupted
    /// before their outcome was durably classified.
    pub ambiguous_urls: Vec<String>,
    /// Desired number of definite helper placements.
    pub target_count: usize,
}

/// A committed share and its previously computed placement plan.
///
/// The round, bundle, proposal, nullifier, wire payload, target count, and
/// schedule are deliberately absent: [`crate::vote::CommittedVote`] derives
/// them from its persisted commitment and the selected plan, preventing a
/// caller from journaling one share while sending another.
#[derive(Clone, Copy, Debug)]
pub struct ShareSubmissionRequest<'a> {
    /// Domain index of the committed share payload to submit.
    pub share_index: u32,
    /// Plan returned by the helper-share planner for this payload.
    pub plan: &'a ShareSubmissionPlan,
    /// Complete current helper fleet at delivery time.
    ///
    /// The fleet must be nonempty, canonicalizable, and canonically distinct;
    /// every planned target must belong to it and the plan's target count must
    /// match the policy target derived from its size. It may differ from the
    /// planning-time fleet only when the stored plan remains valid under those
    /// rules.
    pub configured_server_urls: &'a [String],
    /// Current Unix time used only for process-local helper health ordering.
    pub now_seconds: u64,
}

/// A freshly built share plus the durable identity used internally to journal each POST.
#[derive(Clone, Copy, Debug)]
pub(crate) struct InitialShareSubmissionParams<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub share_wire_json: &'a str,
    #[cfg(test)]
    pub planned_servers: &'a [String],
    #[cfg(test)]
    pub fallback_servers: &'a [String],
    pub target_count: usize,
    pub submit_at: u64,
    pub now_seconds: u64,
}

/// What one tracking pass did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShareTrackingReport {
    /// Shares durably marked confirmed during this pass.
    pub confirmed: Vec<ShareKey>,
    /// Shares that reached a new helper during this pass.
    pub resubmitted: Vec<ResubmittedShare>,
    /// Recovery attempts whose helper acceptance outcome remains unknown.
    pub ambiguous: Vec<ResubmittedShare>,
    /// Shares skipped because their recovery material is missing.
    ///
    /// These cannot be repaired by retrying; a wallet should surface them
    /// rather than spin on them.
    pub unrecoverable: Vec<ShareKey>,
    /// True when the pass stopped early because `cancel` fired.
    pub cancelled: bool,
    /// Seconds to wait before the next pass, or `None` when nothing is pending.
    pub next_delay_seconds: Option<u64>,
}

/// Inputs for a focused confirmation check over one durable helper share.
///
/// Unlike [`ShareTrackingParams`], this request never replenishes or
/// resubmits a share and does not walk other shares in the round. It is meant
/// for a foreground completion gate that needs the same configured-helper
/// quorum and generation binding as [`track_pending_shares`].
pub struct ShareConfirmationParams<'a> {
    /// Round that owns `share`.
    pub round_id: &'a str,
    /// Exact durable share key to check.
    pub share: ShareKey,
    /// Complete helper fleet currently configured for this wallet.
    pub configured_server_urls: &'a [String],
    /// Unix time used for process-local helper health ordering.
    pub now_seconds: u64,
}

/// Result of one focused helper-share confirmation check.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ShareConfirmationReport {
    /// True when this call observed the configured-helper quorum and durably
    /// confirmed the exact share generation, or found it already confirmed.
    pub confirmed: bool,
    /// True when caller cancellation stopped the check.
    pub cancelled: bool,
}

/// Inputs for one tracking pass.
pub struct ShareTrackingParams<'a> {
    /// Round whose unconfirmed shares should be tracked.
    pub round_id: &'a str,
    /// Helper URLs currently configured for this wallet.
    ///
    /// A share's persisted `sent_to_urls` is intersected with this list, so a
    /// helper dropped from config is neither polled nor counted.
    /// The list must be nonempty, canonicalizable, and canonically distinct.
    pub configured_server_urls: &'a [String],
    /// Unix time at the start of this tracking pass.
    pub now_seconds: u64,
    /// Unix vote-end time used to derive retry and cutoff windows.
    ///
    /// Without it, tracking can poll but does not classify shares as overdue.
    pub vote_end_time_seconds: Option<u64>,
    /// Timing thresholds used for polling, retry, and cutoff decisions.
    pub policy: ShareTimingPolicy,
    /// Source of CSPRNG bytes for randomized resubmission order.
    ///
    /// Callers supply this so tests can be deterministic; production wallets
    /// pass [`os_random_bytes`].
    pub random_bytes: &'a (dyn Fn(usize) -> Vec<u8> + Send + Sync),
}

/// Fills `len` bytes from the operating system CSPRNG.
pub fn os_random_bytes(len: usize) -> Vec<u8> {
    use rand::RngCore as _;

    let mut bytes = vec![0u8; len];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes
}

mod configured_fleet;
mod confirmation;
mod initial_delivery;
mod recovery;

use configured_fleet::ConfiguredHelperFleet;
#[cfg(test)]
use confirmation::{finish_expired_polls, poll_share_helpers_with_budget};
use confirmation::{poll_share_helpers, ShareStatusOutcome};
pub(crate) use initial_delivery::submit_committed_share_to_helpers;
#[cfg(test)]
use initial_delivery::submit_share_to_helpers;
use recovery::{
    resubmit_to_next_helper, ResubmissionCandidates, ResubmissionSchedule, ResubmitOutcome,
    ResubmitRequest,
};

/// Polls and, on quorum, confirms exactly one durable helper share.
///
/// This focused path intentionally bypasses the normal status-check grace: a
/// foreground flow calls it only after the vote transaction is confirmed and
/// the immediate share has been delivered. It still enforces the same
/// configured-fleet trust boundary, health ordering, four-request concurrency
/// limit, ten-second total status budget, cancellable per-share lock, and
/// generation-qualified confirmation write as [`track_pending_shares`]. It
/// never performs recovery POSTs and never inspects unrelated shares.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when the helper fleet is invalid or
/// the requested durable share does not exist. Storage errors are returned
/// unchanged.
pub async fn confirm_pending_share(
    db: &VotingDb,
    params: &ShareConfirmationParams<'_>,
    client: &HelperClient,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<ShareConfirmationReport, VotingError> {
    let scope = share::ShareOperationScope::capture(db);
    let configured_fleet = ConfiguredHelperFleet::new(params.configured_server_urls)?;
    let loaded_share = share::get_delegation_for_scope(
        db,
        &scope,
        params.round_id,
        params.share.bundle_index,
        params.share.proposal_id,
        params.share.share_index,
    )?
    .ok_or_else(|| VotingError::InvalidInput {
        message: format!(
            "helper share not found: round={}, bundle={}, proposal={}, share={}",
            params.round_id,
            params.share.bundle_index,
            params.share.proposal_id,
            params.share.share_index
        ),
    })?;

    let Some(_operation_guard) = lock_share_operation_or_cancel(
        &scope,
        params.round_id,
        params.share.bundle_index,
        params.share.proposal_id,
        params.share.share_index,
        cancel,
    )
    .await?
    else {
        return Ok(ShareConfirmationReport {
            cancelled: true,
            ..ShareConfirmationReport::default()
        });
    };

    let Some(share) = share::get_delegation_for_scope(
        db,
        &scope,
        params.round_id,
        params.share.bundle_index,
        params.share.proposal_id,
        params.share.share_index,
    )?
    .filter(|share| share.nullifier == loaded_share.nullifier) else {
        return Ok(ShareConfirmationReport::default());
    };

    poll_and_confirm_share(
        db,
        &scope,
        params.round_id,
        &share,
        configured_fleet.urls(),
        client,
        params.now_seconds,
        cancel,
    )
    .await
}

async fn poll_and_confirm_share(
    db: &VotingDb,
    scope: &share::ShareOperationScope,
    round_id: &str,
    share: &ShareDelegationRecord,
    configured_urls: &[String],
    client: &HelperClient,
    now_seconds: u64,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<ShareConfirmationReport, VotingError> {
    if share.confirmed {
        return Ok(ShareConfirmationReport {
            confirmed: true,
            cancelled: false,
        });
    }

    let share_id = hex::encode(&share.nullifier);
    match poll_share_helpers(
        client,
        round_id,
        &share_id,
        configured_urls,
        now_seconds,
        cancel,
    )
    .await
    {
        ShareStatusOutcome::Cancelled => Ok(ShareConfirmationReport {
            confirmed: false,
            cancelled: true,
        }),
        ShareStatusOutcome::ConfiguredHelperQuorumNotObserved => {
            Ok(ShareConfirmationReport::default())
        }
        ShareStatusOutcome::ConfiguredHelperQuorumObserved => {
            let generation = share::ShareGeneration::new(scope, &share.nullifier);
            let confirmed = share::confirm_for_generation(
                db,
                round_id,
                share.bundle_index,
                share.proposal_id,
                share.share_index,
                generation,
            )?;
            Ok(ShareConfirmationReport {
                confirmed,
                cancelled: false,
            })
        }
    }
}

/// Runs one confirm-or-retry pass over a round's unconfirmed shares.
///
/// For each unconfirmed share, in persisted order:
///
/// 1. Compute [`ShareTrackingFlags`] and the configured definite placement.
/// 2. When ready, poll the current configured fleet for global on-chain
///    confirmation. `pending` never proves helper possession, so ambiguous
///    attempts remain ambiguous.
/// 3. When two distinct configured helpers report confirmation—or the only
///    configured helper in a one-helper fleet does—persist it with
///    [`share::confirm`] and move on.
/// 4. Before the vote-end cutoff, when overdue or below the desired placement,
///    walk a health-aware randomized resubmission order and durably retain each
///    attempt before contacting another helper. Early replenishment preserves
///    the persisted `submit_at`, preferring untried helpers before interrupted
///    attempts. Explicit ambiguity remains overdue-only. Overdue recovery uses
///    zero so helpers act immediately and may also retry ambiguous or accepted
///    helpers, converging through helper-side duplicate detection.
///
/// `cancel` is polled between every helper and every share. When it fires the
/// pass returns what it has already durably recorded with
/// [`ShareTrackingReport::cancelled`] set; nothing is rolled back, because
/// every effect recorded so far actually happened.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when the configured fleet is empty,
/// contains canonical duplicates, or any URL fails
/// [`crate::helper::url::canonicalize_helper_base_url`]. The complete trust
/// boundary is validated before storage or network effects. Storage failures
/// are returned unchanged.
///
pub async fn track_pending_shares(
    db: &VotingDb,
    params: &ShareTrackingParams<'_>,
    client: &HelperClient,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<ShareTrackingReport, VotingError> {
    let started_at = Instant::now();
    track_pending_shares_with_elapsed(db, params, client, cancel, &|| {
        started_at.elapsed().as_secs()
    })
    .await
}

async fn track_pending_shares_with_elapsed(
    db: &VotingDb,
    params: &ShareTrackingParams<'_>,
    client: &HelperClient,
    cancel: &(dyn Fn() -> bool + Send + Sync),
    elapsed_seconds: &(dyn Fn() -> u64 + Send + Sync),
) -> Result<ShareTrackingReport, VotingError> {
    let scope = share::ShareOperationScope::capture(db);
    // Validate the complete trust boundary before reading or mutating storage
    // and before dispatching any helper request.
    let configured_fleet = ConfiguredHelperFleet::new(params.configured_server_urls)?;
    let configured_urls = configured_fleet.urls();
    let mut report = ShareTrackingReport::default();

    for loaded_share in share::unconfirmed_for_scope(db, &scope, params.round_id)? {
        if cancel() {
            report.cancelled = true;
            break;
        }
        let Some(_operation_guard) = lock_share_operation_or_cancel(
            &scope,
            params.round_id,
            loaded_share.bundle_index,
            loaded_share.proposal_id,
            loaded_share.share_index,
            cancel,
        )
        .await?
        else {
            report.cancelled = true;
            break;
        };
        let Some(share) = share::unconfirmed_for_scope(db, &scope, params.round_id)?
            .into_iter()
            .find(|share| {
                share.bundle_index == loaded_share.bundle_index
                    && share.proposal_id == loaded_share.proposal_id
                    && share.share_index == loaded_share.share_index
                    && share.nullifier == loaded_share.nullifier
            })
        else {
            continue;
        };

        // Only configured helpers count toward current placement or polling.
        let configured_definite_acceptance_urls = share
            .sent_to_urls
            .iter()
            .filter(|url| configured_fleet.contains(url))
            .cloned()
            .collect::<Vec<_>>();
        // An `attempting` marker left by an interrupted process is an unknown
        // POST outcome. Keep it separate from explicit ambiguity so recovery
        // can reconcile the crash marker even without vote-end timing.
        let configured_outcome_unknown_urls = share
            .ambiguous_urls
            .iter()
            .filter(|url| configured_fleet.contains(url))
            .cloned()
            .collect::<Vec<_>>();
        let configured_interrupted_attempt_urls = share
            .attempting_urls
            .iter()
            .filter(|url| configured_fleet.contains(url))
            .cloned()
            .collect::<Vec<_>>();
        let mut delivery_state = share::ShareDeliveryState::from_url_lists(
            &configured_definite_acceptance_urls,
            &configured_outcome_unknown_urls,
            &configured_interrupted_attempt_urls,
        )?;
        // Network failures that are definitely known not to have placed a
        // share are not durable state, but they must still be remembered for
        // this pass so filling a multi-helper deficit never contacts the same
        // failing endpoint again.
        let mut attempted_urls_this_pass = Vec::new();
        let target_count =
            effective_share_submission_target_count(share.target_count, configured_fleet.len());
        let mut current_time = params.now_seconds.saturating_add(elapsed_seconds());
        let mut flags = share_tracking_flags(
            &share,
            current_time,
            params.vote_end_time_seconds,
            params.policy,
        );
        if flags.is_idle()
            && delivery_state.accepted_urls().len() >= target_count
            && configured_interrupted_attempt_urls.is_empty()
        {
            continue;
        }

        if flags.ready_for_status_check {
            let confirmation = poll_and_confirm_share(
                db,
                &scope,
                params.round_id,
                &share,
                configured_urls,
                client,
                current_time,
                cancel,
            )
            .await?;
            if confirmation.cancelled {
                report.cancelled = true;
                break;
            }
            if confirmation.confirmed {
                report.confirmed.push(ShareKey::of(&share));
                continue;
            }
        }

        // A status walk can consume enough time to cross an overdue or cutoff
        // boundary. Refresh before making any recovery decision.
        current_time = params.now_seconds.saturating_add(elapsed_seconds());
        flags = share_tracking_flags(
            &share,
            current_time,
            params.vote_end_time_seconds,
            params.policy,
        );

        let resubmission_window_open = params.vote_end_time_seconds.is_none_or(|vote_end| {
            is_share_resubmission_window_open(current_time, vote_end, params.policy)
        });
        let under_placed = delivery_state.accepted_urls().len() < target_count;
        let reconcile_interrupted_only = !flags.overdue_for_retry
            && !under_placed
            && !configured_interrupted_attempt_urls.is_empty();
        if resubmission_window_open
            && (flags.overdue_for_retry
                || under_placed
                || !configured_interrupted_attempt_urls.is_empty())
        {
            let schedule = if flags.overdue_for_retry {
                ResubmissionSchedule::Immediate
            } else {
                ResubmissionSchedule::PreserveScheduledSubmitAt(share.submit_at)
            };
            loop {
                let resubmission = resubmit_to_next_helper(
                    db,
                    &scope,
                    params,
                    client,
                    &ResubmitRequest {
                        share: &share,
                        configured_urls,
                        definite_acceptance_urls: delivery_state.accepted_urls(),
                        ambiguous_urls: &configured_outcome_unknown_urls,
                        interrupted_attempt_urls: &configured_interrupted_attempt_urls,
                        target_count,
                        schedule,
                        candidates: if reconcile_interrupted_only {
                            ResubmissionCandidates::InterruptedOnly
                        } else {
                            ResubmissionCandidates::FullRecoveryOrder
                        },
                    },
                    &mut attempted_urls_this_pass,
                    cancel,
                    elapsed_seconds,
                )
                .await?;
                if matches!(resubmission.outcome, ResubmitOutcome::StaleGeneration) {
                    break;
                }
                for server_url in resubmission.outcome_unknown_urls {
                    let newly_outcome_unknown =
                        !delivery_state.outcome_unknown_urls().contains(&server_url);
                    delivery_state.mark_outcome_unknown(&server_url)?;
                    if newly_outcome_unknown {
                        report.ambiguous.push(ResubmittedShare {
                            share: ShareKey::of(&share),
                            server_url,
                        });
                    }
                }
                match resubmission.outcome {
                    ResubmitOutcome::DefinitelyAcceptedByHelper(server_url) => {
                        // An overdue re-POST can convert an outcome-unknown
                        // helper into a definite placement.
                        let newly_definite_placement =
                            !delivery_state.accepted_urls().contains(&server_url);
                        delivery_state.mark_accepted(&server_url)?;
                        report.resubmitted.push(ResubmittedShare {
                            share: ShareKey::of(&share),
                            server_url,
                        });
                        if !reconcile_interrupted_only
                            && (delivery_state.accepted_urls().len() >= target_count
                                || !newly_definite_placement)
                        {
                            break;
                        }
                    }
                    ResubmitOutcome::Unrecoverable => {
                        report.unrecoverable.push(ShareKey::of(&share));
                        break;
                    }
                    ResubmitOutcome::AwaitingVcPosition
                    | ResubmitOutcome::StaleGeneration
                    | ResubmitOutcome::NoDefiniteAcceptanceObserved
                    | ResubmitOutcome::CutoffReached => break,
                    ResubmitOutcome::Cancelled => {
                        report.cancelled = true;
                        break;
                    }
                }
            }
            if report.cancelled {
                break;
            }
        }
    }

    // Recompute from storage so explicit confirmations made by another task
    // during this pass do not remain in the next-delay calculation.
    let current_time = params.now_seconds.saturating_add(elapsed_seconds());
    report.next_delay_seconds = next_tracking_delay_seconds(
        &share::unconfirmed_for_scope(db, &scope, params.round_id)?,
        current_time,
        params.policy,
    );
    Ok(report)
}

fn dedupe_preserving_order(urls: impl Iterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut ordered = Vec::new();
    for url in urls {
        if seen.insert(url.clone()) {
            ordered.push(url);
        }
    }
    ordered
}

#[cfg(test)]
mod tests;
