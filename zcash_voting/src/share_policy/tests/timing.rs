use super::{super::*, fixtures::share};

#[test]
fn last_moment_buffer_uses_two_fifths_of_round_duration() {
    assert_eq!(last_moment_buffer_seconds(1_000, 1_600), Some(240));
}

#[test]
fn last_moment_buffer_caps_at_six_hours() {
    assert_eq!(
        last_moment_buffer_seconds(1_000, 1_000 + 24 * 60 * 60),
        Some(LAST_MOMENT_BUFFER_MAX_SECONDS)
    );
}

#[test]
fn last_moment_buffer_caps_without_u64_overflow() {
    assert_eq!(
        last_moment_buffer_seconds(0, u64::MAX),
        Some(LAST_MOMENT_BUFFER_MAX_SECONDS)
    );
}

#[test]
fn last_moment_buffer_rejects_invalid_round_timing() {
    assert_eq!(last_moment_buffer_seconds(1_000, 1_000), None);
    assert_eq!(last_moment_buffer_seconds(1_001, 1_000), None);
}

#[test]
fn last_moment_buffer_rounds_up_to_whole_seconds() {
    assert_eq!(last_moment_buffer_seconds(1_000, 1_001), Some(1));
    assert_eq!(last_moment_buffer_seconds(1_000, 1_002), Some(1));
    assert_eq!(last_moment_buffer_seconds(1_000, 1_003), Some(2));
}

#[test]
fn last_moment_deadline_subtracts_buffer_from_vote_end() {
    assert_eq!(last_moment_deadline_seconds(1_000, 1_600), Some(1_360));
    assert_eq!(
        last_moment_deadline_seconds(1_000, 1_000 + 24 * 60 * 60),
        Some(1_000 + 18 * 60 * 60)
    );
}

#[test]
fn last_moment_predicate_uses_deadline_boundary() {
    assert!(!is_last_moment(1_359, 1_000, 1_600));
    assert!(is_last_moment(1_360, 1_000, 1_600));
    assert!(is_last_moment(1_599, 1_000, 1_600));
    assert!(!is_last_moment(1_600, 1_000, 1_600));
    assert!(!is_last_moment(1_000, 1_000, 1_000));
}

#[test]
fn retry_uses_capped_submit_at_without_adding_another_window() {
    let now = 1_000_000;
    let vote_end = now + 30 * 24 * 60 * 60;
    let submit_at = scheduled_share_submit_at_from_random_unit(
        now,
        vote_end,
        Some(LAST_MOMENT_BUFFER_MAX_SECONDS),
        false,
        0.5,
    )
    .unwrap();
    let share = share(submit_at, now);
    let policy = ShareTimingPolicy::default();

    assert_eq!(share_recovery_base_time(&share), now + 50 * 60 * 60);
    assert!(!should_resubmit_share(
        &share,
        submit_at + SHARE_MAX_OVERDUE_THRESHOLD_SECONDS - 1,
        vote_end,
        policy,
    ));
    assert!(should_resubmit_share(
        &share,
        submit_at + SHARE_MAX_OVERDUE_THRESHOLD_SECONDS,
        vote_end,
        policy,
    ));
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
fn resubmission_window_closes_exactly_at_the_cutoff() {
    let policy = ShareTimingPolicy::default();
    let vote_end = 200;

    assert!(is_share_resubmission_window_open(189, vote_end, policy));
    assert!(!is_share_resubmission_window_open(190, vote_end, policy));
    assert!(!is_share_resubmission_window_open(200, vote_end, policy));
    assert!(!is_share_resubmission_window_open(
        u64::MAX,
        vote_end,
        policy
    ));
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

    let summary = summarize_share_tracking(&shares, 130, Some(200), ShareTimingPolicy::default());

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
