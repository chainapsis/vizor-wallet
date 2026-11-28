//! Delegate mode's calls of zcash_voting's delegate APIs for Dart
//! (contracts-v1 §11.12 and §15.1), reached only behind
//! `VIZOR_PROXY_DELEGATION_ENABLED`.
//!
//! zcash_voting builds every body, reads every answer and keeps the device's
//! delegate records; these calls open the sidecar's one app-level
//! delegate-mode scope, [`DELEGATE_MODE_WALLET_ID`], and map the answers
//! onto bridge types, flat where the wire type is an enum with data. Dart
//! fetches and posts the bytes, runs the participation reader's proofs and
//! keeps the device's one delegate key in secure storage as its `zvdsk1…`
//! export (contracts-v1 §11.2).
//!
//! Each signing call takes that export for just the call. It is zeroed when
//! the call returns, best effort, and no call stores, logs or puts one in
//! an error. Only [`create_delegate_key`] returns one.

use std::sync::Arc;

use rand::rngs::OsRng;
use zcash_vote_delegate::{DelegateKey, DelegateSigningKey, IdentityProvider};
use zcash_voting::proxy::delegate::{
    self, AttestationExpectation, BallotAnswer, BallotError, ChainDelegateBallot, CompleteBallot,
    DelegateChain, DelegateEntryError, DelegateModeError, DelegateOpAnswer, DelegateOpAnswerError,
    DelegateOpKind, DelegateRoundTiming, ProvenDelegateEntry, RegisterAnswer, RetireAnswer,
    SignedDelegateOp,
};
use zcash_voting::proxy::registry::ProvenValue;
use zcash_voting::storage::VotingDb;
use zcash_voting::wire::{
    BallotPreflight, BallotSubmitResult, DelegateAttestation, DelegateBallotBlock,
    DelegateBallotView, DelegateKeyInfo, DelegateModeStatus, DelegateRetireResult,
    DelegateVerifierError, DelegateVerifierRefusal, ProxyDelegateProvider,
};
use zcash_voting::ProposalRosterEntry;
use zeroize::Zeroizing;

use super::proxy_delegation::ApiProvenRegistryEntry;
use super::proxy_delegator::{ApiDelegateBallotKind, ApiDelegateBallotView};
use super::voting_session::ApiProposalRosterEntry;
use crate::wallet::keys::parse_network;
use crate::wallet::voting::{db, network::voting_network, participation};

/// The voting sidecar's wallet scope for delegate mode. Delegate mode is
/// app-level, not an account's, and an account scope is a UUID, so this id
/// never meets one.
pub const DELEGATE_MODE_WALLET_ID: &str = "vizor-delegate-mode";

/// Where delegate mode keeps its records: the voting sidecar beside the
/// wallet database, on the wallet's network.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateModeScope {
    /// The main wallet database path; the sidecar lives beside it.
    pub db_path: String,
    /// The wallet network: `main`, `test` or `regtest`.
    pub network: String,
}

/// Which delegate-mode failure happened, as far as Dart tells them apart.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegateModeErrorKind {
    /// Proven registry bytes are not a usable entry of the device's key,
    /// or the entry is proven absent; the host proves it again later.
    EntryUnverifiable,
    /// A chain answer Dart fetched is not in the contract's shape.
    ChainAnswer,
    /// Anything else: malformed input, an attestation that does not bind
    /// what the delegate posted, a ballot that cannot be signed, or the
    /// device's records.
    Other,
}

/// A failed delegate-mode call. `message` is zcash_voting's description,
/// which names public keys at most, never a secret.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateModeError {
    /// What failed.
    pub kind: ApiDelegateModeErrorKind,
    /// zcash_voting's description, for logs.
    pub message: String,
}

/// A delegate key just created: its public half and the secret to store.
#[derive(Clone, PartialEq, Eq)]
pub struct ApiNewDelegateKey {
    /// The public key.
    pub key: DelegateKeyInfo,
    /// The key's `zvdsk1…` export, which Dart puts in secure storage.
    pub secret: String,
}

/// The device's delegate key, as its records show it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDeviceDelegateKey {
    /// The key.
    pub key: DelegateKeyInfo,
    /// The key's entry, once a proven entry showed it.
    pub delegate_index: Option<u32>,
}

