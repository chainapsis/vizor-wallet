use super::{super::*, fixtures::random_bytes};
use crate::types::VotingError;

#[test]
fn helper_order_random_bytes_required_matches_shuffle_steps() {
    assert_eq!(share_server_order_random_bytes_required(0), 0);
    assert_eq!(share_server_order_random_bytes_required(1), 0);
    assert_eq!(share_server_order_random_bytes_required(3), 16);
}

#[test]
fn resubmission_order_random_bytes_required_matches_group_shuffles() {
    let configured = vec![
        "https://already-one.example.com".to_string(),
        "https://untried-one.example.com".to_string(),
        "https://untried-two.example.com".to_string(),
        "https://already-two.example.com".to_string(),
    ];
    let sent = vec![
        "https://already-one.example.com".to_string(),
        "https://already-two.example.com".to_string(),
    ];

    assert_eq!(
        resubmission_server_order_random_bytes_required(&configured, &sent),
        16
    );
}

#[test]
fn randomized_helper_order_uses_entropy() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
        "https://three.example.com".to_string(),
    ];

    let ordered = shuffled_share_server_order(&servers, &random_bytes(&[1, 0])).unwrap();

    assert_eq!(
        ordered,
        vec![
            "https://three.example.com".to_string(),
            "https://one.example.com".to_string(),
            "https://two.example.com".to_string()
        ]
    );
}

#[test]
fn randomized_helper_order_rejects_missing_entropy() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://two.example.com".to_string(),
    ];

    assert!(matches!(
        shuffled_share_server_order(&servers, &[]),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn randomized_helper_order_rejects_duplicate_server_urls() {
    let servers = vec![
        "https://one.example.com".to_string(),
        "https://one.example.com".to_string(),
    ];

    assert!(matches!(
        shuffled_share_server_order(&servers, &random_bytes(&[0])),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn resubmission_order_tries_ordered_untried_helpers_first() {
    let untried = vec![
        "https://untried-two.example.com".to_string(),
        "https://untried-one.example.com".to_string(),
    ];
    let already_sent = vec!["https://already.example.com".to_string()];

    assert_eq!(
        resubmission_server_order_from_groups(&untried, &already_sent),
        vec![
            "https://untried-two.example.com".to_string(),
            "https://untried-one.example.com".to_string(),
            "https://already.example.com".to_string()
        ]
    );
}

#[test]
fn randomized_resubmission_order_shuffles_groups_separately() {
    let configured = vec![
        "https://already-one.example.com".to_string(),
        "https://untried-one.example.com".to_string(),
        "https://untried-two.example.com".to_string(),
        "https://already-two.example.com".to_string(),
    ];
    let sent = vec![
        "https://already-one.example.com".to_string(),
        "https://already-two.example.com".to_string(),
    ];

    assert_eq!(
        resubmission_server_order(&configured, &sent, &random_bytes(&[0, 0])).unwrap(),
        vec![
            "https://untried-two.example.com".to_string(),
            "https://untried-one.example.com".to_string(),
            "https://already-two.example.com".to_string(),
            "https://already-one.example.com".to_string()
        ]
    );
}

#[test]
fn randomized_resubmission_order_rejects_missing_entropy() {
    let configured = vec![
        "https://untried-one.example.com".to_string(),
        "https://untried-two.example.com".to_string(),
    ];

    assert!(matches!(
        resubmission_server_order(&configured, &[], &[]),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn randomized_resubmission_order_rejects_duplicate_configured_urls() {
    let configured = vec![
        "https://untried-one.example.com".to_string(),
        "https://untried-one.example.com".to_string(),
    ];

    assert!(matches!(
        resubmission_server_order(&configured, &[], &random_bytes(&[0])),
        Err(VotingError::InvalidInput { .. })
    ));
}

#[test]
fn resubmission_order_from_configured_order_preserves_group_order() {
    let configured = vec![
        "https://already.example.com".to_string(),
        "https://untried.example.com".to_string(),
    ];
    let sent = vec!["https://already.example.com".to_string()];

    assert_eq!(
        resubmission_server_order_from_configured_order(&configured, &sent),
        vec![
            "https://untried.example.com".to_string(),
            "https://already.example.com".to_string()
        ]
    );
}
