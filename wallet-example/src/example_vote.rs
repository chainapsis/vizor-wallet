use std::collections::BTreeMap;

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use zcash_voting::prelude::{
    canonical_helper_url_list, commit_atomic_vote_batch, commit_batch, os_random_bytes,
    sync_vote_tree, track_pending_shares, van_witness, CommittedVote, DraftVote, HelperClient,
    NoopProgressReporter, SharePlan, ShareSubmissionReport, ShareSubmissionRequest,
    ShareTimingPolicy, ShareTrackingParams, ShareTrackingReport, SignedVoteBatch,
    SignedVoteCommitment, SignedVoteCommitments, VanWitness, VoteSigner, VoteSubmission, VotingDb,
    VotingHotkey,
};
use zcash_voting::share::policy::{
    plan_share_submissions, share_submission_random_bytes_required, share_submission_target_count,
    SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, VOTE_COMMITMENT_SHARE_COUNT,
};

/// Inputs for deriving a Merkle witness for one confirmed delegation bundle.
///
/// `round_id` and `bundle_index` identify a bundle whose VAN position has
/// already been recorded after delegation confirmation. `vote_node_url` is the
/// vote-chain endpoint used to sync the vote-authority-note tree.
pub struct WalletVanWitnessRequest<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub vote_node_url: &'a str,
}

/// Inputs for committing one cast-vote for one proposal.
///
/// `draft` is the wallet's proposal choice. `van_witness` must come from the
/// confirmed bundle identified by `round_id` and `bundle_index`, and
/// `voting_hotkey` signs the cast-vote payload.
pub struct WalletVoteCommitRequest<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub draft: &'a DraftVote,
    pub van_witness: &'a VanWitness,
    pub voting_hotkey: &'a VotingHotkey,
}

/// Inputs for the historical batch-named singleton compatibility API.
///
/// `drafts` must contain exactly one item. Use
/// [`WalletAtomicVoteBatchRequest`] for multiple proposals.
pub struct WalletVoteCommitBatchRequest<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub drafts: &'a [DraftVote],
    pub van_witness: &'a VanWitness,
    pub voting_hotkey: &'a VotingHotkey,
}

/// Inputs for committing one bundle's cast-votes in one atomic transaction.
pub struct WalletAtomicVoteBatchRequest<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub drafts: &'a [DraftVote],
    pub van_witness: &'a VanWitness,
    pub voting_hotkey: &'a VotingHotkey,
}

/// Persist this complete plan set before submitting its first helper share.
///
/// Keeping the canonical fleet with the plans lets restart recovery reuse the
/// same commitment-wide balancing and quota context.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WalletHelperSharePlan {
    /// Canonical planning-time fleet retained as historical plan context.
    /// Submission separately validates the wallet's current configured fleet.
    pub configured_server_urls: Vec<String>,
    pub share_plans: Vec<SharePlan>,
}

/// Inputs for planning all helper shares in one committed vote.
pub struct WalletHelperSharePlanningRequest<'a> {
    /// Complete configured fleet. Exact and canonically equivalent duplicates
    /// are rejected rather than silently collapsed.
    pub configured_server_urls: &'a [String],
    pub now_seconds: u64,
    pub vote_end_time_seconds: u64,
    pub last_moment_buffer_seconds: Option<u64>,
    /// Whether the committed vote contains the protocol's single share.
    /// This is valid only when the commitment exposes exactly one payload.
    pub single_share: bool,
    /// Position in this committed vote's share payloads, not a domain share ID.
    pub immediate_share_index: Option<u32>,
}

/// Inputs for submitting a persisted complete helper-share plan.
pub struct WalletHelperShareSubmissionRequest<'a> {
    /// The original complete plan set persisted before the first helper POST.
    pub persisted_plan: &'a WalletHelperSharePlan,
    /// Complete current helper fleet. It may differ from the planning fleet,
    /// but every stored plan must remain valid against it.
    pub configured_server_urls: &'a [String],
    /// Current Unix time used only for process-local helper health ordering.
    pub now_seconds: u64,
}

/// One durably journaled initial helper-share delivery result.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WalletShareDelivery {
    pub share_index: u32,
    pub submission: ShareSubmissionReport,
}

/// Inputs for one confirmation and recovery pass over a round.
pub struct WalletShareTrackingRequest<'a> {
    pub round_id: &'a str,
    /// The complete current helper fleet, which may differ from initial plans.
    pub configured_server_urls: &'a [String],
    pub now_seconds: u64,
    pub vote_end_time_seconds: Option<u64>,
}

