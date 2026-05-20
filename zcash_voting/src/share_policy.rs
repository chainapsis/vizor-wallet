use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::types::{ShareDelegationRecord, VotingError};

/// Seconds to wait after helper submission time before polling share status.
pub const SHARE_STATUS_CHECK_GRACE_SECONDS: u64 = 10;
/// Minimum seconds before an unconfirmed share is considered overdue.
pub const SHARE_MIN_OVERDUE_THRESHOLD_SECONDS: u64 = 30;
/// Maximum seconds before an unconfirmed share is considered overdue.
pub const SHARE_MAX_OVERDUE_THRESHOLD_SECONDS: u64 = 60 * 60;
/// Seconds near the vote end when resubmission should stop.
pub const SHARE_RESUBMIT_CUTOFF_SECONDS: u64 = 10;

/// Pure timing knobs for helper-share scheduling and recovery.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareTimingPolicy {
    pub status_check_grace_seconds: u64,
    pub min_overdue_threshold_seconds: u64,
    pub max_overdue_threshold_seconds: u64,
    pub resubmit_cutoff_seconds: u64,
}

impl Default for ShareTimingPolicy {
    fn default() -> Self {
        Self {
            status_check_grace_seconds: SHARE_STATUS_CHECK_GRACE_SECONDS,
            min_overdue_threshold_seconds: SHARE_MIN_OVERDUE_THRESHOLD_SECONDS,
            max_overdue_threshold_seconds: SHARE_MAX_OVERDUE_THRESHOLD_SECONDS,
            resubmit_cutoff_seconds: SHARE_RESUBMIT_CUTOFF_SECONDS,
        }
    }
}

/// Planned helper-share submission values that SDKs can apply to payloads.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareSubmissionPlan {
    /// Unix seconds when helpers should submit the share, or 0 for immediate.
    pub submit_at: u64,
    /// Number of helpers each share should reach.
    pub target_count: u64,
    /// Deterministic targets selected from the caller-provided server order.
    pub target_servers: Vec<String>,
}

/// Counts shares by their recovery status.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareTrackingSummary {
    pub total: u64,
    pub confirmed: u64,
    pub waiting: u64,
    pub ready: u64,
    pub overdue: u64,
}

impl ShareTrackingSummary {
    pub fn has_shares(&self) -> bool {
        self.total > 0
    }
}

/// Return the time recovery should use as the share's base time.
///
/// Delayed shares use `submit_at`; immediate shares use `created_at`.
pub fn share_recovery_base_time(share: &ShareDelegationRecord) -> u64 {
    if share.submit_at > 0 {
        share.submit_at
    } else {
        share.created_at
    }
}

/// Return true once a helper has had enough time to process this share.
pub fn is_share_ready_for_status_check(
    share: &ShareDelegationRecord,
    now_seconds: u64,
    policy: ShareTimingPolicy,
) -> bool {
    if share.confirmed {
        return false;
    }
    now_seconds >= share_recovery_base_time(share).saturating_add(policy.status_check_grace_seconds)
}

/// Return the bounded overdue threshold for a share.
///
/// The threshold is one quarter of the remaining vote window from the share's
/// base time, bounded by the policy's minimum and maximum seconds.
pub fn overdue_threshold_seconds(
    share: &ShareDelegationRecord,
    vote_end_time_seconds: u64,
    policy: ShareTimingPolicy,
) -> u64 {
    let base_time = share_recovery_base_time(share);
    let remaining_window = vote_end_time_seconds.saturating_sub(base_time);
    let threshold = remaining_window / 4;
    let max_threshold = policy
        .max_overdue_threshold_seconds
        .max(policy.min_overdue_threshold_seconds);
    threshold
        .max(policy.min_overdue_threshold_seconds)
        .min(max_threshold)
}

