use super::*;
use crate::share_policy::SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS;

// ---- Initial fan-out -------------------------------------------------

#[tokio::test(start_paused = true)]
async fn fan_out_stops_at_the_target_count() {
    let transport = Arc::new(MockTransport::default());
    for index in 1..=5 {
        transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(index)),
            json_status("queued"),
        );
    }

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(5),
        3,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(1), helper(2), helper(3)]);
    assert!(report.ambiguous_urls.is_empty());
    assert_eq!(report.target_count, 3);
    assert_eq!(transport.calls().len(), 3);
}

#[tokio::test(start_paused = true)]
async fn overlapping_initial_fan_outs_share_one_target() {
    let db = db_with_recoverable_vote();
    let servers = helpers(4);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post_after(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        Duration::from_secs(1),
        json_status("queued"),
    );
    for index in 2..=4 {
        transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(index)),
            json_status("queued"),
        );
    }
    let client = client_with(transport.clone());
    let params = InitialShareSubmissionParams {
        target_count: 2,
        ..initial_submission(&servers)
    };

    let first_cancel = never_cancel();
    let second_cancel = never_cancel();
    let (first, second) = tokio::join!(
        submit_share_to_helpers(&db, &client, &params, &first_cancel),
        submit_share_to_helpers(&db, &client, &params, &second_cancel),
    );

    assert_eq!(first.unwrap().accepted_urls.len(), 2);
    assert_eq!(second.unwrap().accepted_urls.len(), 2);
    assert_eq!(transport.call_count("/shares"), 2);
    assert_eq!(only_share(&db).sent_to_urls.len(), 2);
}

#[tokio::test(start_paused = true)]
async fn cancellation_aborts_initial_wait_for_live_share_operation() {
    use std::sync::atomic::{AtomicBool, Ordering};

    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id("initial-cancellation-lock-wait");
    seed_recoverable_vote_for_wallet(&db, "initial-cancellation-lock-wait");
    let scope = share::ShareOperationScope::capture(&db);
    let _operation_guard = lock_share_operation(&scope, ROUND_ID, 0, 1, 0)
        .await
        .unwrap();
    let servers = helpers(2);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let submission = InitialShareSubmissionParams {
        target_count: 1,
        ..initial_submission(&servers)
    };
    let cancelled = AtomicBool::new(false);
    let cancel = || cancelled.load(Ordering::Relaxed);

    let trigger_cancellation = async {
        tokio::time::sleep(Duration::from_millis(1)).await;
        cancelled.store(true, Ordering::Relaxed);
    };
    let (report, ()) = tokio::join!(
        submit_share_to_helpers(&db, &client, &submission, &cancel),
        trigger_cancellation,
    );
    let report = report.unwrap();

    assert!(report.accepted_urls.is_empty());
    assert!(report.ambiguous_urls.is_empty());
    assert!(transport.calls().is_empty());
    assert!(only_share(&db).attempting_urls.is_empty());
}

#[tokio::test(start_paused = true)]
async fn tracking_waits_for_live_initial_fan_out_before_replenishing() {
    let db = Arc::new(db_with_recoverable_vote());
    let servers = helpers(3);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post_after(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        Duration::from_secs(1),
        json_status("queued"),
    );
    for index in 2..=3 {
        transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(index)),
            json_status("queued"),
        );
    }
    let client = client_with(transport.clone());
    let initial_db = Arc::clone(&db);
    let initial_client = client.clone();
    let initial_servers = servers.clone();
    let initial = tokio::spawn(async move {
        let params = InitialShareSubmissionParams {
            target_count: 2,
            ..initial_submission(&initial_servers)
        };
        submit_share_to_helpers(&initial_db, &initial_client, &params, &never_cancel())
            .await
            .unwrap();
    });
    while transport.call_count(&helper(1)) == 0 {
        tokio::task::yield_now().await;
    }
    let random = zero_bytes;
    let mut tracking_params = params(&servers, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;

    let report = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();
    initial.await.unwrap();

    assert!(report.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shares"), 2);
    assert_eq!(only_share(&db).sent_to_urls.len(), 2);
}

#[tokio::test(start_paused = true)]
async fn fan_out_moves_past_a_refusing_helper() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(3),
        1,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(2)]);
    assert_eq!(client.health().failure_count(&helper(1)), 1);
}

#[tokio::test(start_paused = true)]
async fn fan_out_never_retries_the_same_helper() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &[helper(1)],
        3,
        10,
        &never_cancel(),
    )
    .await;

    assert!(report.accepted_urls.is_empty());
    // One attempt, then the candidate pool is exhausted — no spinning.
    assert_eq!(transport.call_count(&helper(1)), 1);
}

#[tokio::test(start_paused = true)]
async fn fan_out_returns_partial_acceptance_rather_than_failing() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("queued"),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        http_status(400),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        2,
        10,
        &never_cancel(),
    )
    .await;

    // Under-placed, not lost: tracking spreads it further later.
    assert_eq!(report.accepted_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn fan_out_retains_ambiguous_attempts_separately() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        Err(HelperTransportError::Ambiguous(
            "connection closed before headers".to_string(),
        )),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        1,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(2)]);
    assert_eq!(report.ambiguous_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&helper(1)), 1);
}

