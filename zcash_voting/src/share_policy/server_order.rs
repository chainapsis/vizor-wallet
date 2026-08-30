use std::collections::HashSet;

use crate::types::VotingError;

use super::ShareServerSelectionPolicy;

/// Number of encrypted shares in one complete vote commitment.
pub const VOTE_COMMITMENT_SHARE_COUNT: usize = 16;
/// Numerator of the strict initial per-helper share fraction.
pub const SHARE_HELPER_INITIAL_MAX_FRACTION_NUMERATOR: usize = 3;
/// Denominator of the strict initial per-helper share fraction.
pub const SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR: usize = 4;
/// Maximum initial shares assigned to one helper in a complete normal batch.
pub const SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER: usize = VOTE_COMMITMENT_SHARE_COUNT
    * SHARE_HELPER_INITIAL_MAX_FRACTION_NUMERATOR
    / SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR;
/// Protocol cap on definite helper acceptances targeted for one share.
pub const SHARE_HELPER_TARGET_COUNT_CAP: usize = 10;
/// Initial helper readiness window before slower transports keep racing.
pub const SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS: u64 = 2_000;
/// Absolute deadline for the helper readiness race.
pub const SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS: u64 = 30_000;
/// Maximum time for one helper share POST over the wallet's privacy transport.
pub const SHARE_HELPER_POST_TIMEOUT_MILLISECONDS: u64 = 30_000;
/// Maximum time for initial share delivery before recovery takes over.
pub const SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS: u64 = 60_000;
/// Minimum delivery budget required to start another initial POST attempt.
///
/// An attempt started with less remaining budget than this is all but
/// guaranteed to be cut off by the overall delivery deadline, which would
/// burn the helper into an outcome-unknown state for that share.
pub const SHARE_DELIVERY_MIN_ATTEMPT_BUDGET_MILLISECONDS: u64 = 1_000;
/// Maximum helper share POSTs a client should keep in flight at once.
pub const SHARE_HELPER_MAX_CONCURRENT_POSTS: usize = VOTE_COMMITMENT_SHARE_COUNT;

const _: () = assert!(VOTE_COMMITMENT_SHARE_COUNT >= 2);
const _: () = assert!(SHARE_HELPER_INITIAL_MAX_FRACTION_DENOMINATOR > 0);
const _: () = assert!(SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER > 0);
const _: () = assert!(SHARE_HELPER_TARGET_COUNT_CAP > 0);

/// Return how many helpers should receive each initial share.
///
/// This is half of the configured helpers, rounded up and capped by the
/// protocol's helper-distribution policy. It is 0 when there are no helpers.
pub fn share_submission_target_count(server_count: usize) -> usize {
    (server_count / 2 + server_count % 2).min(SHARE_HELPER_TARGET_COUNT_CAP)
}

/// Return the effective target for a durable share and current helper fleet.
pub(crate) fn effective_share_submission_target_count(
    stored_target_count: u32,
    server_count: usize,
) -> usize {
    let target_count = if stored_target_count == 0 {
        share_submission_target_count(server_count)
    } else {
        usize::try_from(stored_target_count).unwrap_or(usize::MAX)
    };
    target_count
        .min(SHARE_HELPER_TARGET_COUNT_CAP)
        .min(server_count)
}

fn minimum_complete_batch_planning_server_count(target_count: usize) -> usize {
    if target_count == 0 {
        return 0;
    }
    VOTE_COMMITMENT_SHARE_COUNT
        .checked_mul(target_count)
        .expect("share-count-derived assignment total fits usize")
        .div_ceil(SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER)
}

/// Return the shared helper probe and initial-delivery policy.
pub fn share_server_selection_policy(server_count: usize) -> ShareServerSelectionPolicy {
    let target_count = share_submission_target_count(server_count);
    let (max_shares_per_server, min_server_count) = if server_count == 0 {
        (0, 0)
    } else if server_count == 1 {
        (VOTE_COMMITMENT_SHARE_COUNT, 1)
    } else {
        (
            SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER,
            minimum_complete_batch_planning_server_count(target_count),
        )
    };

    ShareServerSelectionPolicy {
        target_count: target_count as u32,
        max_shares_per_server: max_shares_per_server as u32,
        min_server_count: min_server_count as u32,
        preflight_soft_timeout_milliseconds: SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS,
        preflight_hard_timeout_milliseconds: SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS,
        post_timeout_milliseconds: SHARE_HELPER_POST_TIMEOUT_MILLISECONDS,
        initial_delivery_timeout_milliseconds: SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS,
        max_concurrent_posts: SHARE_HELPER_MAX_CONCURRENT_POSTS as u32,
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
/// `server_urls` must not contain duplicates. Duplicate helpers are treated as
/// configuration errors because target counts are based on distinct endpoints.
///
/// `random_bytes` must contain at least
/// `share_server_order_random_bytes_required(server_urls.len())` bytes from a
/// cryptographically secure RNG. Extra bytes are ignored.
pub fn shuffled_share_server_order(
    server_urls: &[String],
    random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    require_unique_share_servers(server_urls)?;
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
/// `configured_server_urls` must not contain duplicates because retry order is
/// based on distinct helper endpoints.
/// Each group is shuffled separately using `server_random_bytes`, then the
/// shuffled untried group is followed by the shuffled already-sent group.
/// Callers can use `resubmission_server_order_random_bytes_required` to size
/// the entropy input.
pub fn resubmission_server_order(
    configured_server_urls: &[String],
    sent_to_urls: &[String],
    server_random_bytes: &[u8],
) -> Result<Vec<String>, VotingError> {
    require_unique_share_servers(configured_server_urls)?;
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

pub(super) fn require_unique_share_servers(server_urls: &[String]) -> Result<(), VotingError> {
    let mut seen = HashSet::new();
    for server_url in server_urls {
        if !seen.insert(server_url.as_str()) {
            return Err(VotingError::InvalidInput {
                message: "server_urls must not contain duplicates".to_string(),
            });
        }
    }
    Ok(())
}