/// Return true when a pending share should be retried immediately.
pub fn should_resubmit_share(
    share: &ShareDelegationRecord,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    policy: ShareTimingPolicy,
) -> bool {
    if share.confirmed {
        return false;
    }
    let base_time = share_recovery_base_time(share);
    let retry_at = base_time.saturating_add(overdue_threshold_seconds(
        share,
        vote_end_time_seconds,
        policy,
    ));
    now_seconds >= retry_at
        && vote_end_time_seconds > now_seconds.saturating_add(policy.resubmit_cutoff_seconds)
}

/// Return the next delay before polling share status again.
///
/// Returns `None` when all shares are confirmed. Returns `Some(0)` when at
/// least one status check or retry is already due.
pub fn next_tracking_delay_seconds(
    shares: &[ShareDelegationRecord],
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
    policy: ShareTimingPolicy,
) -> Option<u64> {
    let mut next_second: Option<u64> = None;

    for share in shares.iter().filter(|share| !share.confirmed) {
        let base_time = share_recovery_base_time(share);
        let check_at = base_time.saturating_add(policy.status_check_grace_seconds);
        next_second = min_second(next_second, check_at);

        if let Some(vote_end_time_seconds) = vote_end_time_seconds {
            let retry_at = base_time.saturating_add(overdue_threshold_seconds(
                share,
                vote_end_time_seconds,
                policy,
            ));
            if vote_end_time_seconds > retry_at.saturating_add(policy.resubmit_cutoff_seconds) {
                next_second = min_second(next_second, retry_at);
            }
        }
    }

    next_second.map(|next| next.saturating_sub(now_seconds))
}

/// Summarize share tracking state using the same precedence as wallet UIs.
pub fn summarize_share_tracking(
    shares: &[ShareDelegationRecord],
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
    policy: ShareTimingPolicy,
) -> ShareTrackingSummary {
    let mut summary = ShareTrackingSummary {
        total: shares.len() as u64,
        confirmed: 0,
        waiting: 0,
        ready: 0,
        overdue: 0,
    };

    for share in shares {
        if share.confirmed {
            summary.confirmed += 1;
        } else if match vote_end_time_seconds {
            Some(vote_end_time_seconds) => {
                should_resubmit_share(share, now_seconds, vote_end_time_seconds, policy)
            }
            None => false,
        } {
            summary.overdue += 1;
        } else if is_share_ready_for_status_check(share, now_seconds, policy) {
            summary.ready += 1;
        } else {
            summary.waiting += 1;
        }
    }

    summary
}

/// Plan the delayed helper submission time for an initial share delegation.
///
/// `vote_end_time_seconds` is required because callers should only schedule
/// share submission for an active voting session. `last_moment_buffer_seconds`
/// is optional because some round timing data cannot produce a delayed-share
/// window. When the buffer is missing, or when `single_share` is true, this
/// returns 0 and the share should be submitted immediately.
///
/// `random_unit` must be a finite sample in or near the `[0, 1)` range. Values
/// outside that range are clamped so FFI callers cannot accidentally schedule
/// after the deadline.
pub fn scheduled_share_submit_at(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    random_unit: f64,
) -> Result<u64, VotingError> {
    if single_share {
        return Ok(0);
    }

    let Some(last_moment_buffer_seconds) = last_moment_buffer_seconds else {
        return Ok(0);
    };

    let deadline = vote_end_time_seconds.saturating_sub(last_moment_buffer_seconds);
    if deadline <= now_seconds {
        return Ok(0);
    }
    if !random_unit.is_finite() {
        return Err(VotingError::InvalidInput {
            message: "random_unit must be finite".to_string(),
        });
    }

    let window_seconds = deadline - now_seconds;
    let clamped = random_unit.clamp(0.0, 0.999_999_999);
    let delay_seconds = (clamped * window_seconds as f64).floor() as u64;
    Ok(now_seconds.saturating_add(delay_seconds))
}

/// Return how many helpers should receive each initial share.
///
/// This is half of the available helpers, rounded up, and 0 when there are no
/// helpers.
pub fn share_submission_target_count(server_count: usize) -> usize {
    if server_count == 0 {
        0
    } else {
        server_count / 2 + server_count % 2
    }
}