#[tokio::test(start_paused = true)]
async fn fan_out_retains_unusable_successful_response_as_ambiguous() {
    let transport = Arc::new(MockTransport::default());
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(&first_url, Ok(HelperResponse::json(200, br#"{}"#.to_vec())));
    transport.queue_post(&first_url, json_status("queued"));
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        1,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(2)]);
    assert_eq!(report.ambiguous_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&first_url), 1);
}

#[tokio::test(start_paused = true)]
async fn fan_out_retains_server_error_as_ambiguous_without_retrying() {
    let transport = Arc::new(MockTransport::default());
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(&first_url, http_status(503));
    transport.queue_post(&first_url, json_status("queued"));
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        1,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(2)]);
    assert_eq!(report.ambiguous_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&first_url), 1);
}

#[tokio::test(start_paused = true)]
async fn fan_out_stops_at_the_overall_deadline_and_clamps_the_last_request() {
    let transport = Arc::new(MockTransport::default());
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let second_url = format!("{}/shielded-vote/v1/shares", helper(2));
    transport.queue_post_after(&first_url, Duration::from_secs(50), json_status("queued"));
    transport.queue_post_after(&second_url, Duration::from_secs(20), json_status("queued"));
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );
    let config = HelperClientConfig::default()
        .with_post_timeout(Duration::from_secs(90))
        .unwrap()
        .without_retries();
    let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
    let started = tokio::time::Instant::now();

    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(3),
        3,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(
        started.elapsed(),
        Duration::from_millis(SHARE_INITIAL_DELIVERY_TIMEOUT_MILLISECONDS)
    );
    assert_eq!(report.accepted_urls, vec![helper(1)]);
    assert_eq!(report.ambiguous_urls, vec![helper(2)]);
    assert_eq!(transport.timeout_for(&first_url), Duration::from_secs(60));
    assert_eq!(transport.timeout_for(&second_url), Duration::from_secs(10));
    assert_eq!(transport.call_count(&helper(3)), 0);
}

#[tokio::test(start_paused = true)]
async fn definite_failure_in_backoff_is_not_marked_ambiguous() {
    let transport = Arc::new(MockTransport::default());
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    // The attempt definitely fails 100 ms before the overall deadline, so
    // the 200 ms retry backoff would cross it. The held definite error
    // must surface instead of the deadline converting it into an unknown
    // outcome mid-sleep.
    transport.queue_post_after(
        &first_url,
        Duration::from_millis(59_900),
        Err(HelperTransportError::Transport(
            "connect refused".to_string(),
        )),
    );
    let config = HelperClientConfig::default()
        .with_post_timeout(Duration::from_secs(90))
        .unwrap();
    let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);

    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        2,
        10,
        &never_cancel(),
    )
    .await;

    assert!(report.accepted_urls.is_empty());
    assert!(
        report.ambiguous_urls.is_empty(),
        "a definite pre-response failure must stay definite: {:?}",
        report.ambiguous_urls
    );
    assert_eq!(transport.call_count(&helper(2)), 0);
}

#[tokio::test(start_paused = true)]
async fn definite_failure_at_backoff_deadline_clears_durable_attempt_and_retries_later() {
    let db = db_with_delivery(&[], &[], 1);
    let transport = Arc::new(MockTransport::default());
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post_after(
        &first_url,
        Duration::from_millis(59_900),
        Err(HelperTransportError::Transport(
            "connect refused".to_string(),
        )),
    );
    transport.queue_post(&first_url, json_status("queued"));
    let config = HelperClientConfig::default()
        .with_post_timeout(Duration::from_secs(90))
        .unwrap();
    let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
    let servers = helpers(2);

    let first =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();
    assert!(first.accepted_urls.is_empty());
    assert!(first.ambiguous_urls.is_empty());
    assert!(only_share(&db).attempting_urls.is_empty());

    let second =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();
    assert_eq!(second.accepted_urls, vec![helper(1)]);
    assert!(only_share(&db).attempting_urls.is_empty());
    assert_eq!(transport.call_count(&first_url), 2);
}

#[tokio::test(start_paused = true)]
async fn no_attempt_starts_under_minimum_budget() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post_after(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        Duration::from_millis(59_500),
        json_status("queued"),
    );
    let config = HelperClientConfig::default()
        .with_post_timeout(Duration::from_secs(90))
        .unwrap()
        .without_retries();
    let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);

    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &helpers(2),
        2,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(1)]);
    assert!(report.ambiguous_urls.is_empty());
    // 500 ms of budget is below the minimum, so the second helper is
    // never contacted rather than burned into ambiguity.
    assert_eq!(transport.call_count(&helper(2)), 0);
}

#[tokio::test(start_paused = true)]
async fn fan_out_canonicalizes_candidates_without_shrinking_the_target() {
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let report = submit_initial_share_to_candidates(
        &client,
        valid_share_json(),
        &[helper(1), format!("{}/", helper(1))],
        3,
        10,
        &never_cancel(),
    )
    .await;

    assert_eq!(report.accepted_urls, vec![helper(1)]);
    assert_eq!(report.target_count, 3);
    assert_eq!(transport.call_count(&helper(1)), 1);
}

