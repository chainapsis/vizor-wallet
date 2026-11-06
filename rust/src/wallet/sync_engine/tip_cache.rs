use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

use tonic::transport::Channel;
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, BlockId,
};

use crate::{network_privacy, wallet::network::WalletNetwork};

use super::{get_latest_block, open_lwd_channel, SyncError};

const TRANSACTION_TIP_MAX_AGE: Duration = Duration::from_secs(15);

/// The route generation that owned a channel before its first asynchronous step.
#[derive(Clone, Copy, Debug)]
pub(crate) struct TipRequestScope {
    route_revision: u64,
}

impl TipRequestScope {
    pub(crate) fn capture() -> Self {
        Self {
            route_revision: network_privacy::route_revision(),
        }
    }

    pub(crate) fn ensure_current(self, should_exit: impl Fn() -> bool) -> Result<(), SyncError> {
        if should_exit() {
            return Err(SyncError::net(
                "network privacy blocked lightwalletd: tip request cancelled",
            ));
        }
        if network_privacy::route_revision() != self.route_revision {
            return Err(SyncError::net(
                "network privacy blocked lightwalletd: tip request route changed",
            ));
        }
        network_privacy::try_tor_client_for_route(false).map_err(|error| {
            SyncError::net(format!("network privacy blocked lightwalletd: {error}"))
        })?;
        if network_privacy::route_revision() != self.route_revision {
            return Err(SyncError::net(
                "network privacy blocked lightwalletd: tip request route changed",
            ));
        }
        if should_exit() {
            return Err(SyncError::net(
                "network privacy blocked lightwalletd: tip request cancelled",
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct CacheKey {
    lightwalletd_url: String,
    network: WalletNetwork,
}

#[derive(Clone)]
struct CacheEntry {
    tip: BlockId,
    observed_at: Instant,
    route_revision: u64,
}

#[derive(Default)]
struct LatestBlockCache {
    entries: HashMap<CacheKey, CacheEntry>,
}

impl LatestBlockCache {
    fn key(lightwalletd_url: &str, network: WalletNetwork) -> CacheKey {
        CacheKey {
            lightwalletd_url: lightwalletd_url.to_string(),
            network,
        }
    }

    fn record(
        &mut self,
        lightwalletd_url: &str,
        network: WalletNetwork,
        tip: BlockId,
        observed_at: Instant,
        route_revision: u64,
    ) {
        self.entries.insert(
            Self::key(lightwalletd_url, network),
            CacheEntry {
                tip,
                observed_at,
                route_revision,
            },
        );
    }

    fn recent(
        &mut self,
        lightwalletd_url: &str,
        network: WalletNetwork,
        now: Instant,
        max_age: Duration,
        route_revision: u64,
    ) -> Option<BlockId> {
        let key = Self::key(lightwalletd_url, network);
        let entry = self.entries.get(&key)?;
        if entry.route_revision != route_revision {
            return None;
        }
        if now.duration_since(entry.observed_at) <= max_age {
            Some(entry.tip.clone())
        } else {
            self.entries.remove(&key);
            None
        }
    }
}

static LATEST_BLOCK_CACHE: LazyLock<Mutex<LatestBlockCache>> =
    LazyLock::new(|| Mutex::new(LatestBlockCache::default()));

fn with_cache<T>(f: impl FnOnce(&mut LatestBlockCache) -> T) -> T {
    let mut cache = LATEST_BLOCK_CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    f(&mut cache)
}

/// Seeds cache fixtures only; production writes must retain request ownership.
#[cfg(test)]
pub(crate) fn record_latest_block(lightwalletd_url: &str, network: WalletNetwork, tip: BlockId) {
    let scope = TipRequestScope::capture();
    with_cache(|cache| {
        cache.record(
            lightwalletd_url,
            network,
            tip,
            Instant::now(),
            scope.route_revision,
        )
    });
}

/// Fetches the latest block, recording it only while its channel's route and
/// operation remain current. No cache lock is held across network work.
pub(crate) async fn get_latest_block_recorded(
    client: &mut CompactTxStreamerClient<Channel>,
    lightwalletd_url: &str,
    network: WalletNetwork,
    scope: TipRequestScope,
    should_exit: impl Fn() -> bool,
) -> Result<BlockId, SyncError> {
    scope.ensure_current(&should_exit)?;
    let response = get_latest_block(client).await;
    scope.ensure_current(&should_exit)?;
    let tip = response?;
    with_cache(|cache| {
        scope.ensure_current(&should_exit)?;
        cache.record(
            lightwalletd_url,
            network,
            tip.clone(),
            Instant::now(),
            scope.route_revision,
        );
        Ok::<_, SyncError>(())
    })?;
    scope.ensure_current(&should_exit)?;
    Ok(tip)
}

/// Returns a recent observation owned by the current route, or refreshes it
/// from lightwalletd when no successful observation is available within 15s.
pub(crate) async fn latest_block_for_transaction(
    lightwalletd_url: &str,
    network: WalletNetwork,
) -> Result<BlockId, SyncError> {
    let scope = TipRequestScope::capture();
    if let Some(tip) = recent_transaction_tip(lightwalletd_url, network, scope)? {
        scope.ensure_current(|| false)?;
        return Ok(tip);
    }
    let mut client = open_lwd_channel(lightwalletd_url).await?;
    get_latest_block_recorded(&mut client, lightwalletd_url, network, scope, || false).await
}

/// Uses a recent observation when possible, otherwise refreshing through the
/// caller's channel, whose scope must have been captured before opening it.
pub(crate) async fn latest_block_for_transaction_with_client(
    client: &mut CompactTxStreamerClient<Channel>,
    lightwalletd_url: &str,
    network: WalletNetwork,
    scope: TipRequestScope,
) -> Result<BlockId, SyncError> {
    if let Some(tip) = recent_transaction_tip(lightwalletd_url, network, scope)? {
        scope.ensure_current(|| false)?;
        return Ok(tip);
    }
    get_latest_block_recorded(client, lightwalletd_url, network, scope, || false).await
}

fn recent_transaction_tip(
    lightwalletd_url: &str,
    network: WalletNetwork,
    scope: TipRequestScope,
) -> Result<Option<BlockId>, SyncError> {
    let tip = with_cache(|cache| {
        scope.ensure_current(|| false)?;
        Ok::<_, SyncError>(cache.recent(
            lightwalletd_url,
            network,
            Instant::now(),
            TRANSACTION_TIP_MAX_AGE,
            scope.route_revision,
        ))
    })?;
    scope.ensure_current(|| false)?;
    Ok(tip)
}

#[cfg(test)]
mod tests;
