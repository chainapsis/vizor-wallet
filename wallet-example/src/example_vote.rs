use anyhow::{Context, Result};
use zcash_voting::prelude::{
    commit_atomic_vote_batch, commit_batch, sync_vote_tree, track_pending_shares, van_witness,
    CommittedVote, DraftVote, HelperClient, HelperFleetPreflight, NoopProgressReporter,
    ShareBatchDeliveryReport, ShareDeliveryPlan, ShareDeliveryPlanningParams,
    ShareDeliverySubmissionParams, ShareTimingPolicy, ShareTrackingParams, ShareTrackingReport,
    SignedVoteBatch, SignedVoteCommitment, SignedVoteCommitments, VanWitness, VoteSigner,
    VoteSubmission, VotingDb, VotingHotkey,
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

/// Inputs for planning all helper shares in one committed vote.
pub struct WalletHelperSharePlanningRequest<'a> {
    pub fleet: &'a HelperFleetPreflight,
    pub now_seconds: u64,
    pub vote_end_time_seconds: u64,
    pub last_moment_buffer_seconds: Option<u64>,
    /// Complete proposal roster from the authenticated round configuration.
    pub proposal_ids: &'a [u32],
}

/// Inputs for submitting the SDK-persisted complete helper-share plan.
pub struct WalletHelperShareSubmissionRequest<'a> {
    pub configured_server_urls: &'a [String],
    pub now_seconds: u64,
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
/// SDK-owned helper-share recovery material. Repeated calls for the same
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
/// Helper shares must be planned with [`prepare_committed_vote_shares`] and sent
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
/// This includes chain fields and stored recovery JSON in one typed object.
/// Helper payloads remain private to the SDK; use
/// [`submit_committed_vote_shares`] for durable delivery.
pub fn committed_vote_signed_commitment(
    voting_db: &VotingDb,
    committed: &CommittedVote,
) -> Result<SignedVoteCommitment> {
    committed
        .signed_commitment(voting_db)
        .context("build signed vote commitment")
}

/// Probes and validates a helper fleet once for reuse across committed votes.
pub async fn preflight_helper_fleet(
    client: &HelperClient,
    configured_server_urls: &[String],
) -> Result<HelperFleetPreflight> {
    client
        .preflight_fleet(configured_server_urls)
        .await
        .context("preflight helper fleet")
}

/// Plans every helper share together and atomically persists the complete plan.
///
/// Calling this again after a restart returns the same generation-bound plan.
/// It may be called before vote confirmation; the SDK synchronizes an exactly
/// matching plan snapshot when confirmation fills the VC tree position. No
/// wallet-owned plan serialization or entropy plumbing is required.
pub fn prepare_committed_vote_shares(
    voting_db: &VotingDb,
    committed: &CommittedVote,
    request: WalletHelperSharePlanningRequest<'_>,
) -> Result<ShareDeliveryPlan> {
    committed
        .prepare_share_delivery(
            voting_db,
            ShareDeliveryPlanningParams {
                fleet: request.fleet,
                now_seconds: request.now_seconds,
                vote_end_time_seconds: request.vote_end_time_seconds,
                last_moment_buffer_seconds: request.last_moment_buffer_seconds,
                proposal_ids: request.proposal_ids,
            },
        )
        .context("prepare helper-share delivery")
}

/// Submits every committed helper share through crate-owned durable journaling.
///
/// `client` is caller-owned so a wallet can enforce its Tor or proxy route.
/// The SDK loads the original plan, validates all payloads before any POST, and
/// enforces its process-wide helper concurrency limit. If planning happened
/// before confirmation, `committed` must be recovered again afterward so its
/// generation exactly matches the confirmation-synchronized plan snapshot.
pub async fn submit_committed_vote_shares(
    voting_db: &VotingDb,
    committed: &CommittedVote,
    client: &HelperClient,
    request: WalletHelperShareSubmissionRequest<'_>,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> Result<ShareBatchDeliveryReport> {
    committed
        .submit_prepared_shares(
            voting_db,
            client,
            ShareDeliverySubmissionParams {
                configured_server_urls: request.configured_server_urls,
                now_seconds: request.now_seconds,
            },
            cancel,
        )
        .await
        .context("submit prepared helper shares")
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
    };
    track_pending_shares(voting_db, &params, client, cancel)
        .await
        .context("track pending helper shares")
}

/// Persists successful vote-chain submission fields.
///
/// Helper-share submission persists each attempt inside
/// `CommittedVote::submit_prepared_shares`; it is intentionally absent here
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
