use super::*;
use crate::{
    helper::client::HelperFleetPreflight,
    share_tracking::{
        ShareDeliveryPlanningParams, ShareDeliverySubmissionParams, SharePlacementGuarantee,
    },
};

static GLOBAL_BATCH_LIMIT_TEST_LOCK: LazyLock<tokio::sync::Mutex<()>> =
    LazyLock::new(|| tokio::sync::Mutex::new(()));

fn planning_params<'a>(fleet: &'a HelperFleetPreflight) -> ShareDeliveryPlanningParams<'a> {
    planning_params_for(fleet, &[1])
}

fn planning_params_for<'a>(
    fleet: &'a HelperFleetPreflight,
    proposal_ids: &'a [u32],
) -> ShareDeliveryPlanningParams<'a> {
    ShareDeliveryPlanningParams {
        fleet,
        now_seconds: SUBMIT_AT,
        vote_end_time_seconds: VOTE_END,
        last_moment_buffer_seconds: None,
        proposal_ids,
    }
}

fn submission_params(configured: &[String]) -> ShareDeliverySubmissionParams<'_> {
    ShareDeliverySubmissionParams {
        configured_server_urls: configured,
        now_seconds: SUBMIT_AT,
    }
}

fn reset_vote_to_preconfirmation(db: &VotingDb) {
    let mut recovery = recovery_bundle_fixture();
    recovery.vc_tree_position = 0;
    let json = serialize_recovery(&recovery).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json,
                              commitment = NULL,
                              vc_tree_position = NULL
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": json,
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
            },
        )
        .unwrap();
}

fn set_recovery_share_count(db: &VotingDb, share_count: usize) {
    let mut recovery = recovery_bundle_fixture();
    recovery.single_share = share_count == 1;
    recovery.encrypted_shares = (0..share_count)
        .map(|index| EncryptedShare {
            c1: point_bytes(index as u64 * 2 + 1),
            c2: point_bytes(index as u64 * 2 + 2),
            share_index: index as u32,
            plaintext_value: index as u64 + 1,
            randomness: vec![index as u8 + 1; 32],
        })
        .collect();
    recovery.share_blinds = (0..share_count)
        .map(|index| field_bytes(index as u8 + 1))
        .collect();
    recovery.share_comms = (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
        .map(|index| field_bytes(index as u8 + 20))
        .collect();
    let json = serialize_recovery(&recovery).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json,
                              commitment = NULL,
                              vc_tree_position = :position
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": json,
                ":position": recovery.vc_tree_position as i64,
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
            },
        )
        .unwrap();
}

fn queue_successes(transport: &MockTransport, configured: &[String], count: usize) {
    for helper_url in configured {
        let post_url = format!("{helper_url}/shielded-vote/v1/shares");
        for _ in 0..count {
            transport.queue_post(&post_url, json_status("queued"));
        }
    }
}

fn stored_plan_snapshot(db: &VotingDb) -> String {
    db.conn()
        .query_row(
            "SELECT commitment_bundle_json FROM helper_share_plans
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
            },
            |row| row.get(0),
        )
        .unwrap()
}

fn replace_stored_share_plans(db: &VotingDb, plans: &[ShareSubmissionPlan]) {
    db.conn()
        .execute(
            "UPDATE helper_share_plans SET share_plans_json = :plans
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":plans": serde_json::to_string(plans).unwrap(),
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
            },
        )
        .unwrap();
}

fn replace_recovery_preserving_vote_commitment(db: &VotingDb) {
    let mut replacement = recovery_bundle_fixture();
    replacement.share_blinds[0] = field_bytes(99);
    let replacement_json = serialize_recovery(&replacement).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": replacement_json,
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
            },
        )
        .unwrap();
}

fn seed_recoverable_vote_for_proposal(db: &VotingDb, proposal_id: u32, choice: u32) {
    db.set_ballot_intent(
        ROUND_ID,
        proposal_id,
        crate::session::Decision::Choice(choice),
        3,
    )
    .unwrap();
    queries::store_vote(
        &db.conn(),
        ROUND_ID,
        &db.wallet_id(),
        0,
        proposal_id,
        choice,
        &[proposal_id as u8; 32],
    )
    .unwrap();
    let mut recovery = recovery_bundle_fixture();
    recovery.proposal_id = proposal_id;
    recovery.vote_decision = choice;
    recovery.vote_commitment[0] = proposal_id as u8;
    let json = serialize_recovery(&recovery).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":json": json,
                ":pos": recovery.vc_tree_position as i64,
                ":round_id": ROUND_ID,
                ":wallet_id": db.wallet_id(),
                ":proposal_id": proposal_id as i64,
            },
        )
        .unwrap();
}

