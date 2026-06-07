use anyhow::{Context, Result};
use zcash_voting::prelude::{
    commit_batch, sync_vote_tree, van_witness, CommittedVote, DraftVote, NoopProgressReporter,
    SharePayload, SignedVoteCommitment, SignedVoteCommitments, VanWitness, VoteSigner,
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

/// Inputs for committing one bundle's cast-votes in one call.
pub struct WalletVoteCommitBatchRequest<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub drafts: &'a [DraftVote],
    pub van_witness: &'a VanWitness,
    pub voting_hotkey: &'a VotingHotkey,
}

/// One helper-share delivery result produced outside the wallet library.
pub struct WalletShareDelivery<'a> {
    pub share_index: u32,
    pub sent_to_urls: &'a [String],
    pub submit_at: u64,
    pub confirmed: bool,
}

/// Network-side results to persist after the caller submits a committed vote.
pub struct WalletVoteExecutionRequest<'a> {
    pub vote_tx_hash: &'a str,
    pub vc_tree_position: u64,
    pub share_deliveries: &'a [WalletShareDelivery<'a>],
}

/// Chain and helper-server payloads derived from a committed vote.
pub struct WalletVoteExecutionPayload<'a> {
    pub submission: VoteSubmission,
    pub share_payloads: &'a [SharePayload],
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
/// bundle is unknown, its VAN position is missing, or the witness cannot be
/// generated at the synced height.
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

/// Builds, signs, and persists recovery state for a bundle's cast-vote batch.
///
/// This is the high-level helper that mirrors wallet API boundaries where one
/// bundle can include multiple proposal drafts in one proof/signing workflow.
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
    .context("commit cast-vote batch")
}

/// Returns the payloads the caller should submit to external services.
///
/// Submit `submission` to the vote chain and each `share_payloads` item to the
/// selected helper server(s). Network requests remain caller-owned; the wallet
/// library only reconstructs the persisted payload fields.
pub fn committed_vote_payloads<'a>(
    voting_db: &VotingDb,
    committed: &'a CommittedVote,
) -> Result<WalletVoteExecutionPayload<'a>> {
    Ok(WalletVoteExecutionPayload {
        submission: committed
            .submission(voting_db)
            .context("build vote submission")?,
        share_payloads: committed.share_payloads(),
    })
}

/// Returns a single wallet-facing aggregate for external API boundaries.
///
/// This includes chain submission fields, helper-share payloads, and the stored
/// recovery JSON in one typed object.
pub fn committed_vote_signed_commitment(
    voting_db: &VotingDb,
    committed: &CommittedVote,
) -> Result<SignedVoteCommitment> {
    committed
        .signed_commitment(voting_db)
        .context("build signed vote commitment")
}

/// Persists successful vote-chain and helper-share submissions.
///
/// Call this after the vote transaction has been accepted and the caller has
/// submitted helper shares. Confirmed helper responses are marked immediately;
/// unconfirmed records remain available for retry and polling.
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

    for delivery in request.share_deliveries {
        committed
            .record_share(
                voting_db,
                delivery.share_index,
                delivery.sent_to_urls,
                delivery.submit_at,
            )
            .context("record helper-share submission")?;
        if delivery.confirmed {
            committed
                .confirm_share(voting_db, delivery.share_index)
                .context("confirm helper-share submission")?;
        }
    }

    Ok(())
}