/// A round's ballot deadline, from the round as ordinary votes read it
/// (zcash_voting `DelegateRoundTiming`). A wrong `vote_end_time` only makes
/// the chain refuse the ballot.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateRoundTiming {
    /// The round id, lowercase hex.
    pub round_id: String,
    /// The round's vote end, in unix seconds.
    pub vote_end_time: u64,
}

/// A request for the verifier API: Dart posts `body` as JSON to a
/// `verifier_api_urls` entry followed by `path`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiVerifierRequest {
    /// The route under the verifier's base URL.
    pub path: String,
    /// The JSON body.
    pub body: Vec<u8>,
}

/// Which delegate op a signed op carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegateOpKind {
    /// Registers the device's key in a new entry.
    Register,
    /// Retires the entry.
    Retire,
    /// One round's ballot.
    Ballot,
}

/// A signed delegate op, for Dart to post to the vote chain's
/// `delegate_op_path` byte for byte. Resending the same body is always safe.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiSignedDelegateOp {
    /// Which op it is.
    pub kind: ApiDelegateOpKind,
    /// The entry it names; 0 for a register op that creates one.
    pub delegate_index: u32,
    /// The key that signed it, `zvdk1…`.
    pub dk: String,
    /// The JSON body to post.
    pub body: Vec<u8>,
}

/// What the node's answer to a posted op means.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegateOpAnswerKind {
    /// CheckTx accepted it (code 0).
    Accepted,
    /// The chain already holds what the op asks for: code 61 for a register
    /// op, 55 for a retire, 57 for a ballot. A register or ballot still
    /// settles from what the chain holds (contracts-v1 §11.12).
    AlreadyApplied,
    /// Any other rejection; key on (`codespace`, `code`).
    Rejected,
    /// The node refused the body before CheckTx (HTTP 400); resending it
    /// cannot help.
    RequestRefused,
    /// No verdict: the op may or may not have reached a mempool, and the
    /// host resends the same body later.
    NoVerdict,
}

/// The node's answer to a posted op, flattened; each field is set only for
/// the kinds its doc names.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateOpAnswer {
    /// What the answer means.
    pub kind: ApiDelegateOpAnswerKind,
    /// `Accepted`: the transaction hash, uppercase hex.
    pub tx_hash: Option<String>,
    /// `Rejected` and `AlreadyApplied`: the ABCI codespace.
    pub codespace: Option<String>,
    /// `Rejected` and `AlreadyApplied`: the error code.
    pub code: Option<u32>,
    /// The node's bounded log line or error; diagnostic only.
    pub detail: Option<String>,
}

/// One delegate ballot as the chain's whole-round list shows it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiChainDelegateBallot {
    /// The delegate.
    pub delegate_index: u32,
    /// One option per proposal, in proposal order.
    pub options: Vec<u32>,
    /// The height it landed at.
    pub height: u64,
}

/// What one ballot list page says.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateBallotSearch {
    /// The `start_after` to fetch the next page with, or `None` on the last
    /// page.
    pub next_start_after: Option<u32>,
    /// The asked delegate's ballot, if the page lists it.
    pub ballot: Option<ApiChainDelegateBallot>,
}

/// zcash_voting's `DelegateRound` with its enums flattened. Dart adds the
/// round's title and questions.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateRound {
    /// The round id, lowercase hex.
    pub round_id: String,
    /// The round's vote end.
    pub vote_end_time: u64,
    /// R, the pool shares revealed to the delegate.
    pub revealed_shares: u64,
    /// The delegate's ballot as published.
    pub ballot: ApiDelegateBallotView,
    /// A ballot this device signed that is not on chain yet.
    pub stored_ballot: Option<Vec<u32>>,
    /// Why this device cannot sign the round's ballot, if it cannot.
    pub ballot_block: Option<DelegateBallotBlock>,
}

/// zcash_voting's `BallotPreflight`, flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiBallotPreflight {
    /// A ballot is on chain, or this device signed one.
    pub already_submitted: bool,
    /// `already_submitted`: the stored ballot.
    pub options: Vec<u32>,
    /// `already_submitted`: whether it equals the ballot being submitted.
    /// (Not named `identical`, which would shadow Dart's `identical`.)
    pub same_options: bool,
}

/// The ballot this device signed for a round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiStoredDelegateBallot {
    /// One option per proposal, in proposal order.
    pub options: Vec<u32>,
    /// The op every post of it carries, rebuilt without a new signature.
    pub op: ApiSignedDelegateOp,
}

