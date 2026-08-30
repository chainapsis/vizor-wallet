use super::*;

// ---- Confirmation policy --------------------------------------------

#[tokio::test(start_paused = true)]
async fn two_distinct_confirmations_stop_status_checks() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    let status_url = |index: usize| {
        format!(
            "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
            helper(index)
        )
    };

    transport.queue_get(&status_url(1), json_status("confirmed"));
    transport.queue_get(&status_url(2), json_status("confirmed"));
    for index in 3..=6 {
        transport.queue_get_after(
            &status_url(index),
            Duration::from_secs(60 * 60),
            json_status("pending"),
        );
    }

    let client = client_with(transport.clone());
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(6),
        1_000,
        &never_cancel(),
    )
    .await;

    assert_eq!(outcome, ShareStatusOutcome::ConfiguredHelperQuorumObserved);
    // The bounded initial group may already be in flight, and one slot may
    // refill after the first confirmation. Observing the second aborts
    // those requests before the final configured helper is dispatched.
    assert_eq!(transport.call_count(&helper(6)), 0);
}

#[tokio::test(start_paused = true)]
async fn one_confirmation_is_not_enough() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    for (index, status) in [(1, "confirmed"), (2, "pending")] {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
                helper(index)
            ),
            json_status(status),
        );
    }

    let client = client_with(transport.clone());
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(2),
        1_000,
        &never_cancel(),
    )
    .await;

    assert_eq!(
        outcome,
        ShareStatusOutcome::ConfiguredHelperQuorumNotObserved
    );
    assert_eq!(transport.calls().len(), 2);
}

#[tokio::test(start_paused = true)]
async fn one_helper_fleet_uses_its_only_available_confirmation() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
            helper(1)
        ),
        json_status("confirmed"),
    );

    let client = client_with(transport.clone());
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(1),
        1_000,
        &never_cancel(),
    )
    .await;

    assert_eq!(outcome, ShareStatusOutcome::ConfiguredHelperQuorumObserved);
    assert_eq!(transport.calls().len(), 1);
}

#[tokio::test(start_paused = true)]
async fn every_helper_pending_reports_not_confirmed() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=3 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }

    let client = client_with(transport.clone());
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(3),
        1_000,
        &never_cancel(),
    )
    .await;

    assert_eq!(
        outcome,
        ShareStatusOutcome::ConfiguredHelperQuorumNotObserved
    );
    assert_eq!(transport.calls().len(), 3);
}

#[tokio::test(start_paused = true)]
async fn expired_status_budget_does_not_start_or_penalize_helpers() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let configured = helpers(SHARE_STATUS_MAX_CONCURRENT_POLLS + 1);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());

    let outcome = poll_share_helpers_with_budget(
        &client,
        &round_id,
        &share_id,
        &configured,
        1_000,
        &never_cancel(),
        0,
    )
    .await;

    assert_eq!(
        outcome,
        ShareStatusOutcome::ConfiguredHelperQuorumNotObserved
    );
    assert!(transport.calls().is_empty());
    for server_url in configured {
        assert_eq!(client.health().failure_count(&server_url), 0);
    }
}

#[tokio::test]
async fn budget_expiry_scores_only_polls_that_are_still_running() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let completed_url = helper(1);
    let stalled_url = helper(2);
    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!("{completed_url}/shielded-vote/v1/share-status/{round_id}/{share_id}"),
        json_status("pending"),
    );
    let client = client_with(transport.clone());
    client.health().record_failure(&completed_url, 900);
    client.health().record_failure(&completed_url, 901);

    let mut polls = tokio::task::JoinSet::new();
    let completed_client = client.clone();
    let completed_round = round_id.clone();
    let completed_share = share_id.clone();
    let completed_server = completed_url.clone();
    polls.spawn(async move {
        let outcome = completed_client
            .share_status(
                &completed_server,
                &completed_round,
                &completed_share,
                1_000,
                &never_cancel(),
            )
            .await;
        (completed_server, outcome)
    });
    let stalled_server = stalled_url.clone();
    polls.spawn(async move {
        std::future::pending::<()>().await;
        #[allow(unreachable_code)]
        (
            stalled_server,
            Err(crate::helper::client::HelperError::Cancelled),
        )
    });

    while transport.call_count(&completed_url) == 0
        || client.health().failure_count(&completed_url) != 0
    {
        tokio::task::yield_now().await;
    }

    let mut in_flight = HashSet::from([completed_url.clone(), stalled_url.clone()]);
    let mut confirmations = 0;
    let quorum = finish_expired_polls(
        &mut polls,
        &mut in_flight,
        &mut confirmations,
        2,
        &client,
        1_001,
    )
    .await;

    assert!(!quorum);
    assert_eq!(client.health().failure_count(&completed_url), 0);
    assert_eq!(client.health().failure_count(&stalled_url), 1);
}

