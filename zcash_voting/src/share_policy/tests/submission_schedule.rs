use super::{super::*, fixtures::random_bytes};
use crate::{share_policy::submission_schedule::delayed_share_window_seconds, types::VotingError};

#[test]
fn scheduled_submit_at_from_random_unit_samples_before_deadline() {
    let submit_at =
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(100), false, 0.5).unwrap();
    assert_eq!(submit_at, 1_450);
}

#[test]
fn delayed_share_window_caps_long_round_at_100_hours() {
    let now = 1_000_000;
    let vote_end = now + 30 * 24 * 60 * 60;

    assert_eq!(
        delayed_share_window_seconds(now, vote_end, Some(LAST_MOMENT_BUFFER_MAX_SECONDS), false,),
        Some(SHARE_SUBMIT_AT_MAX_DELAY_SECONDS)
    );
    assert_eq!(
        scheduled_share_submit_at_from_random_unit(
            now,
            vote_end,
            Some(LAST_MOMENT_BUFFER_MAX_SECONDS),
            false,
            0.5,
        )
        .unwrap(),
        now + 50 * 60 * 60
    );
}

#[test]
fn delayed_share_window_preserves_shorter_round_deadline() {
    let now = 1_000_000;
    let vote_end = now + 36 * 60 * 60;

    assert_eq!(
        delayed_share_window_seconds(now, vote_end, Some(LAST_MOMENT_BUFFER_MAX_SECONDS), false,),
        Some(30 * 60 * 60)
    );
}

#[test]
fn delayed_share_window_is_immediate_inside_last_moment_buffer() {
    let now = 1_000_000;
    let buffer = LAST_MOMENT_BUFFER_MAX_SECONDS;

    assert_eq!(
        delayed_share_window_seconds(now, now + buffer, Some(buffer), false),
        None
    );
    assert_eq!(
        delayed_share_window_seconds(now, now + buffer - 1, Some(buffer), false),
        None
    );
}

#[test]
fn delayed_share_window_handles_clock_skew_without_underflow() {
    assert_eq!(
        delayed_share_window_seconds(u64::MAX, u64::MAX - 1, Some(1), false),
        None
    );
    assert_eq!(delayed_share_window_seconds(1, 5, Some(10), false), None);
    assert_eq!(
        scheduled_share_submit_at_from_entropy(u64::MAX, u64::MAX - 1, Some(1), false, &[])
            .unwrap(),
        0
    );
}

#[test]
fn capped_submit_at_samples_remain_randomized_within_window() {
    let now = 1_000_000;
    let vote_end = now + 30 * 24 * 60 * 60;
    let samples = [0, 1u64 << 62, 1u64 << 63, 3u64 << 62, u64::MAX];
    let window_end = now + SHARE_SUBMIT_AT_MAX_DELAY_SECONDS;
    let mut submit_times = Vec::new();

    for sample in samples {
        let submit_at = scheduled_share_submit_at_from_entropy(
            now,
            vote_end,
            Some(LAST_MOMENT_BUFFER_MAX_SECONDS),
            false,
            &random_bytes(&[sample]),
        )
        .unwrap();
        assert!(submit_at >= now);
        assert!(submit_at < window_end);
        submit_times.push(submit_at);
    }

    assert_eq!(submit_times[0], now);
    assert_eq!(submit_times[4], window_end - 1);
    assert!(submit_times.windows(2).all(|pair| pair[0] < pair[1]));
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
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(100), true, f64::NAN)
            .unwrap(),
        0
    );
    assert_eq!(
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, None, false, f64::NAN).unwrap(),
        0
    );
    assert_eq!(
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(0), false, f64::NAN).unwrap(),
        0
    );
    assert_eq!(
        scheduled_share_submit_at_from_random_unit(1_950, 2_000, Some(100), false, f64::NAN)
            .unwrap(),
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
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(100), false, f64::NAN),
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
fn scheduled_submit_at_from_random_unit_rejects_out_of_range_samples() {
    assert!(matches!(
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(100), false, 1.0),
        Err(VotingError::InvalidInput { .. })
    ));
    assert!(matches!(
        scheduled_share_submit_at_from_random_unit(1_000, 2_000, Some(100), false, -1.0),
        Err(VotingError::InvalidInput { .. })
    ));
}