/// Which submit outcome applies: the variants of zcash_voting's
/// `BallotSubmitResult`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiBallotSubmitKind {
    /// The node accepted the ballot.
    Accepted,
    /// The chain already stores this exact ballot.
    AlreadyAccepted,
    /// The chain refused the ballot.
    Rejected,
}

/// zcash_voting's `BallotSubmitResult`, flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiBallotSubmitResult {
    /// The outcome.
    pub kind: ApiBallotSubmitKind,
    /// `Rejected`: the ABCI codespace.
    pub codespace: Option<String>,
    /// `Rejected`: the error code.
    pub code: Option<u32>,
    /// `Rejected`: why; diagnostic only.
    pub reason: Option<String>,
}

/// Creates a delegate key from the OS RNG (`create_delegate_key`). Nothing
/// is stored, so an abandoned setup leaves no key behind.
pub fn create_delegate_key() -> ApiNewDelegateKey {
    let signing_key = delegate::create_delegate_key(&mut OsRng);
    ApiNewDelegateKey {
        key: delegate::delegate_key_info(&signing_key.delegate_key()),
        secret: signing_key.export().as_str().to_owned(),
    }
}

/// The public key of `secret`, a typed, pasted or scanned `zvdsk1…` export
/// (`DelegateSigningKey::import`), or `None` when it is not one.
pub fn import_delegate_key(secret: String) -> Option<DelegateKeyInfo> {
    let secret = Zeroizing::new(secret);
    let signing_key = DelegateSigningKey::import(secret.trim()).ok()?;
    Some(delegate::delegate_key_info(&signing_key.delegate_key()))
}

/// Records `dk` as the device's delegate key from `now_seconds`, once its
/// secret is in secure storage (`record_delegate_key`). Fails with
/// [`ApiDelegateModeErrorKind::Other`] while the device holds another key.
pub fn record_delegate_key(
    scope: ApiDelegateModeScope,
    dk: String,
    now_seconds: u64,
) -> Result<(), ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    delegate::record_delegate_key(&db, &chain, &decode_key(&dk)?, now_seconds)
        .map_err(mode_error)?;
    Ok(())
}

/// The delegate key the device holds, if any (`device_delegate_key`).
pub fn device_delegate_key(
    scope: ApiDelegateModeScope,
) -> Result<Option<ApiDeviceDelegateKey>, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    Ok(delegate::device_delegate_key(&db, &chain)
        .map_err(mode_error)?
        .map(|held| ApiDeviceDelegateKey {
            key: delegate::delegate_key_info(&held.dk),
            delegate_index: held.delegate_index,
        }))
}

/// Forgets the device's key with any pending register op in one write, so
/// another can be created or imported (`forget_delegate_key`). Dart deletes
/// the secret after.
pub fn forget_delegate_key(scope: ApiDelegateModeScope) -> Result<(), ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    delegate::forget_delegate_key(&db, &chain).map_err(mode_error)
}

/// The vote chain path of the lookup by key for `dk`, under a vote
/// server's base URL (`delegate_by_key_path`).
pub fn delegate_by_key_path(dk: String) -> Result<String, ApiDelegateModeError> {
    Ok(delegate::delegate_by_key_path(&decode_key(&dk)?))
}

/// Reads the lookup by key for `dk`: the entry's index, or `None` when the
/// chain says the key was never registered (`parse_delegate_by_key_response`).
/// Any other answer fails with [`ApiDelegateModeErrorKind::ChainAnswer`].
pub fn parse_delegate_by_key_answer(
    dk: String,
    status: u16,
    body: Vec<u8>,
) -> Result<Option<u32>, ApiDelegateModeError> {
    delegate::parse_delegate_by_key_response(&decode_key(&dk)?, status, &body)
        .map_err(|error| mode_error(error.into()))
}

/// The device's delegate key and its entry (`delegate_mode_status`), or
/// `None` when the device holds no key.
///
/// `entry` is the participation reader's proof of the entry the lookup by
/// key named. It is recorded as the key's entry first (`record_proven_entry`),
/// which settles a pending registration. An entry proven absent counts as
/// none: the proof trails the lookup by a block.
pub fn delegate_mode_status(
    scope: ApiDelegateModeScope,
    entry: Option<ApiProvenRegistryEntry>,
) -> Result<Option<DelegateModeStatus>, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    let entry = entry
        .filter(|entry| entry.entry.is_some())
        .as_ref()
        .map(proven_entry)
        .transpose()?;
    if let Some(entry) = &entry {
        delegate::record_proven_entry(&db, &chain, entry).map_err(mode_error)?;
    }
    delegate::delegate_mode_status(&db, &chain, entry.as_ref()).map_err(mode_error)
}

