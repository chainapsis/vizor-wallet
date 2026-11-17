//! Wallet PIR server config for Dart: a thin adapter over the shared
//! `zakura-pir-config` profile, plus applying the chosen server.
//!
//! Dart owns transport and persistence. It fetches the static document from
//! the config source and the dynamic document from its mirrors over the app's
//! routed HTTP client, stores the opaque snapshot and selection strings these
//! functions return, and passes them back on every load. Every check runs in
//! the shared profile; nothing here performs network I/O.

use zakura_pir_config::{
    resolve_config_from_attempts, resolve_config_snapshot, resolve_static_config,
    ResolvedWalletPirConfig, ServerBase, ServerSelection, ServerSelectionOutcome,
    WalletPirConfigProfile, WalletPirConfigSnapshot, WalletPirNetwork,
};
use zakura_service_config::MirrorAttempt;

use std::sync::{Mutex, PoisonError};

use crate::wallet::pir_config::{process_selection, selected_server_base, SelectedServer};
use crate::wallet::sync_engine::transparent_details::source::retain_service_for;

/// Validates a user-entered HTTPS base with the same rules as advertised
/// servers. Returns its canonical identity without contacting the server.
#[flutter_rust_bridge::frb(sync)]
pub fn normalize_wallet_pir_server_base(base_url: String) -> Result<String, String> {
    ServerBase::parse(base_url.trim())
        .map(|base| base.as_str().to_owned())
        .map_err(|error| error.to_string())
}

/// The same public Enhance initialization route used by the client. A ping
/// measures its HTTPS response and does not create a private query session.
#[flutter_rust_bridge::frb(sync)]
pub fn wallet_pir_server_ping_url(base_url: String) -> Result<String, String> {
    let base = ServerBase::parse(&base_url).map_err(|error| error.to_string())?;
    base.endpoint()
        .product_url(zakura_pir_protocol::endpoint::PirProduct::Enhance, "/init")
        .map_err(|error| error.to_string())
}

/// A static document the profile accepted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiWalletPirStaticConfig {
    /// Identity of source, pin, network and attestation policy. Dart scopes
    /// cached config and the saved selection by it.
    pub scope: String,
    /// Dynamic mirrors to fetch, in order.
    pub dynamic_config_urls: Vec<String>,
}

/// One dynamic mirror fetch. Exactly one of `bytes` / `error` is set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiWalletPirConfigAttempt {
    pub url: String,
    pub bytes: Option<Vec<u8>>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiWalletPirServer {
    /// Display text only.
    pub label: String,
    /// Canonical base shared by all four products; the server's identity.
    pub base_url: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiWalletPirSelectionState {
    /// The saved server is still advertised.
    Kept,
    /// No earlier choice in this scope; the first advertised server was
    /// chosen and must be saved.
    Defaulted,
    /// The config advertises no server. No private PIR traffic.
    NoServers,
    /// The saved server was removed. No private PIR traffic until the user
    /// chooses; keep the saved selection so a restart lands here again.
    SelectionRequired,
}

/// An accepted config and what it means for the saved selection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiWalletPirConfig {
    pub scope: String,
    /// Raw accepted documents to persist as the last good config. Never
    /// trusted as stored: reload re-runs every check through
    /// [`resolve_wallet_pir_config_snapshot`].
    pub snapshot_json: String,
    /// The mirror whose document was accepted.
    pub dynamic_config_url: String,
    /// Advertised servers in published order.
    pub servers: Vec<ApiWalletPirServer>,
    pub selection_state: ApiWalletPirSelectionState,
    /// The server to use, for `Kept` and `Defaulted`.
    pub selected_base_url: Option<String>,
    /// Opaque selection to persist, for `Kept` and `Defaulted`.
    pub selection_json: Option<String>,
    /// The saved server the config no longer advertises.
    pub removed_base_url: Option<String>,
    /// Mirrors passed over before the accepted one, as `url: reason`.
    pub passed_over: Vec<String>,
}

