use crate::types::ShareDelegationRecord;

use super::{ShareTimingPolicy, ShareTrackingSummary};

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
/// Numerator for the last-moment share window fraction.
pub const LAST_MOMENT_BUFFER_FRACTION_NUMERATOR: u64 = 2;
/// Denominator for the last-moment share window fraction.
pub const LAST_MOMENT_BUFFER_FRACTION_DENOMINATOR: u64 = 5;
/// Maximum last-moment share window, in seconds.
pub const LAST_MOMENT_BUFFER_MAX_SECONDS: u64 = 6 * 60 * 60;

/// Return the last-moment buffer for a voting round.
///
/// The buffer is 40% of the round duration from ceremony start to vote end,
/// capped at six hours. The calculation rounds up to whole seconds so callers
/// do not schedule delayed helper shares inside the intended last-moment
/// window. Invalid or zero-length timing returns `None`.
pub fn last_moment_buffer_seconds(
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> Option<u64> {
    let duration = vote_end_time_seconds.checked_sub(ceremony_start_seconds)?;
    if duration == 0 {
        return None;
    }
    let numerator = u128::from(duration) * u128::from(LAST_MOMENT_BUFFER_FRACTION_NUMERATOR);
    let denominator = u128::from(LAST_MOMENT_BUFFER_FRACTION_DENOMINATOR);
    let buffer = (numerator + denominator - 1) / denominator;
    let capped = buffer.min(u128::from(LAST_MOMENT_BUFFER_MAX_SECONDS));
    Some(capped as u64)
}

/// Return the Unix-second boundary where last-moment mode starts.
///
/// Returns `None` when the round timing cannot produce a last-moment buffer.
pub fn last_moment_deadline_seconds(
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> Option<u64> {
    let buffer = last_moment_buffer_seconds(ceremony_start_seconds, vote_end_time_seconds)?;
    Some(vote_end_time_seconds.saturating_sub(buffer))
}

/// Return true when `now_seconds` falls inside the active round's last-moment window.
///
/// Invalid or zero-length round timing is treated as not last moment.
pub fn is_last_moment(
    now_seconds: u64,
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> bool {
    last_moment_deadline_seconds(ceremony_start_seconds, vote_end_time_seconds)
        .is_some_and(|deadline| now_seconds >= deadline && now_seconds < vote_end_time_seconds)
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
        && is_share_resubmission_window_open(now_seconds, vote_end_time_seconds, policy)
}

/// Return true while recovery POSTs are allowed before the vote-end cutoff.
pub(crate) fn is_share_resubmission_window_open(
    now_seconds: u64,
    vote_end_time_seconds: u64,
    policy: ShareTimingPolicy,
) -> bool {
    vote_end_time_seconds > now_seconds.saturating_add(policy.resubmit_cutoff_seconds)
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

fn min_second(current: Option<u64>, candidate: u64) -> Option<u64> {
    match current {
        Some(current) if current <= candidate => Some(current),
        _ => Some(candidate),
    }
}