/// Network-side results to persist after the caller submits a committed vote.
pub struct WalletVoteExecutionRequest<'a> {
    pub vote_tx_hash: &'a str,
    pub vc_tree_position: u64,
}

/// Derives the VAN witness needed to commit votes for one bundle.
///
/// Call this after the bundle's delegation transaction is confirmed and its VAN
/// position is persisted. The returned witness is anchored at the vote-tree
/// height reached by the sync performed inside this function.
///
/// # Errors
///
/// Returns an error if the vote tree cannot be synced from `vote_node_url`, the
/// bundle is unknown, its VAN position or initial commitment is missing, its
/// confirmed position contains a different public leaf, or the witness cannot
/// be generated at the synced height.
pub fn derive_vote_van_witness(
    voting_db: &VotingDb,
    request: WalletVanWitnessRequest<'_>,
) -> Result<VanWitness> {
    // 1. Pull the latest vote-authority-note tree state for the round and keep
    // the synced height as the anchor for the witness produced below.
    let anchor_height = sync_vote_tree(voting_db, request.round_id, request.vote_node_url)
        .context("sync vote tree")?;

    // 2. Derive this bundle's Merkle witness against the freshly synced tree.
    van_witness(
        voting_db,
        request.round_id,
        request.bundle_index,
        anchor_height,
    )
    .context("generate VAN witness")
}

/// Builds, signs, and persists recovery state for one cast-vote.
///
/// The returned `CommittedVote` contains the chain-ready cast-vote fields and
/// helper-share payloads. Repeated calls for the same
/// `(round_id, bundle_index, proposal_id)` return persisted recovery material
/// when the stored draft matches the requested draft.
///
/// # Errors
///
/// Returns an error if the bundle or warmed voting state is missing, the draft
/// conflicts with stored recovery state, proof generation fails, signing fails,
/// or recovery state cannot be persisted.
pub fn commit_vote_bundle(
    voting_db: &VotingDb,
    request: WalletVoteCommitRequest<'_>,
) -> Result<CommittedVote> {
    let progress = NoopProgressReporter;
    CommittedVote::commit(
        voting_db,
        request.round_id,
        request.bundle_index,
        request.draft,
        request.van_witness,
        VoteSigner::hotkey(request.voting_hotkey),
        &progress,
    )
    .context("commit cast-vote")
}

/// Builds one signed commitment through the historical batch-named API.
///
/// `request.drafts` must contain exactly one item. Submit the returned
/// commitment to the singleton cast-vote endpoint.
pub fn commit_vote_bundle_batch(
    voting_db: &VotingDb,
    request: WalletVoteCommitBatchRequest<'_>,
) -> Result<SignedVoteCommitments> {
    let progress = NoopProgressReporter;
    commit_batch(
        voting_db,
        request.round_id,
        request.bundle_index,
        request.drafts,
        request.van_witness,
        VoteSigner::hotkey(request.voting_hotkey),
        &progress,
    )
    .context("commit independent cast-votes")
}

/// Builds, signs, and persists recovery state for one atomic cast-vote batch.
///
/// The returned value contains one canonical batch request body. Its individual
/// commitments must not be submitted through the singleton endpoint.
pub fn commit_atomic_vote_bundle_batch(
    voting_db: &VotingDb,
    request: WalletAtomicVoteBatchRequest<'_>,
) -> Result<SignedVoteBatch> {
    let progress = NoopProgressReporter;
    commit_atomic_vote_batch(
        voting_db,
        request.round_id,
        request.bundle_index,
        request.drafts,
        request.van_witness,
        VoteSigner::hotkey(request.voting_hotkey),
        &progress,
    )
    .context("commit atomic cast-vote batch")
}

/// Returns the cast-vote payload the caller should submit to the vote chain.
///
/// Helper shares must be planned with [`plan_committed_vote_shares`] and sent
/// through [`submit_committed_vote_shares`] so every attempt is journaled
/// before dispatch.
pub fn committed_vote_submission(
    voting_db: &VotingDb,
    committed: &CommittedVote,
) -> Result<VoteSubmission> {
    committed
        .submission(voting_db)
        .context("build vote submission")
}

/// Returns a single wallet-facing aggregate for external API boundaries.
///
/// This includes chain fields, helper-share data, and stored recovery JSON in
/// one typed object. Do not POST its raw helper payloads; use
/// [`submit_committed_vote_shares`] for durable delivery.
pub fn committed_vote_signed_commitment(
    voting_db: &VotingDb,
    committed: &CommittedVote,
) -> Result<SignedVoteCommitment> {
    committed
        .signed_commitment(voting_db)
        .context("build signed vote commitment")
}

