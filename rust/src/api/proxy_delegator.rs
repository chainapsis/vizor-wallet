//! The delegator's calls of zcash_voting's proxy client API for Dart
//! (contracts-v1 §15.1), reached only behind
//! `VIZOR_PROXY_DELEGATION_ENABLED`.
//!
//! zcash_voting decides everything: these calls open the account's voting
//! sidecar, hand over the bytes Dart fetched and map the answers onto flat
//! bridge types where the wire type is an enum with data, which the bridge
//! does not carry. Every call fails with zcash_voting's
//! [`ProxyDelegationError`].

use std::path::Path;
use std::sync::Arc;

use zcash_voting::config::WalletCapabilities;
use zcash_voting::proxy::{
    self, DelegateBallotList, GovNullifierProof, ProxyAvailabilityInputs, ProxyRoundPhase,
};
use zcash_voting::storage::VotingDb;
use zcash_voting::wire::{
    DelegateBallotView, DelegateCheck, ProxyAllocationPreview, ProxyAllocationRequest,
    ProxyAllocationStatus, ProxyAvailability, ProxyDelegateProvider, ProxyDelegationError,
    ProxyDelegationProgress, ProxyDelegationStage, ProxyDelegationView,
};
use zcash_voting::{ChainAdvancePolicy, RoundHostContext};

use crate::wallet::voting::db;

/// The round's timing as ordinary votes read it and the device clock. A
/// wrong time can at most pick the other share layout or show or hide the
/// option: the chain refuses a batch for a round that is not a proxy round
/// without spending the VAN.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApiProxyRoundTiming {
    /// Unix seconds now.
    pub now_seconds: u64,
    /// The round's ceremony start, if known.
    pub ceremony_start_seconds: Option<u64>,
    /// The round's vote end, if known.
    pub vote_end_time_seconds: Option<u64>,
}

/// What the participation reader proved about the account's governance
/// nullifiers in the round: zcash_voting's `GovNullifierProof`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiGovNullifierProof {
    /// None is spent.
    Unspent,
    /// At least one is proven spent.
    Spent,
    /// No proof could be fetched or verified.
    Unavailable,
}

/// The vote chain's answers availability reads, as the bytes Dart fetched.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyChainAnswers {
    /// The body of `GET /shielded-vote/v1/protocol-capabilities`.
    pub protocol_capabilities: Vec<u8>,
    /// The body of `GET /shielded-vote/v1/round/{round_id}`.
    pub vote_round: Vec<u8>,
    /// The body of `GET /shielded-vote/v1/proxy-delegation-params`, or
    /// `None` when the chain answered 404.
    pub proxy_delegation_params: Option<Vec<u8>>,
}

/// Which availability result applies: the variants of zcash_voting's
/// `ProxyAvailability`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiProxyAvailabilityKind {
    /// None of the other results applies.
    Available,
    /// This build, the chain or the round does not offer proxy delegation.
    Unsupported,
    /// Coordinators paused new delegations.
    Paused,
    /// The wallet's weight in the round may already be spent.
    AlreadyVoted,
    /// The host has no round timing.
    TimingUnavailable,
    /// The round's vote end has passed.
    VoteEnded,
}

/// zcash_voting's `ProxyAvailability`, flattened.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApiProxyAvailability {
    /// The result.
    pub kind: ApiProxyAvailabilityKind,
    /// `AlreadyVoted`: spent from another install. False for every other
    /// kind.
    pub used_elsewhere: bool,
}

