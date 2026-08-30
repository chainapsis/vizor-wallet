use std::collections::{HashMap, HashSet};

use super::{
    super::*,
    fixtures::{planned_server_usage, random_bytes},
};
use crate::{
    share_policy::initial_placement::select_batch_share_submission_targets, types::VotingError,
};

#[test]
fn helper_target_count_is_half_rounded_up_and_capped_by_protocol_policy() {
    assert_eq!(share_submission_target_count(0), 0);
    assert_eq!(share_submission_target_count(1), 1);
    assert_eq!(share_submission_target_count(2), 1);
    assert_eq!(share_submission_target_count(3), 2);
    assert_eq!(share_submission_target_count(5), 3);
    assert_eq!(share_submission_target_count(10), 5);
    assert_eq!(share_submission_target_count(20), 10);
    assert_eq!(share_submission_target_count(21), 10);
    assert_eq!(share_submission_target_count(30), 10);
    assert_eq!(share_submission_target_count(100), 10);
    assert_eq!(SHARE_HELPER_TARGET_COUNT_CAP, 10);
    assert_eq!(SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, 12);
    assert_eq!(effective_share_submission_target_count(0, 33), 10);
    assert_eq!(effective_share_submission_target_count(99, 30), 10);
    assert_eq!(effective_share_submission_target_count(99, 10), 10);
}

#[test]
fn helper_selection_policy_exposes_shared_limits() {
    assert_eq!(
        share_server_selection_policy(10),
        ShareServerSelectionPolicy {
            target_count: 5,
            max_shares_per_server: 12,
            min_server_count: 7,
            preflight_soft_timeout_milliseconds: 2_000,
            preflight_hard_timeout_milliseconds: 30_000,
            post_timeout_milliseconds: 30_000,
            initial_delivery_timeout_milliseconds: 60_000,
            max_concurrent_posts: 16,
        }
    );
    assert_eq!(
        (
            share_server_selection_policy(3).target_count,
            share_server_selection_policy(3).max_shares_per_server,
            share_server_selection_policy(3).min_server_count,
        ),
        (2, 12, 3)
    );
    assert_eq!(
        (
            share_server_selection_policy(5).target_count,
            share_server_selection_policy(5).max_shares_per_server,
            share_server_selection_policy(5).min_server_count,
        ),
        (3, 12, 4)
    );
    assert_eq!(
        (
            share_server_selection_policy(100).target_count,
            share_server_selection_policy(100).max_shares_per_server,
            share_server_selection_policy(100).min_server_count,
        ),
        (10, 12, 14)
    );
    assert_eq!(
        (
            share_server_selection_policy(0).target_count,
            share_server_selection_policy(0).max_shares_per_server,
            share_server_selection_policy(0).min_server_count,
        ),
        (0, 0, 0)
    );
    assert_eq!(
        (
            share_server_selection_policy(1).target_count,
            share_server_selection_policy(1).max_shares_per_server,
            share_server_selection_policy(1).min_server_count,
        ),
        (1, 16, 1)
    );
}

#[test]
fn share_submission_plan_randomizes_target_servers() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    let plan = plan_share_submission(
        &servers,
        1_000,
        2_000,
        Some(100),
        false,
        &random_bytes(&[1u64 << 63]),
        &random_bytes(&[1, 0]),
    )
    .unwrap();

    assert_eq!(plan.submit_at, 1_450);
    assert_eq!(plan.target_count, 2);
    assert_eq!(
        plan.target_servers,
        vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string(),
        ]
    );
}

