use std::collections::HashMap;

use crate::{share_policy::ShareSubmissionPlan, types::ShareDelegationRecord};

pub(super) fn planned_server_usage(plans: &[ShareSubmissionPlan]) -> HashMap<String, usize> {
    let mut usage = HashMap::new();
    for server in plans.iter().flat_map(|plan| &plan.target_servers) {
        *usage.entry(server.clone()).or_default() += 1;
    }
    usage
}

pub(super) fn share(submit_at: u64, created_at: u64) -> ShareDelegationRecord {
    ShareDelegationRecord {
        round_id: "round".to_string(),
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        sent_to_urls: vec!["https://helper.example.com".to_string()],
        ambiguous_urls: Vec::new(),
        attempting_urls: Vec::new(),
        target_count: 1,
        nullifier: vec![7; 32],
        confirmed: false,
        submit_at,
        created_at,
    }
}

pub(super) fn random_bytes(samples: &[u64]) -> Vec<u8> {
    samples
        .iter()
        .flat_map(|sample| sample.to_le_bytes())
        .collect()
}