/// The marker `dk` is posted with (`delegate_marker_text`).
pub fn delegate_marker_text(dk: String) -> Result<String, ApiDelegateModeError> {
    Ok(delegate::delegate_marker_text(&decode_key(&dk)?))
}

/// The verifier request asking it to attest `dk` from the post at
/// `proof_url` on `provider` (`attest_request`).
pub fn delegate_attest_request(
    provider: ProxyDelegateProvider,
    proof_url: String,
    dk: String,
) -> Result<ApiVerifierRequest, ApiDelegateModeError> {
    let request =
        delegate::attest_request(identity_provider(provider), &proof_url, &decode_key(&dk)?);
    Ok(ApiVerifierRequest {
        path: delegate::VERIFIER_ATTEST_PATH.to_owned(),
        body: request,
    })
}

/// Reads the verifier's answer to an attest request for `dk`
/// (`parse_attest_response`): the attestation, or the refusal it carries.
pub fn parse_delegate_attest_answer(
    dk: String,
    status: u16,
    body: Vec<u8>,
) -> Result<DelegateAttestation, DelegateVerifierRefusal> {
    let dk = DelegateKey::decode(&dk).map_err(|error| DelegateVerifierRefusal {
        error: DelegateVerifierError::Unknown,
        retry_after: None,
        detail: Some(format!("the attested key is not a delegate key: {error:?}")),
    })?;
    delegate::parse_attest_response(&dk, status, &body)
}

/// Builds the register op for `attestation`, signed with `secret`, the
/// device's key, and stores it as the pending op before Dart posts it
/// (`prepare_register_op`).
///
/// The attestation must bind what the delegate posted: `provider` is the
/// one the marker was posted on. `proxy_params` is the body of a 200 answer
/// to the chain's params, whose verifier set then checks every signature.
pub fn prepare_delegate_register_op(
    scope: ApiDelegateModeScope,
    attestation: DelegateAttestation,
    provider: ProxyDelegateProvider,
    proxy_params: Option<Vec<u8>>,
    secret: String,
    now_seconds: u64,
) -> Result<ApiSignedDelegateOp, ApiDelegateModeError> {
    let signing_key = signing_key(secret)?;
    let (db, chain) = open(&scope)?;
    let verifiers = proxy_params
        .map(|body| delegate::parse_proxy_params_response(200, &body))
        .transpose()
        .map_err(|error| mode_error(error.into()))?;
    let expected = AttestationExpectation {
        provider: identity_provider(provider),
        verifiers: verifiers.as_ref(),
    };
    delegate::prepare_register_op(
        &db,
        &chain,
        &attestation,
        &expected,
        &signing_key,
        now_seconds,
    )
    .map(signed_op)
    .map_err(mode_error)
}

/// The register op the device stored, byte for byte, until a proven entry
/// settles the registration (`pending_register_op`).
pub fn pending_delegate_register_op(
    scope: ApiDelegateModeScope,
) -> Result<Option<ApiSignedDelegateOp>, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    Ok(delegate::pending_register_op(&db, &chain)
        .map_err(mode_error)?
        .map(signed_op))
}

/// The vote chain path signed delegate ops are posted to, under a vote
/// server's base URL (`DELEGATE_OP_PATH`).
pub fn delegate_op_path() -> String {
    delegate::DELEGATE_OP_PATH.to_owned()
}

