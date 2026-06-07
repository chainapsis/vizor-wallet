//! Voting service config resolution.
//!
//! Wallets choose the static config source and fetch bytes using their own
//! transport. This module authenticates and normalizes those bytes, then
//! returns a resolved config and explicit switch plan for wallet state.
//!
//! ```text
//!     ┌──────────────┐
//!     │Wallet chooses│
//!     │static source │
//!     └──────┬───────┘
//!            │ fetch bytes with wallet transport
//!            ▼
//!     ┌──────────────┐      hash mismatch
//!     │Resolve static├──────────────────────┐
//!     │    config    │                      │
//!     └──────┬───────┘                      ▼
//!            │ dynamic_config_url     .───────────────.
//!            ▼                       ( Remote auth    )
//!     ┌──────────────┐                ( failed        )
//!     │Wallet fetches│                 `───────────────'
//!     │dynamic bytes │
//!     └──────┬───────┘
//!            ▼
//!     ┌──────────────┐
//!     │Resolve voting│
//!     │    config    │
//!     └──────┬───────┘
//!            │
//!            ▼
//!     ┌──────────────┐      bad signature
//!     │Authenticate  ├──────────────────────┐
//!     │ round entries│                      │
//!     └──────┬───────┘                      ▼
//!            │                       .───────────────.
//!            │ unsupported version  ( Config error   )
//!            ├─────────────────────> `───────────────'
//!            ▼
//!     ┌──────────────┐
//!     │Plan config   │
//!     │   switch     │
//!     └──────┬───────┘
//!            ▼
//!     ┌──────────────┐
//!     │Wallet applies│
//!     │ invalidation │
//!     └──────────────┘
//! ```
//!
//! The intended integration boundary is:
//!
//! - platform code owns URL choice and network transport;
//! - [`resolve_static_voting_config`] authenticates the static trust anchor and
//!   exposes the `dynamic_config_url` to fetch next;
//! - [`resolve_dynamic_voting_config`] takes that resolved static config plus
//!   the dynamic config bytes and returns a [`ResolvedVotingConfig`];
//! - [`decide_config_switch`] classifies the config change so the wallet can
//!   choose the correct state transition.
//!
use std::collections::BTreeMap;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::types::validate_vote_round_id_hex;

const STATIC_CONFIG_VERSION: u32 = 1;
const DYNAMIC_CONFIG_VERSION: u32 = 1;
const ROUND_AUTH_VERSION_V1: u32 = 1;
const ALG_ED25519: &str = "ed25519";
const CHECKSUM_QUERY_NAME: &str = "checksum";
const SHA256_CHECKSUM_PREFIX: &str = "sha256:";
const VERSION_V0: &str = "v0";
const VOTE_SERVER_VERSION_V1: &str = "v1";
const ROUND_PARAM_BYTE_LEN: usize = 32;

/// Versions of each voting-protocol component implemented by this crate.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WalletCapabilities {
    pub vote_server: Vec<String>,
    pub vote_protocol: Vec<String>,
    pub tally: Vec<String>,
    pub pir: Vec<String>,
}

impl Default for WalletCapabilities {
    fn default() -> Self {
        Self {
            vote_server: vec![VOTE_SERVER_VERSION_V1.to_string()],
            vote_protocol: vec![VERSION_V0.to_string()],
            tally: vec![VERSION_V0.to_string()],
            pir: vec![VERSION_V0.to_string()],
        }
    }
}

/// Options that control voting config resolution.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolveVotingConfigOptions {
    pub capabilities: WalletCapabilities,
}

/// Parsed static-config source chosen by the embedding wallet.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinnedConfigSource {
    pub raw: String,
    pub url: String,
    pub sha256: Option<String>,
}

/// Endpoint advertised by a voting service config.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServiceEndpoint {
    pub url: String,
    pub label: String,
}

/// Protocol component versions advertised by the dynamic config.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SupportedVersions {
    pub pir: Vec<String>,
    pub vote_protocol: String,
    pub tally: String,
    pub vote_server: String,
}

/// Resolved and authenticated static voting config.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedStaticVotingConfig {
    pub source: PinnedConfigSource,
    pub source_fingerprint: String,
    pub trusted_key_fingerprint: String,
    pub dynamic_config_url: String,
    trusted_keys: Vec<TrustedKey>,
}

/// Resolved dynamic voting config, ready for wallet use.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedVotingConfig {
    pub source_fingerprint: String,
    pub trusted_key_fingerprint: String,
    pub dynamic_config_fingerprint: String,
    pub vote_servers: Vec<ServiceEndpoint>,
    pub pir_endpoints: Vec<ServiceEndpoint>,
    pub supported_versions: SupportedVersions,
    pub authenticated_rounds: Vec<AuthenticatedRound>,
    pub skipped_round_ids: Vec<String>,
    pub conditions: Vec<ConfigCondition>,
}