#[test]
fn complete_plan_is_persisted_and_reused() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured[..2]).unwrap();

    let first = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let second = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();

    assert_eq!(first, second);
    assert_eq!(first.placement_guarantee, SharePlacementGuarantee::Strict);
    assert_eq!(first.share_plans.len(), 2);
    assert_eq!(
        first
            .share_plans
            .iter()
            .filter(|plan| plan.immediate)
            .count(),
        1
    );
    let stored: i64 = db
        .conn()
        .query_row("SELECT COUNT(*) FROM helper_share_plans", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(stored, 1);
}

#[test]
fn complete_roster_derives_exactly_one_round_immediate_share() {
    let db = db_with_unique_recoverable_vote();
    seed_recoverable_vote_for_proposal(&db, 2, 1);
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let roster = [1, 2];

    let second = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 2).unwrap();
    let second_plan = second
        .prepare_share_delivery(&db, planning_params_for(&fleet, &roster))
        .unwrap();
    assert!(second_plan.share_plans.iter().all(|plan| !plan.immediate));

    let first = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let first_plan = first
        .prepare_share_delivery(&db, planning_params_for(&fleet, &roster))
        .unwrap();
    assert!(first_plan.share_plans[0].immediate);
    assert_eq!(
        first_plan
            .share_plans
            .iter()
            .chain(&second_plan.share_plans)
            .filter(|plan| plan.immediate)
            .count(),
        1
    );
}

#[test]
fn skipped_lower_proposal_does_not_take_the_immediate_designation() {
    let db = db_with_round_and_bundle();
    db.set_ballot_intent(ROUND_ID, 1, crate::session::Decision::Skipped, 3)
        .unwrap();
    seed_recoverable_vote_for_proposal(&db, 2, 1);
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 2).unwrap();

    let plan = committed
        .prepare_share_delivery(&db, planning_params_for(&fleet, &[1, 2]))
        .unwrap();

    assert!(plan.share_plans[0].immediate);
    assert_eq!(
        plan.share_plans
            .iter()
            .filter(|plan| plan.immediate)
            .count(),
        1
    );
}

#[test]
fn planning_rejects_incomplete_duplicate_and_omitting_rosters_before_persistence() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();

    for roster in [&[][..], &[1, 1][..], &[1, 2][..]] {
        let error = committed
            .prepare_share_delivery(&db, planning_params_for(&fleet, roster))
            .unwrap_err();
        assert!(matches!(error, VotingError::InvalidInput { .. }));
    }
    let stored: i64 = db
        .conn()
        .query_row("SELECT COUNT(*) FROM helper_share_plans", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(stored, 0);

    db.set_ballot_intent(ROUND_ID, 2, crate::session::Decision::Skipped, 3)
        .unwrap();
    let error = committed
        .prepare_share_delivery(&db, planning_params_for(&fleet, &[1]))
        .unwrap_err();
    assert!(error.to_string().contains("exactly match"));
    let stored: i64 = db
        .conn()
        .query_row("SELECT COUNT(*) FROM helper_share_plans", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(stored, 0);
}

#[tokio::test]
async fn later_lower_choice_blocks_stale_submission_and_a_second_immediate_plan() {
    let db = db_with_round_and_bundle();
    seed_recoverable_vote_for_proposal(&db, 2, 1);
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let second = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 2).unwrap();
    let original = second
        .prepare_share_delivery(&db, planning_params_for(&fleet, &[2]))
        .unwrap();
    assert!(original.share_plans[0].immediate);

    db.set_ballot_intent(ROUND_ID, 1, crate::session::Decision::Choice(0), 3)
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    let error = second
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("does not match durable ballot intent"));
    assert!(transport.calls().is_empty());

    let error = second
        .prepare_share_delivery(&db, planning_params_for(&fleet, &[1, 2]))
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("does not match durable ballot intent"));
}

#[test]
fn preexisting_delivery_is_marked_legacy_best_effort() {
    let db = db_with_share(&[helper(1)]);
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();

    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();

    assert_eq!(
        plan.placement_guarantee,
        SharePlacementGuarantee::LegacyBestEffort
    );
    assert_eq!(only_share(&db).sent_to_urls, vec![helper(1)]);
}

