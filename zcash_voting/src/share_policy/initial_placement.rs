use std::collections::HashMap;

use crate::{types::VotingError, wire::BoundedU32};

use super::{
    server_order::{
        require_unique_share_servers, select_share_submission_targets,
        select_share_submission_targets_from_order, share_server_order_random_bytes_required,
        share_server_selection_policy, share_submission_target_count, shuffled_share_server_order,
        SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, VOTE_COMMITMENT_SHARE_COUNT,
    },
    submission_schedule::{
        scheduled_share_submit_at_from_entropy, scheduled_share_submit_at_from_random_unit,
        share_submit_at_random_bytes_required,
    },
    ImmediateShareKey, ShareSubmissionPlan, ShareSubmissionRandomBytesRequired,
};

/// Domain share index used for the round's immediate submission.
///
/// ZKP #2 shuffles denominations before assigning share indexes, so this is a
/// stable identity rather than a guarantee about the share's value.
pub const IMMEDIATE_SHARE_INDEX: u32 = 0;

/// Select the round's immediate share from durable round state.
///
/// Bundles are ordered by value descending, so `highest_bundle_index` denotes
/// the lowest-value eligible bundle. The lowest proposal ID with a recorded
/// ballot choice owns the designation; skipped proposals must not be included.
pub fn round_immediate_share_key(
    highest_bundle_index: Option<u32>,
    voted_proposal_ids: &[u32],
) -> Option<ImmediateShareKey> {
    Some(ImmediateShareKey {
        bundle_index: highest_bundle_index?,
        proposal_id: voted_proposal_ids.iter().copied().min()?,
        share_index: IMMEDIATE_SHARE_INDEX,
    })
}

/// Return the random bytes needed to plan `share_count` independent shares.
///
/// Use these totals with `plan_share_submissions`. The returned counts are split
/// by purpose so callers can draw each byte slice from their platform CSPRNG and
/// pass the slices without having to understand the sampling layout.
pub fn share_submission_random_bytes_required(
    share_count: usize,
    server_count: usize,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> ShareSubmissionRandomBytesRequired {
    let submit_at_per_share = share_submit_at_random_bytes_required(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
    );
    let server_per_share = share_server_order_random_bytes_required(server_count);

    ShareSubmissionRandomBytesRequired {
        submit_at_random_bytes: submit_at_per_share.saturating_mul(share_count),
        server_random_bytes: server_per_share.saturating_mul(share_count),
    }
}

/// Plan the timing and initial helper targets for a share delegation.
///
/// `server_urls` must not be empty. Missing helpers are a configuration error
/// for initial delegation, not a successful zero-target plan.
/// `server_urls` must also not contain duplicates because target counts are
/// based on distinct endpoints.
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

    build_share_submission_plan(false, target_count, target_servers, submit_at)
}

/// Plan independent timing and initial helper targets for multiple shares.
///
/// This is the preferred production helper when a wallet has multiple share
/// payloads. It consumes separate entropy for each returned plan so callers
/// cannot accidentally reuse one `submit_at` or helper target order for every
/// share. Use `share_submission_random_bytes_required` to size the two entropy
/// inputs.
///
/// For a complete normal commitment, each share targets half of the configured
/// helpers rounded up, capped by [`SHARE_HELPER_TARGET_COUNT_CAP`]. Assignments
/// are balanced across the fleet and no helper receives more than the derived
/// three-quarters quota. Each returned plan contains its final initial target
/// list. This guarantee applies only to initial planning. Fallback and recovery
/// may exceed the quota when needed to preserve liveness.
///
/// `server_urls` must contain distinct, valid helper endpoint URLs. This
/// function checks only that the list is non-empty and has no duplicates; it
/// does not parse URLs or probe helper health. Callers are responsible for
/// validating endpoints and assessing health before planning, because
/// unavailable helpers can prevent reaching the returned `target_count`.
///
/// `immediate_share_index` is a position in the caller-supplied batch, not a
/// domain share index. The caller maps the round's [`ImmediateShareKey`] to its
/// batch position. The designated plan remains positionally aligned with the
/// input batch, is marked `immediate`, and receives `submit_at = 0`.
/// `single_share` is valid only when `share_count == 1`; it cannot be used to
/// exempt a complete commitment from commitment-wide placement protections.
pub fn plan_share_submissions(
    share_count: usize,
    server_urls: &[String],
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    immediate_share_index: Option<u32>,
    submit_at_random_bytes: &[u8],
    server_random_bytes: &[u8],
) -> Result<Vec<ShareSubmissionPlan>, VotingError> {
    plan_share_submissions_with_preferred_servers(
        share_count,
        server_urls,
        server_urls.len(),
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
        immediate_share_index,
        submit_at_random_bytes,
        server_random_bytes,
    )
}

