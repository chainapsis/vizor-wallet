use super::*;

fn mark_interrupted_attempt(db: &VotingDb, server_url: &str) {
    let stored = only_share(db);
    let attempt = share::ShareDeliveryAttemptParams {
        round_id: ROUND_ID,
        bundle_index: stored.bundle_index,
        proposal_id: stored.proposal_id,
        share_index: stored.share_index,
        server_url,
        target_count: usize::try_from(stored.target_count).unwrap(),
        submit_at: stored.submit_at,
    };
    assert!(
        share::begin_existing_delivery_attempt(db, &attempt, &[server_url.to_string()]).unwrap()
    );
}

#[tokio::test(start_paused = true)]
async fn invalid_status_scores_a_failure_without_blocking_confirmation() {
    let configured = helpers(5);
    let db = db_with_share(&configured);
    let share_id = share_id_of(&db);
    let now = ready_not_overdue();

    let transport = Arc::new(MockTransport::default());
    let status_url = |index: usize| {
        format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(index)
        )
    };
    // Helper 1 answers outside the protocol's two states.
    transport.queue_get(&status_url(1), json_status("not_found"));
    transport.queue_get(&status_url(2), json_status("confirmed"));
    transport.queue_get(&status_url(3), json_status("confirmed"));

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    // Two distinct configured helpers form the trusted confirmation quorum.
    assert_eq!(
        report.confirmed,
        vec![ShareKey {
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0
        }]
    );
    assert!(only_share(&db).confirmed);
    assert!(share::unconfirmed(&db, ROUND_ID).unwrap().is_empty());

    // The invalid answer cost helper 1 health.
    assert_eq!(client.health().failure_count(&helper(1)), 1);

    // Confirmation short-circuited recovery. The bounded concurrent group
    // may already include helpers beyond the two that formed the quorum.
    assert_eq!(transport.call_count("/shielded-vote/v1/shares"), 0);
    assert!(report.resubmitted.is_empty());
    assert!(transport.calls().len() <= configured.len());

    // Existing definite placement history is unchanged.
    assert_eq!(only_share(&db).sent_to_urls.len(), 5);
}

#[tokio::test(start_paused = true)]
async fn confirmation_stays_bound_to_the_wallet_that_started_tracking() {
    const OTHER_WALLET: &str = "other-share-wallet";

    let configured = helpers(2);
    let db = db_with_delivery(&configured, &[], configured.len());
    db.set_wallet_id(OTHER_WALLET);
    seed_recoverable_vote_for_wallet(&db, OTHER_WALLET);
    let submission = ShareSubmissionReport {
        accepted_urls: configured.clone(),
        ambiguous_urls: Vec::new(),
        target_count: configured.len(),
    };
    share::record_delivery(
        &db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &submission,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    db.set_wallet_id(WALLET_ID);
    let share_id = share_id_of(&db);
    let db = Arc::new(db);

    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("confirmed"),
        );
    }
    let switched_db = Arc::clone(&db);
    transport.observe_gets(move |_| switched_db.set_wallet_id(OTHER_WALLET));
    let client = client_with(transport);
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(db.wallet_id(), OTHER_WALLET);
    assert!(!only_share(&db).confirmed);
    db.set_wallet_id(WALLET_ID);
    assert!(only_share(&db).confirmed);
    assert_eq!(report.confirmed.len(), 1);
}

#[tokio::test(start_paused = true)]
async fn confirmation_does_not_apply_to_a_replaced_share_generation() {
    let configured = helpers(2);
    let db = Arc::new(db_with_delivery(&configured, &[], configured.len()));
    let share_id = share_id_of(&db);
    let replacement_nullifier = vec![0xF1; 32];
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("confirmed"),
        );
    }
    let replacing_db = Arc::clone(&db);
    let replacement_for_observer = replacement_nullifier.clone();
    transport.observe_gets(move |_| {
        replacing_db
            .conn()
            .execute(
                "UPDATE share_delegations SET nullifier = :nullifier
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
                rusqlite::named_params! {
                    ":nullifier": replacement_for_observer,
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
    });
    let client = client_with(transport);
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    let stored = only_share(&db);
    assert_eq!(stored.nullifier, replacement_nullifier);
    assert!(!stored.confirmed);
    assert!(report.confirmed.is_empty());
}

#[tokio::test(start_paused = true)]
async fn two_helper_fleet_polls_beyond_its_single_placement() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("confirmed"),
        );
    }

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.confirmed.len(), 1);
    assert!(only_share(&db).confirmed);
    assert_eq!(transport.call_count(&helper(1)), 1);
    assert_eq!(transport.call_count(&helper(2)), 1);
    assert_eq!(transport.call_count("/shares"), 0);
}

