#![cfg(feature = "test-fixtures")]

#[path = "support/helper_fleet.rs"]
mod helper_fleet;
#[path = "support/vote_fixture.rs"]
mod vote_fixture;

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use helper_fleet::{Endpoint, HelperFleet, Response, ResponseGate};
use rand::{rngs::StdRng, Rng, SeedableRng};
use vote_fixture::{
    committed_vote, db_with_confirmed_committed_vote, ROUND_ID, SHARE_COUNT, VC_TREE_POSITION,
};
use zcash_voting::{
    share,
    share_policy::{ShareTimingPolicy, SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER},
    share_tracking::{
        track_pending_shares, ShareBatchDeliveryReport, ShareDeliveryPlan,
        ShareDeliveryPlanningParams, ShareDeliverySubmissionParams, ShareTrackingParams,
    },
    HelperClient, HelperClientConfig, HelperError, HelperHealth, HyperTransport, VotingError,
};

const NOW: u64 = 1_000;
const VOTE_END: u64 = 100_000;
const LAST_MOMENT_BUFFER: u64 = 10_000;

fn client() -> HelperClient {
    let config = HelperClientConfig::default()
        .with_request_timeout(Duration::from_millis(500))
        .unwrap()
        .with_post_timeout(Duration::from_millis(500))
        .unwrap()
        .with_preflight_timeouts(Duration::from_millis(100), Duration::from_secs(1))
        .unwrap()
        .with_retry_delays(vec![Duration::from_millis(5), Duration::from_millis(10)])
        .unwrap();
    HelperClient::with_config(
        Arc::new(HyperTransport::new()),
        HelperHealth::default(),
        config,
    )
}

fn server_index(urls: &[String], url: &str) -> usize {
    urls.iter()
        .position(|candidate| candidate == url)
        .unwrap_or_else(|| panic!("unknown helper URL {url}"))
}

fn tracking_params<'a>(urls: &'a [String], now_seconds: u64) -> ShareTrackingParams<'a> {
    ShareTrackingParams {
        round_id: ROUND_ID,
        configured_server_urls: urls,
        now_seconds,
        vote_end_time_seconds: Some(VOTE_END),
        policy: ShareTimingPolicy::default(),
    }
}

async fn prepare(
    db: &zcash_voting::round::VotingDb,
    client: &HelperClient,
    urls: &[String],
) -> ShareDeliveryPlan {
    let fleet = client.preflight_fleet(urls).await.unwrap();
    committed_vote(db)
        .prepare_share_delivery(
            db,
            ShareDeliveryPlanningParams {
                fleet: &fleet,
                now_seconds: NOW,
                vote_end_time_seconds: VOTE_END,
                last_moment_buffer_seconds: Some(LAST_MOMENT_BUFFER),
                proposal_ids: &[1],
            },
        )
        .unwrap()
}

async fn prepare_share_zero(
    db: &zcash_voting::round::VotingDb,
    client: &HelperClient,
    urls: &[String],
) -> ShareDeliveryPlan {
    let plan = prepare(db, client, urls).await;
    for (share_index, share_plan) in plan.share_plans.iter().enumerate().skip(1) {
        share::record_delivery_fixture(
            db,
            ROUND_ID,
            0,
            1,
            share_index as u32,
            &share_plan.target_servers,
            &[],
            share_plan.target_count as usize,
            share_plan.submit_at,
        )
        .unwrap();
        share::confirm_fixture(db, ROUND_ID, 0, 1, share_index as u32).unwrap();
    }
    plan
}

async fn submit(
    db: &zcash_voting::round::VotingDb,
    client: &HelperClient,
    urls: &[String],
) -> ShareBatchDeliveryReport {
    committed_vote(db)
        .submit_prepared_shares(
            db,
            client,
            ShareDeliverySubmissionParams {
                configured_server_urls: urls,
                now_seconds: NOW,
            },
            &|| false,
        )
        .await
        .unwrap()
}

