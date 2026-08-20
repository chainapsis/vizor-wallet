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
    decide_config_switch, resolve_dynamic_voting_config_over_mirrors, resolve_static_voting_config,
    AuthenticatedRound, PinnedConfigSource, DYNAMIC_MIRROR_FETCH_TIMEOUT,
};
use zcash_voting::wire::{
    ConfigSwitchDecision, DynamicConfigMirrorFailure, ResolveVotingConfigOptions,
    ResolvedVotingConfig, ResolvedVotingConfigSummary,
};
use zcash_voting::{connect_pir_blocking, HyperTransport, PirClientBlocking};

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
    /// Dynamic config mirrors passed over before one resolved, in order.
    pub skipped_config_urls: Vec<DynamicConfigMirrorFailure>,
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

/// A resolved config plus the dynamic mirrors that were passed over.
pub struct ResolvedWithMirrorReport {
    pub resolved: ResolvedVotingConfig,
    pub skipped_config_urls: Vec<DynamicConfigMirrorFailure>,
}

/// Resolves and authenticates voting config from a static source URL.
///
/// This fetches the static trust anchor with the example HTTPS transport and
/// resolves it via [`resolve_static_voting_config`], then walks the ordered
/// `dynamic_config_urls` it names via
/// [`resolve_dynamic_voting_config_over_mirrors`]. A v1 static config names
/// exactly one mirror, so it behaves exactly as before; a v2 static config
/// falls through to the next mirror when one is unavailable or times out.
///
/// Each mirror attempt is bounded by [`DYNAMIC_MIRROR_FETCH_TIMEOUT`]. Mirrors
/// are fetched lazily and the walk stops at the first that resolves with
/// authenticated rounds, so a healthy primary costs exactly one request.
/// Transport and config errors are flattened into one `anyhow` chain so example
/// callers can surface a single message.
///
/// # Errors
///
/// Returns an error if the static fetch fails, the static hash pin does not
/// match, the static bytes fail to decode, or every dynamic mirror fails.
pub async fn resolve_voting_config_over_https(
    fetcher: &DirectHttpsFetcher,
    source: &str,
) -> Result<ResolvedWithMirrorReport> {
    // The hash-pin checksum lives in the source query but is not part of the
    // fetch URL, so resolve it once to learn where to GET the static bytes.
    let static_url = PinnedConfigSource::parse(source)
        .map_err(|e| anyhow!("parse static config source failed: {e}"))?
        .url;
    let static_bytes = fetcher.fetch_bytes(&static_url).await?;
    let resolved_static = resolve_static_voting_config(source, &static_bytes)
        .map_err(|e| anyhow!("resolve static config failed: {e}"))?;

    // Bound each mirror attempt so a blackholed primary cannot strand a healthy
    // later mirror. Preference rules (including round-less deprioritization)
    // live in the shared walk helper.
    let (resolved, skipped_config_urls) = resolve_dynamic_voting_config_over_mirrors(
        resolved_static,
        DYNAMIC_MIRROR_FETCH_TIMEOUT,
        ResolveVotingConfigOptions::default(),
        |url| async move {
            fetcher
                .fetch_bytes(&url)
                .await
                .map_err(|e| format!("{e:#}"))
        },
    )
    .await
    .map_err(|e| anyhow!("resolve voting config failed: {e}"))?;
    Ok(ResolvedWithMirrorReport {
        resolved,
        skipped_config_urls,
    })
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
    let report = resolve_voting_config_over_https(fetcher, source).await?;
    let next_state = StoredConfigState::from_resolved(&report.resolved);
    let decision = decide_config_switch(
        previous.map(|state| state.summary),
        next_state.summary.clone(),
    );

    Ok(ConfigSwitchOutcome {
        resolved: report.resolved,
        decision,
        next_state,
        skipped_config_urls: report.skipped_config_urls,
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

/// Connects a blocking PIR client using the resolved dynamic config's layout.
///
/// Threads `resolved.pir_layout` and the caller-chosen `pir_server_url` into the
/// PIR handshake so example callers never hardcode depth, tier-split, or YPIR
/// degree constants. Endpoint selection (advertised list / snapshot probing) is the
/// caller's responsibility.
///
/// # Errors
///
/// Returns an error if the layout handshake fails or the transport cannot
/// complete client construction.
pub fn connect_pir_from_resolved(
    resolved: &ResolvedVotingConfig,
    pir_server_url: &str,
) -> Result<PirClientBlocking> {
    connect_pir_blocking(
        resolved.pir_layout,
        pir_server_url,
        std::sync::Arc::new(HyperTransport::new()),
    )
    .map_err(|e| anyhow!("connect PIR from resolved config failed: {e}"))
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