#[tokio::test(start_paused = true)]
async fn stalled_status_poll_does_not_starve_a_later_share() {
    let configured = helpers(SHARE_STATUS_MAX_CONCURRENT_POLLS);
    let db = db_with_delivery_for_wallet("stalled-status-poll", &configured, &[], configured.len());
    let submission = ShareSubmissionReport {
        accepted_urls: configured.clone(),
        ambiguous_urls: Vec::new(),
        target_count: configured.len(),
    };
    share::record_delivery(
        &db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 1,
            submission: &submission,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();

    let first_share_id = share_id_at(&db, 0);
    let second_share_id = share_id_at(&db, 1);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=configured.len() {
        transport.queue_get_after(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{first_share_id}",
                helper(index)
            ),
            Duration::from_secs(60 * 60),
            json_status("pending"),
        );
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{second_share_id}",
                helper(index)
            ),
            json_status(if index <= 2 { "confirmed" } else { "pending" }),
        );
    }
    let config = HelperClientConfig::default()
        .with_request_timeout(Duration::from_secs(60 * 60))
        .unwrap()
        .without_retries();
    let client = HelperClient::with_config(transport, HelperHealth::default(), config);
    let random = zero_bytes;
    let started = tokio::time::Instant::now();

    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(
        started.elapsed(),
        Duration::from_millis(SHARE_STATUS_POLL_BUDGET_MILLISECONDS)
    );
    assert_eq!(
        report.confirmed,
        vec![ShareKey {
            bundle_index: 0,
            proposal_id: 1,
            share_index: 1,
        }]
    );
    let shares = share::list(&db, ROUND_ID).unwrap();
    assert!(
        !shares
            .iter()
            .find(|share| share.share_index == 0)
            .unwrap()
            .confirmed
    );
    assert!(
        shares
            .iter()
            .find(|share| share.share_index == 1)
            .unwrap()
            .confirmed
    );
}

#[tokio::test(start_paused = true)]
async fn one_confirmation_does_not_suppress_under_placement_recovery() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let share_id = share_id_of(&db);
    let post_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("confirmed"),
    );
    for index in 2..=3 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    transport.queue_post(&post_url, json_status("queued"));

    let client = client_with(transport.clone());
    let random = preserve_two_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.confirmed.is_empty());
    assert_eq!(
        report.resubmitted,
        vec![ResubmittedShare {
            share: ShareKey {
                bundle_index: 0,
                proposal_id: 1,
                share_index: 0,
            },
            server_url: helper(2),
        }]
    );
    let stored = only_share(&db);
    assert!(!stored.confirmed);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
    assert_eq!(transport.call_count("share-status"), 3);
    assert_eq!(transport.call_count("/shares"), 1);
    assert_eq!(transport.posted_submit_at(&post_url), SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn overdue_share_reaches_an_untried_helper_and_records_it() {
    let configured = helpers(2);
    let db = db_with_share(&[helper(1)]);
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(2)
        ),
        json_status("pending"),
    );
    // Untried helpers come first in the resubmission order.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(
        report.resubmitted,
        vec![ResubmittedShare {
            share: ShareKey {
                bundle_index: 0,
                proposal_id: 1,
                share_index: 0
            },
            server_url: helper(2),
        }]
    );
    // The new helper is durably recorded, so the next pass polls it too.
    let stored = only_share(&db);
    assert!(!stored.confirmed);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(2)]);
    assert_eq!(stored.submit_at, 0);
    assert_eq!(
        transport.posted_submit_at(&format!("{}/shielded-vote/v1/shares", helper(2))),
        0
    );
}

#[tokio::test(start_paused = true)]
async fn overdue_recovery_reposts_to_accepted_helper_after_untried_helpers_fail() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        http_status(400),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("duplicate"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    assert_eq!(report.resubmitted[0].server_url, helper(1));
    assert_eq!(transport.call_count("/shares"), 2);
    assert_eq!(only_share(&db).sent_to_urls, vec![helper(1)]);
    assert_eq!(only_share(&db).submit_at, 0);
}

