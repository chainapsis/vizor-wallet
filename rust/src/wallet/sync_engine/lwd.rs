//! lightwalletd transport and gRPC download helpers for the sync
//! engine.
//!
//! Everything in this module is an `async` call that talks to the
//! lightwalletd backend via tonic: opening the gRPC channel (TLS for
//! `https://`, plaintext for local `http://` regtest), pulling down the
//! sapling + orchard subtree roots, and streaming compact blocks for
//! one scan batch. The orchestration loop in `sync_engine::mod`
//! treats this module as its network edge — it calls the helpers
//! here, hands their outputs to librustzcash (`put_*_subtree_roots`,
//! `scan_cached_blocks`), and never talks to tonic itself.
//!
//! Error mapping is kept local: every call site wraps tonic / parsing
//! failures into `SyncError::net` or `SyncError::parse`, so the outer
//! loop only ever deals with the typed `SyncError` taxonomy.

use std::{future::Future, time::Duration};

use tonic::{
    transport::{Channel, ClientTlsConfig, Endpoint},
    Request, Response, Status,
};
use zcash_client_backend::{
    data_api::{
        chain::CommitmentTreeRoot, wallet::ConfirmationsPolicy, WalletCommitmentTrees, WalletRead,
    },
    proto::service::{
        self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange, ChainSpec,
        Empty, GetAddressUtxosArg, GetAddressUtxosReply, GetSubtreeRootsArg, RawTransaction,
        SendResponse, TransparentAddressBlockFilter, TreeState, TxFilter,
    },
};
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::block_source::MemoryBlockSource;
use super::{elapsed, SyncError, WalletDatabase};

const LIGHTWALLETD_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const LIGHTWALLETD_UNARY_RPC_TIMEOUT: Duration = Duration::from_secs(20);
const LIGHTWALLETD_STREAM_START_TIMEOUT: Duration = Duration::from_secs(20);
const LIGHTWALLETD_STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(30);

fn timed_request<T>(message: T, timeout: Duration) -> Request<T> {
    let mut request = Request::new(message);
    request.set_timeout(timeout);
    request
}

fn timeout_status(label: &str, timeout: Duration) -> Status {
    Status::deadline_exceeded(format!("{label}: timed out after {}s", timeout.as_secs()))
}

fn status_to_network_error(label: &str, status: Status) -> SyncError {
    SyncError::net(format!("{label}: {status}"))
}

pub(super) fn ironwood_sync_enabled(network: WalletNetwork, height: BlockHeight) -> bool {
    network.is_nu_active(NetworkUpgrade::Nu6_3, height)
}

fn compact_block_pool_types(network: WalletNetwork, end_height: BlockHeight) -> Vec<i32> {
    if ironwood_sync_enabled(network, end_height) {
        vec![
            service::PoolType::Sapling as i32,
            service::PoolType::Orchard as i32,
            service::PoolType::Ironwood as i32,
        ]
    } else {
        Vec::new()
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

async fn await_tonic_stream<T, F>(
    label: &str,
    timeout: Duration,
    future: F,
) -> Result<tonic::Streaming<T>, Status>
where
    F: Future<Output = Result<Response<tonic::Streaming<T>>, Status>>,
{
    match tokio::time::timeout(timeout, future).await {
        Ok(Ok(response)) => Ok(response.into_inner()),
        Ok(Err(status)) => Err(status),
        Err(_) => Err(timeout_status(label, timeout)),
    }
}

// Server-streaming calls intentionally use plain `Request::new` at
// their call sites. A `grpc-timeout` header would bound the whole
// stream lifetime; here we only bound stream start and per-message idle
// waits locally.

/// Opens a tonic gRPC channel to the given lightwalletd URL and
/// returns a `CompactTxStreamerClient`.
///
/// Ensures the process-wide rustls `CryptoProvider` is installed
/// before any TLS work. This is normally done by `init_app()` on
/// the Flutter/FRB path, but the iOS background-sync C FFI
/// entrypoint (`zcash_run_full_sync_for_migration_preparation`) can reach this
/// function on
/// a cold background wake *before* `init_app()` ever ran. Without
/// the `Once` guard here, rustls 0.23+ panics with "no
/// process-level CryptoProvider installed" on the first handshake.
pub(crate) async fn open_lwd_channel(
    lightwalletd_url: &str,
) -> Result<CompactTxStreamerClient<Channel>, SyncError> {
    static RUSTLS_INIT: std::sync::Once = std::sync::Once::new();
    RUSTLS_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });

    let endpoint = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| SyncError::net(format!("invalid URL: {e}")))?
        .connect_timeout(LIGHTWALLETD_CONNECT_TIMEOUT);
    let channel = if lightwalletd_url.starts_with("https://") {
        endpoint
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| SyncError::net(format!("TLS error: {e}")))?
            .connect()
            .await
            .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?
    } else {
        endpoint
            .connect()
            .await
            .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?
    };
    Ok(CompactTxStreamerClient::new(channel))
}