/// Plan initial submissions from a readiness-ranked helper list.
///
/// `ranked_server_urls` contains ready helpers first in response order, then
/// every remaining configured helper in stable order. `preferred_server_count`
/// is the number of ready helpers in that prefix. When fewer than the target
/// are ready, the planner includes enough fallback helpers to return a complete
/// plan. For a complete normal commitment, planning widens the pool to the
/// minimum capacity exposed by [`share_server_selection_policy`], targets are
/// balanced with independent caller-provided entropy for tie-breaking, and the
/// per-helper maximum is enforced as a hard quota. Single-share and incomplete
/// batches keep readiness-first planning and do not claim a commitment-wide
/// quota. Recovery is outside this initial-only contract and may use any
/// configured helper.
pub fn plan_share_submissions_with_preferred_servers(
    share_count: usize,
    ranked_server_urls: &[String],
    preferred_server_count: usize,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
    immediate_share_index: Option<u32>,
    submit_at_random_bytes: &[u8],
    server_random_bytes: &[u8],
) -> Result<Vec<ShareSubmissionPlan>, VotingError> {
    if single_share && share_count != 1 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "single_share planning requires exactly one share payload, got {share_count}"
            ),
        });
    }
    if immediate_share_index.is_some_and(|index| index as usize >= share_count) {
        return Err(VotingError::InvalidInput {
            message: format!("immediate_share_index must be less than share_count {share_count}"),
        });
    }

    if share_count == 0 {
        return Ok(Vec::new());
    }

    require_share_servers(ranked_server_urls)?;
    if preferred_server_count > ranked_server_urls.len() {
        return Err(VotingError::InvalidInput {
            message: "preferred_server_count must not exceed ranked_server_urls length".to_string(),
        });
    }
    let submit_at_bytes_per_share = share_submit_at_random_bytes_required(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
    );
    let server_bytes_per_share = share_server_order_random_bytes_required(ranked_server_urls.len());
    let submit_at_bytes_needed = checked_random_bytes_required(
        submit_at_bytes_per_share,
        share_count,
        "submit_at_random_bytes",
    )?;
    let server_bytes_needed =
        checked_random_bytes_required(server_bytes_per_share, share_count, "server_random_bytes")?;
    if submit_at_random_bytes.len() < submit_at_bytes_needed {
        return Err(VotingError::InvalidInput {
            message: format!(
                "submit_at_random_bytes must contain at least {submit_at_bytes_needed} bytes"
            ),
        });
    }
    if server_random_bytes.len() < server_bytes_needed {
        return Err(VotingError::InvalidInput {
            message: format!(
                "server_random_bytes must contain at least {server_bytes_needed} bytes"
            ),
        });
    }

    let target_count = share_submission_target_count(ranked_server_urls.len());
    let complete_normal_batch = share_count == VOTE_COMMITMENT_SHARE_COUNT && !single_share;
    let selection_policy = share_server_selection_policy(ranked_server_urls.len());
    let minimum_planning_server_count = if complete_normal_batch {
        selection_policy.min_server_count as usize
    } else {
        target_count
    };
    if minimum_planning_server_count > ranked_server_urls.len() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "complete share batch requires at least {minimum_planning_server_count} helpers to keep each helper at or below {} initial shares",
                SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER
            ),
        });
    }
    let planning_server_count = preferred_server_count
        .max(minimum_planning_server_count)
        .min(ranked_server_urls.len());
    let planning_servers = &ranked_server_urls[..planning_server_count];
    let max_shares_per_server = (complete_normal_batch && planning_server_count > 1)
        .then_some(SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER);
    let mut server_usage = HashMap::<String, usize>::new();

    let mut plans = Vec::with_capacity(share_count);
    for share_index in 0..share_count {
        let submit_at_start = share_index * submit_at_bytes_per_share;
        let submit_at_end = submit_at_start + submit_at_bytes_per_share;
        let server_start = share_index * server_bytes_per_share;
        let server_end = server_start + server_bytes_per_share;
        let target_servers = select_batch_share_submission_targets(
            planning_servers,
            target_count,
            max_shares_per_server,
            &mut server_usage,
            &server_random_bytes[server_start..server_end],
        )?;
        let immediate = immediate_share_index == Some(share_index as u32);
        let submit_at = if immediate {
            0
        } else {
            scheduled_share_submit_at_from_entropy(
                now_seconds,
                vote_end_time_seconds,
                last_moment_buffer_seconds,
                single_share,
                &submit_at_random_bytes[submit_at_start..submit_at_end],
            )?
        };
        plans.push(build_share_submission_plan(
            immediate,
            target_count,
            target_servers,
            submit_at,
        )?);
    }

    Ok(plans)
}

