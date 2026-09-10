use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

use tonic::transport::Channel;
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, BlockId,
};

use crate::wallet::network::WalletNetwork;

use super::{get_latest_block, open_lwd_channel, SyncError};

const TRANSACTION_TIP_MAX_AGE: Duration = Duration::from_secs(15);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct CacheKey {
    lightwalletd_url: String,
    network: WalletNetwork,
}

#[derive(Clone)]
struct CacheEntry {
    tip: BlockId,
    observed_at: Instant,
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
    ) {
        self.entries.insert(
            Self::key(lightwalletd_url, network),
            CacheEntry { tip, observed_at },
        );
    }

    fn recent(
        &mut self,
        lightwalletd_url: &str,
        network: WalletNetwork,
        now: Instant,
        max_age: Duration,
    ) -> Option<BlockId> {
        let key = Self::key(lightwalletd_url, network);
        let entry = self.entries.get(&key)?;
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

/// Fetches the latest block and records the successful response for later
/// transaction operations.
pub(crate) async fn get_latest_block_recorded(
    client: &mut CompactTxStreamerClient<Channel>,
    lightwalletd_url: &str,
    network: WalletNetwork,
) -> Result<BlockId, SyncError> {
    let tip = get_latest_block(client).await?;
    with_cache(|cache| cache.record(lightwalletd_url, network, tip.clone(), Instant::now()));
    Ok(tip)
}

/// Returns a recently observed tip, or refreshes it from lightwalletd when no
/// successful observation is available from the last 15 seconds.
pub(crate) async fn latest_block_for_transaction(
    lightwalletd_url: &str,
    network: WalletNetwork,
) -> Result<BlockId, SyncError> {
    if let Some(tip) = recent_transaction_tip(lightwalletd_url, network) {
        return Ok(tip);
    }

    let mut client = open_lwd_channel(lightwalletd_url).await?;
    get_latest_block_recorded(&mut client, lightwalletd_url, network).await
}

/// Uses a recent observation when possible, otherwise refreshing through the
/// caller's existing channel.
pub(crate) async fn latest_block_for_transaction_with_client(
    client: &mut CompactTxStreamerClient<Channel>,
    lightwalletd_url: &str,
    network: WalletNetwork,
) -> Result<BlockId, SyncError> {
    if let Some(tip) = recent_transaction_tip(lightwalletd_url, network) {
        return Ok(tip);
    }

    get_latest_block_recorded(client, lightwalletd_url, network).await
}

fn recent_transaction_tip(lightwalletd_url: &str, network: WalletNetwork) -> Option<BlockId> {
    with_cache(|cache| {
        cache.recent(
            lightwalletd_url,
            network,
            Instant::now(),
            TRANSACTION_TIP_MAX_AGE,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tip(height: u64) -> BlockId {
        BlockId {
            height,
            hash: vec![height as u8],
        }
    }

    #[test]
    fn recent_tip_is_scoped_to_endpoint_and_network() {
        let now = Instant::now();
        let mut cache = LatestBlockCache::default();
        cache.record("https://one.example", WalletNetwork::Main, tip(42), now);

        assert_eq!(
            cache
                .recent(
                    "https://one.example",
                    WalletNetwork::Main,
                    now + Duration::from_secs(15),
                    TRANSACTION_TIP_MAX_AGE,
                )
                .map(|tip| tip.height),
            Some(42)
        );
        assert!(cache
            .recent(
                "https://two.example",
                WalletNetwork::Main,
                now,
                TRANSACTION_TIP_MAX_AGE,
            )
            .is_none());
        assert!(cache
            .recent(
                "https://one.example",
                WalletNetwork::Test,
                now,
                TRANSACTION_TIP_MAX_AGE,
            )
            .is_none());
    }

    #[test]
    fn tip_older_than_max_age_is_not_reused() {
        let now = Instant::now();
        let mut cache = LatestBlockCache::default();
        cache.record("https://one.example", WalletNetwork::Main, tip(42), now);

        assert!(cache
            .recent(
                "https://one.example",
                WalletNetwork::Main,
                now + Duration::from_secs(16),
                TRANSACTION_TIP_MAX_AGE,
            )
            .is_none());
    }

    #[test]
    fn recording_again_replaces_height_and_recency() {
        let now = Instant::now();
        let mut cache = LatestBlockCache::default();
        cache.record("https://one.example", WalletNetwork::Main, tip(41), now);
        cache.record(
            "https://one.example",
            WalletNetwork::Main,
            tip(42),
            now + Duration::from_secs(10),
        );

        assert_eq!(
            cache
                .recent(
                    "https://one.example",
                    WalletNetwork::Main,
                    now + Duration::from_secs(24),
                    TRANSACTION_TIP_MAX_AGE,
                )
                .map(|tip| tip.height),
            Some(42)
        );
    }
}