#[tokio::test(start_paused = true)]
async fn ambiguous_accepted_helper_retry_preserves_the_stronger_delivery_state() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        http_status(400),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(503),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    assert_eq!(transport.call_count("/shares"), 2);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn under_placed_share_preserves_delayed_submit_at() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let post_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));

    let client = client_with(transport.clone());
    let random = preserve_two_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    assert_eq!(report.resubmitted[0].server_url, helper(2));
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
    assert_eq!(transport.call_count("share-status"), 0);
    assert_eq!(transport.posted_submit_at(&post_url), SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn one_tracking_pass_fills_the_complete_placement_deficit() {
    let configured = helpers(3);
    let db = db_with_delivery(&[], &[], 3);
    let transport = Arc::new(MockTransport::default());
    for server_url in &configured {
        transport.queue_post(
            &format!("{server_url}/shielded-vote/v1/shares"),
            json_status("queued"),
        );
    }

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 3);
    assert_eq!(transport.call_count("/shares"), 3);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls.len(), 3);
    assert!(configured
        .iter()
        .all(|url| stored.sent_to_urls.contains(url)));
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn early_replenishment_never_reposts_to_an_accepted_helper() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[helper(2)], 2);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        Err(HelperTransportError::Transport("refused".to_string())),
    );

    let client = client_with(transport.clone());
    let random = preserve_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    assert_eq!(transport.call_count(&helper(3)), 1);
    assert_eq!(transport.call_count(&helper(1)), 0);
    assert_eq!(only_share(&db).sent_to_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn one_tracking_pass_does_not_repeat_a_definite_failure() {
    let configured = helpers(4);
    let db = db_with_delivery(&[], &[], 3);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        Err(HelperTransportError::Transport("refused".to_string())),
    );
    for index in 2..=4 {
        transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(index)),
            json_status("queued"),
        );
    }

    let client = client_with(transport.clone());
    let random = preserve_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 3);
    assert_eq!(transport.call_count(&helper(1)), 1);
    assert_eq!(transport.call_count("/shares"), 4);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(2), helper(3), helper(4)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn a_definite_failure_is_eligible_again_on_a_later_pass() {
    let configured = helpers(2);
    let db = db_with_delivery(&[], &[], 1);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(index)),
            Err(HelperTransportError::Transport("refused".to_string())),
        );
    }

    let client = client_with(transport.clone());
    let random = preserve_server_order;
    let first = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();
    assert!(first.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shares"), 2);

    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("queued"),
    );
    let second = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(second.resubmitted[0].server_url, helper(1));
    assert_eq!(transport.call_count(&helper(1)), 2);
    assert_eq!(only_share(&db).sent_to_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn persisted_desired_target_replenishes_when_the_fleet_expands() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1), helper(2)], &[], 3);
    let post_url = format!("{}/shielded-vote/v1/shares", helper(3));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(3));
    let stored = only_share(&db);
    assert_eq!(stored.target_count, 3);
    assert_eq!(stored.sent_to_urls, configured);
}

#[tokio::test(start_paused = true)]
async fn legacy_target_above_protocol_cap_is_effectively_clamped() {
    let configured = helpers(30);
    let accepted = configured[..crate::share_policy::SHARE_HELPER_TARGET_COUNT_CAP].to_vec();
    let db = db_with_delivery(&accepted, &[], 99);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(transport.calls().is_empty());
    assert_eq!(only_share(&db).target_count, 99);
    assert_eq!(only_share(&db).sent_to_urls, accepted);
}

#[tokio::test(start_paused = true)]
async fn under_placement_stops_at_the_resubmission_cutoff() {
    for now_seconds in [
        VOTE_END - ShareTimingPolicy::default().resubmit_cutoff_seconds,
        VOTE_END,
    ] {
        let configured = helpers(2);
        let db = db_with_delivery(&[helper(1)], &[], 2);
        let share_id = share_id_of(&db);
        let transport = Arc::new(MockTransport::default());
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(1)
            ),
            json_status("pending"),
        );

        let client = client_with(transport.clone());
        let no_recovery_randomness = |_: usize| -> Vec<u8> {
            panic!("cutoff must be checked before building a recovery order")
        };
        let report = track_pending_shares(
            &db,
            &params(&configured, now_seconds, &no_recovery_randomness),
            &client,
            &never_cancel(),
        )
        .await
        .unwrap();

        assert!(report.resubmitted.is_empty());
        assert!(report.ambiguous.is_empty());
        assert_eq!(transport.call_count("/shares"), 0);
        let stored = only_share(&db);
        assert_eq!(stored.sent_to_urls, vec![helper(1)]);
        assert_eq!(stored.submit_at, SUBMIT_AT);
    }
}