fn network(name: &str) -> Result<WalletPirNetwork, String> {
    name.parse::<WalletPirNetwork>()
        .map_err(|error| error.to_string())
}

fn profile() -> WalletPirConfigProfile {
    WalletPirConfigProfile::https_transport()
}

/// Verifies the static document and returns the mirrors to fetch.
#[flutter_rust_bridge::frb(sync)]
pub fn resolve_wallet_pir_static_config(
    source: String,
    network_name: String,
    static_bytes: Vec<u8>,
) -> Result<ApiWalletPirStaticConfig, String> {
    let anchor = resolve_static_config(&source, &static_bytes, network(&network_name)?)
        .map_err(|error| error.to_string())?;
    Ok(ApiWalletPirStaticConfig {
        scope: profile().scope(&anchor).as_str().to_owned(),
        dynamic_config_urls: anchor.dynamic_config_urls().to_vec(),
    })
}

/// Accepts the first mirror attempt whose document passes the profile and
/// reconciles `saved_selection_json` with it.
///
/// Dart re-invokes this after each mirror fetch, so a healthy first mirror
/// costs one request. Mirrors are copies of one document; advertised servers
/// are never tried in turn.
#[flutter_rust_bridge::frb(sync)]
pub fn resolve_wallet_pir_config(
    source: String,
    network_name: String,
    static_bytes: Vec<u8>,
    attempts: Vec<ApiWalletPirConfigAttempt>,
    saved_selection_json: Option<String>,
) -> Result<ApiWalletPirConfig, String> {
    let profile = profile();
    let anchor = resolve_static_config(&source, &static_bytes, network(&network_name)?)
        .map_err(|error| error.to_string())?;
    let attempts = attempts.into_iter().map(|attempt| match attempt.bytes {
        Some(bytes) => MirrorAttempt::fetched(attempt.url, bytes),
        None => MirrorAttempt::failed(
            attempt.url,
            attempt.error.unwrap_or_else(|| "fetch failed".to_owned()),
        ),
    });
    let resolution = resolve_config_from_attempts(&profile, &anchor, attempts)
        .map_err(|error| error.summary())?;
    let passed_over = resolution
        .passed_over
        .into_iter()
        .map(|failure| format!("{}: {}", failure.url, failure.reason))
        .collect();
    view(
        &resolution.value,
        saved_selection_json.as_deref(),
        passed_over,
    )
}

/// Re-validates a persisted last good config under the current source and
/// network, exactly as if its documents had just been fetched.
#[flutter_rust_bridge::frb(sync)]
pub fn resolve_wallet_pir_config_snapshot(
    source: String,
    network_name: String,
    snapshot_json: String,
    saved_selection_json: Option<String>,
) -> Result<ApiWalletPirConfig, String> {
    let snapshot: WalletPirConfigSnapshot =
        serde_json::from_str(&snapshot_json).map_err(|error| error.to_string())?;
    let resolved = resolve_config_snapshot(&profile(), &snapshot, &source, network(&network_name)?)
        .map_err(|error| error.to_string())?;
    view(&resolved, saved_selection_json.as_deref(), Vec::new())
}

/// Records the user's explicit choice of an advertised server and returns the
/// selection to persist. The snapshot is re-validated first, so a choice is
/// only ever made against an accepted config.
#[flutter_rust_bridge::frb(sync)]
pub fn select_wallet_pir_server(
    source: String,
    network_name: String,
    snapshot_json: String,
    base_url: String,
) -> Result<String, String> {
    let snapshot: WalletPirConfigSnapshot =
        serde_json::from_str(&snapshot_json).map_err(|error| error.to_string())?;
    let resolved = resolve_config_snapshot(&profile(), &snapshot, &source, network(&network_name)?)
        .map_err(|error| error.to_string())?;
    let base = ServerBase::parse(&base_url).map_err(|error| error.to_string())?;
    let selection = resolved
        .select_server(&base)
        .map_err(|error| error.to_string())?;
    serde_json::to_string(&selection).map_err(|error| error.to_string())
}