/// Reads the node's answer to a posted `op` (`parse_delegate_op_answer`),
/// classified as zcash_voting classifies that op's answers.
pub fn parse_delegate_op_answer(
    op: ApiDelegateOpKind,
    status: u16,
    body: Vec<u8>,
) -> ApiDelegateOpAnswer {
    let answer = match delegate::parse_delegate_op_answer(status, &body) {
        Ok(answer) => answer,
        Err(DelegateOpAnswerError::RequestRefused { message, .. }) => {
            return op_answer(
                ApiDelegateOpAnswerKind::RequestRefused,
                None,
                None,
                None,
                Some(message),
            )
        }
        Err(DelegateOpAnswerError::NoVerdict { detail, .. }) => {
            return op_answer(
                ApiDelegateOpAnswerKind::NoVerdict,
                None,
                None,
                None,
                Some(detail),
            )
        }
    };
    let (tx_hash, codespace, code, log) = match &answer {
        DelegateOpAnswer::Accepted { tx_hash } => (Some(tx_hash.clone()), None, None, None),
        DelegateOpAnswer::Rejected {
            codespace,
            code,
            log,
        } => (
            None,
            Some(codespace.clone()),
            Some(*code),
            Some(log.clone()),
        ),
    };
    let already_applied = match op {
        ApiDelegateOpKind::Register => {
            delegate::classify_register_answer(&answer) == RegisterAnswer::AlreadyRegistered
        }
        ApiDelegateOpKind::Retire => {
            delegate::classify_retire_answer(&answer)
                == RetireAnswer::Settled(DelegateRetireResult::Retired)
        }
        ApiDelegateOpKind::Ballot => {
            delegate::classify_ballot_answer(&answer) == BallotAnswer::BallotExists
        }
    };
    let kind = match (&answer, already_applied) {
        (DelegateOpAnswer::Accepted { .. }, _) => ApiDelegateOpAnswerKind::Accepted,
        (DelegateOpAnswer::Rejected { .. }, true) => ApiDelegateOpAnswerKind::AlreadyApplied,
        (DelegateOpAnswer::Rejected { .. }, false) => ApiDelegateOpAnswerKind::Rejected,
    };
    op_answer(kind, tx_hash, codespace, code, log)
}

/// The vote chain path of round `round_id`'s ballot list page after
/// `start_after` (`delegate_ballots_path`).
pub fn delegate_ballots_page_path(
    round_id: String,
    start_after: u32,
) -> Result<String, ApiDelegateModeError> {
    Ok(delegate::delegate_ballots_path(
        &round_bytes(&round_id)?,
        start_after,
    ))
}

/// Checks the page of round `round_id`'s ballot list fetched with
/// `start_after` (`parse_delegate_ballots_page`): where the next page
/// starts, and `delegate_index`'s ballot if this page lists it. The one
/// paging call for both the delegator and delegate mode.
pub fn delegate_ballot_page(
    round_id: String,
    start_after: u32,
    page: Vec<u8>,
    delegate_index: Option<u32>,
) -> Result<ApiDelegateBallotSearch, ApiDelegateModeError> {
    let page =
        delegate::parse_delegate_ballots_page(&round_bytes(&round_id)?, start_after, 200, &page)
            .map_err(|error| mode_error(error.into()))?;
    Ok(ApiDelegateBallotSearch {
        next_start_after: page.next_start_after,
        ballot: delegate_index
            .and_then(|index| page.ballot_of(index))
            .map(chain_ballot_view),
    })
}

/// The `vote` store key, lowercase hex, of `delegate_index`'s pool share
/// count in round `round_id` (`pool_share_count_store_key`), which Dart
/// reads with a raw store query.
pub fn delegate_pool_share_count_key(
    round_id: String,
    delegate_index: u32,
) -> Result<String, ApiDelegateModeError> {
    Ok(hex::encode(delegate::pool_share_count_store_key(
        &round_bytes(&round_id)?,
        delegate_index,
    )))
}

/// One round as the delegate sees it (`delegate_round`). `entry` is the
/// delegate's proven entry, `chain_ballot` its ballot from the round's
/// whole list and `pool_share_count` the raw store value, `None` when
/// absent.
pub fn delegate_round_view(
    scope: ApiDelegateModeScope,
    round: ApiDelegateRoundTiming,
    entry: Option<ApiProvenRegistryEntry>,
    chain_ballot: Option<ApiChainDelegateBallot>,
    pool_share_count: Option<Vec<u8>>,
    now_seconds: u64,
) -> Result<ApiDelegateRound, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    let timing = round_timing(&round)?;
    let entry = entry.as_ref().map(proven_entry).transpose()?;
    let chain_ballot = chain_ballot.map(chain_ballot_record);
    let view = delegate::delegate_round(
        &db,
        &chain,
        &timing,
        entry.as_ref(),
        chain_ballot.as_ref(),
        pool_share_count.as_deref(),
        now_seconds,
    )
    .map_err(mode_error)?;
    Ok(ApiDelegateRound {
        round_id: view.round_id,
        vote_end_time: view.vote_end_time,
        revealed_shares: view.revealed_shares,
        ballot: ballot_view(view.ballot),
        stored_ballot: view.stored_ballot,
        ballot_block: view.ballot_block,
    })
}