#[tokio::test(start_paused = true)]
async fn resubmission_rechecks_the_cutoff_before_every_post() {
    use std::sync::atomic::{AtomicU64, Ordering};

    let configured = helpers(3);
    let db = db_with_delivery(&[], &[], 3);
    let transport = Arc::new(MockTransport::default());
    for server_url in &configured {
        transport.queue_post(
            &format!("{server_url}/shielded-vote/v1/shares"),
            json_status("queued"),
        );
    }
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let now_seconds = VOTE_END - ShareTimingPolicy::default().resubmit_cutoff_seconds - 1;
    let elapsed = AtomicU64::new(0);
    let elapsed_seconds = || {
        if elapsed.fetch_add(1, Ordering::Relaxed) < 4 {
            0
        } else {
            1
        }
    };

    let report = track_pending_shares_with_elapsed(
        &db,
        &params(&configured, now_seconds, &random),
        &client,
        &never_cancel(),
        &elapsed_seconds,
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    assert_eq!(transport.call_count("/shares"), 1);
    assert_eq!(only_share(&db).sent_to_urls.len(), 1);
}

#[tokio::test(start_paused = true)]
async fn missing_vote_end_still_allows_early_replenishment() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let post_url = format!("{}/shielded-vote/v1/shares", helper(2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;
    let report = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    assert_eq!(transport.posted_submit_at(&post_url), SUBMIT_AT);
    assert_eq!(only_share(&db).submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn pending_status_keeps_an_ambiguous_attempt_out_of_placement() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[helper(2)], 2);
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    assert_eq!(report.resubmitted[0].server_url, helper(3));
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(3)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
    assert_eq!(transport.call_count(&helper(2)), 1);
    assert_eq!(transport.call_count("/shares"), 1);
}

#[tokio::test(start_paused = true)]
async fn ambiguous_resubmission_is_recorded_while_recovery_continues() {
    let configured = helpers(3);
    let db = Arc::new(db_with_delivery(&[helper(1)], &[], 2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        Err(HelperTransportError::Timeout),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );
    let observed_db = db.clone();
    transport.observe_posts(move |url| {
        let expected = if url.contains("helper-2") {
            helper(2)
        } else {
            helper(3)
        };
        assert!(only_share(&observed_db).attempting_urls.contains(&expected));
    });

    let client = client_with(transport.clone());
    let random = preserve_two_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.ambiguous.len(), 1);
    assert_eq!(report.ambiguous[0].server_url, helper(2));
    assert_eq!(report.resubmitted[0].server_url, helper(3));
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(3)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn ambiguous_attempt_is_durable_before_recovery_advances() {
    let configured = helpers(3);
    let db = Arc::new(db_with_delivery(&[helper(1)], &[], 2));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        Err(HelperTransportError::Timeout),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );
    let observed_db = db.clone();
    transport.observe_posts(move |url| {
        if url.contains("helper-3") {
            let stored = only_share(&observed_db);
            assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
            assert_eq!(stored.submit_at, SUBMIT_AT);
        }
    });

    let client = client_with(transport.clone());
    let random = preserve_two_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(!report.cancelled);
    assert_eq!(report.ambiguous.len(), 1);
    assert_eq!(report.ambiguous[0].server_url, helper(2));
    assert_eq!(report.resubmitted[0].server_url, helper(3));
    assert_eq!(transport.call_count(&helper(3)), 1);
}

#[tokio::test(start_paused = true)]
async fn overdue_ambiguous_attempt_resets_the_delayed_schedule() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 2);
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
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        Err(HelperTransportError::Timeout),
    );

    let client = client_with(transport);
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.ambiguous.len(), 1);
    let stored = only_share(&db);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, 0);
}

#[tokio::test(start_paused = true)]
async fn unusable_successful_resubmission_is_recorded_while_recovery_continues() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        Ok(HelperResponse::json(
            200,
            br#"{"message":"queued"}"#.to_vec(),
        )),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let random = preserve_two_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.ambiguous.len(), 1);
    assert_eq!(report.ambiguous[0].server_url, helper(2));
    assert_eq!(report.resubmitted[0].server_url, helper(3));
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(3)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
}

#[tokio::test(start_paused = true)]
async fn early_replenishment_excludes_ambiguous_helpers() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[helper(2)], 2);
    db.conn()
        .execute(
            "UPDATE share_delegations SET ambiguous_urls = :urls",
            rusqlite::named_params! {
                ":urls": serde_json::to_string(&[format!("{}/", helper(2))]).unwrap(),
            },
        )
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        http_status(400),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    assert_eq!(transport.call_count(&helper(3)), 1);
    assert_eq!(transport.call_count(&helper(1)), 0);
    assert_eq!(transport.call_count(&helper(2)), 0);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
}

#[tokio::test(start_paused = true)]
async fn overdue_recovery_retries_ambiguous_helper_after_untried() {
    let configured = helpers(2);
    let db = db_with_delivery(&[], &[helper(2)], 2);
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(2)
        ),
        json_status("pending"),
    );
    // The untried helper is contacted first and definitely refuses.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );
    // The outcome-unknown helper is then re-POSTed and accepts.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(
        report.resubmitted,
        vec![ResubmittedShare {
            share: ShareKey {
                bundle_index: 0,
                proposal_id: 1,
                share_index: 0
            },
            server_url: helper(2),
        }]
    );
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(2)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.submit_at, 0);
}

