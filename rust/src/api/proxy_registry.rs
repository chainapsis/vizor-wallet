//! Proxy delegation registry calls for Dart (contracts-v1 §11.10, §11.11
//! and §12), reached only behind `VIZOR_PROXY_DELEGATION_ENABLED`.
//!
//! zcash_voting's `proxy::registry` makes every check; these calls only hand
//! its values to the bridge. Dart fetches the documents and keeps what these
//! calls hand back: the registry cache as zcash_voting's JSON, and the bytes
//! of the newest wallet list that verified. Every call that takes them reads
//! them again, so a stored copy counts only while it still parses or
//! verifies.
//!
//! Vizor's wallet list signers are pinned here per network (§12.3): the
//! `valargroup` vote-manager key on mainnet and Valar's stage key on
//! testnet. A regtest build takes the key its harness signs with from
//! [`configure_regtest_wallet_list_key`].

use std::sync::OnceLock;

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use zcash_voting::proxy::registry::{
    self, ConfirmContext, PinnedListKey, ProvenRecord, ProvenValue, RegistryCache, RegistryError,
    RegistryPage, RegistryProofRequest, RegistryView, VerifiedWalletList, WalletListPin,
    WalletListUpdate,
};
use zcash_voting::wire::{
    DelegateCheck, DelegateLookup, ProxyAllocationRequest, ProxyDelegateBrowse,
    ProxyDelegateListing,
};

use super::proxy_delegation::ApiProvenRegistryEntry;
use crate::wallet::voting::participation;

/// The wallet id Vizor's list carries and is hosted under.
pub const VIZOR_WALLET_ID: &str = "vizor";

/// The one key that signs Vizor's list on mainnet (`zvote-1`): the
/// `valargroup` vote-manager Keplr-derived key of the prod static config.
const MAIN_LIST_KEY: (&str, &str) = ("valargroup", "8oQiUWq6QDGnAgRw6U3YhnXb6JLFSXauYnWHIFmJRcw=");

/// The one key that signs Vizor's list on testnet (`svote-1`): Valar's
/// Keplr-derived key of the stage static config.
const STAGE_LIST_KEY: (&str, &str) = (
    "valar-test-keplr-derived",
    "NDygCpG+Y4T4uu8M1Sb/YG+74lUVj9XgYypUoMQMXT8=",
);

/// The key a regtest harness signs its test list with; never consulted on
/// mainnet or testnet.
static REGTEST_LIST_KEY: OnceLock<PinnedListKey> = OnceLock::new();

/// A registry call refused its input: Dart passed a malformed value, or a
/// document failed its checks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyRegistryError {
    /// zcash_voting's description; it names no account data.
    pub message: String,
}

/// The unsigned URL lists of `extensions.proxy_delegation_v1` (§12.1).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ApiProxyServiceUrls {
    /// The verifier API the delegate app registers through.
    pub verifier_api_urls: Vec<String>,
    /// RPC hosts that serve the participation reader's proofs.
    pub proof_rpc_urls: Vec<String>,
}

/// The URL lists of one dynamic config document, or `None` when it has no
/// `extensions.proxy_delegation_v1` (zcash_voting `proxy_service_urls`).
pub fn proxy_service_urls(
    dynamic_config_bytes: Vec<u8>,
) -> Result<Option<ApiProxyServiceUrls>, ApiProxyRegistryError> {
    Ok(registry::proxy_service_urls(&dynamic_config_bytes)
        .map_err(registry_error)?
        .map(|urls| ApiProxyServiceUrls {
            verifier_api_urls: urls.verifier_api_urls,
            proof_rpc_urls: urls.proof_rpc_urls,
        }))
}

/// The REST path of the registry page after `start_after`.
#[flutter_rust_bridge::frb(sync)]
pub fn proxy_registry_page_path(start_after: u32) -> String {
    registry::registry_page_path(start_after)
}

/// Checks the answer to [`proxy_registry_page_path`]`(start_after)` and
/// returns the `start_after` of the next page, or `None` on the last one
/// (zcash_voting `parse_registry_page`).
pub fn proxy_registry_next_start_after(
    start_after: u32,
    status: u16,
    body: Vec<u8>,
) -> Result<Option<u32>, ApiProxyRegistryError> {
    Ok(page(start_after, status, &body)?.next_start_after)
}

/// One fetched registry page.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiRegistryPage {
    /// The `start_after` it was fetched with.
    pub start_after: u32,
    /// The 200 answer's body.
    pub body: Vec<u8>,
}