fn share_zero(
    report: &ShareBatchDeliveryReport,
) -> &zcash_voting::share_tracking::ShareSubmissionReport {
    &report
        .deliveries
        .iter()
        .find(|delivery| delivery.share_index == 0)
        .expect("share zero must be processed")
        .submission
}

#[tokio::test(flavor = "multi_thread")]
async fn ten_helper_planning_preflight_and_submission_obey_distribution_policy() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    for index in 5..10 {
        fleet.server(index).enqueue(
            Endpoint::Readiness,
            Response::ok().delayed(Duration::from_millis(300)),
        );
    }
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let plan = prepare(&db, &helper_client, &urls).await;

    let mut usage = HashMap::<String, usize>::new();
    for share_plan in &plan.share_plans {
        assert_eq!(share_plan.target_count, 5);
        assert_eq!(share_plan.target_servers.len(), 5);
        assert_eq!(
            share_plan
                .target_servers
                .iter()
                .collect::<HashSet<_>>()
                .len(),
            5
        );
        for server in &share_plan.target_servers {
            *usage.entry(server.clone()).or_default() += 1;
        }
    }
    assert_eq!(usage.values().sum::<usize>(), SHARE_COUNT * 5);
    assert!(
        usage.len() >= 7,
        "planning must widen beyond five ready helpers"
    );
    assert!(usage
        .values()
        .all(|count| *count <= SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER));

    let report = submit(&db, &helper_client, &urls).await;
    assert_eq!(report.deliveries.len(), SHARE_COUNT);
    assert!(report
        .deliveries
        .iter()
        .all(|delivery| delivery.submission.target_count == 5
            && delivery.submission.accepted_urls.len() == 5
            && delivery.submission.ambiguous_urls.is_empty()));
    assert_eq!(fleet.post_requests().len(), SHARE_COUNT * 5);
    for request in fleet.post_requests() {
        let body = request.json();
        assert_eq!(body["vote_round_id"], ROUND_ID);
        assert_eq!(body["proposal_id"], 1);
        assert_eq!(body["tree_position"], VC_TREE_POSITION);
        let share_index = body["share_index"].as_u64().unwrap() as usize;
        assert_eq!(body["submit_at"], plan.share_plans[share_index].submit_at);
        assert!(body.get("all_enc_shares").is_none());
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn mixed_initial_failures_follow_current_retry_and_durability_rules() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
    let plan = &delivery_plan.share_plans[0];
    let planned = &plan.target_servers;

    let throttled = server_index(&urls, &planned[0]);
    fleet.server(throttled).enqueue_many(
        Endpoint::Submit,
        [Response::status(429), Response::queued()],
    );
    let server_error = server_index(&urls, &planned[1]);
    // Current code intentionally classifies every 5xx, including 501, as
    // outcome-unknown and never retries it on initial delivery.
    fleet
        .server(server_error)
        .enqueue(Endpoint::Submit, Response::status(501));
    let closed = server_index(&urls, &planned[2]);
    fleet.server(closed).enqueue(
        Endpoint::Submit,
        Response::CloseAfterRequest {
            delay: Duration::ZERO,
        },
    );
    let unavailable = server_index(&urls, &planned[3]);
    fleet.server(unavailable).stop();

    let batch = submit(&db, &helper_client, &urls).await;
    let report = share_zero(&batch);
    assert_eq!(report.accepted_urls.len(), 5);
    assert_eq!(report.ambiguous_urls.len(), 2);
    assert_eq!(
        fleet.server(throttled).request_count(Endpoint::Submit),
        2,
        "{:?}",
        fleet.server(throttled).requests()
    );
    assert_eq!(
        fleet.server(server_error).request_count(Endpoint::Submit),
        1
    );
    assert_eq!(fleet.server(closed).request_count(Endpoint::Submit), 1);
    assert_eq!(fleet.server(unavailable).request_count(Endpoint::Submit), 0);

    let stored = &share::list(&db, ROUND_ID).unwrap()[0];
    assert_eq!(stored.sent_to_urls.len(), 5);
    assert_eq!(stored.ambiguous_urls.len(), 2);
    assert!(stored.attempting_urls.is_empty());
    assert!(stored
        .sent_to_urls
        .iter()
        .all(|url| !stored.ambiguous_urls.contains(url)));
}