#[tokio::test(start_paused = true)]
async fn concurrent_confirmation_stops_outcome_unknown_retry() {
    let configured = helpers(2);
    let db = Arc::new(db_with_delivery(&[], &[helper(2)], 2));
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(2)
        ),
        json_status("pending"),
    );
    // The fresh helper refuses after another task confirms the share.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );
    // This response is intentionally queued: reaching it would reproduce
    // the stale-snapshot bug by re-POSTing the outcome-unknown helper.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );
    let confirming_db = db.clone();
    transport.observe_posts(move |url| {
        if url.contains("helper-1") {
            share::confirm(&confirming_db, ROUND_ID, 0, 1, 0).unwrap();
        }
    });

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    assert_eq!(
        transport.call_count(&helper(1)),
        2,
        "status GET plus recovery POST"
    );
    assert_eq!(transport.call_count(&helper(2)), 1, "status GET only");
    assert_eq!(transport.call_count("share-status"), 2);
    assert_eq!(transport.call_count("/shares"), 1);
    let stored = only_share(&db);
    assert!(stored.confirmed);
    assert!(stored.sent_to_urls.is_empty());
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
    assert_eq!(report.next_delay_seconds, None);
}

#[tokio::test(start_paused = true)]
async fn small_fleet_all_ambiguous_still_recovers() {
    // The review scenario: every helper produced one outcome-unknown POST
    // during initial fan-out, and all have since recovered. An overdue
    // pass must still deliver instead of locking the share out.
    let configured = helpers(2);
    let db = db_with_delivery(&[], &[helper(1), helper(2)], 1);
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    // The helper kept the original POST after all: `duplicate` converges
    // to a definite acceptance without double-counting.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        json_status("duplicate"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted.len(), 1);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert_eq!(stored.ambiguous_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, 0);
    assert_eq!(transport.call_count(&helper(2)), 1, "status poll only");
}

#[tokio::test(start_paused = true)]
async fn early_replenishment_prefers_untried_before_an_interrupted_attempt() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    mark_interrupted_attempt(&db, &helper(2));
    let post_url = format!("{}/shielded-vote/v1/shares", helper(3));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("queued"));

    let client = client_with(transport.clone());
    let random = preserve_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(3));
    assert_eq!(transport.call_count(&helper(2)), 0);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(3)]);
    assert_eq!(stored.attempting_urls, vec![helper(2)]);
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn overdue_recovery_retries_an_interrupted_attempt_after_untried_helpers() {
    let configured = helpers(2);
    let db = db_with_delivery(&[], &[], 1);
    mark_interrupted_attempt(&db, &helper(2));
    let share_id = share_id_of(&db);
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("duplicate"),
    );

    let client = client_with(transport.clone());
    let random = preserve_server_order;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(2));
    assert_eq!(transport.call_count("/shares"), 2);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(2)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, 0);
}

#[tokio::test(start_paused = true)]
async fn failed_interrupted_attempt_retry_becomes_explicitly_ambiguous() {
    let configured = helpers(1);
    let db = db_with_delivery(&[], &[], 1);
    mark_interrupted_attempt(&db, &helper(1));
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

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert_eq!(report.ambiguous[0].server_url, helper(1));
    assert_eq!(transport.call_count("/shares"), 1);
    let stored = only_share(&db);
    assert!(stored.sent_to_urls.is_empty());
    assert_eq!(stored.ambiguous_urls, vec![helper(1)]);
    assert!(stored.attempting_urls.is_empty());
}

