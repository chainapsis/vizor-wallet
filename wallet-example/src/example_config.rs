use std::fs;
use std::io::ErrorKind;
use std::path::Path;

use anyhow::{anyhow, Context, Result};
use bytes::Bytes;
use http::{Method, Request};
use http_body_util::{BodyExt, Full};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};
use serde::{Deserialize, Serialize};
use zcash_voting::config::{
    decide_config_switch, resolve_dynamic_voting_config, resolve_static_voting_config,
    AuthenticatedRound, PinnedConfigSource,
};
use zcash_voting::wire::{
    ConfigSwitchDecision, ResolveVotingConfigOptions, ResolvedVotingConfig,
    ResolvedVotingConfigSummary,
};

type RequestBody = Full<Bytes>;
type HyperClient = Client<HttpsConnector<HttpConnector>, RequestBody>;

/// Persisted config summary used to classify the next config switch.
///
/// Wallets store this between runs so [`resolve_config_switch`] can compare the
/// previously resolved service identity against a freshly resolved config. Only
/// the stable switch-relevant fields are kept; the static source is
/// intentionally excluded because a new URL or hash pin can resolve to the same
/// operational service.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct StoredConfigState {
    pub summary: ResolvedVotingConfigSummary,
    pub dynamic_config_fingerprint: String,
    pub authenticated_rounds: Vec<AuthenticatedRound>,
}

impl StoredConfigState {
    /// Captures the switch-relevant state of a freshly resolved config.
    pub fn from_resolved(resolved: &ResolvedVotingConfig) -> Self {
        Self {
            summary: ResolvedVotingConfigSummary::from(resolved),
            dynamic_config_fingerprint: resolved.dynamic_config_fingerprint.clone(),
            authenticated_rounds: resolved.authenticated_rounds.clone(),
        }
    }
}

/// A resolved config paired with its switch classification and next state.
///
/// `decision` describes how much wallet state the move from `previous` should
/// invalidate. `next_state` is the value the caller should persist for the
/// following resolution.
pub struct ConfigSwitchOutcome {
    pub resolved: ResolvedVotingConfig,
    pub decision: ConfigSwitchDecision,
    pub next_state: StoredConfigState,
}

/// Builds trusted round params from resolved config and server round metadata.
///
/// This is the intended session-path usage of
/// [`ResolvedVotingConfig::trusted_voting_round_params`]: use server-provided
/// dynamic fields (`snapshot_height`, roots), but always bind `ea_pk` from the
/// authenticated dynamic config embedded in `resolved`.
///
/// # Errors
///
/// Returns an error if the requested round is not authenticated in
/// `resolved` or if any binary field has an invalid length.
pub fn build_trusted_round_params_from_status(
    resolved: &ResolvedVotingConfig,
    round_id: String,
    snapshot_height: u64,
    nc_root: Vec<u8>,
    nullifier_imt_root: Vec<u8>,
) -> Result<zcash_voting::wire::VotingRoundParams> {
    resolved
        .trusted_voting_round_params(round_id, snapshot_height, nc_root, nullifier_imt_root)
        .map_err(|e| anyhow!("build trusted round params failed: {e}"))
}

/// Resolves and authenticates voting config from a static source URL.
///
/// This fetches the static trust anchor with the example HTTPS transport and
/// resolves it via [`resolve_static_voting_config`], learns the dynamic config
/// URL it points at, fetches that too, and then resolves it via
/// [`resolve_dynamic_voting_config`]. During resolution, round entries are
/// authenticated against the trusted static keys before `ResolvedVotingConfig`
/// is returned. Transport and config errors are flattened into one `anyhow`
/// chain so example callers can surface a single message.
///
/// # Errors
///
/// Returns an error if either fetch fails, the static hash pin does not match,
/// the config bytes fail to decode, or round signatures/versions are invalid.
pub async fn resolve_voting_config_over_https(
    fetcher: &DirectHttpsFetcher,
    source: &str,
) -> Result<ResolvedVotingConfig> {
    // The hash-pin checksum lives in the source query but is not part of the
    // fetch URL, so resolve it once to learn where to GET the static bytes.
    let static_url = PinnedConfigSource::parse(source)
        .map_err(|e| anyhow!("parse static config source failed: {e}"))?
        .url;
    let static_bytes = fetcher.fetch_bytes(&static_url).await?;
    let resolved_static = resolve_static_voting_config(source, &static_bytes)
        .map_err(|e| anyhow!("resolve static config failed: {e}"))?;
    let dynamic_bytes = fetcher
        .fetch_bytes(&resolved_static.dynamic_config_url)
        .await?;
    resolve_dynamic_voting_config(
        resolved_static,
        &dynamic_bytes,
        ResolveVotingConfigOptions::default(),
    )
    .map_err(|e| anyhow!("resolve voting config failed: {e}"))
}