#[test]
fn changing_vote_generation_invalidates_the_plan() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();

    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = NULL
             WHERE round_id = ?1 AND wallet_id = ?2 AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::params![ROUND_ID, db.wallet_id()],
        )
        .unwrap();

    let stored: i64 = db
        .conn()
        .query_row("SELECT COUNT(*) FROM helper_share_plans", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(stored, 0);
}

#[test]
fn stale_handle_cannot_prepare_same_commitment_replacement() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();

    replace_recovery_preserving_vote_commitment(&db);

    let error = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap_err();
    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert_eq!(
        db.conn()
            .query_row("SELECT COUNT(*) FROM helper_share_plans", [], |row| {
                row.get::<_, i64>(0)
            })
            .unwrap(),
        0
    );
}

#[tokio::test]
async fn stale_handle_cannot_submit_same_commitment_replacement_plan() {
    let db = db_with_unique_recoverable_vote();
    let stale_handle = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();

    replace_recovery_preserving_vote_commitment(&db);
    let current_handle = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    current_handle
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let transport = Arc::new(MockTransport::default());

    let error = stale_handle
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(error
        .to_string()
        .contains("committed vote changed before helper-share submission"));
    assert!(transport.calls().is_empty());
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test]
async fn same_commitment_replacement_after_plan_load_stops_every_post() {
    use std::sync::atomic::{AtomicBool, Ordering};

    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, 2);
    let replaced = AtomicBool::new(false);
    let replace_after_load = || {
        if !replaced.swap(true, Ordering::SeqCst) {
            replace_recovery_preserving_vote_commitment(&db);
        }
        false
    };

    let error = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &replace_after_load,
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(transport.calls().is_empty());
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test]
async fn delayed_immediate_plan_is_rejected_before_network() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let mut plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let immediate = plan
        .share_plans
        .iter_mut()
        .find(|share_plan| share_plan.immediate)
        .unwrap();
    immediate.submit_at = SUBMIT_AT;
    replace_stored_share_plans(&db, &plan.share_plans);

    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, plan.share_plans.len());
    let error = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(error.to_string().contains("nonzero submit_at"));
    assert!(transport.calls().is_empty());
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test]
async fn prepared_batch_stays_bound_to_its_starting_wallet() {
    use std::sync::atomic::{AtomicBool, Ordering};

    const OTHER_WALLET: &str = "other-prepared-batch-wallet";

    let db = db_with_unique_recoverable_vote();
    let starting_wallet = db.wallet_id();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    db.set_wallet_id(OTHER_WALLET);
    seed_recoverable_vote_for_wallet(&db, OTHER_WALLET);
    db.set_wallet_id(&starting_wallet);

    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, 2);
    let switched = AtomicBool::new(false);
    let switch_wallet_after_plan_load = || {
        if !switched.swap(true, Ordering::SeqCst) {
            db.set_wallet_id(OTHER_WALLET);
        }
        false
    };

    let report = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport),
            submission_params(&configured),
            &switch_wallet_after_plan_load,
        )
        .await
        .unwrap();

    assert_eq!(report.deliveries.len(), 2);
    assert_eq!(db.wallet_id(), OTHER_WALLET);
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    db.set_wallet_id(&starting_wallet);
    assert_eq!(share::list(&db, ROUND_ID).unwrap().len(), 2);
    assert!(share::list(&db, ROUND_ID)
        .unwrap()
        .iter()
        .all(|record| record.sent_to_urls == configured));
}

#[tokio::test]
async fn preconfirmation_plan_survives_confirmation_restart_and_submission() {
    let db = db_with_unique_recoverable_vote();
    reset_vote_to_preconfirmation(&db);
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured[..2]).unwrap();
    let committed_before = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let prepared = committed_before
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let snapshot_before = stored_plan_snapshot(&db);

    crate::vote::record_vc_position(&db, ROUND_ID, 0, 1, 456).unwrap();

    let snapshot_after = stored_plan_snapshot(&db);
    assert_ne!(snapshot_after, snapshot_before);
    let committed_after = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    assert_eq!(
        committed_after
            .prepare_share_delivery(&db, planning_params(&fleet))
            .unwrap(),
        prepared
    );

    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, prepared.share_plans.len());
    let report = committed_after
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.placement_guarantee, SharePlacementGuarantee::Strict);
    assert_eq!(
        report
            .deliveries
            .iter()
            .map(|delivery| delivery.share_index)
            .collect::<Vec<_>>(),
        vec![0, 1]
    );
    assert!(report.pending_share_indices.is_empty());
    assert!(!report.cancelled);
    assert_eq!(share::list(&db, ROUND_ID).unwrap().len(), 2);
}