#[tokio::test(start_paused = true)]
async fn interrupted_one_helper_share_recovers_without_vote_end_time() {
    let configured = helpers(1);
    let db = db_with_delivery(&[], &[], 1);
    mark_interrupted_attempt(&db, &helper(1));
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("duplicate"));
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;

    let report = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(1));
    assert_eq!(transport.call_count("/shares"), 1);
    assert_eq!(transport.posted_submit_at(&post_url), SUBMIT_AT);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn placement_satisfied_share_reconciles_interrupted_attempt_without_expanding() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    mark_interrupted_attempt(&db, &helper(2));
    let interrupted_post = format!("{}/shielded-vote/v1/shares", helper(2));
    let untried_post = format!("{}/shielded-vote/v1/shares", helper(3));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&interrupted_post, json_status("duplicate"));
    transport.queue_post(&untried_post, json_status("queued"));
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;

    let report = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(2));
    assert_eq!(transport.call_count(&interrupted_post), 1);
    assert_eq!(transport.call_count(&untried_post), 0);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(2)]);
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn interrupted_retry_does_not_resolve_a_replaced_share_generation() {
    let configured = helpers(1);
    let db = Arc::new(db_with_delivery(&[], &[], 1));
    mark_interrupted_attempt(&db, &helper(1));
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, json_status("duplicate"));
    let replacing_db = Arc::clone(&db);
    transport.observe_posts(move |_| {
        replacing_db
            .conn()
            .execute(
                "UPDATE share_delegations SET nullifier = :nullifier
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
                rusqlite::named_params! {
                    ":nullifier": vec![0xF3_u8; 32],
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
    });
    let client = client_with(transport);
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;

    let report = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    let stored = only_share(&db);
    assert_eq!(stored.nullifier, vec![0xF3; 32]);
    assert!(stored.sent_to_urls.is_empty());
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.attempting_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn failed_early_interrupted_retry_is_not_repeated_without_vote_end_time() {
    let configured = helpers(1);
    let db = db_with_delivery(&[], &[], 1);
    mark_interrupted_attempt(&db, &helper(1));
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(&post_url, http_status(400));
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;

    let first = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();
    let second = track_pending_shares(&db, &tracking_params, &client, &never_cancel())
        .await
        .unwrap();

    assert_eq!(first.ambiguous[0].server_url, helper(1));
    assert!(second.resubmitted.is_empty());
    assert!(second.ambiguous.is_empty());
    assert_eq!(transport.call_count("/shares"), 1);
    let stored = only_share(&db);
    assert_eq!(stored.ambiguous_urls, vec![helper(1)]);
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn cancellation_before_interrupted_retry_keeps_the_crash_marker() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    let configured = helpers(1);
    let db = db_with_delivery(&[], &[], 1);
    mark_interrupted_attempt(&db, &helper(1));
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let mut tracking_params = params(&configured, SUBMIT_AT - 1, &random);
    tracking_params.vote_end_time_seconds = None;
    let checks = AtomicUsize::new(0);
    let cancel_before_dispatch = || checks.fetch_add(1, Ordering::Relaxed) > 0;

    let report = track_pending_shares(&db, &tracking_params, &client, &cancel_before_dispatch)
        .await
        .unwrap();

    assert!(report.cancelled);
    assert!(transport.calls().is_empty());
    let stored = only_share(&db);
    assert_eq!(stored.attempting_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn ambiguous_repost_failure_keeps_ambiguous_state() {
    let configured = helpers(1);
    let db = db_with_delivery(&[], &[helper(1)], 1);
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );
    // A definite refusal of the re-POST says nothing about the original
    // outcome-unknown POST.
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(1)),
        http_status(400),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.resubmitted.is_empty());
    assert!(report.ambiguous.is_empty());
    let stored = only_share(&db);
    assert!(stored.sent_to_urls.is_empty());
    assert_eq!(stored.ambiguous_urls, vec![helper(1)]);
}

#[tokio::test(start_paused = true)]
async fn resubmission_demotes_degraded_helpers_within_the_untried_group() {
    let configured = helpers(3);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let transport = Arc::new(MockTransport::default());
    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(3)),
        json_status("queued"),
    );

    let client = client_with(transport.clone());
    for _ in 0..crate::helper::health::HELPER_FAILURE_THRESHOLD {
        client.health().record_failure(&helper(2), SUBMIT_AT);
    }
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.resubmitted[0].server_url, helper(3));
    assert_eq!(transport.call_count(&helper(2)), 0);
}

#[tokio::test(start_paused = true)]
async fn confirmed_share_is_never_resubmitted_even_when_overdue() {
    let configured = helpers(2);
    let db = db_with_share(&configured);
    let share_id = share_id_of(&db);
    let now = overdue();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("confirmed"),
    );
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(2)
        ),
        json_status("confirmed"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, now, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.confirmed.len(), 1);
    assert!(only_share(&db).confirmed);
    assert!(report.resubmitted.is_empty());
    // Confirmation short-circuits the overdue branch entirely.
    assert_eq!(transport.call_count("/shielded-vote/v1/shares"), 0);
    assert_eq!(only_share(&db).sent_to_urls, configured);
}

#[tokio::test(start_paused = true)]
async fn idle_share_contacts_no_helper() {
    let configured = helpers(3);
    let db = db_with_share(&configured);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(transport.calls().is_empty());
    assert!(report.confirmed.is_empty());
    // Still pending, so the caller is told when to come back.
    assert!(report.next_delay_seconds.is_some());
}

#[tokio::test(start_paused = true)]
async fn unconfigured_helpers_are_not_polled() {
    let configured = vec![helper(1)];
    // The share was also sent to a helper the wallet has since dropped.
    let db = db_with_share(&[helper(1), helper(9)]);
    let share_id = share_id_of(&db);

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(transport.call_count(&helper(9)), 0);
}