/// Whether a ballot is already stored for entry `delegate_index` in round
/// `round_id`, compared with `options` (`ballot_preflight`). `chain_ballot`
/// is the delegate's ballot from the round's whole list.
pub fn delegate_ballot_preflight(
    scope: ApiDelegateModeScope,
    round_id: String,
    delegate_index: u32,
    chain_ballot: Option<ApiChainDelegateBallot>,
    options: Vec<u32>,
) -> Result<ApiBallotPreflight, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    let chain_ballot = chain_ballot.map(chain_ballot_record);
    let preflight = delegate::ballot_preflight(
        &db,
        &chain,
        &round_bytes(&round_id)?,
        delegate_index,
        chain_ballot.as_ref(),
        &options,
    )
    .map_err(mode_error)?;
    Ok(match preflight {
        BallotPreflight::NoBallot => ApiBallotPreflight {
            already_submitted: false,
            options: Vec::new(),
            same_options: false,
        },
        BallotPreflight::AlreadySubmitted { options, identical } => ApiBallotPreflight {
            already_submitted: true,
            options,
            same_options: identical,
        },
    })
}

/// Signs `options` as `entry`'s one ballot for `round`, with `secret`, the
/// entry's key, and stores the op before Dart posts it
/// (`CompleteBallot::new`, then `sign_ballot`). `proposals` is the
/// round's authenticated roster. An identical ballot already stored comes
/// back without a new signature; a different one is refused.
pub fn sign_delegate_ballot(
    scope: ApiDelegateModeScope,
    round: ApiDelegateRoundTiming,
    entry: ApiProvenRegistryEntry,
    proposals: Vec<ApiProposalRosterEntry>,
    options: Vec<u32>,
    secret: String,
    now_seconds: u64,
) -> Result<ApiSignedDelegateOp, ApiDelegateModeError> {
    let signing_key = signing_key(secret)?;
    let (db, chain) = open(&scope)?;
    let timing = round_timing(&round)?;
    let entry = proven_entry(&entry)?;
    let roster: Vec<ProposalRosterEntry> = proposals
        .iter()
        .map(|proposal| ProposalRosterEntry {
            proposal_id: proposal.proposal_id,
            num_options: proposal.num_options,
        })
        .collect();
    let ballot = CompleteBallot::new(timing.round_id, &roster, options).map_err(ballot_error)?;
    let stored = delegate::sign_ballot(
        &db,
        &chain,
        &timing,
        &entry,
        &ballot,
        &signing_key,
        now_seconds,
    )
    .map_err(ballot_error)?;
    Ok(signed_op(stored.op()))
}

/// The ballot this device signed for entry `delegate_index` in round
/// `round_id`, if any (`stored_ballot`). A retry posts its op unchanged,
/// with no secret.
pub fn stored_delegate_ballot(
    scope: ApiDelegateModeScope,
    round_id: String,
    delegate_index: u32,
) -> Result<Option<ApiStoredDelegateBallot>, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    Ok(
        delegate::stored_ballot(&db, &chain, &round_bytes(&round_id)?, delegate_index)
            .map_err(mode_error)?
            .map(|stored| ApiStoredDelegateBallot {
                options: stored.options().to_vec(),
                op: signed_op(stored.op()),
            }),
    )
}

/// Settles a code 57 answer to the stored ballot of entry `delegate_index`
/// in round `round_id` from the delegate's ballot in the round's whole list
/// (`existing_ballot_result`): `None` while the list does not show it yet,
/// or when no ballot is stored.
pub fn existing_delegate_ballot_result(
    scope: ApiDelegateModeScope,
    round_id: String,
    delegate_index: u32,
    chain_ballot: Option<ApiChainDelegateBallot>,
) -> Result<Option<ApiBallotSubmitResult>, ApiDelegateModeError> {
    let (db, chain) = open(&scope)?;
    let Some(stored) =
        delegate::stored_ballot(&db, &chain, &round_bytes(&round_id)?, delegate_index)
            .map_err(mode_error)?
    else {
        return Ok(None);
    };
    let chain_ballot = chain_ballot.map(chain_ballot_record);
    Ok(delegate::existing_ballot_result(&stored, chain_ballot.as_ref()).map(submit_result))
}