/// Whether a delegator may preview and commit a new allocation in
/// `round_id` (`proxy::availability`, contracts-v1 §11.4).
///
/// The wallet capabilities are zcash_voting's defaults, which offer proxy
/// delegation only once its `PROXY_DELEGATION_ENABLED` is set.
pub fn proxy_delegation_availability(
    db_path: String,
    account_uuid: String,
    round_id: String,
    chain: ApiProxyChainAnswers,
    gov_nullifiers: ApiGovNullifierProof,
    timing: ApiProxyRoundTiming,
) -> Result<ApiProxyAvailability, ProxyDelegationError> {
    let db = open(&db_path, &account_uuid)?;
    let capabilities = WalletCapabilities::default();
    let inputs = ProxyAvailabilityInputs {
        wallet_capabilities: &capabilities,
        protocol_capabilities: &chain.protocol_capabilities,
        vote_round: &chain.vote_round,
        proxy_delegation_params: chain.proxy_delegation_params.as_deref(),
        gov_nullifiers: match gov_nullifiers {
            ApiGovNullifierProof::Unspent => GovNullifierProof::Unspent,
            ApiGovNullifierProof::Spent => GovNullifierProof::Spent,
            ApiGovNullifierProof::Unavailable => GovNullifierProof::Unavailable,
        },
    };
    let availability = proxy::availability(&db, &round_id, &inputs, &host(timing))?;
    Ok(api_availability(availability))
}

/// Plans `request` for the account's bundles without recording it
/// (`proxy::preview`).
pub fn preview_proxy_allocation(
    db_path: String,
    account_uuid: String,
    request: ProxyAllocationRequest,
    timing: ApiProxyRoundTiming,
) -> Result<ProxyAllocationPreview, ProxyDelegationError> {
    let db = open(&db_path, &account_uuid)?;
    proxy::preview(&db, &request, &host(timing))
}

/// Records `request` as the round's one allocation (`proxy::commit`).
///
/// `confirmed` is the preview the delegator confirmed: a plan that no
/// longer splits the same fails with `PlanChanged`. `checks` are the
/// confirm-time pre-proving verdicts, one per choice in order, and only
/// `Ok` commits. `roster` is the round's proposal ids: a plan that keeps
/// ballots fails with `KeptShareUnanswered` unless the ballot intents
/// recorded for them answer every one.
pub fn commit_proxy_allocation(
    db_path: String,
    account_uuid: String,
    request: ProxyAllocationRequest,
    confirmed: ProxyAllocationPreview,
    checks: Vec<DelegateCheck>,
    timing: ApiProxyRoundTiming,
    roster: Vec<u32>,
) -> Result<(), ProxyDelegationError> {
    let db = open(&db_path, &account_uuid)?;
    proxy::commit(&db, &request, &confirmed, &checks, &host(timing), &roster)
}

/// Where the round stands on chain: zcash_voting's `ProxyRoundPhase`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiProxyRoundPhase {
    /// `PENDING` or `ACTIVE`.
    Active,
    /// `TALLYING` or `FINALIZED`.
    Closed,
}

/// Which delegate ballot view applies: the variants of zcash_voting's
/// `DelegateBallotView`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegateBallotKind {
    /// The round is active and no ballot landed.
    NoBallotYet,
    /// The round is active and the ballot landed.
    Submitted,
    /// The tally counted the delegate's pool into this ballot.
    Counted,
    /// No ballot landed before the tally, so the pool was not counted.
    NotCounted,
}

/// zcash_voting's `DelegateBallotView`, flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateBallotView {
    /// The view.
    pub kind: ApiDelegateBallotKind,
    /// `Submitted` and `Counted`: one option per proposal, in proposal
    /// order. Empty for the other kinds.
    pub options: Vec<u32>,
}

/// zcash_voting's `ProxyDelegationView` with its ballot flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyDelegationView {
    /// The delegate's registry index.
    pub delegate_index: u32,
    /// The provider of the delegate's account.
    pub provider: ProxyDelegateProvider,
    /// The delegate's handle, without `@`.
    pub handle: String,
    /// The ballots delegated.
    pub ballots: u64,
    /// Where the delegation stands.
    pub stage: ProxyDelegationStage,
    /// The delegate's ballot as published.
    pub ballot: ApiDelegateBallotView,
}

/// zcash_voting's `ProxyAllocationStatus` with its views flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyAllocationStatus {
    /// One view per chosen delegate, in request order.
    pub delegations: Vec<ApiProxyDelegationView>,
    /// The ballots the wallet votes itself.
    pub kept_ballots: u64,
}

/// zcash_voting's `ProxyDelegationProgress` with its views flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyDelegationProgress {
    /// One view per chosen delegate, in request order.
    pub delegations: Vec<ApiProxyDelegationView>,
    /// A landed DC's share 0 was planned with `submit_at = 0`.
    pub planned_immediate: bool,
    /// Every such share 0's reveal is confirmed.
    pub immediate_reveal_confirmed: bool,
    /// The chain refused a sent batch's last attempt. The job keeps sending
    /// it until it lands or voting ends.
    pub refused_by_chain: bool,
}