/// Resolves config and classifies the switch against previously stored state.
///
/// Pass the `previous` state loaded with [`read_config_state`] (or `None` on
/// first run). The returned `next_state` should be persisted with
/// [`write_config_state`] so the following call can classify its own switch.
///
/// # Errors
///
/// Returns an error if resolution fails for any of the reasons listed on
/// [`resolve_voting_config_over_https`].
pub async fn resolve_config_switch(
    fetcher: &DirectHttpsFetcher,
    source: &str,
    previous: Option<StoredConfigState>,
) -> Result<ConfigSwitchOutcome> {
    let resolved = resolve_voting_config_over_https(fetcher, source).await?;
    let next_state = StoredConfigState::from_resolved(&resolved);
    let decision = decide_config_switch(
        previous.map(|state| state.summary),
        next_state.summary.clone(),
    );

    Ok(ConfigSwitchOutcome {
        resolved,
        decision,
        next_state,
    })
}

/// Loads previously persisted config state, if any.
///
/// A missing file is treated as "no prior state" so the first run reports an
/// initial load rather than an error.
///
/// # Errors
///
/// Returns an error if the file exists but cannot be read or decoded.
pub fn read_config_state(state_path: &Path) -> Result<Option<StoredConfigState>> {
    match fs::read(state_path) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .with_context(|| format!("decode {}", state_path.display()))
            .map(Some),
        Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e).with_context(|| format!("read {}", state_path.display())),
    }
}

/// Persists config state for use in the next switch decision.
///
/// # Errors
///
/// Returns an error if the state cannot be serialized or written to disk.
pub fn write_config_state(state_path: &Path, state: &StoredConfigState) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(state).context("encode config state")?;
    fs::write(state_path, bytes).with_context(|| format!("write {}", state_path.display()))
}

/// A minimal direct-HTTPS transport for config fetching.
///
/// Config resolution is transport-agnostic: the crate parses and authenticates
/// bytes the wallet supplies. This fetcher is the reference transport for Rust
/// consumers that do not need a custom client. Production wallets should plug in
/// their own networking stack and feed the response bytes back to
/// [`resolve_voting_config_over_https`].
pub struct DirectHttpsFetcher {
    client: HyperClient,
}

impl Default for DirectHttpsFetcher {
    fn default() -> Self {
        Self::new()
    }
}

impl DirectHttpsFetcher {
    /// Builds an HTTPS-only client that trusts the bundled webpki roots.
    pub fn new() -> Self {
        let mut connector = HttpConnector::new();
        connector.enforce_http(false);
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_only()
            .enable_http1()
            .enable_http2()
            .wrap_connector(connector);
        let client = Client::builder(TokioExecutor::new()).build(https);
        Self { client }
    }

    /// Fetches the body bytes at `url`, sending no-cache request headers.
    ///
    /// # Errors
    ///
    /// Returns an error if the request cannot be built or sent, the response
    /// status is not success, or the body cannot be read.
    pub async fn fetch_bytes(&self, url: &str) -> Result<Vec<u8>> {
        let request = Request::builder()
            .method(Method::GET)
            .uri(url)
            .header("Cache-Control", "no-cache")
            .header("Pragma", "no-cache")
            .body(Full::new(Bytes::new()))
            .context("build config request")?;
        let response = self
            .client
            .request(request)
            .await
            .context("send config request")?;
        if !response.status().is_success() {
            return Err(anyhow!("config fetch returned HTTP {}", response.status()));
        }
        Ok(response
            .into_body()
            .collect()
            .await
            .context("read config response body")?
            .to_bytes()
            .to_vec())
    }
}