/// Dynamic round metadata authenticated by trusted static keys.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthenticatedRound {
    pub round_id: String,
    #[serde(with = "base64_bytes")]
    pub ea_pk: Vec<u8>,
}

impl ResolvedVotingConfig {
    /// Build round params from server metadata while binding trusted `ea_pk`.
    ///
    /// Dynamic server fields (`snapshot_height`, roots) are accepted as inputs,
    /// but `ea_pk` is always sourced from authenticated dynamic config material.
    pub fn trusted_voting_round_params(
        &self,
        round_id: String,
        snapshot_height: u64,
        nc_root: Vec<u8>,
        nullifier_imt_root: Vec<u8>,
    ) -> Result<crate::wire::VotingRoundParams, VotingConfigError> {
        if nc_root.len() != ROUND_PARAM_BYTE_LEN {
            return Err(VotingConfigError::InvalidInput {
                message: format!("nc_root must be exactly {ROUND_PARAM_BYTE_LEN} bytes"),
            });
        }
        if nullifier_imt_root.len() != ROUND_PARAM_BYTE_LEN {
            return Err(VotingConfigError::InvalidInput {
                message: format!("nullifier_imt_root must be exactly {ROUND_PARAM_BYTE_LEN} bytes"),
            });
        }

        let trusted_round = self
            .authenticated_rounds
            .iter()
            .find(|round| round.round_id == round_id)
            .ok_or_else(|| VotingConfigError::RemoteAuthenticationFailed {
                message: format!("round {round_id} is not authenticated in resolved voting config"),
            })?;
        if trusted_round.ea_pk.len() != ROUND_PARAM_BYTE_LEN {
            return Err(VotingConfigError::InvalidInput {
                message: format!(
                    "authenticated round {round_id} has invalid ea_pk length: expected {ROUND_PARAM_BYTE_LEN} bytes"
                ),
            });
        }

        Ok(crate::wire::VotingRoundParams {
            vote_round_id: round_id,
            snapshot_height,
            ea_pk: trusted_round.ea_pk.clone(),
            nc_root,
            nullifier_imt_root,
        })
    }
}

/// Structured status emitted while resolving a voting config.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConfigCondition {
    pub kind: ConfigConditionKind,
    pub status: bool,
    pub message: String,
}

/// Machine-readable condition categories for config resolution.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConfigConditionKind {
    StaticHashPinVerified,
    StaticConfigDecoded,
    DynamicConfigDecoded,
    DynamicSignaturesVerified,
    VersionsSupported,
}

/// Small, stable summary used to decide how much state a config switch
/// invalidates.
///
/// The static source fingerprint is intentionally absent. A new static URL or
/// hash pin can resolve to the same operational service. Switching wallet state
/// should be driven by the resolved service identity below, not by where the
/// wallet fetched the trust anchor from.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedVotingConfigSummary {
    pub trusted_key_fingerprint: String,
    pub vote_server_fingerprint: String,
    pub pir_endpoint_fingerprint: String,
    pub authenticated_round_set_fingerprint: String,
    pub protocol_versions: SupportedVersions,
}

impl From<&ResolvedVotingConfig> for ResolvedVotingConfigSummary {
    fn from(config: &ResolvedVotingConfig) -> Self {
        let authenticated_round_ids = config
            .authenticated_rounds
            .iter()
            .map(|round| round.round_id.clone())
            .collect::<Vec<_>>();
        Self {
            trusted_key_fingerprint: config.trusted_key_fingerprint.clone(),
            vote_server_fingerprint: fingerprint_json(&config.vote_servers),
            pir_endpoint_fingerprint: fingerprint_json(&config.pir_endpoints),
            authenticated_round_set_fingerprint: fingerprint_json(&authenticated_round_ids),
            protocol_versions: config.supported_versions.clone(),
        }
    }
}

/// Semantic decision for moving between resolved configs.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConfigSwitchDecision {
    pub kind: ConfigSwitchKind,
}

/// High-level meaning of a resolved config switch.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConfigSwitchKind {
    /// The resolved config summary is unchanged.
    Unchanged,
    /// There was no prior resolved config summary.
    InitialLoad,
    /// Same authenticated round set and protocol tuple, but endpoint or
    /// trusted-signing-key material changed.
    ///
    /// Wallets should restart endpoint caches, status polls, share tracking,
    /// and PIR/delegation precompute. They should keep round-id-indexed wallet
    /// artifacts.
    SameChainServiceUpdate,
    /// The authenticated round set changed.
    ///
    /// Wallets should treat this as moving to a new chain/round context for
    /// active UI and in-flight work. Durable state for old round ids can remain
    /// indexed by round id, but the current visible round context should be
    /// discarded or reselected from the reloaded authenticated round list.
    NewChainOrRound,
    /// The resolved protocol-version tuple changed.
    ///
    /// Wallets should stop using cached voting state until compatibility is
    /// re-established.
    ProtocolChanged,
}