/// Select initial helper targets from a caller-provided server order.
///
/// Callers that want random distribution should shuffle `server_urls` before
/// calling this function. The selector itself stays deterministic for tests and
/// FFI bindings.
pub fn select_share_submission_targets(server_urls: &[String], target_count: usize) -> Vec<String> {
    server_urls
        .iter()
        .take(target_count.min(server_urls.len()))
        .cloned()
        .collect()
}

/// Plan the timing and initial helper targets for a share delegation.
///
/// Missing `last_moment_buffer_seconds` means there is no delayed-share window,
/// so the returned plan uses `submit_at = 0`.
pub fn plan_share_submission(
    server_urls: &[String],
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    random_unit: f64,
) -> Result<ShareSubmissionPlan, VotingError> {
    let target_count = share_submission_target_count(server_urls.len());
    let target_servers = select_share_submission_targets(server_urls, target_count);
    let submit_at = scheduled_share_submit_at(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
        random_unit,
    )?;

    Ok(ShareSubmissionPlan {
        submit_at,
        target_count: target_count as u64,
        target_servers,
    })
}

/// Return resubmission order with untried helpers before helpers already used.
pub fn resubmission_server_order(
    configured_server_urls: &[String],
    sent_to_urls: &[String],
) -> Vec<String> {
    let sent: HashSet<&str> = sent_to_urls.iter().map(String::as_str).collect();
    configured_server_urls
        .iter()
        .filter(|server| !sent.contains(server.as_str()))
        .chain(
            configured_server_urls
                .iter()
                .filter(|server| sent.contains(server.as_str())),
        )
        .cloned()
        .collect()
}