/// The account's committed allocation in `round_id` as the delegator sees
/// it, or `None` before it commits one (`proxy::status`). `ballot_pages`
/// must be the round's complete delegate ballot list, page by page.
pub fn proxy_allocation_status(
    db_path: String,
    account_uuid: String,
    round_id: String,
    ballot_pages: Vec<Vec<u8>>,
    phase: ApiProxyRoundPhase,
) -> Result<Option<ApiProxyAllocationStatus>, ProxyDelegationError> {
    let ballots = ballot_list(&round_id, &ballot_pages)?;
    let db = open(&db_path, &account_uuid)?;
    Ok(
        proxy::status(&db, &round_id, &ballots, round_phase(phase))?.map(
            |status: ProxyAllocationStatus| ApiProxyAllocationStatus {
                delegations: status
                    .delegations
                    .into_iter()
                    .map(delegation_view)
                    .collect(),
                kept_ballots: status.kept_ballots,
            },
        ),
    )
}

/// The delegation job's view of the account's committed allocation in
/// `round_id`, or `None` before it commits one (`proxy::progress`). Takes
/// what [`proxy_allocation_status`] takes.
pub fn proxy_delegation_progress(
    db_path: String,
    account_uuid: String,
    round_id: String,
    ballot_pages: Vec<Vec<u8>>,
    phase: ApiProxyRoundPhase,
) -> Result<Option<ApiProxyDelegationProgress>, ProxyDelegationError> {
    let ballots = ballot_list(&round_id, &ballot_pages)?;
    let db = open(&db_path, &account_uuid)?;
    Ok(
        proxy::progress(&db, &round_id, &ballots, round_phase(phase))?.map(
            |progress: ProxyDelegationProgress| ApiProxyDelegationProgress {
                delegations: progress
                    .delegations
                    .into_iter()
                    .map(delegation_view)
                    .collect(),
                planned_immediate: progress.planned_immediate,
                immediate_reveal_confirmed: progress.immediate_reveal_confirmed,
                refused_by_chain: progress.refused_by_chain,
            },
        ),
    )
}

/// One round whose committed proxy allocation still owes work.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiPendingProxyRound {
    /// The account whose sidecar scope holds the allocation.
    pub account_uuid: String,
    /// The round id, lowercase hex.
    pub round_id: String,
}

/// The rounds of `account_uuids` whose committed proxy allocation still
/// owes work, for the background restorer. That is a delegation not handed
/// off, or a share 0 planned at once whose reveal is not confirmed
/// (`proxy::progress` read as the delegation job reads it while a round
/// runs), or answers recorded for the kept share whose casts are not all
/// confirmed, including once every delegation is handed off. Whether each
/// round is still open is the caller's question.
///
/// It only reads. A wallet without a voting sidecar has no such round, and
/// none is created.
pub fn list_pending_proxy_rounds(
    db_path: String,
    account_uuids: Vec<String>,
) -> Result<Vec<ApiPendingProxyRound>, ProxyDelegationError> {
    if !VotingDb::wallet_sidecar_path(Path::new(&db_path)).exists() {
        return Ok(Vec::new());
    }
    let mut pending = Vec::new();
    for account_uuid in account_uuids.iter().filter(|uuid| !uuid.is_empty()) {
        let db = open(&db_path, account_uuid)?;
        for round in db.list_rounds()? {
            // Ballots change no stage, so an empty list serves.
            let mut ballots = DelegateBallotList::new(&round.round_id)?;
            ballots.add_page(b"{}")?;
            let Some(progress) =
                proxy::progress(&db, &round.round_id, &ballots, ProxyRoundPhase::Active)?
            else {
                continue;
            };
            if progress.owes_work() || owes_kept_casts(&db, &round.round_id)? {
                pending.push(ApiPendingProxyRound {
                    account_uuid: account_uuid.clone(),
                    round_id: round.round_id,
                });
            }
        }
    }
    Ok(pending)
}