fn view(
    resolved: &ResolvedWalletPirConfig,
    saved_selection_json: Option<&str>,
    passed_over: Vec<String>,
) -> Result<ApiWalletPirConfig, String> {
    // An unreadable saved selection is treated as absent only when the saved
    // string is empty; anything else is surfaced rather than silently
    // replaced by a default.
    let saved: Option<ServerSelection> = match saved_selection_json {
        None | Some("") => None,
        Some(json) => {
            Some(serde_json::from_str(json).map_err(|error| format!("saved selection: {error}"))?)
        }
    };
    let outcome = resolved.reconcile_selection(saved.as_ref());
    let (selection_state, removed) = match &outcome {
        ServerSelectionOutcome::Kept(_) => (ApiWalletPirSelectionState::Kept, None),
        ServerSelectionOutcome::Defaulted(_) => (ApiWalletPirSelectionState::Defaulted, None),
        ServerSelectionOutcome::NoServers => (ApiWalletPirSelectionState::NoServers, None),
        ServerSelectionOutcome::SelectionRequired { removed } => (
            ApiWalletPirSelectionState::SelectionRequired,
            Some(removed.as_str().to_owned()),
        ),
    };
    let selection = outcome.selection();
    Ok(ApiWalletPirConfig {
        scope: resolved.scope().as_str().to_owned(),
        snapshot_json: serde_json::to_string(resolved.snapshot())
            .map_err(|error| error.to_string())?,
        dynamic_config_url: resolved.dynamic_config_url().to_owned(),
        servers: resolved
            .servers()
            .iter()
            .map(|server| ApiWalletPirServer {
                label: server.label.clone(),
                base_url: server.base.as_str().to_owned(),
            })
            .collect(),
        selection_state,
        selected_base_url: selection.map(|selection| selection.base().as_str().to_owned()),
        selection_json: selection
            .map(serde_json::to_string)
            .transpose()
            .map_err(|error| error.to_string())?,
        removed_base_url: removed,
        passed_over,
    })
}

/// The server all four private products currently use, if any.
#[flutter_rust_bridge::frb(sync)]
pub fn selected_wallet_pir_server() -> Option<String> {
    selected_server_base()
}

/// Uses `base_url` for private queries, or no server with `None`.
/// Returns whether the applied server changed.
///
/// Dart pauses sync before calling this and restarts it afterwards. Display
/// services tied to the old server are dropped. Enhance, Status and Transparent
/// sessions are rebuilt from the selected base; wallet keys and history stay
/// unchanged. Receiver recovery notices the change on its next round or filter
/// step and forgets the old server's history (see `swap_private::adopt_server`).
pub fn apply_wallet_pir_server(base_url: Option<String>) -> Result<bool, String> {
    // Concurrent applies would interleave their stages.
    static APPLY: Mutex<()> = Mutex::new(());
    let _applying = APPLY.lock().unwrap_or_else(PoisonError::into_inner);
    apply_server(process_selection(), base_url.as_deref(), || {
        retain_service_for(None);
        Ok(())
    })
}