/// Return the current chain tip with a bounded response wait.
pub(crate) async fn get_latest_block(
    client: &mut CompactTxStreamerClient<Channel>,
) -> Result<BlockId, SyncError> {
    await_tonic_response(
        "get_latest_block",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.get_latest_block(timed_request(
            ChainSpec::default(),
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
    .map_err(|e| status_to_network_error("get_latest_block", e))
}

/// Return the note commitment tree state for a block with a bounded
/// response wait.
pub(super) async fn get_tree_state(
    client: &mut CompactTxStreamerClient<Channel>,
    height: u64,
) -> Result<TreeState, SyncError> {
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
    .map_err(|e| status_to_network_error("get_tree_state", e))
}

/// Return a raw transaction response. This keeps the original tonic
/// `Status` so callers that distinguish `NotFound` from transient
/// network failures can make that decision after the timeout wrapper.
pub(crate) async fn get_transaction(
    client: &mut CompactTxStreamerClient<Channel>,
    hash: Vec<u8>,
) -> Result<RawTransaction, Status> {
    await_tonic_response(
        "get_transaction",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.get_transaction(timed_request(
            TxFilter {
                block: None,
                index: 0,
                hash,
            },
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
}

/// Submit a raw transaction with a bounded response wait.
pub(crate) async fn send_transaction_with_status(
    client: &mut CompactTxStreamerClient<Channel>,
    data: &[u8],
) -> Result<SendResponse, Status> {
    await_tonic_response(
        "send_transaction",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.send_transaction(timed_request(
            RawTransaction {
                data: data.to_vec(),
                height: 0,
            },
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
}

/// Submit a raw transaction with a bounded response wait and map tonic
/// errors into the sync error taxonomy.
pub(crate) async fn send_transaction(
    client: &mut CompactTxStreamerClient<Channel>,
    data: &[u8],
) -> Result<SendResponse, SyncError> {
    send_transaction_with_status(client, data)
        .await
        .map_err(|e| status_to_network_error("send_transaction", e))
}

/// Open the deprecated transparent-address transaction stream with a
/// bounded wait for response headers. Individual stream messages must
/// still be read with [`next_stream_message`] to bound an idle stream.
pub(crate) async fn get_taddress_txids(
    client: &mut CompactTxStreamerClient<Channel>,
    address: String,
    start_height: u64,
    end_height: u64,
) -> Result<tonic::Streaming<RawTransaction>, SyncError> {
    await_tonic_stream(
        "get_taddress_txids",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_taddress_txids(Request::new(TransparentAddressBlockFilter {
            address,
            range: Some(BlockRange {
                start: Some(BlockId {
                    height: start_height,
                    hash: vec![],
                }),
                end: Some(BlockId {
                    height: end_height,
                    hash: vec![],
                }),
                pool_types: vec![],
            }),
        })),
    )
    .await
    .map_err(|e| status_to_network_error("get_taddress_txids", e))
}

/// Open a transparent UTXO stream with a bounded wait for response headers.
/// Callers should read individual messages with [`next_stream_message`] so a
/// stalled lightwalletd stream cannot pin the sync loop indefinitely.
pub(super) async fn get_address_utxos_stream(
    client: &mut CompactTxStreamerClient<Channel>,
    addresses: Vec<String>,
    start_height: BlockHeight,
) -> Result<tonic::Streaming<GetAddressUtxosReply>, SyncError> {
    await_tonic_stream(
        "get_address_utxos_stream",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_address_utxos_stream(Request::new(GetAddressUtxosArg {
            addresses,
            start_height: u32::from(start_height) as u64,
            max_entries: 0,
        })),
    )
    .await
    .map_err(|e| status_to_network_error("get_address_utxos_stream", e))
}

/// Read the next server-streaming message with a bounded idle wait.
/// `Ok(None)` remains the server's normal EOF signal.
pub(crate) async fn next_stream_message<T>(
    stream: &mut tonic::Streaming<T>,
    label: &str,
) -> Result<Option<T>, SyncError> {
    match tokio::time::timeout(LIGHTWALLETD_STREAM_IDLE_TIMEOUT, stream.message()).await {
        Ok(Ok(message)) => Ok(message),
        Ok(Err(status)) => Err(status_to_network_error(label, status)),
        Err(_) => Err(SyncError::net(format!(
            "{label}: timed out after {}s waiting for next message",
            LIGHTWALLETD_STREAM_IDLE_TIMEOUT.as_secs()
        ))),
    }
}

/// Pulls the latest shielded subtree roots from lightwalletd
/// and writes them into `db` via `put_*_subtree_roots`. The starting
/// index for each protocol comes from `db`'s wallet summary, so a
/// follow-up sync only fetches roots for subtrees the wallet has not
/// seen yet.
///
/// Every byte slice from the wire is length-checked: a subtree root
/// is exactly 32 bytes, and a short or long payload is rejected as a
/// `SyncError::parse` rather than being sliced with a hard-coded
/// range (which would panic before `try_into` could catch the
/// mismatch).
pub(super) async fn download_subtree_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    chain_tip: BlockHeight,
) -> Result<(), SyncError> {
    let ironwood_enabled = ironwood_sync_enabled(network, chain_tip);
    let (sap_start, orch_start, ironwood_start) = {
        let summary = db
            .get_wallet_summary(ConfirmationsPolicy::default())
            .map_err(|e| SyncError::db(format!("get_wallet_summary: {e}")))?;
        match summary {
            Some(s) => (
                s.next_sapling_subtree_index(),
                s.next_orchard_subtree_index(),
                s.next_ironwood_subtree_index(),
            ),
            None => (0, 0, 0),
        }
    };
    if ironwood_enabled {
        log::info!(
            "[{}] sync: subtree roots start: sapling={}, orchard={}, ironwood={}",
            elapsed(),
            sap_start,
            orch_start,
            ironwood_start
        );
    } else {
        log::info!(
            "[{}] sync: subtree roots start: sapling={}, orchard={}",
            elapsed(),
            sap_start,
            orch_start
        );
    }

    // Sapling
    let mut stream = await_tonic_stream(
        "sapling subtree roots",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_subtree_roots(Request::new(GetSubtreeRootsArg {
            start_index: sap_start as u32,
            shielded_protocol: service::ShieldedProtocol::Sapling.into(),
            max_entries: 0,
        })),
    )
    .await
    .map_err(|e| status_to_network_error("sapling subtree roots", e))?;

    let mut roots = Vec::new();
    while let Some(root) = next_stream_message(&mut stream, "sapling subtree roots stream").await? {
        // `SubtreeRoot::root_hash` is `bytes = "vec"` in the proto,
        // not a fixed-length field. A slice expression like
        // `root_hash[..32]` would panic before `try_into()` runs if
        // the server sent fewer than 32 bytes, so convert from the
        // full buffer via `as_slice` and let `try_into` reject both
        // short and long payloads.
        let bytes: [u8; 32] = root.root_hash.as_slice().try_into().map_err(|_| {
            SyncError::parse(format!(
                "sapling subtree root: expected 32 bytes, got {}",
                root.root_hash.len()
            ))
        })?;
        let node = Option::from(sapling_crypto::Node::from_bytes(bytes))
            .ok_or_else(|| SyncError::parse("sapling subtree root: bad node bytes".to_string()))?;
        roots.push(CommitmentTreeRoot::from_parts(
            BlockHeight::from_u32(root.completing_block_height as u32),
            node,
        ));
    }
    log::info!(
        "[{}] sync: downloaded {} sapling subtree roots",
        elapsed(),
        roots.len()
    );
    if !roots.is_empty() {
        with_wallet_db_write_lock("sync_engine.put_sapling_subtree_roots", || {
            db.put_sapling_subtree_roots(sap_start, roots.as_slice())
                .map_err(|e| SyncError::db(format!("put_sapling_subtree_roots: {e}")))
        })?;
    }

    // Orchard
    let mut stream = await_tonic_stream(
        "orchard subtree roots",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_subtree_roots(Request::new(GetSubtreeRootsArg {
            start_index: orch_start as u32,
            shielded_protocol: service::ShieldedProtocol::Orchard.into(),
            max_entries: 0,
        })),
    )
    .await
    .map_err(|e| status_to_network_error("orchard subtree roots", e))?;

    let mut roots = Vec::new();
    while let Some(root) = next_stream_message(&mut stream, "orchard subtree roots stream").await? {
        let bytes: [u8; 32] = root.root_hash.as_slice().try_into().map_err(|_| {
            SyncError::parse(format!(
                "orchard subtree root: expected 32 bytes, got {}",
                root.root_hash.len()
            ))
        })?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes))
            .ok_or_else(|| SyncError::parse("orchard subtree root: bad node bytes".to_string()))?;
        roots.push(CommitmentTreeRoot::from_parts(
            BlockHeight::from_u32(root.completing_block_height as u32),
            node,
        ));
    }
    log::info!(
        "[{}] sync: downloaded {} orchard subtree roots",
        elapsed(),
        roots.len()
    );
    if !roots.is_empty() {
        with_wallet_db_write_lock("sync_engine.put_orchard_subtree_roots", || {
            db.put_orchard_subtree_roots(orch_start, roots.as_slice())
                .map_err(|e| SyncError::db(format!("put_orchard_subtree_roots: {e}")))
        })?;
    }

    if ironwood_enabled {
        let mut stream = await_tonic_stream(
            "ironwood subtree roots",
            LIGHTWALLETD_STREAM_START_TIMEOUT,
            client.get_subtree_roots(Request::new(GetSubtreeRootsArg {
                start_index: ironwood_start as u32,
                shielded_protocol: service::ShieldedProtocol::Ironwood.into(),
                max_entries: 0,
            })),
        )
        .await
        .map_err(|e| status_to_network_error("ironwood subtree roots", e))?;

        let mut roots = Vec::new();
        while let Some(root) =
            next_stream_message(&mut stream, "ironwood subtree roots stream").await?
        {
            let bytes: [u8; 32] = root.root_hash.as_slice().try_into().map_err(|_| {
                SyncError::parse(format!(
                    "ironwood subtree root: expected 32 bytes, got {}",
                    root.root_hash.len()
                ))
            })?;
            let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes))
                .ok_or_else(|| {
                    SyncError::parse("ironwood subtree root: bad node bytes".to_string())
                })?;
            roots.push(CommitmentTreeRoot::from_parts(
                BlockHeight::from_u32(root.completing_block_height as u32),
                node,
            ));
        }
        log::info!(
            "[{}] sync: downloaded {} ironwood subtree roots",
            elapsed(),
            roots.len()
        );
        if !roots.is_empty() {
            with_wallet_db_write_lock("sync_engine.put_ironwood_subtree_roots", || {
                db.put_ironwood_subtree_roots(ironwood_start, roots.as_slice())
                    .map_err(|e| SyncError::db(format!("put_ironwood_subtree_roots: {e}")))
            })?;
        }
    }

    log::info!("[{}] sync: subtree roots done", elapsed());
    Ok(())
}

/// Open a server-streaming `GetMempoolStream` RPC against
/// lightwalletd and return the tonic stream of raw transactions
/// sitting in the server's mempool.
///
/// The caller owns the reconnect loop. lightwalletd closes this
/// stream every time a new block is mined (the server-side
/// comment on `get_mempool_stream` explicitly says: "*close the
/// returned stream when a new block is mined*"), and the
/// [`crate::wallet::sync_engine::mempool`] observer relies on
/// that EOF to kick off its reconnect / re-decrypt cycle. Normal
/// termination therefore surfaces as `stream.message().await`
/// returning `Ok(None)`, not as an `Err` — the caller should not
/// treat that case as a failure.
///
/// This helper stays a thin wrapper on `client.get_mempool_stream`
/// so that error-to-`SyncError::Network` mapping lives in the
/// same place as every other lwd gRPC call.
pub(crate) async fn start_mempool_stream(
    client: &mut CompactTxStreamerClient<Channel>,
) -> Result<tonic::Streaming<RawTransaction>, SyncError> {
    await_tonic_stream(
        "get_mempool_stream",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_mempool_stream(Request::new(Empty {})),
    )
    .await
    .map_err(|e| status_to_network_error("get_mempool_stream", e))
}

/// Streams compact blocks in `[start, end]` (inclusive) from
/// lightwalletd into an in-memory [`MemoryBlockSource`] that the scan
/// loop can hand straight to `scan_cached_blocks`. No file I/O — the
/// batch lives in RAM for exactly one scan call and is dropped
/// immediately after.
pub(super) async fn download_blocks(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
    network: WalletNetwork,
) -> Result<MemoryBlockSource, SyncError> {
    let mut stream = await_tonic_stream(
        "get_block_range",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_block_range(Request::new(BlockRange {
            start: Some(BlockId {
                height: u32::from(start) as u64,
                hash: vec![],
            }),
            end: Some(BlockId {
                height: u32::from(end) as u64,
                hash: vec![],
            }),
            pool_types: compact_block_pool_types(network, end),
        })),
    )
    .await
    .map_err(|e| status_to_network_error("get_block_range", e))?;

    let mut blocks = Vec::new();
    while let Some(block) = next_stream_message(&mut stream, "get_block_range stream").await? {
        blocks.push(block);
    }

    Ok(MemoryBlockSource::new(blocks))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_ironwood_pool_requests_follow_nu6_3_activation() {
        let all_shielded_pools = vec![
            service::PoolType::Sapling as i32,
            service::PoolType::Orchard as i32,
            service::PoolType::Ironwood as i32,
        ];

        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            let activation = network
                .activation_height(NetworkUpgrade::Nu6_3)
                .expect("NU6.3 activation height");

            assert!(compact_block_pool_types(network, activation - 1).is_empty());
            assert_eq!(
                compact_block_pool_types(network, activation),
                all_shielded_pools,
            );
        }
    }
}
