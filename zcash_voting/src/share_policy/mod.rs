mod initial_placement;
mod server_order;
mod submission_schedule;
mod timing;

use serde::{Deserialize, Serialize};

/// Planned helper-share submission values that SDKs can apply to payloads.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareSubmissionPlan {
    /// True only for the round's designated immediate share.
    ///
    /// This is distinct from `submit_at == 0`: last-moment and single-share
    /// planning can schedule other, undesignated shares immediately.
    #[serde(default)]
    pub immediate: bool,
    /// Unix seconds when helpers should submit the share, or 0 for immediate.
    pub submit_at: u64,
    /// Number of helpers each share should reach.
    pub target_count: u32,
    /// Helper targets selected for initial share submission.
    pub target_servers: Vec<String>,
}

/// Identifies the round's single designated immediate helper share.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImmediateShareKey {
    pub bundle_index: u32,
    pub proposal_id: u32,
    /// Domain share index, always [`IMMEDIATE_SHARE_INDEX`].
    pub share_index: u32,
}

/// Random byte counts needed to plan one or more share submissions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareSubmissionRandomBytesRequired {
    /// Bytes needed for independent delayed `submit_at` samples.
    pub submit_at_random_bytes: usize,
    /// Bytes needed for independent helper-order shuffles.
    pub server_random_bytes: usize,
}

/// Shared helper probing and initial-delivery values.
///
/// Clients own transport and recovery. They should start all readiness probes
/// together, inspect responses after the soft timeout, and continue until at
/// least `target_count` helpers are ready or the hard timeout expires. For a
/// complete commitment, `max_shares_per_server` is a hard initial-assignment
/// quota when at least `min_server_count` helpers are available. These limits
/// are derived from [`VOTE_COMMITMENT_SHARE_COUNT`]. Retries may exceed them
/// when needed for liveness. The limit is per helper and does not make a claim
/// about the combined view of colluding helpers.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareServerSelectionPolicy {
    pub target_count: u32,
    pub max_shares_per_server: u32,
    pub min_server_count: u32,
    pub preflight_soft_timeout_milliseconds: u64,
    pub preflight_hard_timeout_milliseconds: u64,
    pub post_timeout_milliseconds: u64,
    pub initial_delivery_timeout_milliseconds: u64,
    pub max_concurrent_posts: u32,
}

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

pub use initial_placement::{
    plan_share_submission, plan_share_submission_from_order, plan_share_submissions,
    plan_share_submissions_with_preferred_servers, round_immediate_share_key,
    share_submission_random_bytes_required, IMMEDIATE_SHARE_INDEX,
};
pub use server_order::{
    resubmission_server_order, resubmission_server_order_from_configured_order,
    resubmission_server_order_from_groups, resubmission_server_order_random_bytes_required,
    select_share_submission_targets, select_share_submission_targets_from_order,
    share_server_order_random_bytes_required, share_server_selection_policy,
    share_submission_target_count, shuffled_share_server_order,
    SHARE_DELIVERY_MIN_ATTEMPT_BUDGET_MILLISECONDS, SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR,
    SHARE_HELPER_INITIAL_MAX_FRACTION_NUMERATOR, SHARE_HELPER_MAX_CONCURRENT_POSTS,
    SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, SHARE_HELPER_POST_TIMEOUT_MILLISECONDS,
    SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS,
    SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS, SHARE_HELPER_TARGET_COUNT_CAP,
    SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS, VOTE_COMMITMENT_SHARE_COUNT,
};
pub use submission_schedule::{
    scheduled_share_submit_at_from_entropy, scheduled_share_submit_at_from_random_unit,
    share_submit_at_random_bytes_required, SHARE_SUBMIT_AT_MAX_DELAY_SECONDS,
    SHARE_SUBMIT_AT_RANDOM_BYTES,
};
pub use timing::{
    is_last_moment, is_share_ready_for_status_check, last_moment_buffer_seconds,
    last_moment_deadline_seconds, next_tracking_delay_seconds, overdue_threshold_seconds,
    share_recovery_base_time, should_resubmit_share, summarize_share_tracking,
    LAST_MOMENT_BUFFER_FRACTION_DENOMINATOR, LAST_MOMENT_BUFFER_FRACTION_NUMERATOR,
    LAST_MOMENT_BUFFER_MAX_SECONDS, SHARE_FUTURE_CHECK_MAX_DELAY_SECONDS,
    SHARE_MAX_OVERDUE_THRESHOLD_SECONDS, SHARE_MIN_OVERDUE_THRESHOLD_SECONDS,
    SHARE_MIN_TRACKING_DELAY_SECONDS, SHARE_READY_POLL_INTERVAL_SECONDS,
    SHARE_RESUBMIT_CUTOFF_SECONDS, SHARE_STATUS_CHECK_GRACE_SECONDS,
};

pub(crate) use server_order::effective_share_submission_target_count;
pub(crate) use timing::is_share_resubmission_window_open;

#[cfg(test)]
mod tests;
