//! Subtree root preparation for isolated gift-card wallets.

use std::time::Instant;

use tonic::transport::Channel;
use zcash_client_backend::{
    data_api::WalletRead, proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use super::{lwd, SyncError, WalletDatabase};
use crate::wallet::{network::WalletNetwork, wallet_summary_cache::get_wallet_summary_cached};

fn ironwood_only(network: WalletNetwork, birthday: Option<BlockHeight>) -> bool {
    birthday.is_some_and(|height| network.is_nu_active(NetworkUpgrade::Nu6_3, height))
}

fn next_index(path: &str, network: WalletNetwork) -> Result<u64, SyncError> {
    Ok(get_wallet_summary_cached(path, network)
        .map_err(SyncError::db)?
        .map_or(0, |s| s.next_ironwood_subtree_index()))
}

/// Current cards are funded into Ironwood. Older birthdays retain the full
/// pool path because issued links do not encode their funding pool.
pub(super) async fn prepare_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    tip: BlockHeight,
) -> Result<(), SyncError> {
    let start = Instant::now();
    let birthday = db
        .get_wallet_birthday()
        .map_err(|e| SyncError::db(e.to_string()))?;
    if !ironwood_only(network, birthday) {
        return lwd::download_subtree_roots(client, db, db_path, network, tip).await;
    }
    let cursor = next_index(db_path, network)?;
    log::info!("PaymentLinkClaim: fetching Ironwood roots start_index={cursor}");
    lwd::download_ironwood_subtree_roots(client, db, cursor).await?;
    log::info!(
        "PaymentLinkClaim: roots ready elapsed_ms={}",
        start.elapsed().as_millis()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_post_activation_cards_skip_legacy_roots() {
        let network = WalletNetwork::Main;
        let activation = network.activation_height(NetworkUpgrade::Nu6_3).unwrap();
        assert!(!ironwood_only(network, None));
        assert!(!ironwood_only(network, Some(activation - 1)));
        assert!(ironwood_only(network, Some(activation)));
        assert!(ironwood_only(network, Some(activation + 10)));
    }
}