/// Plans every helper share together using fresh independent OS entropy.
///
/// The helper URLs are canonicalized before planning because placement counts
/// distinct endpoint identities. Persist the returned value before calling
/// [`submit_committed_vote_shares`] and reuse it after restart; planning only
/// missing shares would lose commitment-wide balancing and quota context.
pub fn plan_committed_vote_shares(
    committed: &CommittedVote,
    request: WalletHelperSharePlanningRequest<'_>,
) -> Result<WalletHelperSharePlan> {
    let configured_server_urls = canonical_distinct_helper_urls(request.configured_server_urls)?;
    let share_count = committed.share_payloads().len();
    let required = share_submission_random_bytes_required(
        share_count,
        configured_server_urls.len(),
        request.now_seconds,
        request.vote_end_time_seconds,
        request.last_moment_buffer_seconds,
        request.single_share,
    );
    let submit_at_random_bytes = os_random_bytes(required.submit_at_random_bytes);
    let server_random_bytes = os_random_bytes(required.server_random_bytes);
    let share_plans = plan_share_submissions(
        share_count,
        &configured_server_urls,
        request.now_seconds,
        request.vote_end_time_seconds,
        request.last_moment_buffer_seconds,
        request.single_share,
        request.immediate_share_index,
        &submit_at_random_bytes,
        &server_random_bytes,
    )
    .context("plan helper-share submissions")?;

    Ok(WalletHelperSharePlan {
        configured_server_urls,
        share_plans,
    })
}

fn canonical_distinct_helper_urls(configured_server_urls: &[String]) -> Result<Vec<String>> {
    if configured_server_urls.is_empty() {
        bail!("configured helper URLs must not be empty");
    }
    let canonical =
        canonical_helper_url_list(configured_server_urls).context("validate helper URLs")?;
    if canonical.len() != configured_server_urls.len() {
        bail!("configured helper URLs must contain distinct canonical helpers");
    }
    Ok(canonical)
}

/// Submits every committed helper share through crate-owned durable journaling.
///
/// `client` is caller-owned so a wallet can enforce its Tor or proxy route.
/// Each returned report describes state already persisted by
/// `CommittedVote::submit_share_to_helpers`; do not record it a second time.
/// The complete plan set is validated against the current fleet before any
/// share is journaled or sent.
pub async fn submit_committed_vote_shares(
    voting_db: &VotingDb,
    committed: &CommittedVote,
    client: &HelperClient,
    request: WalletHelperShareSubmissionRequest<'_>,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<Vec<WalletShareDelivery>> {
    let share_count = committed.share_payloads().len();
    let configured_server_urls = validate_helper_submission_plan(
        request.persisted_plan,
        request.configured_server_urls,
        share_count,
    )?;

    let mut deliveries = Vec::with_capacity(share_count);
    for (share_index, plan) in request.persisted_plan.share_plans.iter().enumerate() {
        if cancel() {
            break;
        }
        let share_index = u32::try_from(share_index).context("share index exceeds u32")?;
        let submission = committed
            .submit_share_to_helpers(
                voting_db,
                client,
                ShareSubmissionRequest {
                    share_index,
                    plan,
                    configured_server_urls: &configured_server_urls,
                    now_seconds: request.now_seconds,
                },
                cancel,
            )
            .await
            .with_context(|| format!("submit helper share {share_index}"))?;
        deliveries.push(WalletShareDelivery {
            share_index,
            submission,
        });
    }

    Ok(deliveries)
}