#[tokio::test]
async fn preconfirmation_handle_is_stale_after_confirmation_transition() {
    let db = db_with_unique_recoverable_vote();
    reset_vote_to_preconfirmation(&db);
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let committed_before = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    committed_before
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();

    crate::vote::record_vc_position(&db, ROUND_ID, 0, 1, 456).unwrap();

    let transport = Arc::new(MockTransport::default());
    let error = committed_before
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(error
        .to_string()
        .contains("recover the current committed vote"));
    assert!(transport.calls().is_empty());
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test]
async fn restart_resumes_with_a_replaced_helper_without_contacting_the_removed_target() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let removed = plan.share_plans[0].target_servers[0].clone();
    let drifted = configured
        .iter()
        .filter(|url| *url != &removed)
        .cloned()
        .chain(std::iter::once(helper(4)))
        .collect::<Vec<_>>();
    let recovered = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let drifted_fleet = HelperFleetPreflight::from_readiness(&drifted, &drifted).unwrap();
    assert_eq!(
        recovered
            .prepare_share_delivery(&db, planning_params(&drifted_fleet))
            .unwrap(),
        plan
    );
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &drifted, plan.share_plans.len());

    let report = recovered
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&drifted),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.deliveries.len(), plan.share_plans.len());
    assert!(report.deliveries.iter().all(|delivery| {
        delivery.submission.target_count == plan.share_plans[0].target_count as usize
            && delivery.submission.accepted_urls.len() == plan.share_plans[0].target_count as usize
            && delivery
                .submission
                .accepted_urls
                .iter()
                .all(|url| drifted.contains(url))
    }));
    assert_eq!(transport.call_count(&removed), 0);
}

#[tokio::test]
async fn fleet_reordering_preserves_persisted_fleet_identity() {
    let db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&db, 1);
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let reordered = configured.iter().rev().cloned().collect::<Vec<_>>();
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, plan.share_plans.len());

    let report = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&reordered),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.deliveries.len(), 1);
    assert_eq!(
        report.deliveries[0].submission.accepted_urls.len(),
        plan.share_plans[0].target_count as usize
    );
}

#[tokio::test]
async fn restart_after_fleet_expansion_preserves_the_original_target() {
    let db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&db, 1);
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(3);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let expanded = helpers(5);
    let recovered = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let expanded_fleet = HelperFleetPreflight::from_readiness(&expanded, &expanded).unwrap();
    assert_eq!(
        recovered
            .prepare_share_delivery(&db, planning_params(&expanded_fleet))
            .unwrap(),
        plan
    );
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &expanded, plan.share_plans.len());

    let report = recovered
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&expanded),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(
        report.deliveries[0].submission.target_count,
        plan.share_plans[0].target_count as usize
    );
    assert_eq!(
        report.deliveries[0].submission.accepted_urls.len(),
        plan.share_plans[0].target_count as usize
    );
}

#[tokio::test]
async fn restart_after_fleet_contraction_clamps_delivery_to_current_helpers() {
    let db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&db, 1);
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = helpers(5);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let contracted = helpers(2);
    let recovered = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let contracted_fleet = HelperFleetPreflight::from_readiness(&contracted, &contracted).unwrap();
    assert_eq!(
        recovered
            .prepare_share_delivery(&db, planning_params(&contracted_fleet))
            .unwrap(),
        plan
    );
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &contracted, plan.share_plans.len());

    let report = recovered
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&contracted),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(
        report.deliveries[0].submission.target_count,
        plan.share_plans[0].target_count as usize
    );
    assert_eq!(report.deliveries[0].submission.accepted_urls.len(), 2);
    assert!(report.deliveries[0]
        .submission
        .accepted_urls
        .iter()
        .all(|url| contracted.contains(url)));
    let stored = share::list(&db, ROUND_ID).unwrap();
    assert_eq!(stored[0].target_count, plan.share_plans[0].target_count);
    assert!(stored[0]
        .sent_to_urls
        .iter()
        .all(|url| contracted.contains(url)));
}