/// Whether `round_id` has recorded answers whose casts are not all
/// confirmed: the round plan over the recorded proposals has a vote to
/// cast, which is the Dart restorer's `roundPlanOwesBallotCasts`.
fn owes_kept_casts(db: &VotingDb, round_id: &str) -> Result<bool, ProxyDelegationError> {
    let proposal_ids: Vec<u32> = db
        .ballot_intents(round_id)?
        .into_iter()
        .map(|(proposal_id, _)| proposal_id)
        .collect();
    if proposal_ids.is_empty() {
        return Ok(false);
    }
    let plan = zcash_voting::session::resume_plan(db, round_id, &proposal_ids)?;
    Ok(!plan.nothing_left_to_vote && plan.open_proposals.is_empty() && !plan.all_decided)
}

/// The account's scoped voting sidecar.
fn open(db_path: &str, account_uuid: &str) -> Result<Arc<VotingDb>, ProxyDelegationError> {
    Ok(db::open_voting_db(db_path, account_uuid)?)
}

/// The round context the delegator calls read: only the timing, since none
/// of them runs a step.
fn host(timing: ApiProxyRoundTiming) -> RoundHostContext {
    RoundHostContext {
        configured_helper_urls: Vec::new(),
        now_seconds: timing.now_seconds,
        ceremony_start_seconds: timing.ceremony_start_seconds,
        vote_end_time_seconds: timing.vote_end_time_seconds,
        vote_tree_node_urls: Vec::new(),
        delegation: None,
        chain_policy: ChainAdvancePolicy::default(),
        max_proof_concurrency: 1,
    }
}

/// The round's ballot list from `pages`, fetched in order.
fn ballot_list(
    round_id: &str,
    pages: &[Vec<u8>],
) -> Result<DelegateBallotList, ProxyDelegationError> {
    let mut list = DelegateBallotList::new(round_id)?;
    for page in pages {
        list.add_page(page)?;
    }
    Ok(list)
}

/// zcash_voting's phase for `phase`.
fn round_phase(phase: ApiProxyRoundPhase) -> ProxyRoundPhase {
    match phase {
        ApiProxyRoundPhase::Active => ProxyRoundPhase::Active,
        ApiProxyRoundPhase::Closed => ProxyRoundPhase::Closed,
    }
}

/// The bridge form of an availability result.
fn api_availability(availability: ProxyAvailability) -> ApiProxyAvailability {
    let kind = |kind| ApiProxyAvailability {
        kind,
        used_elsewhere: false,
    };
    match availability {
        ProxyAvailability::Available => kind(ApiProxyAvailabilityKind::Available),
        ProxyAvailability::Unsupported => kind(ApiProxyAvailabilityKind::Unsupported),
        ProxyAvailability::Paused => kind(ApiProxyAvailabilityKind::Paused),
        ProxyAvailability::AlreadyVoted { used_elsewhere } => ApiProxyAvailability {
            kind: ApiProxyAvailabilityKind::AlreadyVoted,
            used_elsewhere,
        },
        ProxyAvailability::TimingUnavailable => kind(ApiProxyAvailabilityKind::TimingUnavailable),
        ProxyAvailability::VoteEnded => kind(ApiProxyAvailabilityKind::VoteEnded),
    }
}

/// The bridge form of a delegation view.
fn delegation_view(view: ProxyDelegationView) -> ApiProxyDelegationView {
    let (kind, options) = match view.ballot {
        DelegateBallotView::NoBallotYet => (ApiDelegateBallotKind::NoBallotYet, Vec::new()),
        DelegateBallotView::Submitted { options } => (ApiDelegateBallotKind::Submitted, options),
        DelegateBallotView::Counted { options } => (ApiDelegateBallotKind::Counted, options),
        DelegateBallotView::NotCounted => (ApiDelegateBallotKind::NotCounted, Vec::new()),
    };
    ApiProxyDelegationView {
        delegate_index: view.delegate_index,
        provider: view.provider,
        handle: view.handle,
        ballots: view.ballots,
        stage: view.stage,
        ballot: ApiDelegateBallotView { kind, options },
    }
}

#[cfg(test)]
mod tests;