#[tokio::test(flavor = "multi_thread")]
async fn every_http_post_is_journaled_before_the_helper_can_answer() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
    let plan = &delivery_plan.share_plans[0];
    let first = server_index(&urls, &plan.target_servers[0]);
    let gate = Arc::new(ResponseGate::default());
    fleet.server(first).enqueue(
        Endpoint::Submit,
        Response::GatedJson {
            gate: Arc::clone(&gate),
            status: 200,
            body: r#"{"status":"queued"}"#.to_string(),
        },
    );
    let submission = submit(&db, &helper_client, &urls);
    let observe_journal = async {
        while fleet.post_requests().is_empty() {
            tokio::task::yield_now().await;
        }
        let stored = &share::list(&db, ROUND_ID).unwrap()[0];
        assert_eq!(stored.attempting_urls, vec![plan.target_servers[0].clone()]);
        assert!(stored.sent_to_urls.is_empty());
        gate.release();
    };

    let (report, ()) = tokio::join!(submission, observe_journal);
    assert_eq!(share_zero(&report).accepted_urls.len(), 5);
    let stored = &share::list(&db, ROUND_ID).unwrap()[0];
    assert!(stored.attempting_urls.is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn early_and_overdue_recovery_preserve_then_reset_the_schedule() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
    let plan = &delivery_plan.share_plans[0];
    let initially_accepted = plan
        .target_servers
        .iter()
        .take(2)
        .cloned()
        .collect::<HashSet<_>>();
    for (index, url) in urls.iter().enumerate() {
        fleet.server(index).enqueue(
            Endpoint::Submit,
            if initially_accepted.contains(url) {
                Response::queued()
            } else {
                Response::status(400)
            },
        );
    }
    let initial = submit(&db, &helper_client, &urls).await;
    assert_eq!(share_zero(&initial).accepted_urls.len(), 2);
    let initial_posts = fleet.post_requests().len();

    let early = track_pending_shares(
        &db,
        &tracking_params(&urls, plan.submit_at - 1),
        &helper_client,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(early.resubmitted.len(), 3);
    let early_posts = fleet.post_requests();
    assert_eq!(early_posts.len() - initial_posts, 3);
    assert!(early_posts[initial_posts..]
        .iter()
        .all(|request| request.json()["submit_at"] == plan.submit_at));
    assert_eq!(share::list(&db, ROUND_ID).unwrap()[0].sent_to_urls.len(), 5);

    let before_overdue = fleet.post_requests().len();
    let overdue = track_pending_shares(
        &db,
        &tracking_params(&urls, plan.submit_at + 3_601),
        &helper_client,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(overdue.resubmitted.len(), 1);
    let overdue_posts = fleet.post_requests();
    assert_eq!(overdue_posts.len(), before_overdue + 1);
    assert_eq!(overdue_posts.last().unwrap().json()["submit_at"], 0);
    assert_eq!(share::list(&db, ROUND_ID).unwrap()[0].submit_at, 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn mixed_status_latency_respects_concurrency_and_confirmation_quorum() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
    let plan = &delivery_plan.share_plans[0];
    submit(&db, &helper_client, &urls).await;
    let posts_before_poll = fleet.post_requests().len();

    fleet.server(0).enqueue(
        Endpoint::ShareStatus,
        Response::confirmed().delayed(Duration::from_millis(30)),
    );
    fleet.server(1).enqueue(
        Endpoint::ShareStatus,
        Response::confirmed().delayed(Duration::from_millis(40)),
    );
    fleet.server(2).enqueue(
        Endpoint::ShareStatus,
        Response::Stall {
            duration: Duration::from_millis(700),
        },
    );
    for index in 3..10 {
        fleet.server(index).enqueue(
            Endpoint::ShareStatus,
            Response::pending().delayed(Duration::from_millis(70)),
        );
    }
    let report = track_pending_shares(
        &db,
        &tracking_params(&urls, plan.submit_at + 11),
        &helper_client,
        &|| false,
    )
    .await
    .unwrap();

    assert_eq!(report.confirmed.len(), 1);
    assert!(share::list(&db, ROUND_ID).unwrap()[0].confirmed);
    assert_eq!(fleet.post_requests().len(), posts_before_poll);
    assert!(fleet.max_concurrent_status_requests() <= 4);
    assert!(fleet.max_concurrent_status_requests() >= 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn restart_keeps_ambiguous_delivery_poll_only_until_overdue() {
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
    let plan = &delivery_plan.share_plans[0];
    let ambiguous = server_index(&urls, &plan.target_servers[0]);
    fleet.server(ambiguous).enqueue(
        Endpoint::Submit,
        Response::CloseAfterRequest {
            delay: Duration::ZERO,
        },
    );
    for index in 0..10 {
        if index != ambiguous {
            fleet
                .server(index)
                .enqueue(Endpoint::Submit, Response::status(400));
        }
    }
    submit(&db, &helper_client, &urls).await;
    assert_eq!(fleet.server(ambiguous).request_count(Endpoint::Submit), 1);

    for index in 0..10 {
        if index != ambiguous {
            fleet
                .server(index)
                .enqueue(Endpoint::Submit, Response::status(400));
        }
    }
    submit(&db, &client(), &urls).await;
    assert_eq!(
        fleet.server(ambiguous).request_count(Endpoint::Submit),
        1,
        "a recreated client must not replay outcome-unknown initial delivery"
    );

    for index in 0..10 {
        if index == ambiguous {
            fleet
                .server(index)
                .enqueue(Endpoint::Submit, Response::duplicate());
        } else {
            fleet
                .server(index)
                .enqueue(Endpoint::Submit, Response::status(400));
        }
    }
    let report = track_pending_shares(
        &db,
        &tracking_params(&urls, plan.submit_at + 3_601),
        &client(),
        &|| false,
    )
    .await
    .unwrap();
    assert!(report
        .resubmitted
        .iter()
        .any(|item| item.server_url == urls[ambiguous]));
    assert_eq!(fleet.server(ambiguous).request_count(Endpoint::Submit), 2);
    let stored = &share::list(&db, ROUND_ID).unwrap()[0];
    assert!(stored.sent_to_urls.contains(&urls[ambiguous]));
    assert!(!stored.ambiguous_urls.contains(&urls[ambiguous]));
    assert_eq!(stored.submit_at, 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn current_boundary_rejects_schema_invalid_bodies_and_canonical_duplicates() {
    // These assertions intentionally follow the current implementation where
    // it differs from PR #235: direct bodies use the closed wire schema, and
    // canonically duplicate configured helpers fail instead of collapsing.
    let fleet = HelperFleet::new(10);
    let urls = fleet.urls();
    let error = client()
        .submit_share(&urls[0], r#"{"status":"queued"}"#, NOW, &|| false)
        .await
        .unwrap_err();
    assert!(matches!(error, HelperError::InvalidRequest { .. }));
    assert!(fleet.requests().is_empty());

    let db = db_with_confirmed_committed_vote();
    let helper_client = client();
    prepare(&db, &helper_client, &urls).await;
    let mut duplicated = urls.clone();
    duplicated[9] = format!("{}/", urls[0]);
    let result = committed_vote(&db)
        .submit_prepared_shares(
            &db,
            &helper_client,
            ShareDeliverySubmissionParams {
                configured_server_urls: &duplicated,
                now_seconds: NOW,
            },
            &|| false,
        )
        .await;
    assert!(matches!(result, Err(VotingError::InvalidInput { .. })));
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert!(fleet.post_requests().is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn seeded_mixed_networks_preserve_safety_and_converge_after_healing() {
    for seed in [7_u64, 29, 113, 997] {
        let fleet = HelperFleet::new(10);
        let urls = fleet.urls();
        let mut rng = StdRng::seed_from_u64(seed);
        let db = db_with_confirmed_committed_vote();
        let helper_client = client();
        let delivery_plan = prepare_share_zero(&db, &helper_client, &urls).await;
        let plan = &delivery_plan.share_plans[0];
        let mut modes = Vec::new();
        for index in 0..10 {
            let mode = rng.gen_range(0..5);
            modes.push(mode);
            match mode {
                0 => fleet
                    .server(index)
                    .enqueue(Endpoint::Submit, Response::queued()),
                1 => fleet.server(index).enqueue_many(
                    Endpoint::Submit,
                    [Response::status(429), Response::queued()],
                ),
                2 => fleet
                    .server(index)
                    .enqueue(Endpoint::Submit, Response::status(501)),
                3 => fleet.server(index).enqueue(
                    Endpoint::Submit,
                    Response::CloseAfterRequest {
                        delay: Duration::ZERO,
                    },
                ),
                _ => fleet
                    .server(index)
                    .enqueue(Endpoint::Submit, Response::status(400)),
            }
        }

        let initial_batch = submit(&db, &helper_client, &urls).await;
        let initial = share_zero(&initial_batch);
        let initial_counts = (0..10)
            .map(|index| fleet.server(index).request_count(Endpoint::Submit))
            .collect::<Vec<_>>();
        for (index, mode) in modes.iter().copied().enumerate() {
            let upper_bound = usize::from(mode == 1) + 1;
            assert!(
                initial_counts[index] <= upper_bound,
                "seed {seed}: helper {index} exceeded initial retry bound"
            );
        }
        let initial_ambiguous = initial.ambiguous_urls.clone();

        track_pending_shares(
            &db,
            &tracking_params(&urls, plan.submit_at - 1),
            &helper_client,
            &|| false,
        )
        .await
        .unwrap();
        for url in &initial_ambiguous {
            let index = server_index(&urls, url);
            assert_eq!(
                fleet.server(index).request_count(Endpoint::Submit),
                initial_counts[index],
                "seed {seed}: early recovery replayed an ambiguous helper"
            );
        }

        track_pending_shares(
            &db,
            &tracking_params(&urls, plan.submit_at + 3_601),
            &helper_client,
            &|| false,
        )
        .await
        .unwrap();
        let stored = &share::list(&db, ROUND_ID).unwrap()[0];
        assert!(
            stored.sent_to_urls.len() >= 5,
            "seed {seed}: healed fleet did not restore target placement"
        );
        assert!(stored
            .sent_to_urls
            .iter()
            .all(|url| !stored.ambiguous_urls.contains(url)));
        assert!(stored
            .sent_to_urls
            .iter()
            .all(|url| !stored.attempting_urls.contains(url)));
        assert!(stored
            .ambiguous_urls
            .iter()
            .all(|url| !stored.attempting_urls.contains(url)));
        for url in &initial_ambiguous {
            let index = server_index(&urls, url);
            assert!(
                fleet.server(index).request_count(Endpoint::Submit) <= initial_counts[index] + 1,
                "seed {seed}: overdue recovery repeated an ambiguous helper"
            );
        }

        fleet
            .server(0)
            .enqueue(Endpoint::ShareStatus, Response::confirmed());
        fleet
            .server(1)
            .enqueue(Endpoint::ShareStatus, Response::confirmed());
        let posts_before_confirmation = fleet.post_requests().len();
        let confirmation_now = share::list(&db, ROUND_ID).unwrap()[0]
            .created_at
            .saturating_add(11);
        let confirmation = track_pending_shares(
            &db,
            &tracking_params(&urls, confirmation_now),
            &helper_client,
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(
            confirmation.confirmed.len(),
            1,
            "seed {seed}: healed confirmation quorum was not observed"
        );
        assert_eq!(fleet.post_requests().len(), posts_before_confirmation);
    }
}