#[tokio::test(start_paused = true)]
async fn initial_post_is_journaled_before_transport_dispatch() {
    let db = Arc::new(db_with_delivery(&[], &[], 1));
    let transport = Arc::new(MockTransport::default());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(&post_url, json_status("queued"));
    let observed_db = db.clone();
    transport.observe_posts(move |_| {
        let stored = only_share(&observed_db);
        assert_eq!(stored.attempting_urls, vec![helper(1)]);
        assert!(stored.sent_to_urls.is_empty());
    });
    let client = client_with(transport);
    let servers = vec![helper(1)];

    let report =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();

    assert_eq!(report.accepted_urls, vec![helper(1)]);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.attempting_urls.is_empty());
}

#[tokio::test(start_paused = true)]
async fn submit_rejects_invalid_candidate_url_before_any_network_io() {
    let db = db_with_delivery(&[], &[], 1);
    let before = only_share(&db);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let servers = vec![helper(1), "helper.example:443".to_string()];

    let error =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap_err();

    assert!(
        matches!(error, VotingError::InvalidInput { .. }),
        "unexpected error: {error}"
    );
    assert_eq!(transport.call_count(&helper(1)), 0);
    let after = only_share(&db);
    assert_eq!(after.sent_to_urls, before.sent_to_urls);
    assert_eq!(after.ambiguous_urls, before.ambiguous_urls);
    assert_eq!(after.attempting_urls, before.attempting_urls);
    assert_eq!(after.target_count, before.target_count);
    assert_eq!(after.submit_at, before.submit_at);
}

#[tokio::test(start_paused = true)]
async fn invalid_candidate_url_does_not_create_a_share_record() {
    let db = db_with_recoverable_vote();
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let servers = vec![helper(1), "helper.example:443".to_string()];

    let error =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn committed_vote_submission_keeps_degraded_planned_target_before_healthy_fallback() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET vc_tree_position = 789
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
    let configured = helpers(2);
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 1,
        target_servers: vec![helper(2)],
    };
    let post_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));
    let health = HelperHealth::default();
    for _ in 0..HELPER_FAILURE_THRESHOLD {
        health.record_failure(&helper(2), SUBMIT_AT);
    }
    let client = HelperClient::new(transport.clone(), health);

    let report = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.accepted_urls, vec![helper(2)]);
    let body = transport.posted_json(&post_url);
    assert_eq!(body["vote_round_id"], ROUND_ID);
    assert_eq!(body["proposal_id"], 1);
    assert_eq!(body["share_index"], 0);
    assert_eq!(body["tree_position"], 789);
    assert_eq!(body["submit_at"], 4_321);
    let stored = only_share(&db);
    assert_eq!(stored.bundle_index, 0);
    assert_eq!(stored.proposal_id, 1);
    assert_eq!(stored.share_index, 0);
    assert_eq!(stored.sent_to_urls, vec![helper(2)]);
    assert_eq!(transport.call_count(&helper(1)), 0);
}

#[tokio::test(start_paused = true)]
async fn stale_committed_vote_submission_is_rejected_before_side_effects() {
    let db = db_with_round_and_bundle();
    let original_recovery = recovery_bundle_fixture();
    crate::vote::insert_recovery_fixture(&db, &original_recovery).unwrap();
    let original_handle = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let stale_handle = original_handle.clone();

    let mut replacement_recovery = original_recovery;
    replacement_recovery.vote_commitment = [0x42; 32];
    crate::vote::insert_recovery_fixture(&db, &replacement_recovery).unwrap();
    let current_handle = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    current_handle.record_vc_position(&db, 789).unwrap();

    let configured = helpers(1);
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 1,
        target_servers: configured.clone(),
    };
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));
    let client = client_with(transport.clone());

    let error = stale_handle
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(
        error
            .to_string()
            .contains("committed vote changed before helper share submission"),
        "{error}"
    );
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(transport.calls().is_empty());
    let persisted = crate::vote::recovery_bundle(&db, ROUND_ID, 0, 1)
        .unwrap()
        .unwrap();
    assert_eq!(
        persisted.vote_commitment,
        replacement_recovery.vote_commitment
    );
    assert_eq!(persisted.vc_tree_position, 789);
}

#[test]
fn generation_bound_preparation_rejects_replacement_after_validation() {
    let db = db_with_round_and_bundle();
    let original_recovery = recovery_bundle_fixture();
    crate::vote::insert_recovery_fixture(&db, &original_recovery).unwrap();
    let expected_commitment_bundle_json =
        crate::vote::serialize_recovery(&original_recovery).unwrap();
    let expected_nullifier = share::nullifier_from_recovery_json(
        &expected_commitment_bundle_json,
        original_recovery.proposal_id,
        0,
    )
    .unwrap();
    let scope = share::ShareOperationScope::capture(&db);
    let submission = ShareSubmissionReport {
        target_count: 1,
        ..ShareSubmissionReport::default()
    };
    let params = share::ShareDeliveryRecordParams {
        round_id: ROUND_ID,
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        submission: &submission,
        submit_at: 4_321,
    };

    // This replacement models the interval after the committed-handle check
    // and before preparation journals the first helper attempt.
    let mut replacement_recovery = original_recovery;
    replacement_recovery.vote_commitment = [0x42; 32];
    crate::vote::insert_recovery_fixture(&db, &replacement_recovery).unwrap();

    let error = share::record_delivery_for_committed_vote(
        &db,
        &scope,
        &params,
        &expected_commitment_bundle_json,
        &expected_nullifier,
    )
    .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(
        error
            .to_string()
            .contains("committed vote changed before helper share delivery"),
        "{error}"
    );
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test(start_paused = true)]
async fn repeated_committed_submission_preserves_the_original_schedule() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(2);
    let first_plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 1,
        target_servers: vec![helper(1)],
    };
    let second_plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 9_876,
        target_count: 1,
        target_servers: vec![helper(2)],
    };
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("queued"),
    );
    let client = client_with(transport.clone());

    for plan in [&first_plan, &second_plan] {
        committed
            .submit_share_to_helpers_internal(
                &db,
                &client,
                CommittedShareSubmissionRequest {
                    share_index: 0,
                    plan,
                    planning_server_urls: &configured,
                    configured_server_urls: &configured,
                    now_seconds: SUBMIT_AT,
                },
                &never_cancel(),
            )
            .await
            .unwrap();
    }

    let stored = only_share(&db);
    assert_eq!(stored.submit_at, first_plan.submit_at);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&helper(1)), 1);
    assert_eq!(transport.call_count(&helper(2)), 0);
}

