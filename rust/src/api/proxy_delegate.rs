//! The delegate ballot list's paging for Dart (contracts-v1 §8
//! `DelegateBallots`), reached only behind `VIZOR_PROXY_DELEGATION_ENABLED`.
//! The delegator client reads each round's whole list page by page, and
//! zcash_voting checks how the pages chain.

use zcash_voting::proxy::delegate::{self, ChainDelegateBallot, DelegateModeError};

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

/// A round id's 32 bytes.
fn round_bytes(round_id: &str) -> Result<[u8; 32], ApiDelegateModeError> {
    hex::decode(round_id)
        .ok()
        .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
        .ok_or_else(|| invalid_input(format!("round id {round_id} is not 32 bytes of hex")))
}

/// The bridge form of a listed ballot.
fn chain_ballot_view(ballot: &ChainDelegateBallot) -> ApiChainDelegateBallot {
    ApiChainDelegateBallot {
        delegate_index: ballot.delegate_index,
        options: ballot.options.clone(),
        height: ballot.height,
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

/// An [`ApiDelegateModeErrorKind::Other`] failure for malformed input.
fn invalid_input(message: impl Into<String>) -> ApiDelegateModeError {
    ApiDelegateModeError {
        kind: ApiDelegateModeErrorKind::Other,
        message: message.into(),
    }
}

#[cfg(test)]
mod tests;