/// Plan share submission using a caller-provided helper order.
///
/// `server_urls` must not be empty. Missing helpers are a configuration error
/// for initial delegation, not a successful zero-target plan.
/// `server_urls` must also not contain duplicates because target counts are
/// based on distinct endpoints.
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
    let submit_at = scheduled_share_submit_at_from_random_unit(
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        single_share,
        random_unit,
    )?;

    build_share_submission_plan(false, target_count, target_servers, submit_at)
}

fn build_share_submission_plan(
    immediate: bool,
    target_count: usize,
    target_servers: Vec<String>,
    submit_at: u64,
) -> Result<ShareSubmissionPlan, VotingError> {
    Ok(ShareSubmissionPlan {
        immediate,
        submit_at,
        target_count: BoundedU32::try_from(target_count)
            .map_err(|_| VotingError::InvalidInput {
                message: format!("target_count {target_count} does not fit u32"),
            })?
            .0,
        target_servers,
    })
}

fn require_share_servers(server_urls: &[String]) -> Result<(), VotingError> {
    if server_urls.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "server_urls must not be empty".to_string(),
        });
    }

    require_unique_share_servers(server_urls)
}

/// Select the final targets for one share before its batch plan is constructed.
pub(super) fn select_batch_share_submission_targets(
    server_urls: &[String],
    target_count: usize,
    max_shares_per_server: Option<usize>,
    server_usage: &mut HashMap<String, usize>,
    server_random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    let randomized_order = shuffled_share_server_order(server_urls, server_random_bytes)?;
    let mut ranked: Vec<_> = randomized_order.iter().enumerate().collect();
    ranked.sort_by_key(|(random_rank, server)| {
        let usage = server_usage.get(*server).copied().unwrap_or(0);
        (usage, *random_rank)
    });
    let selected: Vec<_> = ranked
        .into_iter()
        .filter(|(_, server)| {
            max_shares_per_server
                .is_none_or(|maximum| server_usage.get(*server).copied().unwrap_or(0) < maximum)
        })
        .take(target_count)
        .map(|(_, server)| server.clone())
        .collect();
    if selected.len() != target_count {
        return Err(VotingError::InvalidInput {
            message: format!(
                "cannot select {target_count} distinct helpers without exceeding the initial per-helper share quota"
            ),
        });
    }
    for server in &selected {
        *server_usage.entry(server.clone()).or_default() += 1;
    }
    Ok(selected)
}

fn checked_random_bytes_required(
    per_share: usize,
    share_count: usize,
    name: &str,
) -> Result<usize, VotingError> {
    per_share
        .checked_mul(share_count)
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!("{name} requirement overflows usize"),
        })
}