#[tokio::test]
async fn one_helper_fleet_is_planned_and_submitted_by_the_sdk() {
    let db = db_with_unique_recoverable_vote();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    assert!(plan
        .share_plans
        .iter()
        .all(|share| share.target_count == 1 && share.target_servers == configured));
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, plan.share_plans.len());

    let report = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(report.deliveries.len(), plan.share_plans.len());
    assert!(report
        .deliveries
        .iter()
        .all(|delivery| delivery.submission.accepted_urls == configured));
}

#[tokio::test]
async fn every_payload_is_validated_before_the_first_post() {
    let db = db_with_unique_recoverable_vote();
    let mut committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    committed.share_payloads_mut()[1].enc_share.c1 = vec![0xFF];
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, 2);

    let error = committed
        .submit_prepared_shares(
            &db,
            &client_with(transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();

    assert!(matches!(error, VotingError::InvalidInput { .. }));
    assert!(transport.calls().is_empty());
    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
}

#[tokio::test]
async fn restart_reuses_the_plan_and_resumes_definite_delivery_deficits() {
    let db = db_with_unique_recoverable_vote();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    let committed = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    let plan = committed
        .prepare_share_delivery(&db, planning_params(&fleet))
        .unwrap();
    let snapshot = stored_plan_snapshot(&db);
    let failing_transport = Arc::new(MockTransport::default());
    for _ in 0..plan.share_plans.len() {
        failing_transport.queue_post(
            &format!("{}/shielded-vote/v1/shares", helper(1)),
            http_status(400),
        );
    }
    let first = committed
        .submit_prepared_shares(
            &db,
            &client_with(failing_transport),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap();
    assert!(first
        .deliveries
        .iter()
        .all(|delivery| delivery.submission.accepted_urls.is_empty()));

    let recovered = crate::vote::CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
    assert_eq!(stored_plan_snapshot(&db), snapshot);
    let transport = Arc::new(MockTransport::default());
    queue_successes(&transport, &configured, plan.share_plans.len());
    let resumed = recovered
        .submit_prepared_shares(
            &db,
            &client_with(transport),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap();

    assert_eq!(resumed.deliveries.len(), plan.share_plans.len());
    assert!(resumed
        .deliveries
        .iter()
        .all(|delivery| delivery.submission.accepted_urls == configured));
    assert!(share::list(&db, ROUND_ID)
        .unwrap()
        .iter()
        .all(|share| share.sent_to_urls == configured));
}

#[tokio::test]
async fn quota_rejects_strict_and_legacy_tampering_but_legacy_metadata_propagates() {
    let _global_limit_guard = GLOBAL_BATCH_LIMIT_TEST_LOCK.lock().await;
    let configured = helpers(2);
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();

    let strict_db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&strict_db, 16);
    let strict = crate::vote::CommittedVote::recover(&strict_db, ROUND_ID, 0, 1).unwrap();
    let strict_plan = strict
        .prepare_share_delivery(&strict_db, planning_params(&fleet))
        .unwrap();
    let concentrated = strict_plan
        .share_plans
        .iter()
        .cloned()
        .map(|mut plan| {
            plan.target_count = 1;
            plan.target_servers = vec![helper(1)];
            plan
        })
        .collect::<Vec<_>>();
    replace_stored_share_plans(&strict_db, &concentrated);
    let strict_transport = Arc::new(MockTransport::default());
    let error = strict
        .submit_prepared_shares(
            &strict_db,
            &client_with(strict_transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("initial maximum"));
    assert!(strict_transport.calls().is_empty());

    let legacy_db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&legacy_db, 16);
    share::record_delivery(
        &legacy_db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &ShareSubmissionReport {
                accepted_urls: vec![helper(1)],
                ambiguous_urls: vec![],
                target_count: 1,
            },
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    let legacy = crate::vote::CommittedVote::recover(&legacy_db, ROUND_ID, 0, 1).unwrap();
    let legacy_plan = legacy
        .prepare_share_delivery(&legacy_db, planning_params(&fleet))
        .unwrap();
    assert_eq!(
        legacy_plan.placement_guarantee,
        SharePlacementGuarantee::LegacyBestEffort
    );
    replace_stored_share_plans(&legacy_db, &concentrated);
    let legacy_transport = Arc::new(MockTransport::default());
    let error = legacy
        .submit_prepared_shares(
            &legacy_db,
            &client_with(legacy_transport.clone()),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("initial maximum"));
    assert!(legacy_transport.calls().is_empty());

    replace_stored_share_plans(&legacy_db, &legacy_plan.share_plans);
    let valid_legacy_transport = Arc::new(MockTransport::default());
    queue_successes(&valid_legacy_transport, &configured, 16);
    let report = legacy
        .submit_prepared_shares(
            &legacy_db,
            &client_with(valid_legacy_transport),
            submission_params(&configured),
            &never_cancel(),
        )
        .await
        .unwrap();
    assert_eq!(
        report.placement_guarantee,
        SharePlacementGuarantee::LegacyBestEffort
    );
    assert_eq!(report.deliveries.len(), 16);
}

#[tokio::test(start_paused = true)]
async fn global_ceiling_is_sixteen_and_queued_cancellation_returns_pending_shares() {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    let _global_limit_guard = GLOBAL_BATCH_LIMIT_TEST_LOCK.lock().await;
    let saturating_db = db_with_unique_recoverable_vote();
    set_recovery_share_count(&saturating_db, 16);
    let saturating = crate::vote::CommittedVote::recover(&saturating_db, ROUND_ID, 0, 1).unwrap();
    let queued_db = db_with_unique_recoverable_vote();
    let queued = crate::vote::CommittedVote::recover(&queued_db, ROUND_ID, 0, 1).unwrap();
    let configured = vec![helper(1)];
    let fleet = HelperFleetPreflight::from_readiness(&configured, &configured).unwrap();
    saturating
        .prepare_share_delivery(&saturating_db, planning_params(&fleet))
        .unwrap();
    queued
        .prepare_share_delivery(&queued_db, planning_params(&fleet))
        .unwrap();
    let transport = Arc::new(MockTransport::default());
    let post_url = format!("{}/shielded-vote/v1/shares", helper(1));
    for _ in 0..16 {
        transport.queue_post_after(&post_url, Duration::from_secs(1), json_status("queued"));
    }
    let client = client_with(transport.clone());
    let cancel_queued = Arc::new(AtomicBool::new(false));
    let queued_cancel_checks = Arc::new(AtomicUsize::new(0));
    let queued_cancel_check = {
        let cancel_queued = cancel_queued.clone();
        let queued_cancel_checks = queued_cancel_checks.clone();
        move || {
            queued_cancel_checks.fetch_add(1, Ordering::SeqCst);
            cancel_queued.load(Ordering::SeqCst)
        }
    };
    let queued_finished = Arc::new(tokio::sync::Notify::new());
    let queued_vote = &queued;
    let queued_db_ref = &queued_db;
    let queued_client = &client;
    let queued_configured = &configured;
    let queued_cancel = &queued_cancel_check;
    let queued_submission = {
        let queued_finished = queued_finished.clone();
        async move {
            let result = queued_vote
                .submit_prepared_shares(
                    queued_db_ref,
                    queued_client,
                    submission_params(queued_configured),
                    queued_cancel,
                )
                .await;
            queued_finished.notify_one();
            result
        }
    };
    let never_cancel_saturating = never_cancel();
    let observe_ceiling = async {
        while transport.call_count("/shares") < 16 {
            tokio::task::yield_now().await;
        }
        assert_eq!(transport.call_count("/shares"), 16);
        while queued_cancel_checks.load(Ordering::SeqCst) == 0 {
            tokio::task::yield_now().await;
        }
        cancel_queued.store(true, Ordering::SeqCst);
        tokio::time::timeout(Duration::from_millis(100), queued_finished.notified())
            .await
            .expect(
                "queued delivery must observe cancellation while every permit remains occupied",
            );
    };

    let (saturating_report, queued_report, ()) = tokio::join!(
        saturating.submit_prepared_shares(
            &saturating_db,
            &client,
            submission_params(&configured),
            &never_cancel_saturating,
        ),
        queued_submission,
        observe_ceiling,
    );
    let saturating_report = saturating_report.unwrap();
    let queued_report = queued_report.unwrap();

    assert_eq!(saturating_report.deliveries.len(), 16);
    assert!(queued_report.cancelled);
    assert!(queued_report.deliveries.is_empty());
    assert_eq!(queued_report.pending_share_indices, vec![0, 1]);
    assert_eq!(transport.call_count("/shares"), 16);
    assert_eq!(
        saturating_report
            .deliveries
            .iter()
            .map(|delivery| delivery.share_index)
            .collect::<Vec<_>>(),
        (0..16).collect::<Vec<_>>()
    );
}
