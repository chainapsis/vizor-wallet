//! lightwalletd query helpers for wallet SDK delegation flows.
//!
//! These helpers keep the tonic/lightwalletd edge in `zcash_voting` for callers
//! that need Zcash mainnet chain state while preparing delegation witnesses.

use std::{future::Future, time::Duration};

use prost::Message;
use tonic::{
    transport::{Channel, ClientTlsConfig, Endpoint},
    Request, Response, Status,
};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, BlockId, ChainSpec, TreeState,
};
use zcash_protocol::consensus::{BlockHeight, BranchId};

use crate::types::{Network, VotingError};

const LIGHTWALLETD_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const LIGHTWALLETD_UNARY_RPC_TIMEOUT: Duration = Duration::from_secs(20);
const LIGHTWALLETD_RETRY_ATTEMPTS: u32 = 3;

/// Opens a tonic gRPC channel to a lightwalletd URL.
pub async fn open_channel(
    lightwalletd_url: &str,
) -> Result<CompactTxStreamerClient<Channel>, VotingError> {
    static RUSTLS_INIT: std::sync::Once = std::sync::Once::new();
    RUSTLS_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });

    let endpoint = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| VotingError::InvalidInput {
            message: format!("invalid lightwalletd URL: {e}"),
        })?
        .connect_timeout(LIGHTWALLETD_CONNECT_TIMEOUT);

    let channel = if lightwalletd_url.starts_with("https://") {
        endpoint
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| VotingError::Internal {
                message: format!("lightwalletd TLS config failed: {e}"),
            })?
            .connect()
            .await
            .map_err(|e| VotingError::Internal {
                message: format!("lightwalletd connect failed: {e}"),
            })?
    } else {
        endpoint
            .connect()
            .await
            .map_err(|e| VotingError::Internal {
                message: format!("lightwalletd connect failed: {e}"),
            })?
    };

    Ok(CompactTxStreamerClient::new(channel))
}

/// Returns the current lightwalletd chain tip with a bounded response wait.
pub async fn get_latest_block(
    client: &mut CompactTxStreamerClient<Channel>,
) -> Result<BlockId, VotingError> {
    await_tonic_response(
        "get_latest_block",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.get_latest_block(timed_request(
            ChainSpec::default(),
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
    .map_err(|e| status_to_error("get_latest_block", e))
}

/// Opens lightwalletd and returns the latest known block height.
pub async fn latest_block_height(lightwalletd_url: &str) -> Result<u64, VotingError> {
    let mut client = open_channel(lightwalletd_url).await?;
    Ok(get_latest_block(&mut client).await?.height)
}

/// Opens lightwalletd and returns the latest known block height with bounded retry behavior.
pub async fn latest_block_height_with_retry(lightwalletd_url: &str) -> Result<u64, VotingError> {
    let mut last_error = None;
    for attempt in 1..=LIGHTWALLETD_RETRY_ATTEMPTS {
        match latest_block_height(lightwalletd_url).await {
            Ok(height) => return Ok(height),
            Err(error) => {
                if attempt == LIGHTWALLETD_RETRY_ATTEMPTS {
                    last_error = Some(error);
                    break;
                }
                last_error = Some(error);
                tokio::time::sleep(Duration::from_millis(500 * u64::from(attempt))).await;
            }
        }
    }

    Err(last_error.unwrap_or_else(|| VotingError::Internal {
        message: "chain height fetch failed".to_string(),
    }))
}

/// Returns the note commitment tree state for `height`.
pub async fn get_tree_state(
    client: &mut CompactTxStreamerClient<Channel>,
    height: u64,
) -> Result<TreeState, VotingError> {
    await_tonic_response(
        "get_tree_state",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.get_tree_state(timed_request(
            BlockId {
                height,
                hash: vec![],
            },
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
    .map_err(|e| status_to_error("get_tree_state", e))
}

/// Opens lightwalletd and returns the serialized `TreeState` for `height`.
pub async fn tree_state_bytes(lightwalletd_url: &str, height: u64) -> Result<Vec<u8>, VotingError> {
    let mut client = open_channel(lightwalletd_url).await?;
    Ok(get_tree_state(&mut client, height).await?.encode_to_vec())
}

/// Fetches a snapshot anchor `TreeState` with bounded retry behavior around
/// transient lightwalletd failures.
pub async fn anchor_tree_state_with_retry(
    lightwalletd_url: &str,
    snapshot_height: u64,
) -> Result<TreeState, VotingError> {
    let mut last_error = None;
    for attempt in 1..=LIGHTWALLETD_RETRY_ATTEMPTS {
        match fetch_tree_state(lightwalletd_url, snapshot_height).await {
            Ok(tree_state) => return Ok(tree_state),
            Err(error) => {
                if attempt == LIGHTWALLETD_RETRY_ATTEMPTS {
                    last_error = Some(error);
                    break;
                }
                last_error = Some(error);
                tokio::time::sleep(Duration::from_millis(500 * u64::from(attempt))).await;
            }
        }
    }

    Err(last_error.unwrap_or_else(|| VotingError::Internal {
        message: "snapshot tree state fetch failed".to_string(),
    }))
}

/// Fetches a snapshot anchor `TreeState` as protobuf bytes.
pub async fn anchor_tree_state_bytes_with_retry(
    lightwalletd_url: &str,
    snapshot_height: u64,
) -> Result<Vec<u8>, VotingError> {
    Ok(
        anchor_tree_state_with_retry(lightwalletd_url, snapshot_height)
            .await?
            .encode_to_vec(),
    )
}

/// Resolves the consensus branch ID active at `height` for `network`.
pub fn branch_id_for_height(network: Network, height: u64) -> Result<u32, VotingError> {
    let height = u32::try_from(height)
        .map(BlockHeight::from_u32)
        .map_err(|_| VotingError::InvalidInput {
            message: format!("chain height {height} does not fit in u32"),
        })?;

    Ok(u32::from(BranchId::for_height(&network, height)))
}

fn timed_request<T>(message: T, timeout: Duration) -> Request<T> {
    let mut request = Request::new(message);
    request.set_timeout(timeout);
    request
}

async fn fetch_tree_state(lightwalletd_url: &str, height: u64) -> Result<TreeState, VotingError> {
    let mut client = open_channel(lightwalletd_url).await?;
    get_tree_state(&mut client, height).await
}

fn timeout_status(label: &str, timeout: Duration) -> Status {
    Status::deadline_exceeded(format!("{label}: timed out after {}s", timeout.as_secs()))
}

fn status_to_error(label: &str, status: Status) -> VotingError {
    VotingError::Internal {
        message: format!("{label}: {status}"),
    }
}

async fn await_tonic_response<T, F>(label: &str, timeout: Duration, future: F) -> Result<T, Status>
where
    F: Future<Output = Result<Response<T>, Status>>,
{
    match tokio::time::timeout(timeout, future).await {
        Ok(Ok(response)) => Ok(response.into_inner()),
        Ok(Err(status)) => Err(status),
        Err(_) => Err(timeout_status(label, timeout)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn branch_id_for_height_follows_network_activation_heights() {
        assert_eq!(
            branch_id_for_height(Network::Mainnet, 3_146_399).unwrap(),
            0xC8E7_1055
        );
        assert_eq!(
            branch_id_for_height(Network::Mainnet, 3_146_400).unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            branch_id_for_height(Network::Testnet, 3_536_500).unwrap(),
            0x4DEC_4DF0
        );
        assert_eq!(
            branch_id_for_height(Network::Regtest, 1).unwrap(),
            0x5437_F330
        );
    }
}
