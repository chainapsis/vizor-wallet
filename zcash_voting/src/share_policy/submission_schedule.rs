use crate::types::VotingError;

/// Random bytes needed to sample an initial delayed share submission time.
pub const SHARE_SUBMIT_AT_RANDOM_BYTES: usize = 8;
/// Maximum randomized delay before an initial helper share submission.
pub const SHARE_SUBMIT_AT_MAX_DELAY_SECONDS: u64 = 100 * 60 * 60;

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
/// The sampled delay is capped at 100 hours and still ends before the round's
/// last-moment window.
///
/// This is useful for deterministic tests and FFI callers that already expose a
/// random sample in the `[0, 1)` range. Production submission paths should use
/// `scheduled_share_submit_at_from_entropy` to keep sampling policy inside the
/// crate.
pub fn scheduled_share_submit_at_from_random_unit(
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
    if !random_unit.is_finite() || !(0.0..1.0).contains(&random_unit) {
        return Err(VotingError::InvalidInput {
            message: "random_unit must be finite and in [0, 1)".to_string(),
        });
    }

    let delay_seconds = (random_unit * window_seconds as f64).floor() as u64;
    Ok(now_seconds.saturating_add(delay_seconds))
}

/// Plan the delayed helper submission time using caller-provided entropy.
///
/// The sampled delay is capped at 100 hours and still ends before the round's
/// last-moment window.
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

/// Return the nonempty randomized delay window for an initial helper share.
///
/// The window ends no later than the round's last-moment boundary and is capped
/// at 100 hours from `now_seconds`.
pub(super) fn delayed_share_window_seconds(
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

    Some((deadline - now_seconds).min(SHARE_SUBMIT_AT_MAX_DELAY_SECONDS))
}
