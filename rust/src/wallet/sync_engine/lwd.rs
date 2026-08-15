//! lightwalletd transport and gRPC download helpers for the sync
//! engine.
//!
//! Everything in this module is an `async` call that talks to the
//! lightwalletd backend via tonic: opening the gRPC channel (TLS for
//! `https://`, plaintext for local `http://` regtest), pulling down the
//! Sapling, Orchard, and Ironwood subtree roots, and streaming compact
//! blocks for one scan batch. The orchestration loop in `sync_engine::mod`
//! treats this module as its network edge — it calls the helpers
//! here, hands their outputs to librustzcash (`put_*_subtree_roots`,
//! `scan_cached_blocks`), and never talks to tonic itself.
//!
//! Error mapping is kept local: every call site wraps tonic / parsing
//! failures into `SyncError::net` or `SyncError::parse`, so the outer
//! loop only ever deals with the typed `SyncError` taxonomy.

use std::{future::Future, time::Duration};

use http::Uri;
use hyper_util::client::legacy::connect::HttpConnector;
use tonic::{
    transport::{Channel, ClientTlsConfig, Endpoint},
    Request, Response, Status,
};
use tower_service::Service;
use zcash_client_backend::{
    data_api::{chain::CommitmentTreeRoot, WalletCommitmentTrees},
    proto::service::{
        self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange, ChainSpec,
        Empty, GetAddressUtxosArg, GetAddressUtxosReply, GetSubtreeRootsArg, RawTransaction,
        SendResponse, TransparentAddressBlockFilter, TreeState, TxFilter,
    },
};
use zcash_primitives::block::BlockHash;
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

type AddressUtxoStream = tonic::Streaming<GetAddressUtxosReply>;

async fn await_address_utxo_stream<F>(
    timeout: Duration,
    future: F,
) -> Result<AddressUtxoStream, SyncError>
where
    F: Future<Output = Result<Response<AddressUtxoStream>, Status>>,
{
    await_tonic_stream("get_address_utxos_stream", timeout, future)
        .await
        .map_err(|e| status_to_network_error("get_address_utxos_stream", e))
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
/// the Flutter/FRB path, but Android background preparation JNI can reach this
/// function on a cold background wake *before* `init_app()` ever ran. Without
/// the `Once` guard here, rustls 0.23+ panics with "no
/// process-level CryptoProvider installed" on the first handshake.
pub(crate) async fn open_lwd_channel(
    lightwalletd_url: &str,
) -> Result<CompactTxStreamerClient<Channel>, SyncError> {
    open_lwd_channel_for_route(lightwalletd_url, false).await
}

/// Opens an isolated Tor circuit when Tor is enabled. Direct mode retains its
/// normal direct transport. Use this for transaction broadcasts that must not
/// share a Tor circuit with other wallet activity.
pub(crate) async fn open_isolated_lwd_channel(
    lightwalletd_url: &str,
) -> Result<CompactTxStreamerClient<Channel>, SyncError> {
    open_lwd_channel_for_route(lightwalletd_url, true).await
}

/// Opens a lightwalletd channel that is always direct, bypassing the
/// process-wide route policy entirely.
///
/// This is the transport for iOS background migration work, and it is pinned
/// direct as a product decision: Tor covers the app's foreground traffic, and
/// a background pass never brings Tor up or borrows the foreground's client —
/// a launch where Dart never ran has no client, and a warm process may drop
/// its client at any moment. Routing background work through the policy would
/// therefore only convert it into failures whenever Tor is on. It uses a
/// plain connector rather than the leased one, so a foreground toggle to Tor
/// does not abort a background broadcast already in flight.
///
/// Nothing in the foreground may use this: every foreground path goes through
/// [`open_lwd_channel`] or [`open_isolated_lwd_channel`], which respect the
/// user's chosen route and fail closed while Tor is starting or broken.
pub(crate) async fn open_background_direct_lwd_channel(
    lightwalletd_url: &str,
) -> Result<CompactTxStreamerClient<Channel>, SyncError> {
    static RUSTLS_INIT: std::sync::Once = std::sync::Once::new();
    RUSTLS_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });

    let endpoint = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| SyncError::net(format!("invalid URL: {e}")))?
        .connect_timeout(LIGHTWALLETD_CONNECT_TIMEOUT);
    let endpoint = if lightwalletd_url.starts_with("https://") {
        endpoint
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| SyncError::net(format!("TLS error: {e}")))?
    } else {
        endpoint
    };
    let channel = endpoint
        .connect()
        .await
        .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?;
    Ok(CompactTxStreamerClient::new(channel))
}