/// Errors from voting config parsing, authentication, and compatibility checks.
#[derive(Clone, Debug, Error, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum VotingConfigError {
    #[error("invalid input: {message}")]
    InvalidInput { message: String },
    #[error("decode failed: {message}")]
    DecodeFailed { message: String },
    #[error("unsupported version for {component}: {advertised}")]
    UnsupportedVersion {
        component: String,
        advertised: String,
    },
    #[error("remote authentication failed: {message}")]
    RemoteAuthenticationFailed { message: String },
}

/// Parse and authenticate the static config bytes selected by the wallet.
pub fn resolve_static_voting_config(
    source: &str,
    static_config_bytes: &[u8],
) -> Result<ResolvedStaticVotingConfig, VotingConfigError> {
    let source = PinnedConfigSource::parse(source)?;
    if let Some(expected_hex) = &source.sha256 {
        let actual = Sha256::digest(static_config_bytes);
        let actual_hex = hex::encode(actual);
        if actual_hex != *expected_hex {
            return Err(VotingConfigError::RemoteAuthenticationFailed {
                message: format!(
                    "static config hash-pin mismatch: expected {}, got {}",
                    expected_hex, actual_hex
                ),
            });
        }
    }

    let static_config: WireStaticVotingConfig = serde_json::from_slice(static_config_bytes)
        .map_err(|e| VotingConfigError::DecodeFailed {
            message: format!("static config decode failed: {e}"),
        })?;
    validate_static_config(&static_config)?;

    Ok(ResolvedStaticVotingConfig {
        source_fingerprint: source.fingerprint(),
        trusted_key_fingerprint: fingerprint_json(&static_config.trusted_keys),
        source,
        dynamic_config_url: static_config.dynamic_config_url,
        trusted_keys: static_config.trusted_keys,
    })
}

/// Resolve and authenticate the dynamic voting config from supplied bytes.
///
/// The static trust anchor must already be resolved through a separate
/// [`resolve_static_voting_config`] call. Given that authenticated static config
/// and the dynamic config bytes the wallet fetched from
/// `resolved_static.dynamic_config_url`, this validates advertised versions and
/// authenticates round entries against the static trusted keys.
pub fn resolve_dynamic_voting_config(
    resolved_static: ResolvedStaticVotingConfig,
    dynamic_bytes: &[u8],
    options: ResolveVotingConfigOptions,
) -> Result<ResolvedVotingConfig, VotingConfigError> {
    let dynamic_config: WireVotingServiceConfig =
        serde_json::from_slice(dynamic_bytes).map_err(|e| VotingConfigError::DecodeFailed {
            message: format!("dynamic config decode failed: {e}"),
        })?;
    validate_dynamic_config(&dynamic_config, &options.capabilities)?;
    let authenticated_rounds =
        authenticate_dynamic_rounds(&dynamic_config.rounds, &resolved_static.trusted_keys);

    let authenticated_count = authenticated_rounds.authenticated_rounds.len();
    let skipped_count = authenticated_rounds.skipped_round_ids.len();

    Ok(ResolvedVotingConfig {
        source_fingerprint: resolved_static.source_fingerprint,
        trusted_key_fingerprint: resolved_static.trusted_key_fingerprint,
        dynamic_config_fingerprint: fingerprint_bytes(dynamic_bytes),
        vote_servers: dynamic_config.vote_servers,
        pir_endpoints: dynamic_config.pir_endpoints,
        supported_versions: dynamic_config.supported_versions,
        authenticated_rounds: authenticated_rounds.authenticated_rounds,
        skipped_round_ids: authenticated_rounds.skipped_round_ids.clone(),
        conditions: vec![
            ConfigCondition {
                kind: ConfigConditionKind::StaticHashPinVerified,
                status: true,
                message: "static hash pin verified".to_string(),
            },
            ConfigCondition {
                kind: ConfigConditionKind::DynamicConfigDecoded,
                status: true,
                message: "dynamic config decoded".to_string(),
            },
            ConfigCondition {
                kind: ConfigConditionKind::DynamicSignaturesVerified,
                status: true,
                message: format!(
                    "dynamic round signatures verified: authenticated={}, skipped={}",
                    authenticated_count, skipped_count
                ),
            },
            ConfigCondition {
                kind: ConfigConditionKind::VersionsSupported,
                status: true,
                message: "advertised versions are supported".to_string(),
            },
        ],
    })
}

/// Classify the wallet transition required to switch to `next`.
pub fn decide_config_switch(
    current: Option<ResolvedVotingConfigSummary>,
    next: ResolvedVotingConfigSummary,
) -> ConfigSwitchDecision {
    let Some(current) = current else {
        return ConfigSwitchDecision {
            kind: ConfigSwitchKind::InitialLoad,
        };
    };

    let kind = if current.protocol_versions != next.protocol_versions {
        ConfigSwitchKind::ProtocolChanged
    } else if current.authenticated_round_set_fingerprint
        != next.authenticated_round_set_fingerprint
    {
        ConfigSwitchKind::NewChainOrRound
    } else if current.trusted_key_fingerprint != next.trusted_key_fingerprint
        || current.vote_server_fingerprint != next.vote_server_fingerprint
        || current.pir_endpoint_fingerprint != next.pir_endpoint_fingerprint
    {
        ConfigSwitchKind::SameChainServiceUpdate
    } else {
        ConfigSwitchKind::Unchanged
    };

    ConfigSwitchDecision { kind }
}