#[tokio::test(start_paused = true)]
async fn fresh_recovery_cancelled_before_dispatch_clears_marker_and_remains_retryable() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let cancel_after_journal = || only_share(&db).attempting_urls.contains(&helper(2));

    let cancelled = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &cancel_after_journal,
    )
    .await
    .unwrap();

    assert!(cancelled.cancelled);
    assert!(transport.calls().is_empty());
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);

    transport.queue_post(
        &format!("{}/shielded-vote/v1/shares", helper(2)),
        json_status("queued"),
    );
    let retried = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(!retried.cancelled);
    assert_eq!(retried.resubmitted[0].server_url, helper(2));
    assert_eq!(transport.call_count("/shares"), 1);
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1), helper(2)]);
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn cancelled_outcome_unknown_retry_preserves_ambiguous_state() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    let configured = helpers(1);
    let db = db_with_delivery(&[], &[helper(1)], 1);
    let stored = only_share(&db);
    let outcome_unknown_urls = vec![helper(1)];
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let tracking_params = params(&configured, overdue(), &random);
    let cancel_checks = AtomicUsize::new(0);
    let cancel_before_dispatch = || cancel_checks.fetch_add(1, Ordering::Relaxed) > 0;
    let mut attempted_urls = Vec::new();
    let scope = share::ShareOperationScope::capture(&db);

    let report = resubmit_to_next_helper(
        &db,
        &scope,
        &tracking_params,
        &client,
        &ResubmitRequest {
            share: &stored,
            configured_urls: &configured,
            definite_acceptance_urls: &[],
            ambiguous_urls: &outcome_unknown_urls,
            interrupted_attempt_urls: &[],
            target_count: 1,
            schedule: ResubmissionSchedule::Immediate,
            candidates: ResubmissionCandidates::FullRecoveryOrder,
        },
        &mut attempted_urls,
        &cancel_before_dispatch,
        &|| 0,
    )
    .await
    .unwrap();

    assert!(matches!(report.outcome, ResubmitOutcome::Cancelled));
    assert!(transport.calls().is_empty());
    let stored = only_share(&db);
    assert!(stored.sent_to_urls.is_empty());
    assert_eq!(stored.ambiguous_urls, vec![helper(1)]);
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn cancelled_accepted_fallback_preserves_acceptance() {
    use std::sync::atomic::{AtomicUsize, Ordering};

    let configured = helpers(1);
    let db = db_with_delivery(&[helper(1)], &[], 1);
    let stored = only_share(&db);
    let definite_acceptance_urls = vec![helper(1)];
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let tracking_params = params(&configured, overdue(), &random);
    let cancel_checks = AtomicUsize::new(0);
    let cancel_before_dispatch = || cancel_checks.fetch_add(1, Ordering::Relaxed) > 0;
    let mut attempted_urls = Vec::new();
    let scope = share::ShareOperationScope::capture(&db);

    let report = resubmit_to_next_helper(
        &db,
        &scope,
        &tracking_params,
        &client,
        &ResubmitRequest {
            share: &stored,
            configured_urls: &configured,
            definite_acceptance_urls: &definite_acceptance_urls,
            ambiguous_urls: &[],
            interrupted_attempt_urls: &[],
            target_count: 1,
            schedule: ResubmissionSchedule::Immediate,
            candidates: ResubmissionCandidates::FullRecoveryOrder,
        },
        &mut attempted_urls,
        &cancel_before_dispatch,
        &|| 0,
    )
    .await
    .unwrap();

    assert!(matches!(report.outcome, ResubmitOutcome::Cancelled));
    assert!(transport.calls().is_empty());
    let stored = only_share(&db);
    assert_eq!(stored.sent_to_urls, vec![helper(1)]);
    assert!(stored.ambiguous_urls.is_empty());
    assert!(stored.attempting_urls.is_empty());
    assert_eq!(stored.submit_at, SUBMIT_AT);
}

#[tokio::test(start_paused = true)]
async fn cancelled_pass_reports_cancellation_and_keeps_durable_effects() {
    let configured = helpers(2);
    let db = db_with_share(&configured);
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let always_cancel = || true;

    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &always_cancel,
    )
    .await
    .unwrap();

    assert!(report.cancelled);
    assert!(transport.calls().is_empty());
    assert!(!only_share(&db).confirmed);
}

#[tokio::test(start_paused = true)]
async fn cancellation_aborts_wait_for_live_share_operation() {
    use std::sync::atomic::{AtomicBool, Ordering};

    let configured = helpers(2);
    let db =
        db_with_delivery_for_wallet("cancellation-lock-wait", &configured, &[], configured.len());
    let scope = share::ShareOperationScope::capture(&db);
    let _operation_guard = lock_share_operation(&scope, ROUND_ID, 0, 1, 0)
        .await
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;
    let cancelled = AtomicBool::new(false);
    let cancel = || cancelled.load(Ordering::Relaxed);
    let tracking_params = params(&configured, ready_not_overdue(), &random);

    let trigger_cancellation = async {
        tokio::time::sleep(Duration::from_millis(1)).await;
        cancelled.store(true, Ordering::Relaxed);
    };
    let (report, ()) = tokio::join!(
        track_pending_shares(&db, &tracking_params, &client, &cancel),
        trigger_cancellation,
    );
    let report = report.unwrap();

    assert!(report.cancelled);
    assert!(transport.calls().is_empty());
    assert!(!only_share(&db).confirmed);
}