async fn open_lwd_channel_for_route(
    lightwalletd_url: &str,
    isolated: bool,
) -> Result<CompactTxStreamerClient<Channel>, SyncError> {
    static RUSTLS_INIT: std::sync::Once = std::sync::Once::new();
    RUSTLS_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });

    let endpoint = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| SyncError::net(format!("invalid URL: {e}")))?
        .connect_timeout(LIGHTWALLETD_CONNECT_TIMEOUT);
    if let Some(tor_client) = crate::network_privacy::tor_client_for_route(isolated)
        .map_err(|e| SyncError::net(format!("network privacy blocked lightwalletd: {e}")))?
    {
        let allow_onion_services = endpoint_allows_onion_services(&endpoint);
        return tor_client
            .connect_to_lightwalletd(endpoint.uri().clone(), allow_onion_services)
            .await
            .map_err(|e| SyncError::net(format!("Tor gRPC connect failed: {e}")));
    }
    let endpoint = if lightwalletd_url.starts_with("https://") {
        endpoint
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| SyncError::net(format!("TLS error: {e}")))?
    } else {
        endpoint
    };
    let channel = endpoint
        .connect_with_connector(DirectRouteConnector::new())
        .await
        .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?;
    Ok(CompactTxStreamerClient::new(channel))
}

#[derive(Clone)]
struct DirectRouteConnector {
    inner: HttpConnector,
}

impl DirectRouteConnector {
    fn new() -> Self {
        let mut inner = HttpConnector::new();
        inner.enforce_http(false);
        // Tonic applies the endpoint's `tcp_nodelay` (enabled by default) only
        // to its own connector, while hyper-util defaults to Nagle enabled.
        // Direct mode must keep the transport behaviour it had before the
        // route lease was interposed.
        inner.set_nodelay(true);
        Self { inner }
    }
}

impl Service<Uri> for DirectRouteConnector {
    type Response =
        crate::network_privacy::DirectRouteIo<hyper_util::rt::TokioIo<tokio::net::TcpStream>>;
    type Error = Box<dyn std::error::Error + Send + Sync>;
    type Future =
        std::pin::Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        self.inner
            .poll_ready(cx)
            .map(|result| result.map_err(|error| Box::new(error) as Self::Error))
    }

    fn call(&mut self, uri: Uri) -> Self::Future {
        let future = self.inner.call(uri);
        let route = crate::network_privacy::DirectRouteLease::new();
        Box::pin(async move {
            let mut future = Box::pin(future);
            let connected = std::future::poll_fn(|cx| {
                route.poll(cx, |cx| match future.as_mut().poll(cx) {
                    std::task::Poll::Ready(Ok(connected)) => std::task::Poll::Ready(Ok(connected)),
                    std::task::Poll::Ready(Err(error)) => {
                        std::task::Poll::Ready(Err(Box::new(error) as Self::Error))
                    }
                    std::task::Poll::Pending => std::task::Poll::Pending,
                })
            })
            .await?;
            Ok(route.into_io(connected))
        })
    }
}