impl PinnedConfigSource {
    /// Parse an HTTPS static-config source with an optional
    /// `checksum=sha256:{hex}` query item.
    pub fn parse(raw: &str) -> Result<Self, VotingConfigError> {
        let trimmed = raw.trim();
        validate_https_url(trimmed, "static config source")?;

        let (base, query) = match trimmed.split_once('?') {
            Some((base, query)) => (base, Some(query)),
            None => (trimmed, None),
        };
        let mut kept_query_items = Vec::new();
        let mut sha256 = None;

        if let Some(query) = query {
            for item in query.split('&').filter(|s| !s.is_empty()) {
                let (name, value) = item.split_once('=').unwrap_or((item, ""));
                if name == CHECKSUM_QUERY_NAME {
                    let hex = value.strip_prefix(SHA256_CHECKSUM_PREFIX).ok_or_else(|| {
                        VotingConfigError::InvalidInput {
                            message: "checksum must start with sha256:".to_string(),
                        }
                    })?;
                    validate_lowercase_hex_32(hex, "sha256")?;
                    sha256 = Some(hex.to_string());
                } else {
                    kept_query_items.push(item);
                }
            }
        }

        let url = if kept_query_items.is_empty() {
            base.to_string()
        } else {
            format!("{}?{}", base, kept_query_items.join("&"))
        };

        Ok(Self {
            raw: trimmed.to_string(),
            url,
            sha256,
        })
    }