fn min_second(current: Option<u64>, candidate: u64) -> Option<u64> {
    match current {
        Some(current) if current <= candidate => Some(current),
        _ => Some(candidate),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn share(submit_at: u64, created_at: u64) -> ShareDelegationRecord {
        ShareDelegationRecord {
            round_id: "round".to_string(),
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            sent_to_urls: vec!["https://helper.example.com".to_string()],
            nullifier: vec![7; 32],
            confirmed: false,
            submit_at,
            created_at,
        }
    }

    #[test]
    fn scheduled_submit_at_samples_before_deadline() {
        let submit_at = scheduled_share_submit_at(1_000, 2_000, Some(100), false, 0.5).unwrap();
        assert_eq!(submit_at, 1_450);
    }

    #[test]
    fn scheduled_submit_at_is_immediate_without_a_delay_window() {
        assert_eq!(
            scheduled_share_submit_at(1_000, 2_000, Some(100), true, f64::NAN).unwrap(),
            0
        );
        assert_eq!(
            scheduled_share_submit_at(1_000, 2_000, None, false, f64::NAN).unwrap(),
            0
        );
        assert_eq!(
            scheduled_share_submit_at(1_950, 2_000, Some(100), false, f64::NAN).unwrap(),
            0
        );
    }

    #[test]
    fn scheduled_submit_at_rejects_non_finite_random_unit_for_delay_window() {
        assert!(matches!(
            scheduled_share_submit_at(1_000, 2_000, Some(100), false, f64::NAN),
            Err(VotingError::InvalidInput { .. })
        ));
    }

    #[test]
    fn scheduled_submit_at_clamps_random_unit() {
        let submit_at = scheduled_share_submit_at(1_000, 2_000, Some(100), false, 1.5).unwrap();
        assert_eq!(submit_at, 1_899);

        let submit_at = scheduled_share_submit_at(1_000, 2_000, Some(100), false, -1.0).unwrap();
        assert_eq!(submit_at, 1_000);
    }

    #[test]
    fn immediate_shares_use_created_at_for_status_and_retry() {
        let share = share(0, 100);
        let policy = ShareTimingPolicy::default();

        assert_eq!(share_recovery_base_time(&share), 100);
        assert!(!is_share_ready_for_status_check(&share, 109, policy));
        assert!(is_share_ready_for_status_check(&share, 110, policy));
        assert!(!should_resubmit_share(&share, 129, 200, policy));
        assert!(should_resubmit_share(&share, 130, 200, policy));
    }

    #[test]
    fn delayed_shares_use_submit_at_for_status_and_retry() {
        let share = share(200, 100);
        let policy = ShareTimingPolicy::default();

        assert_eq!(share_recovery_base_time(&share), 200);
        assert!(!is_share_ready_for_status_check(&share, 209, policy));
        assert!(is_share_ready_for_status_check(&share, 210, policy));
        assert!(!should_resubmit_share(&share, 229, 320, policy));
        assert!(should_resubmit_share(&share, 230, 320, policy));
    }

    #[test]
    fn overdue_threshold_is_quarter_window_with_bounds() {
        let share = share(0, 100);
        let policy = ShareTimingPolicy::default();

        assert_eq!(overdue_threshold_seconds(&share, 500, policy), 100);
        assert_eq!(overdue_threshold_seconds(&share, 120, policy), 30);
        assert_eq!(overdue_threshold_seconds(&share, 20_000, policy), 3_600);
    }

    #[test]
    fn should_resubmit_respects_vote_end_cutoff() {
        let share = share(0, 100);
        let policy = ShareTimingPolicy::default();

        assert!(should_resubmit_share(&share, 130, 200, policy));
        assert!(!should_resubmit_share(&share, 190, 200, policy));
    }

    #[test]
    fn next_tracking_delay_uses_status_and_retry_times() {
        let shares = vec![share(0, 100), share(200, 100)];
        let policy = ShareTimingPolicy::default();

        assert_eq!(
            next_tracking_delay_seconds(&shares, 105, Some(320), policy),
            Some(5)
        );
        assert_eq!(
            next_tracking_delay_seconds(&shares, 130, Some(320), policy),
            Some(0)
        );
    }

    #[test]
    fn tracking_summary_uses_confirmed_overdue_ready_waiting_order() {
        let mut confirmed = share(0, 100);
        confirmed.confirmed = true;
        let overdue = share(0, 100);
        let ready = share(120, 100);
        let waiting = share(300, 100);
        let shares = vec![confirmed, overdue, ready, waiting];

        let summary =
            summarize_share_tracking(&shares, 130, Some(200), ShareTimingPolicy::default());

        assert_eq!(
            summary,
            ShareTrackingSummary {
                total: 4,
                confirmed: 1,
                waiting: 1,
                ready: 1,
                overdue: 1,
            }
        );
        assert!(summary.has_shares());
    }

    #[test]
    fn helper_target_count_is_half_rounded_up() {
        assert_eq!(share_submission_target_count(0), 0);
        assert_eq!(share_submission_target_count(1), 1);
        assert_eq!(share_submission_target_count(2), 1);
        assert_eq!(share_submission_target_count(3), 2);
        assert_eq!(share_submission_target_count(5), 3);
    }

    #[test]
    fn share_submission_plan_uses_caller_server_order() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ];

        let plan = plan_share_submission(&servers, 1_000, 2_000, Some(100), false, 0.0).unwrap();

        assert_eq!(plan.submit_at, 1_000);
        assert_eq!(plan.target_count, 2);
        assert_eq!(
            plan.target_servers,
            vec![
                "https://one.example.com".to_string(),
                "https://two.example.com".to_string()
            ]
        );
    }

    #[test]
    fn resubmission_order_tries_untried_helpers_first() {
        let configured = vec![
            "https://already.example.com".to_string(),
            "https://untried.example.com".to_string(),
        ];
        let sent = vec!["https://already.example.com".to_string()];

        assert_eq!(
            resubmission_server_order(&configured, &sent),
            vec![
                "https://untried.example.com".to_string(),
                "https://already.example.com".to_string()
            ]
        );
    }
}