/// Switches `selection` to `base_url`, running `cleanup` between dropping the
/// old server and installing the new one.
fn apply_server(
    selection: &SelectedServer,
    base_url: Option<&str>,
    cleanup: impl FnOnce() -> Result<(), String>,
) -> Result<bool, String> {
    let Some(switch) = selection.begin_switch(base_url)? else {
        return Ok(false);
    };
    cleanup()?;
    selection.finish_switch(switch);
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    #[test]
    fn custom_servers_use_the_shared_https_base_rules() {
        assert_eq!(
            normalize_wallet_pir_server_base(" HTTPS://Server.Example:443/pir/ ".into()),
            Ok("https://server.example/pir".into())
        );
        for url in [
            "http://server.example",
            "https://user@server.example",
            "https://server.example?query=1",
            "https://server.example#fragment",
            "https://server.example/pir//other",
            "not a url",
        ] {
            assert!(
                normalize_wallet_pir_server_base(url.into()).is_err(),
                "{url}"
            );
        }
    }

    #[test]
    fn ping_uses_the_shared_product_path_and_preserves_the_base_path() {
        assert_eq!(
            wallet_pir_server_ping_url("https://server.example/wallet/".into()),
            Ok("https://server.example/wallet/enhance/v1/init".into())
        );
        assert!(wallet_pir_server_ping_url("http://server.example".into()).is_err());
    }

    const MIRROR_A: &str = "https://valargroup.github.io/wallet-pir-config/prod/dynamic.json";
    const MIRROR_B: &str =
        "https://raw.githubusercontent.com/valargroup/wallet-pir-config/main/prod/dynamic.json";

    fn source_and_bytes() -> (String, Vec<u8>) {
        let bytes = serde_json::json!({
            "static_config_version": 1,
            "network": "mainnet",
            "dynamic_config_urls": [MIRROR_A, MIRROR_B],
            "attestation": {"method": "https-transport", "trust": null},
        })
        .to_string()
        .into_bytes();
        let source = format!(
            "https://valargroup.github.io/wallet-pir-config/pins/prod/static.json?checksum=sha256:{}",
            hex::encode(Sha256::digest(&bytes))
        );
        (source, bytes)
    }

    fn dynamic(servers: serde_json::Value) -> Vec<u8> {
        serde_json::json!({"config_version": 1, "network": "mainnet", "servers": servers})
            .to_string()
            .into_bytes()
    }

    fn fetched(url: &str, bytes: Vec<u8>) -> ApiWalletPirConfigAttempt {
        ApiWalletPirConfigAttempt {
            url: url.into(),
            bytes: Some(bytes),
            error: None,
        }
    }

    fn two_servers() -> Vec<u8> {
        dynamic(serde_json::json!([
            {"label": "Valar", "url": "https://wallet-pir.valargroup.dev/"},
            {"label": "Backup", "url": "https://backup.example/pir"},
        ]))
    }

    fn load(dynamic_bytes: Vec<u8>, saved: Option<String>) -> ApiWalletPirConfig {
        let (source, bytes) = source_and_bytes();
        resolve_wallet_pir_config(
            source,
            "mainnet".into(),
            bytes,
            vec![fetched(MIRROR_A, dynamic_bytes)],
            saved,
        )
        .unwrap()
    }

    #[test]
    fn a_failed_first_mirror_falls_through_to_the_second() {
        let (source, bytes) = source_and_bytes();
        let anchor =
            resolve_wallet_pir_static_config(source.clone(), "mainnet".into(), bytes.clone())
                .unwrap();
        assert_eq!(anchor.dynamic_config_urls, vec![MIRROR_A, MIRROR_B]);

        let config = resolve_wallet_pir_config(
            source,
            "mainnet".into(),
            bytes,
            vec![
                ApiWalletPirConfigAttempt {
                    url: MIRROR_A.into(),
                    bytes: None,
                    error: Some("timed out".into()),
                },
                fetched(MIRROR_B, two_servers()),
            ],
            None,
        )
        .unwrap();
        assert_eq!(config.scope, anchor.scope);
        assert_eq!(config.dynamic_config_url, MIRROR_B);
        assert_eq!(config.passed_over.len(), 1);
        assert_eq!(
            config.servers[0].base_url,
            "https://wallet-pir.valargroup.dev"
        );
        assert_eq!(
            config.selection_state,
            ApiWalletPirSelectionState::Defaulted
        );
        assert_eq!(
            config.selected_base_url.as_deref(),
            Some("https://wallet-pir.valargroup.dev")
        );
    }

    #[test]
    fn an_empty_list_selects_nothing() {
        let config = load(dynamic(serde_json::json!([])), None);
        assert_eq!(
            config.selection_state,
            ApiWalletPirSelectionState::NoServers
        );
        assert_eq!(config.selected_base_url, None);
        assert_eq!(config.selection_json, None);
    }

    #[test]
    fn reorder_and_relabel_keep_the_choice_and_removal_requires_a_new_one() {
        let first = load(two_servers(), None);
        let (source, _) = source_and_bytes();
        let chosen = select_wallet_pir_server(
            source,
            "mainnet".into(),
            first.snapshot_json.clone(),
            "https://backup.example/pir/".into(),
        )
        .unwrap();

        let reordered = load(
            dynamic(serde_json::json!([
                {"label": "Renamed backup", "url": "https://backup.example/pir"},
                {"label": "Valar", "url": "https://wallet-pir.valargroup.dev"},
            ])),
            Some(chosen.clone()),
        );
        assert_eq!(reordered.selection_state, ApiWalletPirSelectionState::Kept);
        assert_eq!(
            reordered.selected_base_url.as_deref(),
            Some("https://backup.example/pir")
        );

        let removed = load(
            dynamic(serde_json::json!([
                {"label": "Valar", "url": "https://wallet-pir.valargroup.dev"},
            ])),
            Some(chosen),
        );
        assert_eq!(
            removed.selection_state,
            ApiWalletPirSelectionState::SelectionRequired
        );
        assert_eq!(removed.selected_base_url, None);
        assert_eq!(
            removed.removed_base_url.as_deref(),
            Some("https://backup.example/pir")
        );
    }

    #[test]
    fn a_snapshot_revalidates_only_under_its_own_source() {
        let first = load(two_servers(), None);
        let (source, _) = source_and_bytes();
        let reloaded = resolve_wallet_pir_config_snapshot(
            source,
            "mainnet".into(),
            first.snapshot_json.clone(),
            first.selection_json.clone(),
        )
        .unwrap();
        assert_eq!(reloaded.selection_state, ApiWalletPirSelectionState::Kept);

        let other_source = format!(
            "https://valargroup.github.io/wallet-pir-config/pins/stage/static.json?checksum=sha256:{}",
            "0".repeat(64)
        );
        assert!(resolve_wallet_pir_config_snapshot(
            other_source,
            "mainnet".into(),
            first.snapshot_json,
            None,
        )
        .is_err());
    }

    #[test]
    fn an_unadvertised_server_cannot_be_chosen() {
        let first = load(two_servers(), None);
        let (source, _) = source_and_bytes();
        assert!(select_wallet_pir_server(
            source,
            "mainnet".into(),
            first.snapshot_json,
            "https://elsewhere.example".into(),
        )
        .is_err());
    }

    #[test]
    fn an_invalid_mirror_document_does_not_resolve() {
        let (source, bytes) = source_and_bytes();
        assert!(resolve_wallet_pir_config(
            source,
            "mainnet".into(),
            bytes,
            vec![fetched(MIRROR_A, b"{".to_vec())],
            None,
        )
        .is_err());
    }

    #[test]
    fn a_failed_cleanup_leaves_no_server_and_retry_runs_it_again() {
        let selection = SelectedServer::new();
        apply_server(&selection, Some("https://a.example"), || Ok(())).unwrap();
        assert!(apply_server(&selection, Some("https://b.example"), || {
            Err("cleanup failed".into())
        })
        .is_err());
        assert_eq!(selection.base(), None);
        assert!(selection.cleanup_pending());
        let mut retried = false;
        apply_server(&selection, Some("https://b.example"), || {
            retried = true;
            Ok(())
        })
        .unwrap();
        assert!(retried);
        assert_eq!(selection.base().as_deref(), Some("https://b.example"));
        assert!(!selection.cleanup_pending());
    }

    #[test]
    fn an_invalid_server_changes_nothing() {
        let selection = SelectedServer::new();
        assert_eq!(
            apply_server(&selection, Some("https://a.example"), || Ok(())),
            Ok(true)
        );
        assert!(apply_server(&selection, Some("http://a.example"), || {
            panic!("cleanup ran for an invalid server")
        })
        .is_err());
        assert_eq!(selection.base().as_deref(), Some("https://a.example"));
    }
}