#[tokio::test(start_paused = true)]
async fn repeated_partial_committed_submission_sends_original_schedule_to_new_helper() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let first_plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 2,
        target_servers: vec![helper(1), helper(2)],
    };
    let second_plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 9_876,
        target_count: 2,
        target_servers: vec![helper(3), helper(2)],
    };
    let first_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let second_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let new_url = format!("{}/shielded-vote/v1/shares", helper(3));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post_after(&first_url, Duration::from_secs(50), json_status("queued"));
    transport.queue_post_after(&second_url, Duration::from_secs(20), json_status("queued"));
    transport.queue_post(&new_url, json_status("queued"));
    let config = HelperClientConfig::default()
        .with_post_timeout(Duration::from_secs(90))
        .unwrap()
        .without_retries();
    let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);

    let first = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &first_plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(first.accepted_urls, vec![helper(1)]);
    assert_eq!(first.ambiguous_urls, vec![helper(2)]);
    assert_eq!(first.target_count, 2);
    assert_eq!(transport.call_count(&helper(3)), 0);

    let second = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &second_plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(second.accepted_urls, vec![helper(1), helper(3)]);
    assert_eq!(second.ambiguous_urls, vec![helper(2)]);
    assert_eq!(second.target_count, 2);
    assert_eq!(transport.posted_submit_at(&new_url), first_plan.submit_at);
    assert_eq!(transport.call_count(&helper(1)), 1);
    assert_eq!(transport.call_count(&helper(2)), 1);
    assert_eq!(transport.call_count(&helper(3)), 1);
    let stored = only_share(&db);
    assert_eq!(stored.submit_at, first_plan.submit_at);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(3)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert!(stored.attempting_urls.is_empty());
}

#[tokio::test(start_paused = true)]
async fn repeated_committed_submission_does_not_resurrect_zero_schedule() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let initial = ShareSubmissionReport {
        accepted_urls: vec![helper(1)],
        target_count: 2,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &initial,
            submit_at: 0,
        },
    )
    .unwrap();
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 9_876,
        target_count: 2,
        target_servers: vec![helper(2), helper(3)],
    };
    let new_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&new_url, json_status("queued"));
    let client = client_with(transport.clone());

    let report = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.accepted_urls, vec![helper(1), helper(2)]);
    assert_eq!(transport.posted_submit_at(&new_url), 0);
    assert_eq!(transport.call_count(&helper(3)), 0);
    assert_eq!(only_share(&db).submit_at, 0);
}