    /// Stable fingerprint for comparing config sources across runs.
    pub fn fingerprint(&self) -> String {
        fingerprint_json(self)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
struct WireStaticVotingConfig {
    static_config_version: u32,
    dynamic_config_url: String,
    trusted_keys: Vec<TrustedKey>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
struct TrustedKey {
    key_id: String,
    alg: String,
    #[serde(with = "base64_bytes")]
    pubkey: Vec<u8>,
    notes: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
struct WireVotingServiceConfig {
    config_version: u32,
    vote_servers: Vec<ServiceEndpoint>,
    pir_endpoints: Vec<ServiceEndpoint>,
    supported_versions: SupportedVersions,
    rounds: BTreeMap<String, RoundEntry>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
struct RoundEntry {
    auth_version: u32,
    #[serde(with = "base64_bytes")]
    ea_pk: Vec<u8>,
    signatures: Vec<RoundSignature>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
struct RoundSignature {
    key_id: String,
    alg: String,
    #[serde(with = "base64_bytes")]
    sig: Vec<u8>,
}

fn validate_static_config(config: &WireStaticVotingConfig) -> Result<(), VotingConfigError> {
    if config.static_config_version != STATIC_CONFIG_VERSION {
        return Err(VotingConfigError::DecodeFailed {
            message: format!(
                "unsupported static_config_version {}",
                config.static_config_version
            ),
        });
    }
    validate_https_url(&config.dynamic_config_url, "dynamic_config_url")?;
    if config.trusted_keys.is_empty() {
        return Err(VotingConfigError::DecodeFailed {
            message: "trusted_keys must contain at least one entry".to_string(),
        });
    }
    for key in &config.trusted_keys {
        if key.alg != ALG_ED25519 {
            return Err(VotingConfigError::DecodeFailed {
                message: format!("trusted_keys[{}].alg unsupported: {}", key.key_id, key.alg),
            });
        }
        if key.pubkey.len() != 32 {
            return Err(VotingConfigError::DecodeFailed {
                message: format!(
                    "trusted_keys[{}].pubkey must decode to 32 bytes",
                    key.key_id
                ),
            });
        }
    }
    Ok(())
}

fn validate_dynamic_config(
    config: &WireVotingServiceConfig,
    capabilities: &WalletCapabilities,
) -> Result<(), VotingConfigError> {
    if config.config_version != DYNAMIC_CONFIG_VERSION {
        return Err(VotingConfigError::DecodeFailed {
            message: format!("unsupported config_version {}", config.config_version),
        });
    }
    validate_endpoints(&config.vote_servers, "vote_servers")?;
    validate_endpoints(&config.pir_endpoints, "pir_endpoints")?;
    for round_id in config.rounds.keys() {
        validate_vote_round_id_hex(round_id).map_err(|e| VotingConfigError::DecodeFailed {
            message: format!("invalid rounds key: {e}"),
        })?;
    }
    require_supported(
        "vote_server",
        &config.supported_versions.vote_server,
        &capabilities.vote_server,
    )?;
    require_supported(
        "vote_protocol",
        &config.supported_versions.vote_protocol,
        &capabilities.vote_protocol,
    )?;
    require_supported(
        "tally",
        &config.supported_versions.tally,
        &capabilities.tally,
    )?;
    if config
        .supported_versions
        .pir
        .iter()
        .all(|v| !capabilities.pir.contains(v))
    {
        return Err(VotingConfigError::UnsupportedVersion {
            component: "pir".to_string(),
            advertised: config.supported_versions.pir.join(","),
        });
    }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct AuthenticatedRounds {
    authenticated_rounds: Vec<AuthenticatedRound>,
    skipped_round_ids: Vec<String>,
}

fn authenticate_dynamic_rounds(
    rounds: &BTreeMap<String, RoundEntry>,
    trusted_keys: &[TrustedKey],
) -> AuthenticatedRounds {
    let mut authenticated_rounds = Vec::new();
    let mut skipped_round_ids = Vec::new();
    for (round_id, entry) in rounds {
        if !verify_round_entry(entry, trusted_keys) {
            skipped_round_ids.push(round_id.clone());
            continue;
        }
        authenticated_rounds.push(AuthenticatedRound {
            round_id: round_id.clone(),
            ea_pk: entry.ea_pk.clone(),
        });
    }
    AuthenticatedRounds {
        authenticated_rounds,
        skipped_round_ids,
    }
}

fn verify_round_entry(entry: &RoundEntry, trusted_keys: &[TrustedKey]) -> bool {
    if entry.auth_version != ROUND_AUTH_VERSION_V1
        || entry.ea_pk.len() != 32
        || entry.signatures.is_empty()
    {
        return false;
    }

    for signature in &entry.signatures {
        let Some(key) = trusted_keys
            .iter()
            .find(|key| key.key_id == signature.key_id)
        else {
            continue;
        };
        if key.alg != ALG_ED25519 || signature.alg != key.alg || signature.sig.len() != 64 {
            continue;
        }

        let Ok(pubkey_bytes) = <[u8; 32]>::try_from(key.pubkey.as_slice()) else {
            continue;
        };
        let Ok(sig_bytes) = <[u8; 64]>::try_from(signature.sig.as_slice()) else {
            continue;
        };
        let Ok(verifying_key) = VerifyingKey::from_bytes(&pubkey_bytes) else {
            continue;
        };
        let sig = Signature::from_bytes(&sig_bytes);
        if verifying_key.verify(&entry.ea_pk, &sig).is_ok() {
            return true;
        }
    }
    false
}

fn require_supported(
    component: &str,
    advertised: &str,
    supported: &[String],
) -> Result<(), VotingConfigError> {
    if supported.iter().any(|v| v == advertised) {
        Ok(())
    } else {
        Err(VotingConfigError::UnsupportedVersion {
            component: component.to_string(),
            advertised: advertised.to_string(),
        })
    }
}

fn validate_endpoints(endpoints: &[ServiceEndpoint], field: &str) -> Result<(), VotingConfigError> {
    if endpoints.is_empty() {
        return Err(VotingConfigError::DecodeFailed {
            message: format!("{field} must contain at least one entry"),
        });
    }
    for (index, endpoint) in endpoints.iter().enumerate() {
        validate_https_url(&endpoint.url, &format!("{field}[{index}].url"))?;
    }
    Ok(())
}

fn validate_https_url(value: &str, field: &str) -> Result<(), VotingConfigError> {
    let rest = value
        .strip_prefix("https://")
        .ok_or_else(|| VotingConfigError::InvalidInput {
            message: format!("{field} must use https"),
        })?;
    let host = rest.split(['/', '?', '#']).next().unwrap_or_default();
    if host.is_empty() || host.contains('@') {
        return Err(VotingConfigError::InvalidInput {
            message: format!("{field} must include a valid host"),
        });
    }
    Ok(())
}

fn validate_lowercase_hex_32(value: &str, field: &str) -> Result<(), VotingConfigError> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(VotingConfigError::InvalidInput {
            message: format!("{field} must be 64 lowercase hex characters"),
        });
    }
    Ok(())
}

fn fingerprint_json<T: Serialize>(value: &T) -> String {
    let bytes = serde_json::to_vec(value).expect("serialize fingerprint input");
    fingerprint_bytes(&bytes)
}

fn fingerprint_bytes(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

mod base64_bytes {
    use super::*;
    use serde::{Deserializer, Serializer};

    pub fn serialize<S>(bytes: &[u8], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&BASE64.encode(bytes))
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Vec<u8>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        BASE64.decode(value).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";
    const ROUND_ID_2: &str = "0000000000000000000000000000000000000000000000000000000000000002";

    fn source() -> String {
        "https://example.com/static.json".to_string()
    }

    fn static_bytes(signing_key: &SigningKey) -> Vec<u8> {
        let pubkey = signing_key.verifying_key().to_bytes();
        serde_json::json!({
            "static_config_version": 1,
            "dynamic_config_url": "https://example.com/dynamic.json",
            "trusted_keys": [{
                "key_id": "k1",
                "alg": "ed25519",
                "pubkey": BASE64.encode(pubkey),
                "notes": null
            }]
        })
        .to_string()
        .into_bytes()
    }

    fn dynamic_bytes_with_round_signers(round_signers: &[(&str, &SigningKey)]) -> Vec<u8> {
        let mut rounds = serde_json::Map::new();
        for (round_id, signing_key) in round_signers {
            let ea_pk = [7u8; 32];
            let sig = signing_key.sign(&ea_pk).to_bytes();
            rounds.insert(
                (*round_id).to_string(),
                serde_json::json!({
                    "auth_version": 1,
                    "ea_pk": BASE64.encode(ea_pk),
                    "signatures": [{
                        "key_id": "k1",
                        "alg": "ed25519",
                        "sig": BASE64.encode(sig)
                    }]
                }),
            );
        }
        serde_json::json!({
            "config_version": 1,
            "vote_servers": [{"url": "https://vote.example.com", "label": "vote"}],
            "pir_endpoints": [{"url": "https://pir.example.com", "label": "pir"}],
            "supported_versions": {
                "pir": ["v0"],
                "vote_protocol": "v0",
                "tally": "v0",
                "vote_server": "v1"
            },
            "rounds": rounds
        })
        .to_string()
        .into_bytes()
    }

    fn dynamic_bytes(signing_key: &SigningKey) -> Vec<u8> {
        dynamic_bytes_with_round_signers(&[(ROUND_ID, signing_key)])
    }

    #[test]
    fn static_resolution_verifies_hash_pin_and_exposes_dynamic_url() {
        let signing_key = SigningKey::from_bytes(&[3u8; 32]);
        let bytes = static_bytes(&signing_key);
        let hash = fingerprint_bytes(&bytes);
        let source = format!("{}?checksum=sha256:{}", source(), hash);

        let resolved = resolve_static_voting_config(&source, &bytes).unwrap();

        assert_eq!(
            resolved.dynamic_config_url,
            "https://example.com/dynamic.json"
        );
        assert_eq!(resolved.source.url, "https://example.com/static.json");
    }

    #[test]
    fn static_resolution_reports_remote_authentication_for_hash_mismatch() {
        let signing_key = SigningKey::from_bytes(&[3u8; 32]);
        let bytes = static_bytes(&signing_key);
        let source = format!("{}?checksum=sha256:{}", source(), "00".repeat(32));

        let err = resolve_static_voting_config(&source, &bytes).unwrap_err();

        assert!(matches!(
            err,
            VotingConfigError::RemoteAuthenticationFailed { .. }
        ));
        assert!(err.to_string().contains("remote authentication failed"));
    }

    #[test]
    fn dynamic_resolution_verifies_round_signatures() {
        let signing_key = SigningKey::from_bytes(&[3u8; 32]);
        let resolved_static =
            resolve_static_voting_config(&source(), &static_bytes(&signing_key)).unwrap();

        let resolved = resolve_dynamic_voting_config(
            resolved_static,
            &dynamic_bytes(&signing_key),
            ResolveVotingConfigOptions::default(),
        )
        .unwrap();

        assert_eq!(
            resolved.authenticated_rounds,
            vec![AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: vec![7u8; 32],
            }]
        );
        assert!(resolved.skipped_round_ids.is_empty());
    }

    #[test]
    fn dynamic_resolution_skips_rounds_with_bad_signature() {
        let trusted_key = SigningKey::from_bytes(&[3u8; 32]);
        let bad_key = SigningKey::from_bytes(&[4u8; 32]);
        let resolved_static =
            resolve_static_voting_config(&source(), &static_bytes(&trusted_key)).unwrap();

        let resolved = resolve_dynamic_voting_config(
            resolved_static,
            &dynamic_bytes(&bad_key),
            ResolveVotingConfigOptions::default(),
        )
        .unwrap();

        assert!(resolved.authenticated_rounds.is_empty());
        assert_eq!(resolved.skipped_round_ids, vec![ROUND_ID.to_string()]);
    }

    #[test]
    fn dynamic_resolution_partitions_authenticated_and_skipped_rounds() {
        let trusted_key = SigningKey::from_bytes(&[3u8; 32]);
        let bad_key = SigningKey::from_bytes(&[4u8; 32]);
        let resolved_static =
            resolve_static_voting_config(&source(), &static_bytes(&trusted_key)).unwrap();

        let resolved = resolve_dynamic_voting_config(
            resolved_static,
            &dynamic_bytes_with_round_signers(&[(ROUND_ID, &trusted_key), (ROUND_ID_2, &bad_key)]),
            ResolveVotingConfigOptions::default(),
        )
        .unwrap();

        assert_eq!(
            resolved.authenticated_rounds,
            vec![AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: vec![7u8; 32],
            }]
        );
        assert_eq!(resolved.skipped_round_ids, vec![ROUND_ID_2.to_string()]);
    }

    #[test]
    fn summary_fingerprint_ignores_skipped_round_ids() {
        let base = ResolvedVotingConfig {
            source_fingerprint: "src".to_string(),
            trusted_key_fingerprint: "keys".to_string(),
            dynamic_config_fingerprint: "dyn".to_string(),
            vote_servers: vec![ServiceEndpoint {
                url: "https://vote.example.com".to_string(),
                label: "vote".to_string(),
            }],
            pir_endpoints: vec![ServiceEndpoint {
                url: "https://pir.example.com".to_string(),
                label: "pir".to_string(),
            }],
            supported_versions: SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
            authenticated_rounds: vec![AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: vec![7u8; 32],
            }],
            skipped_round_ids: vec![ROUND_ID_2.to_string()],
            conditions: vec![],
        };
        let mut with_different_skips = base.clone();
        with_different_skips.skipped_round_ids = vec!["f".repeat(64)];

        let summary_base = ResolvedVotingConfigSummary::from(&base);
        let summary_with_different_skips = ResolvedVotingConfigSummary::from(&with_different_skips);
        assert_eq!(
            summary_base.authenticated_round_set_fingerprint,
            summary_with_different_skips.authenticated_round_set_fingerprint
        );
    }

    fn resolved_config_with_authenticated_round(ea_pk: Vec<u8>) -> ResolvedVotingConfig {
        ResolvedVotingConfig {
            source_fingerprint: "src".to_string(),
            trusted_key_fingerprint: "keys".to_string(),
            dynamic_config_fingerprint: "dyn".to_string(),
            vote_servers: vec![],
            pir_endpoints: vec![],
            supported_versions: SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
            authenticated_rounds: vec![AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk,
            }],
            skipped_round_ids: vec![],
            conditions: vec![],
        }
    }

    #[test]
    fn trusted_voting_round_params_uses_authenticated_ea_pk() {
        let config = resolved_config_with_authenticated_round(vec![7u8; 32]);

        let params = config
            .trusted_voting_round_params(ROUND_ID.to_string(), 123, vec![2u8; 32], vec![3u8; 32])
            .unwrap();

        assert_eq!(params.vote_round_id, ROUND_ID);
        assert_eq!(params.snapshot_height, 123);
        assert_eq!(params.ea_pk, vec![7u8; 32]);
        assert_eq!(params.nc_root, vec![2u8; 32]);
        assert_eq!(params.nullifier_imt_root, vec![3u8; 32]);
    }

    #[test]
    fn trusted_voting_round_params_rejects_unauthenticated_round() {
        let config = resolved_config_with_authenticated_round(vec![7u8; 32]);

        let err = config
            .trusted_voting_round_params("f".repeat(64), 123, vec![2u8; 32], vec![3u8; 32])
            .unwrap_err();
        assert!(matches!(
            err,
            VotingConfigError::RemoteAuthenticationFailed { .. }
        ));
    }

    #[test]
    fn trusted_voting_round_params_rejects_invalid_nc_root_length() {
        let config = resolved_config_with_authenticated_round(vec![7u8; 32]);

        let err = config
            .trusted_voting_round_params(ROUND_ID.to_string(), 123, vec![2u8; 31], vec![3u8; 32])
            .unwrap_err();

        assert!(matches!(err, VotingConfigError::InvalidInput { .. }));
        assert!(err.to_string().contains("nc_root must be exactly"));
    }

    #[test]
    fn trusted_voting_round_params_rejects_invalid_nullifier_imt_root_length() {
        let config = resolved_config_with_authenticated_round(vec![7u8; 32]);

        let err = config
            .trusted_voting_round_params(ROUND_ID.to_string(), 123, vec![2u8; 32], vec![3u8; 31])
            .unwrap_err();

        assert!(matches!(err, VotingConfigError::InvalidInput { .. }));
        assert!(err
            .to_string()
            .contains("nullifier_imt_root must be exactly"));
    }

    #[test]
    fn trusted_voting_round_params_rejects_invalid_authenticated_ea_pk_length() {
        let config = resolved_config_with_authenticated_round(vec![7u8; 31]);

        let err = config
            .trusted_voting_round_params(ROUND_ID.to_string(), 123, vec![2u8; 32], vec![3u8; 32])
            .unwrap_err();

        assert!(matches!(err, VotingConfigError::InvalidInput { .. }));
        assert!(err.to_string().contains("has invalid ea_pk length"));
    }

    #[test]
    fn resolve_dynamic_voting_config_resolves_dynamic_bytes() {
        let trusted_key = SigningKey::from_bytes(&[3u8; 32]);
        let static_config = static_bytes(&trusted_key);
        let source_url = format!(
            "{}?checksum=sha256:{}",
            source(),
            fingerprint_bytes(&static_config)
        );
        let dynamic_config = dynamic_bytes(&trusted_key);
        let resolved_static = resolve_static_voting_config(&source_url, &static_config).unwrap();

        let resolved = resolve_dynamic_voting_config(
            resolved_static,
            &dynamic_config,
            ResolveVotingConfigOptions::default(),
        )
        .unwrap();

        assert_eq!(
            resolved.authenticated_rounds,
            vec![AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: vec![7u8; 32],
            }]
        );
    }

    #[test]
    fn config_switch_for_pir_change_is_service_update() {
        let versions = SupportedVersions {
            pir: vec!["v0".to_string()],
            vote_protocol: "v0".to_string(),
            tally: "v0".to_string(),
            vote_server: "v1".to_string(),
        };
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "a".to_string(),
            vote_server_fingerprint: "b".to_string(),
            pir_endpoint_fingerprint: "c".to_string(),
            authenticated_round_set_fingerprint: "d".to_string(),
            protocol_versions: versions.clone(),
        };
        let mut next = current.clone();
        next.pir_endpoint_fingerprint = "changed".to_string();

        let decision = decide_config_switch(Some(current), next);

        assert_eq!(decision.kind, ConfigSwitchKind::SameChainServiceUpdate);
    }

