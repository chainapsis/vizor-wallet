use std::panic::UnwindSafe;

use flutter_rust_bridge::DartFnFuture;
use zcash_voting::config::{self, ResolveConfigError};
use zcash_voting::wire::{
    ConfigSwitchKind, ResolveVotingConfigOptions, ResolvedVotingConfig, ResolvedVotingConfigSummary,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingConfigResolution {
    pub config: ResolvedVotingConfig,
    pub switch_kind: ConfigSwitchKind,
}

/// Resolve static + dynamic voting config via a wallet-owned fetch callback.
///
/// Rust validates config authenticity and computes config switch semantics.
/// The wallet keeps transport ownership via `fetch_bytes`.
pub async fn resolve_voting_config(
    source: String,
    previous: Option<ResolvedVotingConfig>,
    fetch_bytes: impl Fn(String) -> DartFnFuture<Vec<u8>> + UnwindSafe,
) -> Result<VotingConfigResolution, String> {
    let next = config::resolve_config(&source, ResolveVotingConfigOptions::default(), |url| {
        let response = fetch_bytes(url.clone());
        async move { Ok::<_, String>(response.await) }
    })
    .await
    .map_err(|error| match error {
        ResolveConfigError::Transport(transport) => transport,
        ResolveConfigError::Config(config_error) => config_error.to_string(),
    })?;

    let switch_kind = config::decide_config_switch(
        previous.as_ref().map(ResolvedVotingConfigSummary::from),
        ResolvedVotingConfigSummary::from(&next),
    )
    .kind;

    Ok(VotingConfigResolution {
        config: next,
        switch_kind,
    })
}