#[test]
fn share_submission_plan_rejects_empty_server_list() {
    assert!(matches!(
        plan_share_submission(
            &[],
            1_000,
            2_000,
            Some(100),
            false,
            &random_bytes(&[1u64 << 63]),
            &[]
        ),
        Err(VotingError::InvalidInput { .. })
    ));
    assert!(matches!(
        plan_share_submission_from_order(&[], 1_000, 2_000, Some(100), false, 0.0),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn share_submission_plan_rejects_duplicate_server_urls() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://one.example.com".to_string(),
    ];

    assert!(matches!(
        plan_share_submission(
            &servers,
            1_000,
            2_000,
            Some(100),
            false,
            &random_bytes(&[1u64 << 63]),
            &random_bytes(&[0])
        ),
        Err(VotingError::InvalidInput { .. })
    ));
    assert!(matches!(
        plan_share_submission_from_order(&servers, 1_000, 2_000, Some(100), false, 0.0),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn share_submission_random_bytes_required_counts_independent_share_plans() {
    assert_eq!(
        share_submission_random_bytes_required(2, 3, 1_000, 2_000, Some(100), false),
        ShareSubmissionRandomBytesRequired {
            submit_at_random_bytes: 16,
            server_random_bytes: 32,
        }
    );
    assert_eq!(
        share_submission_random_bytes_required(2, 3, 1_000, 2_000, Some(100), true),
        ShareSubmissionRandomBytesRequired {
            submit_at_random_bytes: 0,
            server_random_bytes: 32,
        }
    );
}

#[test]
fn share_submission_batch_plan_uses_independent_entropy_per_share() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    let plans = plan_share_submissions(
        2,
        &servers,
        1_000,
        2_000,
        Some(100),
        false,
        None,
        &random_bytes(&[0, 1u64 << 63]),
        &random_bytes(&[1, 0, 0, 1]),
    )
    .unwrap();

    assert_eq!(plans.len(), 2);
    assert_eq!(plans[0].submit_at, 1_000);
    assert_eq!(
        plans[0].target_servers,
        vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string(),
        ]
    );
    assert_eq!(plans[1].submit_at, 1_450);
    assert_eq!(
        plans[1].target_servers,
        vec![
            "https://two.example.com".to_string(),
            "https://three.example.com".to_string(),
        ]
    );
}

#[test]
fn complete_batch_with_three_helpers_balances_two_targets() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];
    let repeated_shuffle = vec![0u64; 16 * 2];

    let plans = plan_share_submissions(
        16,
        &servers,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &random_bytes(&repeated_shuffle),
    )
    .unwrap();

    let mut usage = HashMap::<String, usize>::new();
    for plan in &plans {
        assert_eq!(plan.target_servers.len(), 2);
        assert_eq!(plan.target_servers.iter().collect::<HashSet<_>>().len(), 2);
        for server in &plan.target_servers {
            *usage.entry(server.clone()).or_default() += 1;
        }
    }
    assert_eq!(usage.values().sum::<usize>(), 32);
    assert!(usage.values().all(|count| (10..=11).contains(count)));
}

#[test]
fn complete_batch_caps_helper_usage_at_derived_three_quarters() {
    let servers: Vec<String> = (0..10)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let server_random_bytes = vec![
        0;
        VOTE_COMMITMENT_SHARE_COUNT
            * share_server_order_random_bytes_required(servers.len())
    ];

    let plans = plan_share_submissions(
        VOTE_COMMITMENT_SHARE_COUNT,
        &servers,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &server_random_bytes,
    )
    .unwrap();

    let usage = planned_server_usage(&plans);
    let target_count = share_submission_target_count(servers.len());
    for plan in &plans {
        assert_eq!(plan.target_servers.len(), target_count);
        assert_eq!(
            plan.target_servers.iter().collect::<HashSet<_>>().len(),
            target_count
        );
    }
    assert!(servers
        .iter()
        .all(|server| usage.get(server).copied() == Some(8)));
    assert!(usage
        .values()
        .all(|count| *count <= SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER));
}

#[test]
fn complete_batch_assignment_changes_with_entropy() {
    let servers: Vec<String> = (0..10)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let samples_per_plan = VOTE_COMMITMENT_SHARE_COUNT
        * share_server_order_random_bytes_required(servers.len())
        / std::mem::size_of::<u64>();
    let zero_entropy = random_bytes(&vec![0; samples_per_plan]);
    let varied_entropy = random_bytes(
        &(0..samples_per_plan)
            .map(|index| (index as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15))
            .collect::<Vec<_>>(),
    );

    let plan = |entropy: &[u8]| {
        plan_share_submissions(
            VOTE_COMMITMENT_SHARE_COUNT,
            &servers,
            1_000,
            2_000,
            None,
            false,
            None,
            &[],
            entropy,
        )
        .unwrap()
    };

    assert_ne!(plan(&zero_entropy), plan(&varied_entropy));
}

#[test]
fn complete_batch_balances_larger_fleet() {
    let servers: Vec<String> = (0..33)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let server_random_bytes = vec![
        0;
        VOTE_COMMITMENT_SHARE_COUNT
            * share_server_order_random_bytes_required(servers.len())
    ];

    let plans = plan_share_submissions(
        VOTE_COMMITMENT_SHARE_COUNT,
        &servers,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &server_random_bytes,
    )
    .unwrap();

    let mut usage = HashMap::<String, usize>::new();
    let target_count = share_submission_target_count(servers.len());
    for plan in &plans {
        assert_eq!(plan.target_servers.len(), target_count);
        for server in &plan.target_servers {
            *usage.entry(server.clone()).or_default() += 1;
        }
    }
    assert_eq!(
        usage.values().sum::<usize>(),
        VOTE_COMMITMENT_SHARE_COUNT * target_count
    );
    assert_eq!(usage.len(), servers.len());
    assert!(usage.values().all(|count| (4..=5).contains(count)));
}