#[tokio::test(start_paused = true)]
async fn committed_vote_submission_rejects_mismatched_plan_before_side_effects() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(2);
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 1,
        target_servers: vec![helper(3)],
    };
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());

    let error = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn committed_submission_rejects_duplicate_spelling_fleet_before_effects() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1), format!("HTTPS://HELPER-1.EXAMPLE:443/")];
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 1,
        target_servers: vec![helper(1)],
    };
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());

    let error = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn committed_vote_submission_rejects_uncapped_large_fleet_target() {
    let db = db_with_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(33);
    let plan = ShareSubmissionPlan {
        immediate: false,
        submit_at: 4_321,
        target_count: 11,
        target_servers: configured[..11].to_vec(),
    };
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());

    let error = committed
        .submit_share_to_helpers_internal(
            &db,
            &client,
            CommittedShareSubmissionRequest {
                share_index: 0,
                plan: &plan,
                planning_server_urls: &configured,
                configured_server_urls: &configured,
                now_seconds: SUBMIT_AT,
            },
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn tracking_rejects_invalid_configured_url() {
    let configured = vec![
        helper(1),
        "https://helper.example/vote?tenant=1".to_string(),
    ];
    let db = db_with_share(&[helper(1)]);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let error = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap_err();

    assert!(
        matches!(error, VotingError::InvalidInput { .. }),
        "unexpected error: {error}"
    );
    assert_eq!(transport.call_count(&helper(1)), 0);
}

#[tokio::test(start_paused = true)]
async fn tracking_rejects_duplicate_spelling_fleet_before_effects() {
    let configured = vec![helper(1), "HTTPS://HELPER-1.EXAMPLE:443/".to_string()];
    let db = db_with_share(&[helper(1)]);
    let before = only_share(&db);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let error = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    let after = only_share(&db);
    assert_eq!(after.sent_to_urls, before.sent_to_urls);
    assert_eq!(after.ambiguous_urls, before.ambiguous_urls);
    assert_eq!(after.attempting_urls, before.attempting_urls);
    assert_eq!(after.confirmed, before.confirmed);
    assert_eq!(after.submit_at, before.submit_at);
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn tracking_rejects_empty_fleet_before_effects() {
    let db = db_with_share(&[helper(1)]);
    let before = only_share(&db);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let error = track_pending_shares(
        &db,
        &params(&[], ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    let after = only_share(&db);
    assert_eq!(after.sent_to_urls, before.sent_to_urls);
    assert_eq!(after.ambiguous_urls, before.ambiguous_urls);
    assert_eq!(after.attempting_urls, before.attempting_urls);
    assert_eq!(after.confirmed, before.confirmed);
    assert_eq!(after.submit_at, before.submit_at);
    assert!(transport.calls().is_empty());
}

#[tokio::test(start_paused = true)]
async fn definite_initial_failure_clears_attempt_and_remains_retryable() {
    let db = db_with_delivery(&[], &[], 1);
    let transport = Arc::new(MockTransport::default());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(
        &post_url,
        Err(HelperTransportError::Transport(
            "connect failed".to_string(),
        )),
    );
    transport.queue_post(&post_url, json_status("queued"));
    let client = HelperClient::with_config(
        transport.clone(),
        HelperHealth::default(),
        HelperClientConfig::default().without_retries(),
    );
    let servers = vec![helper(1)];

    let first =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();
    assert!(first.accepted_urls.is_empty());
    assert!(only_share(&db).attempting_urls.is_empty());

    let second =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();
    assert_eq!(second.accepted_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&post_url), 2);
}

#[tokio::test(start_paused = true)]
async fn ambiguous_initial_failure_is_not_replayed_by_initial_delivery() {
    let db = db_with_delivery(&[], &[], 1);
    let transport = Arc::new(MockTransport::default());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(
        &post_url,
        Err(HelperTransportError::Ambiguous(
            "request timeout".to_string(),
        )),
    );
    transport.queue_post(&post_url, json_status("queued"));
    let client = client_with(transport.clone());
    let servers = vec![helper(1)];

    submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
        .await
        .unwrap();
    let stored = only_share(&db);
    assert_eq!(stored.ambiguous_urls, vec![helper(1)]);
    assert!(stored.attempting_urls.is_empty());

    submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
        .await
        .unwrap();
    assert_eq!(transport.call_count(&post_url), 1);
}

#[tokio::test(start_paused = true)]
async fn failed_outcome_write_is_reported_as_ambiguous_on_resume() {
    let db = Arc::new(db_with_delivery(&[], &[], 1));
    let transport = Arc::new(MockTransport::default());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    transport.queue_post(&post_url, json_status("queued"));
    let trigger_db = db.clone();
    transport.observe_posts(move |_| {
        trigger_db
            .conn()
            .execute_batch(
                "CREATE TRIGGER fail_delivery_promotion
                 BEFORE UPDATE OF sent_to_urls ON share_delegations
                 BEGIN SELECT RAISE(FAIL, 'injected promotion failure'); END;",
            )
            .unwrap();
    });
    let client = client_with(transport.clone());
    let servers = vec![helper(1)];

    let result =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel()).await;

    assert!(result.is_err());
    let stored = only_share(&db);
    assert_eq!(stored.attempting_urls, vec![helper(1)]);
    assert!(stored.sent_to_urls.is_empty());

    db.conn()
        .execute_batch("DROP TRIGGER fail_delivery_promotion")
        .unwrap();
    transport.queue_post(&post_url, json_status("queued"));
    let resumed =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel())
            .await
            .unwrap();

    assert!(resumed.accepted_urls.is_empty());
    assert_eq!(resumed.ambiguous_urls, vec![helper(1)]);
    assert_eq!(resumed.target_count, 1);
    let stored = only_share(&db);
    assert!(stored.sent_to_urls.is_empty());
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.attempting_urls, vec![helper(1)]);
    assert_eq!(transport.call_count(&post_url), 1);
}

#[tokio::test(start_paused = true)]
async fn failed_attempt_write_prevents_network_dispatch() {
    let db = db_with_delivery(&[], &[], 1);
    db.conn()
        .execute_batch(
            "CREATE TRIGGER fail_attempt_write
             BEFORE UPDATE OF attempting_urls ON share_delegations
             BEGIN SELECT RAISE(FAIL, 'injected attempt failure'); END;",
        )
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let servers = vec![helper(1)];

    let result =
        submit_share_to_helpers(&db, &client, &initial_submission(&servers), &never_cancel()).await;

    assert!(result.is_err());
    assert!(transport.calls().is_empty());
}