/// A registry cache built from one complete download.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyRegistryCache {
    /// zcash_voting's serde form of `RegistryCache`, which Dart stores per
    /// network and passes back unread.
    pub json: String,
    /// How many entries it holds.
    pub entries: u32,
}

/// The registry cache for `network`'s vote chain from every page of one
/// download, fetched in order from `start_after = 0` (zcash_voting
/// `RegistryCache::from_pages`). It is unproven and drives display only.
pub fn build_proxy_registry_cache(
    network: String,
    pages: Vec<ApiRegistryPage>,
) -> Result<ApiProxyRegistryCache, ApiProxyRegistryError> {
    let parsed = pages
        .iter()
        .map(|fetched| page(fetched.start_after, 200, &fetched.body))
        .collect::<Result<Vec<_>, _>>()?;
    let cache = RegistryCache::from_pages(chain_id(&network)?, parsed);
    Ok(ApiProxyRegistryCache {
        json: serde_json::to_string(&cache).map_err(|error| invalid_input(error.to_string()))?,
        entries: u32::try_from(cache.len()).unwrap_or(u32::MAX),
    })
}

/// Pins the key a regtest harness signs Vizor's test list with: `key_id`
/// and the Ed25519 public key in standard base64. It never changes the
/// mainnet or testnet pins, and a second call must name the same key.
pub fn configure_regtest_wallet_list_key(key_id: String, public_key: String) -> Result<(), String> {
    let key = pinned_key(&key_id, &public_key)?;
    // `set` loses to a concurrent first call; only a different key is an error.
    match REGTEST_LIST_KEY.set(key) {
        Err(key) if REGTEST_LIST_KEY.get() != Some(&key) => {
            Err("the regtest wallet list key is already set to another key".into())
        }
        _ => Ok(()),
    }
}

/// What one fetched wallet list did to the stored one (zcash_voting
/// `WalletListUpdate`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiWalletListUpdate {
    /// The document is now the newest list; Dart stores its bytes.
    Adopted,
    /// The document repeats the stored list.
    Unchanged,
    /// The document is an older version; the stored list stays.
    Older,
    /// The document has the stored version with another payload; the stored
    /// list stays and the conflict is logged.
    ConflictingPayload,
    /// The document failed verification; the stored list stays.
    Rejected,
}

/// The wallet list to show after reading one document.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiWalletListResolution {
    /// What the document did.
    pub update: ApiWalletListUpdate,
    /// The older version or the rejection's name, for logs.
    pub detail: Option<String>,
    /// The newest verified list's version, or `None` without one.
    pub version: Option<u64>,
}

/// Verifies a fetched Vizor wallet list for `network` against the pinned
/// signer and keeps the newest of it and `stored`, the bytes Dart stored for
/// the last adopted list (zcash_voting `resolve_wallet_list`). A stored list
/// that no longer verifies counts as none.
pub fn resolve_proxy_wallet_list(
    network: String,
    document: Vec<u8>,
    stored: Option<Vec<u8>>,
) -> Result<ApiWalletListResolution, ApiProxyRegistryError> {
    let pin = wallet_list_pin(&network)?;
    let stored = stored.and_then(|bytes| pin.verify(&bytes).ok());
    let resolution =
        registry::resolve_wallet_list(&pin, &document, stored.as_ref()).map_err(registry_error)?;
    let (update, detail) = match resolution.update {
        WalletListUpdate::Adopted => (ApiWalletListUpdate::Adopted, None),
        WalletListUpdate::Unchanged => (ApiWalletListUpdate::Unchanged, None),
        WalletListUpdate::Older { version } => (
            ApiWalletListUpdate::Older,
            Some(format!("version {version}")),
        ),
        WalletListUpdate::ConflictingPayload => (ApiWalletListUpdate::ConflictingPayload, None),
        WalletListUpdate::Rejected(error) => {
            (ApiWalletListUpdate::Rejected, Some(error.name().to_owned()))
        }
    };
    Ok(ApiWalletListResolution {
        update,
        detail,
        version: resolution.newest.map(|list| list.list().version),
    })
}

/// The picture Vizor's stored list gives entry `delegate_index`, for the
/// delegate's own dashboard; `None` when the list does not verify, has no
/// row for the entry or the row has no picture.
pub fn proxy_wallet_list_picture(
    network: String,
    wallet_list: Vec<u8>,
    delegate_index: u32,
) -> Option<Vec<u8>> {
    verified_list(&network, Some(&wallet_list))?
        .list()
        .row(delegate_index)?
        .picture
        .clone()
}