#[test]
fn preferred_pool_limits_initial_targets() {
    let servers: Vec<String> = (0..12)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let server_random_bytes = vec![
        0;
        VOTE_COMMITMENT_SHARE_COUNT
            * share_server_order_random_bytes_required(servers.len())
    ];

    let plans = plan_share_submissions_with_preferred_servers(
        VOTE_COMMITMENT_SHARE_COUNT,
        &servers,
        10,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &server_random_bytes,
    )
    .unwrap();

    assert!(plans.iter().all(|plan| plan
        .target_servers
        .iter()
        .all(|server| servers[..10].contains(server))));
    assert!(plans.iter().all(|plan| plan
        .target_servers
        .iter()
        .all(|server| !servers[10..].contains(server))));
}

#[test]
fn minimum_planning_pool_enforces_derived_three_quarters_cap() {
    let servers: Vec<String> = (0..10)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let server_random_bytes = vec![
        0;
        VOTE_COMMITMENT_SHARE_COUNT
            * share_server_order_random_bytes_required(servers.len())
    ];

    let plans = plan_share_submissions_with_preferred_servers(
        VOTE_COMMITMENT_SHARE_COUNT,
        &servers,
        3,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &server_random_bytes,
    )
    .unwrap();

    let usage = planned_server_usage(&plans);
    assert!(plans.iter().all(|plan| {
        plan.target_servers.len() == 5
            && plan
                .target_servers
                .iter()
                .all(|server| servers[..7].contains(server))
    }));
    assert_eq!(usage.values().sum::<usize>(), 80);
    assert_eq!(usage.len(), 7);
    assert!(usage
        .values()
        .all(|count| *count <= SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER));
}

#[test]
fn protocol_target_cap_uses_fourteen_helpers_for_complete_batch_capacity() {
    for server_count in [20, 21, 30, 100] {
        let servers: Vec<String> = (0..server_count)
            .map(|index| format!("https://helper-{index}.example.com"))
            .collect();
        let server_random_bytes = vec![
            0;
            VOTE_COMMITMENT_SHARE_COUNT
                * share_server_order_random_bytes_required(servers.len())
        ];

        let plans = plan_share_submissions_with_preferred_servers(
            VOTE_COMMITMENT_SHARE_COUNT,
            &servers,
            1,
            1_000,
            2_000,
            None,
            false,
            None,
            &[],
            &server_random_bytes,
        )
        .unwrap();

        let usage = planned_server_usage(&plans);
        assert!(plans.iter().all(|plan| plan.target_count == 10));
        assert_eq!(usage.values().sum::<usize>(), 160);
        assert_eq!(usage.len(), 14);
        assert!(usage.values().all(|count| (11..=12).contains(count)));
        assert!(usage.keys().all(|server| servers[..14].contains(server)));
    }
}