#[test]
fn concurrent_attempt_reservations_preserve_both_markers() {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "zcash-voting-concurrent-attempts-{}-{unique}.sqlite",
        std::process::id()
    ));
    let path_string = path.to_string_lossy().into_owned();
    let first_db = VotingDb::open(&path_string).unwrap();
    first_db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&first_db);
    let initial = ShareSubmissionReport {
        target_count: 2,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &first_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &initial,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();

    let second_db = VotingDb::open(&path_string).unwrap();
    second_db.set_wallet_id(WALLET_ID);
    let writer = second_db.conn();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    writer
        .execute(
            "UPDATE share_delegations SET attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":attempting_urls": serde_json::to_string(&[helper(2)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let reservation = std::thread::spawn(move || {
        let first_helper = helper(1);
        let attempt = share::ShareDeliveryAttemptParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            server_url: &first_helper,
            target_count: 2,
            submit_at: SUBMIT_AT,
        };
        started_tx.send(()).unwrap();
        let placement_servers = helpers(2);
        let added = share::begin_existing_delivery_attempt(&first_db, &attempt, &placement_servers)
            .unwrap();
        (first_db, added)
    });
    started_rx.recv().unwrap();
    std::thread::sleep(Duration::from_millis(400));
    writer.execute_batch("COMMIT").unwrap();
    drop(writer);

    let (first_db, added) = reservation.join().unwrap();
    assert!(added);
    assert_eq!(
        only_share(&second_db).attempting_urls,
        vec![helper(2), helper(1)]
    );

    drop(first_db);
    drop(second_db);
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{path_string}-shm"));
    let _ = std::fs::remove_file(format!("{path_string}-wal"));
}

#[test]
fn concurrent_attempt_reservations_share_one_placement_capacity() {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "zcash-voting-concurrent-attempt-capacity-{}-{unique}.sqlite",
        std::process::id()
    ));
    let path_string = path.to_string_lossy().into_owned();
    let first_db = VotingDb::open(&path_string).unwrap();
    first_db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&first_db);
    share::record_delivery(
        &first_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &ShareSubmissionReport {
                target_count: 1,
                ..ShareSubmissionReport::default()
            },
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();

    let second_db = VotingDb::open(&path_string).unwrap();
    second_db.set_wallet_id(WALLET_ID);
    let writer = second_db.conn();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    writer
        .execute(
            "UPDATE share_delegations SET attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":attempting_urls": serde_json::to_string(&[helper(2)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let reservation = std::thread::spawn(move || {
        let first_helper = helper(1);
        let placement_servers = helpers(2);
        let attempt = share::ShareDeliveryAttemptParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            server_url: &first_helper,
            target_count: 1,
            submit_at: SUBMIT_AT,
        };
        started_tx.send(()).unwrap();
        let added = share::begin_existing_delivery_attempt(&first_db, &attempt, &placement_servers)
            .unwrap();
        (first_db, added)
    });
    started_rx.recv().unwrap();
    std::thread::sleep(Duration::from_millis(400));
    writer.execute_batch("COMMIT").unwrap();
    drop(writer);

    let (first_db, added) = reservation.join().unwrap();
    assert!(!added);
    assert_eq!(only_share(&second_db).attempting_urls, vec![helper(2)]);

    drop(first_db);
    drop(second_db);
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{path_string}-shm"));
    let _ = std::fs::remove_file(format!("{path_string}-wal"));
}