/// What a delegator has for finding delegates in one round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProxyRegistryView {
    /// The wallet network: `main`, `test` or `regtest`.
    pub network: String,
    /// The stored registry cache, [`ApiProxyRegistryCache::json`].
    pub registry_cache: String,
    /// The newest wallet list that verified, or `None`; without it browse is
    /// empty and nothing shows as reviewed.
    pub wallet_list: Option<Vec<u8>>,
    /// The round's `next_delegate_index_at_creation` as the RPC reports it,
    /// which labels entries new this round.
    pub first_new_index: Option<u32>,
}

/// Browse: Vizor's list rows in list order (zcash_voting
/// `RegistryView::browse`).
pub fn proxy_browse(
    view: ApiProxyRegistryView,
) -> Result<ProxyDelegateBrowse, ApiProxyRegistryError> {
    let parts = ViewParts::new(&view)?;
    Ok(parts.view(&view).browse())
}

/// Exact handle search over the registry cache's live entries (zcash_voting
/// `RegistryView::search`).
pub fn search_proxy_delegates(
    view: ApiProxyRegistryView,
    query: String,
) -> Result<Vec<ProxyDelegateListing>, ApiProxyRegistryError> {
    let parts = ViewParts::new(&view)?;
    Ok(parts.view(&view).search(&query))
}

/// Which answer a paste or scan got: zcash_voting's `DelegateLookup`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegateLookupKind {
    /// The text names this delegate.
    Found,
    /// The text names no delegate in the registry cache.
    NotFound,
    /// The text is not a marker post, a key, an index or a fingerprint.
    Unrecognized,
}

/// zcash_voting's `DelegateLookup`, flattened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegateLookup {
    /// The answer.
    pub kind: ApiDelegateLookupKind,
    /// `Found`: the delegate.
    pub listing: Option<ProxyDelegateListing>,
}

/// Paste or scan of a marker post, `zvdk1…` key, index or fingerprint
/// (zcash_voting `RegistryView::lookup`).
pub fn lookup_proxy_delegate(
    view: ApiProxyRegistryView,
    text: String,
) -> Result<ApiDelegateLookup, ApiProxyRegistryError> {
    let parts = ViewParts::new(&view)?;
    Ok(match parts.view(&view).lookup(&text) {
        DelegateLookup::Found { listing } => ApiDelegateLookup {
            kind: ApiDelegateLookupKind::Found,
            listing: Some(listing),
        },
        DelegateLookup::NotFound => ApiDelegateLookup {
            kind: ApiDelegateLookupKind::NotFound,
            listing: None,
        },
        DelegateLookup::Unrecognized => ApiDelegateLookup {
            kind: ApiDelegateLookupKind::Unrecognized,
            listing: None,
        },
    })
}

/// One choice at confirm: zcash_voting's `ConfirmedDelegate`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiConfirmedDelegate {
    /// The verdict a commit takes.
    pub check: DelegateCheck,
    /// The delegate from the proven entry; `None` unless it is proven and
    /// decodes.
    pub listing: Option<ProxyDelegateListing>,
}

/// The pre-proving check of `request` against `proven`, the proofs of its
/// chosen entries, one verdict per choice in request order (zcash_voting
/// `check_delegates`, contracts-v1 §11.11). An entry `proven` lacks counts
/// as unproven. `wallet_list` is the stored list and `first_new_index` the
/// round's `next_delegate_index_at_creation`; both only label the listings.
pub fn check_proxy_delegates(
    network: String,
    wallet_list: Option<Vec<u8>>,
    first_new_index: Option<u32>,
    request: ProxyAllocationRequest,
    proven: Vec<ApiProvenRegistryEntry>,
) -> Vec<ApiConfirmedDelegate> {
    let wallet_list = verified_list(&network, wallet_list.as_deref());
    let proven: Vec<ProvenRecord> = proven
        .into_iter()
        .map(|record| ProvenRecord {
            request: RegistryProofRequest {
                delegate_index: record.delegate_index,
            },
            value: match record.entry {
                Some(bytes) => ProvenValue::Present(bytes),
                None => ProvenValue::Absent,
            },
        })
        .collect();
    let context = ConfirmContext {
        wallet_list: wallet_list.as_ref(),
        first_new_index,
    };
    registry::check_delegates(&context, &request, &proven)
        .into_iter()
        .map(|confirmed| ApiConfirmedDelegate {
            check: confirmed.check,
            listing: confirmed.listing,
        })
        .collect()
}