    #[test]
    fn config_switch_for_round_set_change_is_new_chain_or_round() {
        let versions = SupportedVersions {
            pir: vec!["v0".to_string()],
            vote_protocol: "v0".to_string(),
            tally: "v0".to_string(),
            vote_server: "v1".to_string(),
        };
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "same-keys".to_string(),
            vote_server_fingerprint: "same-chain".to_string(),
            pir_endpoint_fingerprint: "same-pir".to_string(),
            authenticated_round_set_fingerprint: "rounds-a".to_string(),
            protocol_versions: versions.clone(),
        };
        let mut next = current.clone();
        next.authenticated_round_set_fingerprint = "rounds-b".to_string();

        let decision = decide_config_switch(Some(current), next);

        assert_eq!(decision.kind, ConfigSwitchKind::NewChainOrRound);
    }

    #[test]
    fn config_switch_for_vote_server_change_is_service_update() {
        let versions = SupportedVersions {
            pir: vec!["v0".to_string()],
            vote_protocol: "v0".to_string(),
            tally: "v0".to_string(),
            vote_server: "v1".to_string(),
        };
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "same-keys".to_string(),
            vote_server_fingerprint: "servers-a".to_string(),
            pir_endpoint_fingerprint: "same-pir".to_string(),
            authenticated_round_set_fingerprint: "same-rounds".to_string(),
            protocol_versions: versions.clone(),
        };
        let mut next = current.clone();
        next.vote_server_fingerprint = "servers-b".to_string();

        let decision = decide_config_switch(Some(current), next);

        assert_eq!(decision.kind, ConfigSwitchKind::SameChainServiceUpdate);
    }

    #[test]
    fn config_switch_for_trusted_key_change_is_service_update() {
        let versions = SupportedVersions {
            pir: vec!["v0".to_string()],
            vote_protocol: "v0".to_string(),
            tally: "v0".to_string(),
            vote_server: "v1".to_string(),
        };
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "keys-a".to_string(),
            vote_server_fingerprint: "same-servers".to_string(),
            pir_endpoint_fingerprint: "same-pir".to_string(),
            authenticated_round_set_fingerprint: "same-rounds".to_string(),
            protocol_versions: versions.clone(),
        };
        let mut next = current.clone();
        next.trusted_key_fingerprint = "keys-b".to_string();

        let decision = decide_config_switch(Some(current), next);

        assert_eq!(decision.kind, ConfigSwitchKind::SameChainServiceUpdate);
    }

    #[test]
    fn config_switch_for_protocol_change_wins_over_other_changes() {
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "keys-a".to_string(),
            vote_server_fingerprint: "servers-a".to_string(),
            pir_endpoint_fingerprint: "pir-a".to_string(),
            authenticated_round_set_fingerprint: "rounds-a".to_string(),
            protocol_versions: SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
        };
        let mut next = current.clone();
        next.authenticated_round_set_fingerprint = "rounds-b".to_string();
        next.protocol_versions.vote_protocol = "v1".to_string();

        let decision = decide_config_switch(Some(current), next);

        assert_eq!(decision.kind, ConfigSwitchKind::ProtocolChanged);
    }

    #[test]
    fn config_switch_for_unchanged_summary_is_unchanged() {
        let current = ResolvedVotingConfigSummary {
            trusted_key_fingerprint: "keys-a".to_string(),
            vote_server_fingerprint: "servers-a".to_string(),
            pir_endpoint_fingerprint: "pir-a".to_string(),
            authenticated_round_set_fingerprint: "rounds-a".to_string(),
            protocol_versions: SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
        };

        let decision = decide_config_switch(Some(current.clone()), current);

        assert_eq!(decision.kind, ConfigSwitchKind::Unchanged);
    }
}
