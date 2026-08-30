use super::*;

#[test]
fn confirmed_shares_are_never_ready_or_overdue() {
    let share = share_record(true, 100);
    let flags = share_tracking_flags(&share, 100_000, Some(200_000), ShareTimingPolicy::default());
    assert!(flags.is_idle());
}

#[test]
fn missing_vote_end_suppresses_overdue_but_not_status_checks() {
    let share = share_record(false, 100);
    let flags = share_tracking_flags(&share, 100_000, None, ShareTimingPolicy::default());
    assert!(flags.ready_for_status_check);
    assert!(!flags.overdue_for_retry);
}

#[test]
fn young_share_is_idle_until_the_status_grace_passes() {
    let share = share_record(false, 1_000);
    let policy = ShareTimingPolicy::default();
    let just_before = 1_000 + policy.status_check_grace_seconds - 1;
    assert!(share_tracking_flags(&share, just_before, Some(500_000), policy).is_idle());

    let at_grace = 1_000 + policy.status_check_grace_seconds;
    assert!(share_tracking_flags(&share, at_grace, Some(500_000), policy).ready_for_status_check);
}

#[test]
fn dedupe_keeps_first_occurrence_order() {
    let urls = ["b", "a", "b", "c"].iter().map(|s| s.to_string());
    assert_eq!(dedupe_preserving_order(urls), vec!["b", "a", "c"]);
}