fn validate_helper_submission_plan(
    persisted_plan: &WalletHelperSharePlan,
    configured_server_urls: &[String],
    share_count: usize,
) -> Result<Vec<String>> {
    if persisted_plan.share_plans.len() != share_count {
        bail!(
            "persisted helper-share plan count {} does not match committed share count {share_count}",
            persisted_plan.share_plans.len()
        );
    }

    let configured_server_urls = canonical_distinct_helper_urls(configured_server_urls)?;
    let expected_target = share_submission_target_count(configured_server_urls.len());
    let mut assignment_counts = BTreeMap::<String, usize>::new();
    for (share_index, plan) in persisted_plan.share_plans.iter().enumerate() {
        let planned = canonical_helper_url_list(&plan.target_servers)
            .with_context(|| format!("validate helper-share plan {share_index}"))?;
        if planned.len() != plan.target_servers.len() {
            bail!("helper-share plan {share_index} contains duplicate canonical targets");
        }
        let planned_target = usize::try_from(plan.target_count)
            .context("helper-share plan target count exceeds usize")?;
        if planned_target != expected_target || planned.len() != planned_target {
            bail!(
                "helper-share plan {share_index} target count and target list must match current fleet target {expected_target}"
            );
        }
        if let Some(server_url) = planned
            .iter()
            .find(|server_url| !configured_server_urls.contains(server_url))
        {
            bail!(
                "helper-share plan {share_index} targets helper removed from current configuration: {server_url}"
            );
        }
        for server_url in planned {
            *assignment_counts.entry(server_url).or_default() += 1;
        }
    }

    let complete_normal_batch = share_count == VOTE_COMMITMENT_SHARE_COUNT;
    if complete_normal_batch && configured_server_urls.len() >= 2 {
        if let Some((server_url, assignment_count)) = assignment_counts
            .iter()
            .find(|(_, count)| **count > SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER)
        {
            bail!(
                "persisted helper-share plan assigns {assignment_count} shares to {server_url}, exceeding the complete-batch maximum of {SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER}"
            );
        }
    }

    Ok(configured_server_urls)
}

/// Runs one crate-owned confirmation and recovery pass.
///
/// Schedule the next pass from `next_delay_seconds`. The caller retains
/// ownership of the timer, app-lock and round-expiry cancellation lifecycle.
pub async fn track_committed_vote_shares(
    voting_db: &VotingDb,
    client: &HelperClient,
    request: WalletShareTrackingRequest<'_>,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<ShareTrackingReport> {
    let params = ShareTrackingParams {
        round_id: request.round_id,
        configured_server_urls: request.configured_server_urls,
        now_seconds: request.now_seconds,
        vote_end_time_seconds: request.vote_end_time_seconds,
        policy: ShareTimingPolicy::default(),
        random_bytes: &os_random_bytes,
    };
    track_pending_shares(voting_db, &params, client, cancel)
        .await
        .context("track pending helper shares")
}