#[tokio::test(start_paused = true)]
async fn missing_recovery_material_is_reported_not_retried() {
    let configured = helpers(2);
    let db = db_with_share(&[helper(1)]);
    let share_id = share_id_of(&db);
    // Drop the recovery bundle the resubmission body is built from.
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = NULL, vc_tree_position = NULL
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let transport = Arc::new(MockTransport::default());
    transport.queue_get(
        &format!(
            "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
            helper(1)
        ),
        json_status("pending"),
    );

    let client = client_with(transport.clone());
    let random = zero_bytes;
    let report = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.unrecoverable.len(), 1);
    assert!(report.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shielded-vote/v1/shares"), 0);
}

#[tokio::test(start_paused = true)]
async fn persistent_recovery_nullifier_mismatch_is_reported_unrecoverable() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let mut replacement = recovery_bundle_fixture();
    replacement.share_blinds[0] = field_bytes(9);
    let replacement_json = serialize_recovery(&replacement).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": replacement_json,
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, SUBMIT_AT - 1, &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(report.unrecoverable.len(), 1);
    assert!(report.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shares"), 0);
}

#[tokio::test(start_paused = true)]
async fn recovery_nullifier_mismatch_from_replacement_remains_stale() {
    let configured = helpers(2);
    let db = Arc::new(db_with_delivery(&[helper(1)], &[], 2));
    let share_id = share_id_of(&db);
    let mut replacement = recovery_bundle_fixture();
    replacement.share_blinds[0] = field_bytes(9);
    let replacement_json = serialize_recovery(&replacement).unwrap();
    let replacement_nullifier = share::nullifier_from_recovery_json(&replacement_json, 1, 0)
        .unwrap()
        .to_vec();
    let transport = Arc::new(MockTransport::default());
    for index in 1..=2 {
        transport.queue_get(
            &format!(
                "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
                helper(index)
            ),
            json_status("pending"),
        );
    }
    let replacing_db = Arc::clone(&db);
    transport.observe_gets(move |_| {
        let conn = replacing_db.conn();
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = :json
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": replacement_json,
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
        conn.execute(
            "UPDATE share_delegations SET nullifier = :nullifier
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1 AND share_index = 0",
            rusqlite::named_params! {
                ":nullifier": replacement_nullifier,
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
    });
    let client = client_with(transport.clone());
    let random = zero_bytes;

    let report = track_pending_shares(
        &db,
        &params(&configured, ready_not_overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(report.unrecoverable.is_empty());
    assert!(report.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shares"), 0);
}

#[tokio::test(start_paused = true)]
async fn resubmission_waits_for_the_confirmed_vc_position() {
    let configured = helpers(2);
    let db = db_with_delivery(&[helper(1)], &[], 2);
    let share_id = share_id_of(&db);
    db.conn()
        .execute(
            "UPDATE votes SET vc_tree_position = NULL
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();

    let transport = Arc::new(MockTransport::default());
    let status_url = format!(
        "{}/shielded-vote/v1/share-status/{ROUND_ID}/{share_id}",
        helper(1)
    );
    transport.queue_get(&status_url, json_status("pending"));
    let client = client_with(transport.clone());
    let no_randomness =
        |_: usize| -> Vec<u8> { panic!("recovery order must wait for the real VC position") };

    let deferred = track_pending_shares(
        &db,
        &params(&configured, overdue(), &no_randomness),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert!(deferred.unrecoverable.is_empty());
    assert!(deferred.resubmitted.is_empty());
    assert_eq!(transport.call_count("/shielded-vote/v1/shares"), 0);

    db.conn()
        .execute(
            "UPDATE votes SET vc_tree_position = 789
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
            },
        )
        .unwrap();
    transport.queue_get(&status_url, json_status("pending"));
    let post_url = format!("{}/shielded-vote/v1/shares", helper(2));
    transport.queue_post(&post_url, json_status("queued"));
    let random = zero_bytes;

    let resumed = track_pending_shares(
        &db,
        &params(&configured, overdue(), &random),
        &client,
        &never_cancel(),
    )
    .await
    .unwrap();

    assert_eq!(resumed.resubmitted[0].server_url, helper(2));
    let bodies = transport.post_bodies.lock().unwrap();
    let (_, body) = bodies.iter().find(|(url, _)| url == &post_url).unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(body).unwrap()["tree_position"],
        789
    );
}