fn endpoint_allows_onion_services(endpoint: &Endpoint) -> bool {
    endpoint
        .uri()
        .host()
        .is_some_and(|host| host.to_ascii_lowercase().ends_with(".onion"))
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

/// Fetch and validate the hash of one compact block.
///
/// This is the fallback for conforming lightwalletd servers that omit the
/// optional hash in a `GetLatestBlock` response. A server that also omits the
/// optional
/// [`zcash_client_backend::proto::compact_formats::CompactBlock::hash`] cannot
/// safely prove tip continuity, so this helper returns an incompatibility
/// error.
pub(super) async fn get_compact_block_hash(
    client: &mut CompactTxStreamerClient<Channel>,
    height: u64,
) -> Result<BlockHash, SyncError> {
    let block = await_tonic_response(
        "get_block",
        LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        client.get_block(timed_request(
            BlockId {
                height,
                hash: vec![],
            },
            LIGHTWALLETD_UNARY_RPC_TIMEOUT,
        )),
    )
    .await
    .map_err(|e| status_to_network_error("get_block", e))?;

    if block.height != height {
        return Err(SyncError::net(format!(
            "get_block returned height {} while requesting {height}",
            block.height,
        )));
    }
    BlockHash::try_from_slice(&block.hash).ok_or_else(|| {
        SyncError::net(format!(
            "get_block returned a {}-byte hash at height {height}",
            block.hash.len(),
        ))
    })
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
) -> Result<AddressUtxoStream, SyncError> {
    await_address_utxo_stream(
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_address_utxos_stream(Request::new(GetAddressUtxosArg {
            addresses,
            start_height: u32::from(start_height) as u64,
            max_entries: 0,
        })),
    )
    .await
}

async fn await_stream_message<T, F>(
    label: &str,
    timeout: Duration,
    future: F,
) -> Result<Option<T>, SyncError>
where
    F: Future<Output = Result<Option<T>, Status>>,
{
    match tokio::time::timeout(timeout, future).await {
        Ok(Ok(message)) => Ok(message),
        Ok(Err(status)) => Err(status_to_network_error(label, status)),
        Err(_) => Err(SyncError::net(format!(
            "{label}: timed out after {}s waiting for next message",
            timeout.as_secs()
        ))),
    }
}

/// Read the next server-streaming message with a bounded idle wait.
/// `Ok(None)` remains the server's normal EOF signal.
pub(crate) async fn next_stream_message<T>(
    stream: &mut tonic::Streaming<T>,
    label: &str,
) -> Result<Option<T>, SyncError> {
    await_stream_message(label, LIGHTWALLETD_STREAM_IDLE_TIMEOUT, stream.message()).await
}

async fn fetch_sapling_subtree_roots(
    mut client: CompactTxStreamerClient<Channel>,
    start_index: u64,
) -> Result<Vec<CommitmentTreeRoot<sapling_crypto::Node>>, SyncError> {
    let mut stream = await_tonic_stream(
        "sapling subtree roots",
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_subtree_roots(Request::new(GetSubtreeRootsArg {
            start_index: start_index as u32,
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
            .ok_or_else(|| SyncError::parse("sapling subtree root: bad node bytes"))?;
        roots.push(CommitmentTreeRoot::from_parts(
            BlockHeight::from_u32(root.completing_block_height as u32),
            node,
        ));
    }

    Ok(roots)
}

async fn fetch_orchard_subtree_roots(
    mut client: CompactTxStreamerClient<Channel>,
    start_index: u64,
) -> Result<Vec<CommitmentTreeRoot<orchard::tree::MerkleHashOrchard>>, SyncError> {
    fetch_orchard_family_subtree_roots(
        &mut client,
        start_index,
        service::ShieldedProtocol::Orchard,
        "orchard",
    )
    .await
}

async fn fetch_ironwood_subtree_roots(
    mut client: CompactTxStreamerClient<Channel>,
    start_index: u64,
) -> Result<Vec<CommitmentTreeRoot<orchard::tree::MerkleHashOrchard>>, SyncError> {
    fetch_orchard_family_subtree_roots(
        &mut client,
        start_index,
        service::ShieldedProtocol::Ironwood,
        "ironwood",
    )
    .await
}

async fn fetch_orchard_family_subtree_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    start_index: u64,
    protocol: service::ShieldedProtocol,
    label: &'static str,
) -> Result<Vec<CommitmentTreeRoot<orchard::tree::MerkleHashOrchard>>, SyncError> {
    let rpc_label = format!("{label} subtree roots");
    let stream_label = format!("{label} subtree roots stream");
    let mut stream = await_tonic_stream(
        &rpc_label,
        LIGHTWALLETD_STREAM_START_TIMEOUT,
        client.get_subtree_roots(Request::new(GetSubtreeRootsArg {
            start_index: start_index as u32,
            shielded_protocol: protocol.into(),
            max_entries: 0,
        })),
    )
    .await
    .map_err(|e| status_to_network_error(&rpc_label, e))?;

    let mut roots = Vec::new();
    while let Some(root) = next_stream_message(&mut stream, &stream_label).await? {
        let bytes: [u8; 32] = root.root_hash.as_slice().try_into().map_err(|_| {
            SyncError::parse(format!(
                "{label} subtree root: expected 32 bytes, got {}",
                root.root_hash.len()
            ))
        })?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&bytes))
            .ok_or_else(|| SyncError::parse(format!("{label} subtree root: bad node bytes")))?;
        roots.push(CommitmentTreeRoot::from_parts(
            BlockHeight::from_u32(root.completing_block_height as u32),
            node,
        ));
    }

    Ok(roots)
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
    db_path: &str,
    network: WalletNetwork,
    chain_tip: BlockHeight,
) -> Result<(), SyncError> {
    let ironwood_enabled = ironwood_sync_enabled(network, chain_tip);
    let (sap_start, orch_start, ironwood_start) = {
        let summary =
            crate::wallet::wallet_summary_cache::get_wallet_summary_cached(db_path, network)
                .map_err(SyncError::db)?;
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

    // Finish all network streams before mutating any tree. If one protocol
    // fails, the next retry starts from the same set of indices instead of
    // persisting a partial subtree-root refresh.
    let ironwood = async {
        if ironwood_enabled {
            fetch_ironwood_subtree_roots(client.clone(), ironwood_start).await
        } else {
            Ok(Vec::new())
        }
    };
    let (sapling_roots, orchard_roots, ironwood_roots) = tokio::try_join!(
        fetch_sapling_subtree_roots(client.clone(), sap_start),
        fetch_orchard_subtree_roots(client.clone(), orch_start),
        ironwood,
    )?;

    log::info!(
        "[{}] sync: downloaded {} sapling subtree roots",
        elapsed(),
        sapling_roots.len()
    );
    if !sapling_roots.is_empty() {
        with_wallet_db_write_lock("sync_engine.put_sapling_subtree_roots", || {
            db.put_sapling_subtree_roots(sap_start, sapling_roots.as_slice())
                .map_err(|e| SyncError::db(format!("put_sapling_subtree_roots: {e}")))
        })?;
    }

    log::info!(
        "[{}] sync: downloaded {} orchard subtree roots",
        elapsed(),
        orchard_roots.len()
    );
    if !orchard_roots.is_empty() {
        with_wallet_db_write_lock("sync_engine.put_orchard_subtree_roots", || {
            db.put_orchard_subtree_roots(orch_start, orchard_roots.as_slice())
                .map_err(|e| SyncError::db(format!("put_orchard_subtree_roots: {e}")))
        })?;
    }

    if ironwood_enabled {
        log::info!(
            "[{}] sync: downloaded {} ironwood subtree roots",
            elapsed(),
            ironwood_roots.len()
        );
        if !ironwood_roots.is_empty() {
            with_wallet_db_write_lock("sync_engine.put_ironwood_subtree_roots", || {
                db.put_ironwood_subtree_roots(ironwood_start, ironwood_roots.as_slice())
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
/// immediately after. Short or out-of-order responses are rejected so
/// a lagging server cannot make the scanner repeatedly accept an empty
/// batch.
pub(super) async fn download_blocks(
    client: &mut CompactTxStreamerClient<Channel>,
    start: BlockHeight,
    end: BlockHeight,
    network: WalletNetwork,
) -> Result<MemoryBlockSource, SyncError> {
    let start_height = u32::from(start) as u64;
    let end_height = u32::from(end) as u64;
    let expected_count = expected_block_count(start_height, end_height)?;
    let capacity = usize::try_from(expected_count)
        .map_err(|_| SyncError::other("get_block_range request is too large"))?;
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
    blocks
        .try_reserve_exact(capacity)
        .map_err(|_| SyncError::other("get_block_range request is too large"))?;
    while let Some(block) = next_stream_message(&mut stream, "get_block_range stream").await? {
        if blocks.len() as u64 >= expected_count {
            return Err(SyncError::net(format!(
                "get_block_range returned more than {expected_count} blocks for request \
                 {start_height}..={end_height}"
            )));
        }
        let expected_height = start_height + blocks.len() as u64;
        if block.height != expected_height {
            return Err(SyncError::net(format!(
                "get_block_range returned height {} while expecting {expected_height} \
                 for request {start_height}..={end_height}",
                block.height,
            )));
        }
        blocks.push(block);
    }
    validate_downloaded_block_heights(
        start_height,
        end_height,
        blocks.iter().map(|block| block.height),
    )?;

    Ok(MemoryBlockSource::new(blocks))
}

fn expected_block_count(start_height: u64, end_height: u64) -> Result<u64, SyncError> {
    end_height
        .checked_sub(start_height)
        .and_then(|distance| distance.checked_add(1))
        .ok_or_else(|| {
            SyncError::other(format!(
                "get_block_range received a reversed request {start_height}..={end_height}"
            ))
        })
}

fn validate_downloaded_block_heights(
    start_height: u64,
    end_height: u64,
    heights: impl IntoIterator<Item = u64>,
) -> Result<(), SyncError> {
    let expected_count = expected_block_count(start_height, end_height)?;
    let mut actual_count = 0u64;
    for height in heights {
        let expected_height = start_height + actual_count;
        if height != expected_height {
            return Err(SyncError::net(format!(
                "get_block_range returned height {height} while expecting \
                 {expected_height} for request {start_height}..={end_height}"
            )));
        }
        actual_count += 1;
    }
    if actual_count != expected_count {
        return Err(SyncError::net(format!(
            "get_block_range returned {actual_count} of {expected_count} blocks for \
             request {start_height}..={end_height}"
        )));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn onion_lightwalletd_hosts_enable_onion_service_connections() {
        for (url, expected) in [
            ("https://example.com", false),
            ("https://lightwalletd.example.onion", true),
            ("https://LIGHTWALLETD.EXAMPLE.ONION", true),
        ] {
            let endpoint = Endpoint::from_shared(url.to_string()).expect("valid endpoint");
            assert_eq!(endpoint_allows_onion_services(&endpoint), expected, "{url}");
        }
    }

    #[tokio::test]
    async fn stalled_address_utxo_stream_start_is_bounded() {
        let result = tokio::time::timeout(
            Duration::from_secs(1),
            await_address_utxo_stream(
                Duration::from_millis(5),
                std::future::pending::<Result<Response<AddressUtxoStream>, Status>>(),
            ),
        )
        .await
        .expect("test guard: address UTXO stream start hung");

        assert!(matches!(
            result,
            Err(SyncError::Network(message))
                if message.contains("get_address_utxos_stream")
                    && message.contains("timed out")
        ));
    }

    #[tokio::test]
    async fn stalled_stream_message_is_bounded() {
        let result = tokio::time::timeout(
            Duration::from_secs(1),
            await_stream_message::<service::GetAddressUtxosReply, _>(
                "get_address_utxos_stream",
                Duration::from_millis(5),
                std::future::pending(),
            ),
        )
        .await
        .expect("test guard: address UTXO stream message hung");

        assert!(matches!(
            result,
            Err(SyncError::Network(message))
                if message.contains("get_address_utxos_stream")
                    && message.contains("timed out")
        ));
    }

    #[tokio::test]
    async fn background_transport_stays_direct_while_tor_is_desired() {
        // The background lane is pinned direct as a product decision: Tor
        // covers foreground traffic, and a background pass never brings Tor
        // up or borrows the foreground's client. Routed through the policy,
        // this call would be refused the moment Tor was desired; pinned, it
        // reaches the socket and fails only because nothing is listening.
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        crate::network_privacy::begin_tor_enable();

        let error = open_background_direct_lwd_channel("http://127.0.0.1:1")
            .await
            .expect_err("nothing listens on port 1");

        let message = error.to_string();
        assert!(
            message.contains("gRPC connect failed"),
            "expected a transport failure, got a policy refusal: {message}"
        );
    }

    #[tokio::test]
    async fn direct_connections_keep_tcp_nodelay_enabled() {
        // A direct-route lease aborts itself whenever the process-wide route is
        // Tor, so this has to hold the policy even though it never writes it.
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        let listener = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
            .await
            .expect("bind loopback listener");
        let port = listener.local_addr().expect("listener address").port();
        let accepted =
            tokio::spawn(async move { listener.accept().await.map(|(stream, _)| stream) });

        let uri: Uri = format!("http://127.0.0.1:{port}")
            .parse()
            .expect("valid loopback URI");
        let connection = DirectRouteConnector::new()
            .call(uri)
            .await
            .expect("direct loopback connection");

        assert!(connection
            .inner()
            .inner()
            .nodelay()
            .expect("read TCP_NODELAY"));
        accepted
            .await
            .expect("accept task")
            .expect("accepted connection");
    }

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

    #[test]
    fn downloaded_block_range_must_be_complete_and_ordered() {
        assert!(validate_downloaded_block_heights(10, 12, [10, 11, 12]).is_ok());
        assert!(validate_downloaded_block_heights(10, 12, [10, 12]).is_err());
        assert!(validate_downloaded_block_heights(10, 12, [10, 11]).is_err());
        assert!(validate_downloaded_block_heights(10, 12, [10, 11, 12, 13]).is_err());
        assert!(validate_downloaded_block_heights(10, 12, []).is_err());
        assert!(validate_downloaded_block_heights(12, 10, []).is_err());
    }
}