/// Persists successful vote-chain submission fields.
///
/// Helper-share submission persists each attempt inside
/// `CommittedVote::submit_share_to_helpers`; it is intentionally absent here
/// so a wallet cannot accidentally record a post-hoc result twice.
pub fn record_committed_vote_execution(
    voting_db: &VotingDb,
    committed: &CommittedVote,
    request: WalletVoteExecutionRequest<'_>,
) -> Result<()> {
    committed
        .record_submission(voting_db, request.vote_tx_hash)
        .context("record vote submission")?;
    committed
        .record_vc_position(voting_db, request.vc_tree_position)
        .context("record vote commitment tree position")?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        canonical_distinct_helper_urls, validate_helper_submission_plan, WalletHelperSharePlan,
        SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER, VOTE_COMMITMENT_SHARE_COUNT,
    };
    use zcash_voting::prelude::SharePlan;

    fn helper(index: u32) -> String {
        format!("https://helper-{index}.example")
    }

    fn persisted_plan(target_servers: &[u32], target_count: u32) -> WalletHelperSharePlan {
        WalletHelperSharePlan {
            configured_server_urls: (1..=3).map(helper).collect(),
            share_plans: vec![SharePlan {
                immediate: false,
                submit_at: 1_000,
                target_count,
                target_servers: target_servers.iter().copied().map(helper).collect(),
            }],
        }
    }

    fn full_persisted_plan(targets_for_share: impl Fn(usize) -> Vec<u32>) -> WalletHelperSharePlan {
        WalletHelperSharePlan {
            configured_server_urls: (1..=3).map(helper).collect(),
            share_plans: (0..VOTE_COMMITMENT_SHARE_COUNT)
                .map(|share_index| SharePlan {
                    immediate: false,
                    submit_at: 1_000 + share_index as u64,
                    target_count: 2,
                    target_servers: targets_for_share(share_index)
                        .into_iter()
                        .map(helper)
                        .collect(),
                })
                .collect(),
        }
    }

    #[test]
    fn helper_planning_rejects_exact_and_canonical_duplicates() {
        for configured in [
            vec![
                "https://helper.example".to_string(),
                "https://helper.example".to_string(),
            ],
            vec![
                "https://helper.example:443/".to_string(),
                "https://HELPER.example".to_string(),
            ],
        ] {
            assert!(canonical_distinct_helper_urls(&configured).is_err());
        }
    }

    #[test]
    fn helper_planning_retains_a_unique_canonical_fleet() {
        let configured = vec![
            "https://ONE.example:443/".to_string(),
            "https://two.example/base/".to_string(),
        ];

        assert_eq!(
            canonical_distinct_helper_urls(&configured).unwrap(),
            vec![
                "https://one.example".to_string(),
                "https://two.example/base".to_string(),
            ]
        );
    }

    #[test]
    fn helper_submission_allows_compatible_current_fleet_churn() {
        let plan = persisted_plan(&[1, 2], 2);

        for current in [
            vec![helper(1), helper(2), helper(3)],
            vec![helper(1), helper(2), helper(3), helper(4)],
        ] {
            assert_eq!(
                validate_helper_submission_plan(&plan, &current, 1).unwrap(),
                current
            );
        }
    }

    #[test]
    fn helper_submission_canonicalizes_the_current_fleet() {
        let plan = persisted_plan(&[1, 2], 2);
        let current = vec![
            "HTTPS://HELPER-1.EXAMPLE:443/".to_string(),
            helper(2),
            helper(3),
        ];

        assert_eq!(
            validate_helper_submission_plan(&plan, &current, 1).unwrap(),
            vec![helper(1), helper(2), helper(3)]
        );
    }

    #[test]
    fn helper_submission_rejects_a_removed_planned_target() {
        let plan = persisted_plan(&[1, 3], 2);
        let current = vec![helper(1), helper(2), helper(4)];

        assert!(validate_helper_submission_plan(&plan, &current, 1).is_err());
    }

    #[test]
    fn helper_submission_rejects_current_fleet_target_drift() {
        let plan = persisted_plan(&[1, 2], 2);
        let current = (1..=5).map(helper).collect::<Vec<_>>();

        assert!(validate_helper_submission_plan(&plan, &current, 1).is_err());
    }

    #[test]
    fn helper_submission_accepts_complete_batch_at_assignment_quota() {
        let plan = full_persisted_plan(|share_index| {
            if share_index < SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER {
                vec![1, 2 + (share_index % 2) as u32]
            } else {
                vec![2, 3]
            }
        });
        let current = vec![helper(1), helper(2), helper(3)];

        assert!(
            validate_helper_submission_plan(&plan, &current, VOTE_COMMITMENT_SHARE_COUNT).is_ok()
        );
    }

    #[test]
    fn helper_submission_rejects_complete_batch_assignment_quota_violation() {
        let plan = full_persisted_plan(|share_index| {
            if share_index <= SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER {
                vec![1, 2 + (share_index % 2) as u32]
            } else {
                vec![2, 3]
            }
        });
        let current = vec![helper(1), helper(2), helper(3)];

        assert!(
            validate_helper_submission_plan(&plan, &current, VOTE_COMMITMENT_SHARE_COUNT).is_err()
        );
    }

    #[test]
    fn helper_submission_preserves_the_one_helper_complete_batch_exception() {
        let plan = WalletHelperSharePlan {
            configured_server_urls: vec![helper(1)],
            share_plans: (0..VOTE_COMMITMENT_SHARE_COUNT)
                .map(|share_index| SharePlan {
                    immediate: false,
                    submit_at: 1_000 + share_index as u64,
                    target_count: 1,
                    target_servers: vec![helper(1)],
                })
                .collect(),
        };
        let current = vec![helper(1)];

        assert!(
            validate_helper_submission_plan(&plan, &current, VOTE_COMMITMENT_SHARE_COUNT).is_ok()
        );
    }

    #[test]
    fn helper_submission_rejects_invalid_current_fleets() {
        let plan = persisted_plan(&[1, 2], 2);

        for current in [
            vec![],
            vec![helper(1), helper(1)],
            vec!["not a helper URL".to_string()],
            vec![
                "https://helper.example:443/".to_string(),
                "https://HELPER.example".to_string(),
            ],
        ] {
            assert!(validate_helper_submission_plan(&plan, &current, 1).is_err());
        }
    }

    #[test]
    fn helper_submission_validates_every_plan_before_delivery() {
        let mut plan = persisted_plan(&[1, 2], 2);
        plan.share_plans.push(SharePlan {
            immediate: false,
            submit_at: 2_000,
            target_count: 2,
            target_servers: vec![helper(1), helper(4)],
        });
        let current = vec![helper(1), helper(2), helper(3)];

        assert!(validate_helper_submission_plan(&plan, &current, 2).is_err());
        assert!(validate_helper_submission_plan(&plan, &current, 1).is_err());
    }
}