#[tokio::test]
async fn budget_expiry_preserves_boundary_quorum_without_penalizing_abort() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    let confirmed_urls = [helper(1), helper(2)];
    let stalled_url = helper(3);
    let client = client_with(Arc::new(MockTransport::default()));
    let completed = Arc::new(AtomicUsize::new(0));
    let mut polls = tokio::task::JoinSet::new();
    for server_url in confirmed_urls.clone() {
        let completed = Arc::clone(&completed);
        polls.spawn(async move {
            completed.fetch_add(1, Ordering::Release);
            (
                server_url,
                Ok(crate::helper::client::ShareStatus::Confirmed),
            )
        });
    }
    let stalled_server = stalled_url.clone();
    polls.spawn(async move {
        std::future::pending::<()>().await;
        #[allow(unreachable_code)]
        (
            stalled_server,
            Err(crate::helper::client::HelperError::Cancelled),
        )
    });
    while completed.load(Ordering::Acquire) != confirmed_urls.len() {
        tokio::task::yield_now().await;
    }
    tokio::task::yield_now().await;

    let mut in_flight = HashSet::from([
        confirmed_urls[0].clone(),
        confirmed_urls[1].clone(),
        stalled_url.clone(),
    ]);
    let mut confirmations = 0;
    let quorum = finish_expired_polls(
        &mut polls,
        &mut in_flight,
        &mut confirmations,
        confirmed_urls.len(),
        &client,
        1_001,
    )
    .await;

    assert!(quorum);
    assert_eq!(confirmations, confirmed_urls.len());
    assert_eq!(in_flight, HashSet::from([stalled_url.clone()]));
    assert_eq!(client.health().failure_count(&stalled_url), 0);
}

#[tokio::test(start_paused = true)]
async fn cancellation_aborts_bounded_in_flight_status_polls() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    transport.queue_get_after(
        &format!(
            "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
            helper(1)
        ),
        Duration::from_secs(60 * 60),
        json_status("pending"),
    );
    transport.queue_get_after(
        &format!(
            "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
            helper(2)
        ),
        Duration::from_secs(60 * 60),
        json_status("confirmed"),
    );
    let cancel_after_dispatch = || transport.calls().len() == 2;

    let client = client_with(transport.clone());
    let started = tokio::time::Instant::now();
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(2),
        1_000,
        &cancel_after_dispatch,
    )
    .await;

    assert_eq!(outcome, ShareStatusOutcome::Cancelled);
    assert_eq!(transport.calls().len(), 2);
    assert_eq!(
        started.elapsed(),
        Duration::from_millis(SHARE_STATUS_CANCEL_CHECK_MILLISECONDS)
    );
}

#[tokio::test(start_paused = true)]
async fn late_cancellation_does_not_replace_final_confirmation() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
                helper(index)
            ),
            json_status("confirmed"),
        );
    }
    let cancel_checks = AtomicUsize::new(0);
    let cancel_after_first_join = || cancel_checks.fetch_add(1, Ordering::Relaxed) > 0;

    let client = client_with(transport);
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(2),
        1_000,
        &cancel_after_first_join,
    )
    .await;

    assert_eq!(outcome, ShareStatusOutcome::ConfiguredHelperQuorumObserved);
}

#[tokio::test(start_paused = true)]
async fn late_cancellation_does_not_replace_final_failed_poll() {
    let round_id = field_hex(1);
    let share_id = "cd".repeat(32);
    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{round_id}/{share_id}",
            helper(1)
        ),
        http_status(400),
    );
    let cancel_after_request = || transport.call_count(&helper(1)) > 0;

    let client = client_with(transport.clone());
    let outcome = poll_share_helpers(
        &client,
        &round_id,
        &share_id,
        &helpers(1),
        1_000,
        &cancel_after_request,
    )
    .await;

    assert_eq!(
        outcome,
        ShareStatusOutcome::ConfiguredHelperQuorumNotObserved
    );
    assert_eq!(client.health().failure_count(&helper(1)), 1);
}

#[tokio::test(start_paused = true)]
async fn late_cancellation_does_not_replace_final_failed_resubmission() {
    let configured = helpers(1);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );
    let cancel_after_post = || transport.call_count("/shares") > 0;

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &cancel_after_post,
    )
    .await
    .unwrap();

    assert!(!report.cancelled);
    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    assert_eq!(transport.call_count("/shares"), 1);
    assert_eq!(client.health().failure_count(&helper(1)), 1);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}