#[test]
fn infeasible_initial_assignment_capacity_is_rejected() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
    ];
    let mut usage = HashMap::from([
        (
            servers[0].clone(),
            SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER,
        ),
        (
            servers[1].clone(),
            SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER,
        ),
    ]);

    assert!(matches!(
        select_batch_share_submission_targets(
            &servers,
            1,
            Some(SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER),
            &mut usage,
            &random_bytes(&[0]),
        ),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn incomplete_batch_is_exempt_from_complete_batch_usage_cap() {
    let servers: Vec<String> = (0..15)
        .map(|index| format!("https://helper-{index}.example.com"))
        .collect();
    let share_count = VOTE_COMMITMENT_SHARE_COUNT - 1;
    let plans = plan_share_submissions_with_preferred_servers(
        share_count,
        &servers,
        8,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &vec![0; share_count * share_server_order_random_bytes_required(servers.len())],
    )
    .unwrap();

    let usage = planned_server_usage(&plans);
    assert_eq!(usage.len(), 8);
    assert!(usage.values().all(|count| *count == share_count));
    assert!(usage
        .values()
        .all(|count| *count > SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER));
}

#[test]
fn preferred_pool_rejects_count_beyond_ranked_servers() {
    let servers = vec!["https://only.example.com".to_string()];

    assert!(matches!(
        plan_share_submissions_with_preferred_servers(
            1,
            &servers,
            2,
            1_000,
            2_000,
            None,
            false,
            None,
            &[],
            &[],
        ),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn complete_batch_with_one_helper_is_forced_full_coverage() {
    let servers = vec!["https://only.example.com".to_string()];

    let plans = plan_share_submissions(
        VOTE_COMMITMENT_SHARE_COUNT,
        &servers,
        1_000,
        2_000,
        None,
        false,
        None,
        &[],
        &[],
    )
    .unwrap();

    assert!(plans.iter().all(|plan| plan.target_servers == servers));
    assert_eq!(planned_server_usage(&plans)[&servers[0]], 16);
}

#[test]
fn single_share_mode_is_exempt_from_complete_batch_usage_cap() {
    let servers = vec!["https://only.example.com".to_string()];

    let plans =
        plan_share_submissions(1, &servers, 1_000, 2_000, None, true, None, &[], &[]).unwrap();

    assert_eq!(plans.len(), 1);
    assert_eq!(plans[0].target_servers, servers);
}

#[test]
fn single_share_mode_rejects_non_singleton_batches() {
    let servers = vec!["https://only.example.com".to_string()];

    for share_count in [0, 2, VOTE_COMMITMENT_SHARE_COUNT] {
        assert!(matches!(
            plan_share_submissions(
                share_count,
                &servers,
                1_000,
                2_000,
                None,
                true,
                None,
                &[],
                &vec![0; share_count * share_server_order_random_bytes_required(servers.len())],
            ),
            Err(VotingError::InvalidInput { .. })
        ));
    }
}

#[test]
fn share_submission_batch_plan_rejects_missing_entropy() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    assert!(matches!(
        plan_share_submissions(
            2,
            &servers,
            1_000,
            2_000,
            Some(100),
            false,
            None,
            &random_bytes(&[0]),
            &random_bytes(&[1, 0, 0, 1]),
        ),
        Err(VotingError::InvalidInput { .. })
    ));
    assert!(matches!(
        plan_share_submissions(
            2,
            &servers,
            1_000,
            2_000,
            Some(100),
            false,
            None,
            &random_bytes(&[0, 1u64 << 63]),
            &random_bytes(&[1, 0, 0]),
        ),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn round_immediate_share_key_uses_highest_bundle_lowest_voted_proposal_and_share_zero() {
    assert_eq!(
        round_immediate_share_key(Some(3), &[7, 2, 5]),
        Some(ImmediateShareKey {
            bundle_index: 3,
            proposal_id: 2,
            share_index: 0,
        })
    );
    assert_eq!(round_immediate_share_key(None, &[2]), None);
    assert_eq!(round_immediate_share_key(Some(3), &[]), None);
}

#[test]
fn immediate_batch_position_stays_aligned_and_does_not_perturb_other_plan() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];
    let submit_at = random_bytes(&[0, 1u64 << 63]);
    let server_order = random_bytes(&[1, 0, 0, 1]);
    let baseline = plan_share_submissions(
        2,
        &servers,
        1_000,
        2_000,
        Some(100),
        false,
        None,
        &submit_at,
        &server_order,
    )
    .unwrap();
    let designated = plan_share_submissions(
        2,
        &servers,
        1_000,
        2_000,
        Some(100),
        false,
        Some(1),
        &submit_at,
        &server_order,
    )
    .unwrap();

    assert!(!designated[0].immediate);
    assert_eq!(designated[0], baseline[0]);
    assert!(designated[1].immediate);
    assert_eq!(designated[1].submit_at, 0);
    assert_eq!(designated[1].target_servers, baseline[1].target_servers);
}

#[test]
fn immediate_batch_position_is_validated() {
    let servers = vec!["https://one.example.com".to_string()];
    assert!(matches!(
        plan_share_submissions(0, &servers, 1_000, 2_000, None, false, Some(0), &[], &[],),
        Err(VotingError::InvalidInput { .. })
    ));
    assert!(matches!(
        plan_share_submissions(1, &servers, 1_000, 2_000, None, false, Some(1), &[], &[],),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn immediate_marker_is_distinct_when_all_shares_submit_immediately() {
    let servers = vec!["https://one.example.com".to_string()];
    let plans = plan_share_submissions(
        2,
        &servers,
        1_950,
        2_000,
        Some(100),
        false,
        Some(1),
        &[],
        &[],
    )
    .unwrap();

    assert!(plans.iter().all(|plan| plan.submit_at == 0));
    assert_eq!(plans.iter().filter(|plan| plan.immediate).count(), 1);
    assert!(plans[1].immediate);
}

#[test]
fn share_submission_plan_from_order_uses_caller_server_order() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    let plan =
        plan_share_submission_from_order(&servers, 1_000, 2_000, Some(100), false, 0.0).unwrap();

    assert_eq!(plan.submit_at, 1_000);
    assert_eq!(plan.target_count, 2);
    assert_eq!(
        plan.target_servers,
        vec![
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string(),
        ]
    );
}

#[test]
fn share_submission_target_selection_uses_caller_server_order() {
    let servers = vec![
        "https://three.example.com".to_string(),
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
    ];

    assert_eq!(
        select_share_submission_targets_from_order(&servers, 2),
        vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string()
        ]
    );
}

#[test]
fn randomized_share_submission_target_selection_uses_entropy() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    assert_eq!(
        select_share_submission_targets(&servers, 2, &random_bytes(&[1, 0])).unwrap(),
        vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string()
        ]
    );
}