/// Vizor's list pin for `network`'s vote chain.
fn wallet_list_pin(network: &str) -> Result<WalletListPin, ApiProxyRegistryError> {
    let key = match network {
        "main" => pinned_key(MAIN_LIST_KEY.0, MAIN_LIST_KEY.1).map_err(invalid_input)?,
        "test" => pinned_key(STAGE_LIST_KEY.0, STAGE_LIST_KEY.1).map_err(invalid_input)?,
        "regtest" => REGTEST_LIST_KEY
            .get()
            .cloned()
            .ok_or_else(|| invalid_input("no regtest wallet list key is configured"))?,
        _ => return Err(invalid_input(format!("unknown network {network}"))),
    };
    Ok(WalletListPin {
        wallet_id: VIZOR_WALLET_ID.to_owned(),
        chain_id: chain_id(network)?,
        keys: vec![key],
    })
}

/// The stored list `bytes` verified again under `network`'s pin, or `None`
/// when there is none, the network pins no key, or it no longer verifies.
fn verified_list(network: &str, bytes: Option<&[u8]>) -> Option<VerifiedWalletList> {
    let pin = wallet_list_pin(network).ok()?;
    pin.verify(bytes?)
        .map_err(|error| log::warn!("stored wallet list: {}", error.name()))
        .ok()
}

/// A pinned key from its id and standard base64 public key.
fn pinned_key(key_id: &str, public_key: &str) -> Result<PinnedListKey, String> {
    let bytes = B64
        .decode(public_key)
        .map_err(|_| format!("{key_id}'s public key is not base64"))?;
    let public_key = <[u8; 32]>::try_from(bytes)
        .map_err(|_| format!("{key_id}'s public key is not 32 bytes"))?;
    if key_id.is_empty() || key_id.len() > 64 {
        return Err("a key id is 1 to 64 bytes".into());
    }
    Ok(PinnedListKey {
        key_id: key_id.to_owned(),
        public_key,
    })
}

/// The view's stored documents, read again.
struct ViewParts {
    cache: RegistryCache,
    wallet_list: Option<VerifiedWalletList>,
}

impl ViewParts {
    /// Reads `view`'s cache, which must parse for its chain, and its wallet
    /// list, which counts as absent when it no longer verifies.
    fn new(view: &ApiProxyRegistryView) -> Result<Self, ApiProxyRegistryError> {
        Ok(Self {
            cache: parse_cache(&view.network, &view.registry_cache)?,
            wallet_list: verified_list(&view.network, view.wallet_list.as_deref()),
        })
    }

    /// zcash_voting's view over these parts and `view`'s round.
    fn view(&self, view: &ApiProxyRegistryView) -> RegistryView<'_> {
        RegistryView {
            cache: &self.cache,
            wallet_list: self.wallet_list.as_ref(),
            first_new_index: view.first_new_index,
        }
    }
}

/// The stored registry cache, which must describe `network`'s vote chain.
fn parse_cache(network: &str, json: &str) -> Result<RegistryCache, ApiProxyRegistryError> {
    let cache: RegistryCache = serde_json::from_str(json)
        .map_err(|error| invalid_input(format!("stored registry cache: {error}")))?;
    let chain_id = chain_id(network)?;
    if cache.chain_id() != chain_id {
        return Err(invalid_input(format!(
            "the stored registry cache is chain {}'s, not {chain_id}'s",
            cache.chain_id()
        )));
    }
    Ok(cache)
}

/// One checked registry page.
fn page(start_after: u32, status: u16, body: &[u8]) -> Result<RegistryPage, ApiProxyRegistryError> {
    registry::parse_registry_page(start_after, status, body)
        .map_err(|error| invalid_input(format!("registry page after {start_after}: {error}")))
}

/// The vote chain id the participation reader trusts for `network`.
fn chain_id(network: &str) -> Result<String, ApiProxyRegistryError> {
    participation::vote_chain_id(network).map_err(invalid_input)
}

/// The bridge form of a registry error.
fn registry_error(error: RegistryError) -> ApiProxyRegistryError {
    invalid_input(error.to_string())
}

/// A registry error described by `message`.
fn invalid_input(message: impl Into<String>) -> ApiProxyRegistryError {
    ApiProxyRegistryError {
        message: message.into(),
    }
}

#[cfg(test)]
mod tests;