/// Retire's op for `entry`, signed with `secret`, the entry's key
/// (`build_retire_op`). It counts once the node answers code 55 or the
/// entry, proven again, is retired (contracts-v1 §11.12).
pub fn build_delegate_retire_op(
    scope: ApiDelegateModeScope,
    entry: ApiProvenRegistryEntry,
    secret: String,
) -> Result<ApiSignedDelegateOp, ApiDelegateModeError> {
    let signing_key = signing_key(secret)?;
    let chain = delegate_chain(&scope)?;
    delegate::build_retire_op(&chain, &proven_entry(&entry)?, &signing_key)
        .map(signed_op)
        .map_err(mode_error)
}

/// The signing key of a `zvdsk1…` export. The export is zeroed on every
/// path, and an error never names it.
fn signing_key(secret: String) -> Result<DelegateSigningKey, ApiDelegateModeError> {
    let secret = Zeroizing::new(secret);
    DelegateSigningKey::import(&secret)
        .map_err(|_| invalid_input("the delegate key's secret is not a zvdsk1 export"))
}

/// The sidecar's delegate-mode scope and the chain it acts on.
fn open(
    scope: &ApiDelegateModeScope,
) -> Result<(Arc<VotingDb>, DelegateChain), ApiDelegateModeError> {
    let chain = delegate_chain(scope)?;
    let db = db::open_voting_db(&scope.db_path, DELEGATE_MODE_WALLET_ID)
        .map_err(|error| mode_error(error.into()))?;
    Ok((db, chain))
}

/// The vote chain of `scope`'s network, with the chain id the participation
/// reader trusts.
fn delegate_chain(scope: &ApiDelegateModeScope) -> Result<DelegateChain, ApiDelegateModeError> {
    let network = voting_network(parse_network(&scope.network).map_err(invalid_input)?);
    let chain_id = participation::vote_chain_id(&scope.network).map_err(invalid_input)?;
    DelegateChain::new(network, chain_id).map_err(mode_error)
}

/// The checked entry from the participation reader's proof.
fn proven_entry(
    entry: &ApiProvenRegistryEntry,
) -> Result<ProvenDelegateEntry, ApiDelegateModeError> {
    let proof = match &entry.entry {
        Some(bytes) => ProvenValue::Present(bytes.clone()),
        None => ProvenValue::Absent,
    };
    ProvenDelegateEntry::from_proof(entry.delegate_index, &proof)
        .map_err(entry_error)?
        .ok_or_else(|| ApiDelegateModeError {
            kind: ApiDelegateModeErrorKind::EntryUnverifiable,
            message: format!("entry {} is proven absent", entry.delegate_index),
        })
}

/// zcash_voting's timing of `round`.
fn round_timing(
    round: &ApiDelegateRoundTiming,
) -> Result<DelegateRoundTiming, ApiDelegateModeError> {
    Ok(DelegateRoundTiming {
        round_id: round_bytes(&round.round_id)?,
        vote_end_time: round.vote_end_time,
    })
}

/// A round id's 32 bytes.
fn round_bytes(round_id: &str) -> Result<[u8; 32], ApiDelegateModeError> {
    hex::decode(round_id)
        .ok()
        .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
        .ok_or_else(|| invalid_input(format!("round id {round_id} is not 32 bytes of hex")))
}

/// A `zvdk1…` string's key.
fn decode_key(dk: &str) -> Result<DelegateKey, ApiDelegateModeError> {
    DelegateKey::decode(dk)
        .map_err(|error| invalid_input(format!("{dk} is not a delegate key: {error:?}")))
}

/// zcash_voting's provider for a client API one.
fn identity_provider(provider: ProxyDelegateProvider) -> IdentityProvider {
    match provider {
        ProxyDelegateProvider::X => IdentityProvider::X,
        ProxyDelegateProvider::GitHub => IdentityProvider::GitHub,
    }
}

/// The bridge form of a signed op.
fn signed_op(op: SignedDelegateOp) -> ApiSignedDelegateOp {
    ApiSignedDelegateOp {
        kind: match op.kind() {
            DelegateOpKind::Register => ApiDelegateOpKind::Register,
            DelegateOpKind::Retire => ApiDelegateOpKind::Retire,
            DelegateOpKind::Ballot => ApiDelegateOpKind::Ballot,
        },
        delegate_index: op.delegate_index(),
        dk: op.dk().encode(),
        body: op.body().to_vec(),
    }
}

