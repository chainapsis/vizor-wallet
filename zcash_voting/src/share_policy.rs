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
/// Seconds between polls when all remaining shares are ready but unconfirmed.
pub const SHARE_READY_POLL_INTERVAL_SECONDS: u64 = 15;
/// Maximum seconds to wait for a future share to become ready.
pub const SHARE_FUTURE_CHECK_MAX_DELAY_SECONDS: u64 = 30;
/// Minimum seconds to sleep before the next tracking poll.
pub const SHARE_MIN_TRACKING_DELAY_SECONDS: u64 = 3;
/// Random bytes needed to sample an initial delayed share submission time.
pub const SHARE_SUBMIT_AT_RANDOM_BYTES: usize = 8;

/// Pure timing knobs for helper-share scheduling and recovery.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareTimingPolicy {
    pub status_check_grace_seconds: u64,
    pub min_overdue_threshold_seconds: u64,
    pub max_overdue_threshold_seconds: u64,
    pub resubmit_cutoff_seconds: u64,
    pub ready_poll_interval_seconds: u64,
    pub future_check_max_delay_seconds: u64,
    pub min_tracking_delay_seconds: u64,
}

impl Default for ShareTimingPolicy {
    fn default() -> Self {
        Self {
            status_check_grace_seconds: SHARE_STATUS_CHECK_GRACE_SECONDS,
            min_overdue_threshold_seconds: SHARE_MIN_OVERDUE_THRESHOLD_SECONDS,
            max_overdue_threshold_seconds: SHARE_MAX_OVERDUE_THRESHOLD_SECONDS,
            resubmit_cutoff_seconds: SHARE_RESUBMIT_CUTOFF_SECONDS,
            ready_poll_interval_seconds: SHARE_READY_POLL_INTERVAL_SECONDS,
            future_check_max_delay_seconds: SHARE_FUTURE_CHECK_MAX_DELAY_SECONDS,
            min_tracking_delay_seconds: SHARE_MIN_TRACKING_DELAY_SECONDS,
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
    /// Helper targets selected for initial share submission.
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

/// Return the next delay after a share-status polling pass completes.
///
/// This mirrors the current wallet polling cadence. If any unconfirmed share is
/// still before its status-check grace time, the delay is the soonest future
/// check time capped by `future_check_max_delay_seconds`. If every unconfirmed
/// share is already ready, the delay is `ready_poll_interval_seconds` so callers
/// do not tight-loop on past check times. The returned delay is always at least
/// `min_tracking_delay_seconds`.
pub fn next_tracking_delay_seconds(
    shares: &[ShareDelegationRecord],
    now_seconds: u64,
    policy: ShareTimingPolicy,
) -> Option<u64> {
    let mut next_second: Option<u64> = None;
    let mut has_unconfirmed = false;

    for share in shares.iter().filter(|share| !share.confirmed) {
        has_unconfirmed = true;
        let base_time = share_recovery_base_time(share);
        let check_at = base_time.saturating_add(policy.status_check_grace_seconds);
        if check_at > now_seconds {
            next_second = min_second(next_second, check_at);
        }
    }

    if !has_unconfirmed {
        return None;
    }

    let delay_seconds = match next_second {
        Some(next) => next
            .saturating_sub(now_seconds)
            .min(policy.future_check_max_delay_seconds),
        None => policy.ready_poll_interval_seconds,
    };

    Some(delay_seconds.max(policy.min_tracking_delay_seconds))
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

/// Return the random bytes needed to sample a delayed share submission time.
///
/// `vote_end_time_seconds` is required because callers should only schedule
/// share submission for an active voting session. `last_moment_buffer_seconds`
/// is optional because some round timing data cannot produce a delayed-share
/// window. When the buffer is missing or zero, or when `single_share` is true,
/// no random bytes are needed because the share should be submitted
/// immediately.
pub fn share_submit_at_random_bytes_required(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> usize {
    if delayed_share_window_seconds(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
    )
    .is_some()
    {
        SHARE_SUBMIT_AT_RANDOM_BYTES
    } else {
        0
    }
}

/// Plan the delayed helper submission time from a caller-provided random unit.
///
/// This is useful for deterministic tests and FFI callers that already expose a
/// random sample in or near the `[0, 1)` range. Production submission paths can
/// use `scheduled_share_submit_at_from_entropy` to keep sampling policy inside
/// the crate. Values outside `[0, 1)` are clamped so callers cannot accidentally
/// schedule after the deadline.
pub fn scheduled_share_submit_at(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    random_unit: f64,
) -> Result<u64, VotingError> {
    let Some(window_seconds) = delayed_share_window_seconds(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
    ) else {
        return Ok(0);
    };
    if !random_unit.is_finite() {
        return Err(VotingError::InvalidInput {
            message: "random_unit must be finite".to_string(),
        });
    }

    let clamped = random_unit.clamp(0.0, 0.999_999_999);
    let delay_seconds = (clamped * window_seconds as f64).floor() as u64;
    Ok(now_seconds.saturating_add(delay_seconds))
}

/// Plan the delayed helper submission time using caller-provided entropy.
///
/// `submit_at_random_bytes` must contain at least
/// `share_submit_at_random_bytes_required(...)` bytes from a cryptographically
/// secure RNG. No bytes are needed when the share should be submitted
/// immediately, and callers may pass 8 bytes unconditionally for simplicity.
pub fn scheduled_share_submit_at_from_entropy(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    submit_at_random_bytes: &[u8],
) -> Result<u64, VotingError> {
    let Some(window_seconds) = delayed_share_window_seconds(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
    ) else {
        return Ok(0);
    };
    if submit_at_random_bytes.len() < SHARE_SUBMIT_AT_RANDOM_BYTES {
        return Err(VotingError::InvalidInput {
            message: format!(
                "submit_at_random_bytes must contain at least {SHARE_SUBMIT_AT_RANDOM_BYTES} bytes"
            ),
        });
    }

    let mut sample_bytes = [0u8; 8];
    sample_bytes.copy_from_slice(&submit_at_random_bytes[..8]);
    let sample = u64::from_le_bytes(sample_bytes);
    let delay_seconds = ((sample as u128 * window_seconds as u128) >> 64) as u64;
    Ok(now_seconds.saturating_add(delay_seconds))
}

fn delayed_share_window_seconds(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> Option<u64> {
    if single_share {
        return None;
    }

    let last_moment_buffer_seconds = last_moment_buffer_seconds?;
    if last_moment_buffer_seconds == 0 {
        return None;
    }

    let deadline = vote_end_time_seconds.saturating_sub(last_moment_buffer_seconds);
    if deadline <= now_seconds {
        return None;
    }

    Some(deadline - now_seconds)
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

/// Return the number of random bytes needed to shuffle a server list.
///
/// The bytes should come from a cryptographically secure RNG. The crate owns the
/// shuffle policy, while SDKs only provide entropy from their platform RNG.
pub fn share_server_order_random_bytes_required(server_count: usize) -> usize {
    server_count
        .saturating_sub(1)
        .saturating_mul(std::mem::size_of::<u64>())
}

/// Return the random bytes needed for `resubmission_server_order`.
pub fn resubmission_server_order_random_bytes_required(
    configured_server_urls: &[String],
    sent_to_urls: &[String],
) -> usize {
    let sent: HashSet<&str> = sent_to_urls.iter().map(String::as_str).collect();
    let untried_count = configured_server_urls
        .iter()
        .filter(|server| !sent.contains(server.as_str()))
        .count();
    let already_sent_count = configured_server_urls
        .iter()
        .filter(|server| sent.contains(server.as_str()))
        .count();
    share_server_order_random_bytes_required(untried_count)
        .saturating_add(share_server_order_random_bytes_required(already_sent_count))
}

/// Return a randomized helper-server order using caller-provided entropy.
///
/// `random_bytes` must contain at least
/// `share_server_order_random_bytes_required(server_urls.len())` bytes from a
/// cryptographically secure RNG. Extra bytes are ignored.
pub fn shuffled_share_server_order(
    server_urls: &[String],
    random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    let needed = share_server_order_random_bytes_required(server_urls.len());
    if random_bytes.len() < needed {
        return Err(VotingError::InvalidInput {
            message: format!(
                "server_random_bytes must contain at least {needed} bytes for {} servers",
                server_urls.len()
            ),
        });
    }

    let mut ordered = server_urls.to_vec();
    let mut offset = 0usize;
    for index in (1..ordered.len()).rev() {
        let mut sample_bytes = [0u8; 8];
        sample_bytes.copy_from_slice(&random_bytes[offset..offset + 8]);
        offset += 8;

        let sample = u64::from_le_bytes(sample_bytes);
        let swap_index = (sample % ((index + 1) as u64)) as usize;
        ordered.swap(index, swap_index);
    }
    Ok(ordered)
}

/// Select initial helper targets from a randomized server order.
///
/// Prefer this helper for production submission paths. It owns the privacy
/// sensitive randomization policy and only asks callers to provide CSPRNG bytes.
pub fn select_share_submission_targets(
    server_urls: &[String],
    target_count: usize,
    server_random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    let target_count = target_count.min(server_urls.len());
    if target_count == 0 {
        return Ok(Vec::new());
    }

    let randomized_order = shuffled_share_server_order(server_urls, server_random_bytes)?;
    Ok(select_share_submission_targets_from_order(
        &randomized_order,
        target_count,
    ))
}

/// Select initial helper targets from a caller-provided server order.
///
/// This is deterministic for tests and callers that have already made an
/// explicit ordering decision. Production submission paths should prefer
/// `select_share_submission_targets`.
pub fn select_share_submission_targets_from_order(
    server_urls: &[String],
    target_count: usize,
) -> Vec<String> {
    server_urls
        .iter()
        .take(target_count.min(server_urls.len()))
        .cloned()
        .collect()
}

/// Plan the timing and initial helper targets for a share delegation.
///
/// `server_urls` must not be empty. Missing helpers are a configuration error
/// for initial delegation, not a successful zero-target plan.
///
/// Missing or zero `last_moment_buffer_seconds` means there is no delayed-share
/// window, so the returned plan uses `submit_at = 0`. Helper targets are chosen
/// from a randomized server order using `server_random_bytes`. Callers can use
/// `share_submit_at_random_bytes_required` and
/// `share_server_order_random_bytes_required` to size the entropy inputs.
pub fn plan_share_submission(
    server_urls: &[String],
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    submit_at_random_bytes: &[u8],
    server_random_bytes: &[u8],
) -> Result<ShareSubmissionPlan, VotingError> {
    require_share_servers(server_urls)?;
    let target_count = share_submission_target_count(server_urls.len());
    let target_servers =
        select_share_submission_targets(server_urls, target_count, server_random_bytes)?;
    let submit_at = scheduled_share_submit_at_from_entropy(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
        submit_at_random_bytes,
    )?;

    Ok(ShareSubmissionPlan {
        submit_at,
        target_count: target_count as u64,
        target_servers,
    })
}

/// Plan share submission using a caller-provided helper order.
///
/// `server_urls` must not be empty. Missing helpers are a configuration error
/// for initial delegation, not a successful zero-target plan.
///
/// This is deterministic for tests and callers that have already made an
/// explicit ordering decision. Production submission paths should prefer
/// `plan_share_submission`.
pub fn plan_share_submission_from_order(
    server_urls: &[String],
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    random_unit: f64,
) -> Result<ShareSubmissionPlan, VotingError> {
    require_share_servers(server_urls)?;
    let target_count = share_submission_target_count(server_urls.len());
    let target_servers = select_share_submission_targets_from_order(server_urls, target_count);
    plan_share_submission_with_targets(
        target_count,
        target_servers,
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
        random_unit,
    )
}

fn plan_share_submission_with_targets(
    target_count: usize,
    target_servers: Vec<String>,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    random_unit: f64,
) -> Result<ShareSubmissionPlan, VotingError> {
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

fn require_share_servers(server_urls: &[String]) -> Result<(), VotingError> {
    if server_urls.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "server_urls must not be empty".to_string(),
        });
    }

    Ok(())
}

/// Return resubmission order from separately ordered helper groups.
///
/// The returned order always tries untried helpers before helpers that already
/// received the share. This is deterministic for tests and callers that have
/// already made an explicit ordering decision. Production resubmission paths
/// should prefer `resubmission_server_order`.
pub fn resubmission_server_order_from_groups(
    untried_server_urls: &[String],
    already_sent_server_urls: &[String],
) -> Vec<String> {
    untried_server_urls
        .iter()
        .chain(already_sent_server_urls.iter())
        .cloned()
        .collect()
}

/// Return randomized resubmission order with untried helpers first.
///
/// The configured server list is split into untried and already-sent groups.
/// Each group is shuffled separately using `server_random_bytes`, then the
/// shuffled untried group is followed by the shuffled already-sent group.
/// Callers can use `resubmission_server_order_random_bytes_required` to size
/// the entropy input.
pub fn resubmission_server_order(
    configured_server_urls: &[String],
    sent_to_urls: &[String],
    server_random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    let sent: HashSet<&str> = sent_to_urls.iter().map(String::as_str).collect();
    let untried: Vec<String> = configured_server_urls
        .iter()
        .filter(|server| !sent.contains(server.as_str()))
        .cloned()
        .collect();
    let already_sent: Vec<String> = configured_server_urls
        .iter()
        .filter(|server| sent.contains(server.as_str()))
        .cloned()
        .collect();

    let untried_bytes = share_server_order_random_bytes_required(untried.len());
    let already_sent_bytes = share_server_order_random_bytes_required(already_sent.len());
    let needed =
        resubmission_server_order_random_bytes_required(configured_server_urls, sent_to_urls);
    if server_random_bytes.len() < needed {
        return Err(VotingError::InvalidInput {
            message: format!(
                "server_random_bytes must contain at least {needed} bytes for resubmission order"
            ),
        });
    }

    let randomized_untried =
        shuffled_share_server_order(&untried, &server_random_bytes[..untried_bytes])?;
    let randomized_already_sent = shuffled_share_server_order(
        &already_sent,
        &server_random_bytes[untried_bytes..untried_bytes + already_sent_bytes],
    )?;
    Ok(resubmission_server_order_from_groups(
        &randomized_untried,
        &randomized_already_sent,
    ))
}

/// Return resubmission order from configured helper order and already-sent set.
///
/// This preserves the configured order within each group. It is useful for
/// deterministic tests and callers that have already made an explicit ordering
/// decision. Production resubmission paths should prefer
/// `resubmission_server_order`.
pub fn resubmission_server_order_from_configured_order(
    configured_server_urls: &[String],
    sent_to_urls: &[String],
) -> Vec<String> {
    let sent: HashSet<&str> = sent_to_urls.iter().map(String::as_str).collect();
    let untried: Vec<String> = configured_server_urls
        .iter()
        .filter(|server| !sent.contains(server.as_str()))
        .cloned()
        .collect();
    let already_sent: Vec<String> = configured_server_urls
        .iter()
        .filter(|server| sent.contains(server.as_str()))
        .cloned()
        .collect();
    resubmission_server_order_from_groups(&untried, &already_sent)
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

    fn random_bytes(samples: &[u64]) -> Vec<u8> {
        samples
            .iter()
            .flat_map(|sample| sample.to_le_bytes())
            .collect()
    }

    #[test]
    fn scheduled_submit_at_samples_before_deadline() {
        let submit_at = scheduled_share_submit_at(1_000, 2_000, Some(100), false, 0.5).unwrap();
        assert_eq!(submit_at, 1_450);
    }

    #[test]
    fn scheduled_submit_at_entropy_requirement_matches_delay_window() {
        assert_eq!(
            share_submit_at_random_bytes_required(1_000, 2_000, Some(100), false),
            SHARE_SUBMIT_AT_RANDOM_BYTES
        );
        assert_eq!(
            share_submit_at_random_bytes_required(1_000, 2_000, Some(100), true),
            0
        );
        assert_eq!(
            share_submit_at_random_bytes_required(1_000, 2_000, None, false),
            0
        );
        assert_eq!(
            share_submit_at_random_bytes_required(1_950, 2_000, Some(100), false),
            0
        );
    }

    #[test]
    fn scheduled_submit_at_from_entropy_samples_before_deadline() {
        let submit_at = scheduled_share_submit_at_from_entropy(
            1_000,
            2_000,
            Some(100),
            false,
            &random_bytes(&[1u64 << 63]),
        )
        .unwrap();
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
            scheduled_share_submit_at(1_000, 2_000, Some(0), false, f64::NAN).unwrap(),
            0
        );
        assert_eq!(
            scheduled_share_submit_at(1_950, 2_000, Some(100), false, f64::NAN).unwrap(),
            0
        );
        assert_eq!(
            scheduled_share_submit_at_from_entropy(1_000, 2_000, Some(100), true, &[]).unwrap(),
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
    fn scheduled_submit_at_from_entropy_rejects_missing_entropy_for_delay_window() {
        assert!(matches!(
            scheduled_share_submit_at_from_entropy(1_000, 2_000, Some(100), false, &[]),
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
    fn next_tracking_delay_uses_future_check_times() {
        let shares = vec![share(0, 100), share(200, 100)];
        let policy = ShareTimingPolicy::default();

        assert_eq!(next_tracking_delay_seconds(&shares, 105, policy), Some(5));
    }

    #[test]
    fn next_tracking_delay_applies_minimum_and_future_cap() {
        let shares = vec![share(0, 100), share(200, 100)];
        let policy = ShareTimingPolicy::default();

        assert_eq!(next_tracking_delay_seconds(&shares, 109, policy), Some(3));
        assert_eq!(next_tracking_delay_seconds(&shares, 111, policy), Some(30));
    }

    #[test]
    fn next_tracking_delay_uses_ready_poll_interval_for_ready_pending_shares() {
        let shares = vec![share(0, 100)];
        let policy = ShareTimingPolicy::default();

        assert_eq!(next_tracking_delay_seconds(&shares, 130, policy), Some(15));
        assert_eq!(next_tracking_delay_seconds(&shares, 131, policy), Some(15));
    }

    #[test]
    fn next_tracking_delay_stops_when_all_shares_are_confirmed() {
        let mut confirmed = share(0, 100);
        confirmed.confirmed = true;

        assert_eq!(
            next_tracking_delay_seconds(&[confirmed], 130, ShareTimingPolicy::default()),
            None
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
    fn helper_order_random_bytes_required_matches_shuffle_steps() {
        assert_eq!(share_server_order_random_bytes_required(0), 0);
        assert_eq!(share_server_order_random_bytes_required(1), 0);
        assert_eq!(share_server_order_random_bytes_required(3), 16);
    }

    #[test]
    fn resubmission_order_random_bytes_required_matches_group_shuffles() {
        let configured = vec![
            "https://already-one.example.com".to_string(),
            "https://untried-one.example.com".to_string(),
            "https://untried-two.example.com".to_string(),
            "https://already-two.example.com".to_string(),
        ];
        let sent = vec![
            "https://already-one.example.com".to_string(),
            "https://already-two.example.com".to_string(),
        ];

        assert_eq!(
            resubmission_server_order_random_bytes_required(&configured, &sent),
            16
        );
    }

    #[test]
    fn randomized_helper_order_uses_entropy() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ];

        let ordered = shuffled_share_server_order(&servers, &random_bytes(&[1, 0])).unwrap();

        assert_eq!(
            ordered,
            vec![
                "https://three.example.com".to_string(),
                "https://one.example.com".to_string(),
                "https://two.example.com".to_string()
            ]
        );
    }

    #[test]
    fn randomized_helper_order_rejects_missing_entropy() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
        ];

        assert!(matches!(
            shuffled_share_server_order(&servers, &[]),
            Err(VotingError::InvalidInput { .. })
        ));
    }

    #[test]
    fn share_submission_plan_randomizes_target_servers() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ];

        let plan = plan_share_submission(
            &servers,
            1_000,
            2_000,
            Some(100),
            false,
            &random_bytes(&[1u64 << 63]),
            &random_bytes(&[1, 0]),
        )
        .unwrap();

        assert_eq!(plan.submit_at, 1_450);
        assert_eq!(plan.target_count, 2);
        assert_eq!(
            plan.target_servers,
            vec![
                "https://three.example.com".to_string(),
                "https://one.example.com".to_string()
            ]
        );
    }

    #[test]
    fn share_submission_plan_rejects_empty_server_list() {
        assert!(matches!(
            plan_share_submission(
                &[],
                1_000,
                2_000,
                Some(100),
                false,
                &random_bytes(&[1u64 << 63]),
                &[]
            ),
            Err(VotingError::InvalidInput { .. })
        ));
        assert!(matches!(
            plan_share_submission_from_order(&[], 1_000, 2_000, Some(100), false, 0.0),
            Err(VotingError::InvalidInput { .. })
        ));
    }

    #[test]
    fn share_submission_plan_from_order_uses_caller_server_order() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ];

        let plan = plan_share_submission_from_order(&servers, 1_000, 2_000, Some(100), false, 0.0)
            .unwrap();

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
    fn share_submission_target_selection_uses_caller_server_order() {
        let servers = vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
        ];

        assert_eq!(
            select_share_submission_targets_from_order(&servers, 2),
            vec![
                "https://three.example.com".to_string(),
                "https://one.example.com".to_string()
            ]
        );
    }

    #[test]
    fn randomized_share_submission_target_selection_uses_entropy() {
        let servers = vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ];

        assert_eq!(
            select_share_submission_targets(&servers, 2, &random_bytes(&[1, 0])).unwrap(),
            vec![
                "https://three.example.com".to_string(),
                "https://one.example.com".to_string()
            ]
        );
    }

    #[test]
    fn resubmission_order_tries_ordered_untried_helpers_first() {
        let untried = vec![
            "https://untried-two.example.com".to_string(),
            "https://untried-one.example.com".to_string(),
        ];
        let already_sent = vec!["https://already.example.com".to_string()];

        assert_eq!(
            resubmission_server_order_from_groups(&untried, &already_sent),
            vec![
                "https://untried-two.example.com".to_string(),
                "https://untried-one.example.com".to_string(),
                "https://already.example.com".to_string()
            ]
        );
    }

    #[test]
    fn randomized_resubmission_order_shuffles_groups_separately() {
        let configured = vec![
            "https://already-one.example.com".to_string(),
            "https://untried-one.example.com".to_string(),
            "https://untried-two.example.com".to_string(),
            "https://already-two.example.com".to_string(),
        ];
        let sent = vec![
            "https://already-one.example.com".to_string(),
            "https://already-two.example.com".to_string(),
        ];

        assert_eq!(
            resubmission_server_order(&configured, &sent, &random_bytes(&[0, 0])).unwrap(),
            vec![
                "https://untried-two.example.com".to_string(),
                "https://untried-one.example.com".to_string(),
                "https://already-two.example.com".to_string(),
                "https://already-one.example.com".to_string()
            ]
        );
    }

    #[test]
    fn randomized_resubmission_order_rejects_missing_entropy() {
        let configured = vec![
            "https://untried-one.example.com".to_string(),
            "https://untried-two.example.com".to_string(),
        ];

        assert!(matches!(
            resubmission_server_order(&configured, &[], &[]),
            Err(VotingError::InvalidInput { .. })
        ));
    }

    #[test]
    fn resubmission_order_from_configured_order_preserves_group_order() {
        let configured = vec![
            "https://already.example.com".to_string(),
            "https://untried.example.com".to_string(),
        ];
        let sent = vec!["https://already.example.com".to_string()];

        assert_eq!(
            resubmission_server_order_from_configured_order(&configured, &sent),
            vec![
                "https://untried.example.com".to_string(),
                "https://already.example.com".to_string()
            ]
        );
    }
}
