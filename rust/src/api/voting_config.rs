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

/// Fallible response from the wallet-owned voting config transport callback.
///
/// This keeps ordinary transport failures (timeout/HTTP errors/etc.) in the
/// value domain instead of crossing the FFI callback boundary as panics.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingConfigFetch {
    pub bytes: Option<Vec<u8>>,
    pub error: Option<String>,
}

/// Resolve static + dynamic voting config via a wallet-owned fetch callback.
///
/// Rust validates config authenticity and computes config switch semantics.
/// The wallet keeps transport ownership via `fetch_bytes`.
pub async fn resolve_voting_config(
    source: String,
    previous: Option<ResolvedVotingConfig>,
    fetch_bytes: impl Fn(String) -> DartFnFuture<VotingConfigFetch>,
) -> Result<VotingConfigResolution, String> {
    let next = config::resolve_config(&source, ResolveVotingConfigOptions::default(), |url| {
        let response = fetch_bytes(url.clone());
        async move {
            let response = response.await;
            match (response.bytes, response.error) {
                (Some(bytes), None) => Ok::<_, String>(bytes),
                (None, Some(error)) => Err(error),
                (Some(_), Some(_)) => Err(
                    "voting config transport callback returned both bytes and error".to_string(),
                ),
                (None, None) => Err(
                    "voting config transport callback returned neither bytes nor error".to_string(),
                ),
            }
        }
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