/// An op answer of `kind` with the given fields.
fn op_answer(
    kind: ApiDelegateOpAnswerKind,
    tx_hash: Option<String>,
    codespace: Option<String>,
    code: Option<u32>,
    detail: Option<String>,
) -> ApiDelegateOpAnswer {
    ApiDelegateOpAnswer {
        kind,
        tx_hash,
        codespace,
        code,
        detail,
    }
}

/// The bridge form of a listed ballot.
fn chain_ballot_view(ballot: &ChainDelegateBallot) -> ApiChainDelegateBallot {
    ApiChainDelegateBallot {
        delegate_index: ballot.delegate_index,
        options: ballot.options.clone(),
        height: ballot.height,
    }
}

/// zcash_voting's listed ballot for a bridged one.
fn chain_ballot_record(ballot: ApiChainDelegateBallot) -> ChainDelegateBallot {
    ChainDelegateBallot {
        delegate_index: ballot.delegate_index,
        options: ballot.options,
        height: ballot.height,
    }
}

/// The bridge form of a ballot view.
fn ballot_view(ballot: DelegateBallotView) -> ApiDelegateBallotView {
    let (kind, options) = match ballot {
        DelegateBallotView::NoBallotYet => (ApiDelegateBallotKind::NoBallotYet, Vec::new()),
        DelegateBallotView::Submitted { options } => (ApiDelegateBallotKind::Submitted, options),
        DelegateBallotView::Counted { options } => (ApiDelegateBallotKind::Counted, options),
        DelegateBallotView::NotCounted => (ApiDelegateBallotKind::NotCounted, Vec::new()),
    };
    ApiDelegateBallotView { kind, options }
}

/// The bridge form of a submit outcome.
fn submit_result(result: BallotSubmitResult) -> ApiBallotSubmitResult {
    let outcome = |kind| ApiBallotSubmitResult {
        kind,
        codespace: None,
        code: None,
        reason: None,
    };
    match result {
        BallotSubmitResult::Accepted => outcome(ApiBallotSubmitKind::Accepted),
        BallotSubmitResult::AlreadyAccepted => outcome(ApiBallotSubmitKind::AlreadyAccepted),
        BallotSubmitResult::Rejected {
            codespace,
            code,
            reason,
        } => ApiBallotSubmitResult {
            codespace: Some(codespace),
            code: Some(code),
            reason: Some(reason),
            ..outcome(ApiBallotSubmitKind::Rejected)
        },
    }
}

/// The bridge form of a proven entry that cannot be used.
fn entry_error(error: DelegateEntryError) -> ApiDelegateModeError {
    ApiDelegateModeError {
        kind: ApiDelegateModeErrorKind::EntryUnverifiable,
        message: error.to_string(),
    }
}

/// The bridge form of a delegate-mode failure.
fn mode_error(error: DelegateModeError) -> ApiDelegateModeError {
    let kind = match &error {
        DelegateModeError::ChainRead(_) => ApiDelegateModeErrorKind::ChainAnswer,
        DelegateModeError::NotDeviceEntry { .. } => ApiDelegateModeErrorKind::EntryUnverifiable,
        DelegateModeError::Attestation(_)
        | DelegateModeError::KeyRegistered { .. }
        | DelegateModeError::InvalidInput { .. }
        | DelegateModeError::AnotherKeyHeld { .. }
        | DelegateModeError::CorruptRecord { .. }
        | DelegateModeError::Storage(_) => ApiDelegateModeErrorKind::Other,
    };
    ApiDelegateModeError {
        kind,
        message: error.to_string(),
    }
}

/// The bridge form of a ballot that cannot be built or signed.
fn ballot_error(error: BallotError) -> ApiDelegateModeError {
    match error {
        BallotError::Records(error) => mode_error(error),
        error => ApiDelegateModeError {
            kind: ApiDelegateModeErrorKind::Other,
            message: error.to_string(),
        },
    }
}

/// An [`ApiDelegateModeErrorKind::Other`] failure for malformed input.
fn invalid_input(message: impl Into<String>) -> ApiDelegateModeError {
    ApiDelegateModeError {
        kind: ApiDelegateModeErrorKind::Other,
        message: message.into(),
    }
}

#[cfg(test)]
mod tests;