#[test]
fn concurrent_acceptances_preserve_both_results() {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "zcash-voting-concurrent-acceptances-{}-{unique}.sqlite",
        std::process::id()
    ));
    let path_string = path.to_string_lossy().into_owned();
    let first_db = VotingDb::open(&path_string).unwrap();
    first_db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&first_db);
    let initial = ShareSubmissionReport {
        target_count: 2,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &first_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &initial,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    first_db
        .conn()
        .execute(
            "UPDATE share_delegations SET attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":attempting_urls": serde_json::to_string(&[helper(1), helper(2)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let second_db = VotingDb::open(&path_string).unwrap();
    second_db.set_wallet_id(WALLET_ID);
    let writer = second_db.conn();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    writer
        .execute(
            "UPDATE share_delegations
             SET sent_to_urls = :sent_to_urls, attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":sent_to_urls": serde_json::to_string(&[helper(2)]).unwrap(),
                ":attempting_urls": serde_json::to_string(&[helper(1)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let resolution = std::thread::spawn(move || {
        let first_helper = helper(1);
        let attempt = share::ShareDeliveryAttemptParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            server_url: &first_helper,
            target_count: 2,
            submit_at: SUBMIT_AT,
        };
        started_tx.send(()).unwrap();
        share::resolve_delivery_attempt(
            &first_db,
            &attempt,
            share::ShareDeliveryAttemptOutcome::Accepted,
            false,
        )
        .unwrap();
        first_db
    });
    started_rx.recv().unwrap();
    std::thread::sleep(Duration::from_millis(400));
    writer.execute_batch("COMMIT").unwrap();
    drop(writer);

    let first_db = resolution.join().unwrap();
    let stored = only_share(&second_db);
    assert_eq!(stored.sent_to_urls, vec![helper(2), helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());

    drop(first_db);
    drop(second_db);
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{path_string}-shm"));
    let _ = std::fs::remove_file(format!("{path_string}-wal"));
}

#[test]
fn concurrent_delivery_record_preserves_stronger_state() {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "zcash-voting-concurrent-delivery-record-{}-{unique}.sqlite",
        std::process::id()
    ));
    let path_string = path.to_string_lossy().into_owned();
    let first_db = VotingDb::open(&path_string).unwrap();
    first_db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&first_db);
    let initial = ShareSubmissionReport {
        target_count: 2,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &first_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &initial,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    first_db
        .conn()
        .execute(
            "UPDATE share_delegations SET attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":attempting_urls": serde_json::to_string(&[helper(3)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let second_db = VotingDb::open(&path_string).unwrap();
    second_db.set_wallet_id(WALLET_ID);
    let mut injected_concurrent_update = false;
    let mut after_read = || {
        if injected_concurrent_update {
            return;
        }
        injected_concurrent_update = true;
        second_db
            .conn()
            .execute(
                "UPDATE share_delegations
                 SET sent_to_urls = :sent_to_urls,
                     attempting_urls = :attempting_urls,
                     target_count = 3
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
                rusqlite::named_params! {
                    ":sent_to_urls": serde_json::to_string(&[helper(2)]).unwrap(),
                    ":attempting_urls": serde_json::to_string(&[helper(3)]).unwrap(),
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
    };
    let nullifier = only_share(&first_db).nullifier;
    let conn = first_db.conn();
    let durable_submit_at = queries::record_share_delegation_with_after_read(
        &conn,
        ROUND_ID,
        WALLET_ID,
        0,
        1,
        0,
        &[helper(1)],
        &[],
        2,
        &nullifier,
        SUBMIT_AT + 100,
        &mut after_read,
    )
    .unwrap();
    drop(conn);

    assert!(injected_concurrent_update);
    assert_eq!(durable_submit_at, SUBMIT_AT);
    let stored = only_share(&second_db);
    assert_eq!(stored.sent_to_urls, vec![helper(2), helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.attempting_urls, vec![helper(3)]);
    assert_eq!(stored.target_count, 3);
    assert_eq!(stored.submit_at, SUBMIT_AT);

    drop(first_db);
    drop(second_db);
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{path_string}-shm"));
    let _ = std::fs::remove_file(format!("{path_string}-wal"));
}

#[test]
fn concurrent_definite_failure_does_not_restore_an_accepted_attempt() {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "zcash-voting-concurrent-failure-{}-{unique}.sqlite",
        std::process::id()
    ));
    let path_string = path.to_string_lossy().into_owned();
    let first_db = VotingDb::open(&path_string).unwrap();
    first_db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&first_db);
    let initial = ShareSubmissionReport {
        target_count: 2,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &first_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &initial,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    first_db
        .conn()
        .execute(
            "UPDATE share_delegations SET attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":attempting_urls": serde_json::to_string(&[helper(1), helper(2)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let second_db = VotingDb::open(&path_string).unwrap();
    second_db.set_wallet_id(WALLET_ID);
    let writer = second_db.conn();
    writer.execute_batch("BEGIN IMMEDIATE").unwrap();
    writer
        .execute(
            "UPDATE share_delegations
             SET sent_to_urls = :sent_to_urls, attempting_urls = :attempting_urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":sent_to_urls": serde_json::to_string(&[helper(2)]).unwrap(),
                ":attempting_urls": serde_json::to_string(&[helper(1)]).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let resolution = std::thread::spawn(move || {
        let first_helper = helper(1);
        let attempt = share::ShareDeliveryAttemptParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            server_url: &first_helper,
            target_count: 2,
            submit_at: SUBMIT_AT,
        };
        started_tx.send(()).unwrap();
        share::resolve_delivery_attempt(
            &first_db,
            &attempt,
            share::ShareDeliveryAttemptOutcome::DefiniteFailure,
            false,
        )
        .unwrap();
        first_db
    });
    started_rx.recv().unwrap();
    std::thread::sleep(Duration::from_millis(400));
    writer.execute_batch("COMMIT").unwrap();
    drop(writer);

    let first_db = resolution.join().unwrap();
    let stored = only_share(&second_db);
    assert_eq!(stored.sent_to_urls, vec![helper(2)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());

    drop(first_db);
    drop(second_db);
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{path_string}-shm"));
    let _ = std::fs::remove_file(format!("{path_string}-wal"));
}

#[test]
fn attempting_updates_preserve_noncanonical_legacy_history() {
    let db = db_with_delivery(&[], &[], 1);
    db.conn()
        .execute(
            "UPDATE share_delegations SET attempting_urls = :urls
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":urls": r#"["legacy helper without a URL"]"#,
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
    let attempt = share::ShareDeliveryAttemptParams {
        round_id: ROUND_ID,
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        server_url: &helper(1),
        target_count: 1,
        submit_at: SUBMIT_AT,
    };

    assert!(share::begin_existing_delivery_attempt(&db, &attempt, &[helper(1)]).unwrap());
    let after_add: String = db
        .conn()
        .query_row(
            "SELECT attempting_urls FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Vec<String>>(&after_add).unwrap(),
        vec!["https://helper-1.example", "legacy helper without a URL"]
    );

    share::resolve_delivery_attempt(
        &db,
        &attempt,
        share::ShareDeliveryAttemptOutcome::DefiniteFailure,
        false,
    )
    .unwrap();
    let after_remove: String = db
        .conn()
        .query_row(
            "SELECT attempting_urls FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Vec<String>>(&after_remove).unwrap(),
        vec!["legacy helper without a URL"]
    );
}

#[tokio::test(start_paused = true)]
async fn initial_delivery_stays_bound_to_its_starting_wallet() {
    const OTHER_WALLET: &str = "other-initial-wallet";

    let configured = helpers(1);
    let db = db_with_recoverable_vote();
    db.set_wallet_id(OTHER_WALLET);
    seed_recoverable_vote_for_wallet(&db, OTHER_WALLET);
    let empty = ShareSubmissionReport {
        target_count: 1,
        ..ShareSubmissionReport::default()
    };
    share::record_delivery(
        &db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &empty,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    db.set_wallet_id(WALLET_ID);
    let db = Arc::new(db);
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));
    let switched_db = Arc::clone(&db);
    transport.observe_posts(move |_| switched_db.set_wallet_id(OTHER_WALLET));
    let client = client_with(transport);
    let request = initial_submission(&configured);

    let report = submit_share_to_helpers(&db, &client, &request, &never_cancel())
        .await
        .unwrap();

    assert_eq!(report.accepted_urls, vec![helper(1)]);
    assert_eq!(db.wallet_id(), OTHER_WALLET);
    assert!(only_share(&db).sent_to_urls.is_empty());
    db.set_wallet_id(WALLET_ID);
    assert_eq!(only_share(&db).sent_to_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn initial_delivery_rejects_a_replaced_share_generation() {
    let configured = helpers(1);
    let db = Arc::new(db_with_recoverable_vote());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));
    let replacing_db = Arc::clone(&db);
    transport.observe_posts(move |_| {
        replacing_db
            .conn()
            .execute(
                "UPDATE share_delegations SET nullifier = :nullifier
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
                rusqlite::named_params! {
                    ":nullifier": vec![0xF2_u8; 32],
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
    });
    let client = client_with(transport);
    let request = initial_submission(&configured);

    let error = submit_share_to_helpers(&db, &client, &request, &never_cancel())
        .await
        .unwrap_err();

    assert!(error
        .to_string()
        .contains("committed share changed while helper delivery was in flight"));
    let stored = only_share(&db);
    assert_eq!(stored.nullifier, vec![0xF2; 32]);
    assert!(stored.sent_to_urls.is_empty());
    assert_eq!(stored.attempting_urls, vec![helper(1)]);
}

#[test]
fn wrong_nullifier_generation_cannot_apply_any_delivery_transition() {
    let db = db_with_delivery(&[], &[], 1);
    let stored = only_share(&db);
    let attempt = share::ShareDeliveryAttemptParams {
        round_id: ROUND_ID,
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        server_url: &helper(1),
        target_count: 1,
        submit_at: SUBMIT_AT,
    };
    assert!(share::begin_existing_delivery_attempt(&db, &attempt, &[helper(1)]).unwrap());
    let scope = share::ShareOperationScope::capture(&db);
    let wrong_nullifier = vec![0xF4; 32];
    let wrong_generation = share::ShareGeneration::new(&scope, &wrong_nullifier);

    assert!(matches!(
        share::begin_existing_delivery_attempt_for_generation(
            &db,
            &attempt,
            wrong_generation,
            &[helper(1)],
            share::ShareAttemptCapacityPolicy::EnforcePlacementTarget,
        )
        .unwrap(),
        crate::storage::queries::ShareAttemptReservation::StaleGeneration
    ));
    assert_eq!(
        share::is_confirmed_for_generation(&db, &attempt, wrong_generation).unwrap(),
        None
    );
    assert!(!share::confirm_for_generation(&db, ROUND_ID, 0, 1, 0, wrong_generation).unwrap());
    for outcome in [
        share::ShareDeliveryAttemptOutcome::Accepted,
        share::ShareDeliveryAttemptOutcome::Ambiguous,
        share::ShareDeliveryAttemptOutcome::DefiniteFailure,
    ] {
        assert!(!share::resolve_delivery_attempt_for_generation(
            &db,
            &attempt,
            wrong_generation,
            outcome,
            false,
        )
        .unwrap());
    }

    let unchanged = only_share(&db);
    assert_eq!(unchanged.nullifier, stored.nullifier);
    assert!(unchanged.sent_to_urls.is_empty());
    assert!(unchanged.ambiguous_urls.is_empty());
    assert_eq!(unchanged.attempting_urls, vec![helper(1)]);
    assert!(!unchanged.confirmed);
}

#[tokio::test(start_paused = true)]
async fn initial_delivery_does_not_recreate_share_after_recovery_cleanup() {
    use std::sync::atomic::{AtomicBool, Ordering};

    let configured = helpers(2);
    let db = db_with_recoverable_vote();
    let transport = Arc::new(MockTransport::default());
    for server_url in &configured {
        transport.queue_post(
            &format!("{server_url}/shielded-vote/v1/shares"),
            json_status("queued"),
        );
    }
    let client = client_with(transport.clone());
    let cleared = AtomicBool::new(false);
    let clear_after_first_acceptance = || {
        if !cleared.load(Ordering::Relaxed)
            && share::list(&db, ROUND_ID)
                .unwrap()
                .first()
                .is_some_and(|record| !record.sent_to_urls.is_empty())
        {
            db.clear_recovery_state(ROUND_ID).unwrap();
            cleared.store(true, Ordering::Relaxed);
        }
        false
    };
    let request = InitialShareSubmissionParams {
        target_count: 2,
        ..initial_submission(&configured)
    };

    let error = submit_share_to_helpers(&db, &client, &request, &clear_after_first_acceptance)
        .await
        .unwrap_err();

    assert!(cleared.load(Ordering::Relaxed));
    assert!(error
        .to_string()
        .contains("committed share changed while helper delivery was in flight"));
    assert_eq!(transport.call_count("/shares"), 1);
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}
