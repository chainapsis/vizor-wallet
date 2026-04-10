//! lightwalletd transport and gRPC download helpers for the sync
//! engine.
//!
//! Everything in this module is an `async` call that talks to the
//! lightwalletd backend via tonic: opening the gRPC channel (over
//! plain TLS or through an isolated Tor circuit), pulling down the
//! sapling + orchard subtree roots, and streaming compact blocks for
//! one scan batch. The orchestration loop in `sync_engine::mod`
//! treats this module as its network edge — it calls the helpers
//! here, hands their outputs to librustzcash (`put_*_subtree_roots`,
//! `scan_cached_blocks`), and never talks to tonic itself.
//!
//! Error mapping is kept local: every call site wraps tonic / parsing
//! failures into `SyncError::net` or `SyncError::parse`, so the outer
//! loop only ever deals with the typed `SyncError` taxonomy.

use std::sync::atomic::Ordering;

use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use zcash_client_backend::{
    data_api::{
        chain::CommitmentTreeRoot,
        wallet::ConfirmationsPolicy,
        WalletCommitmentTrees, WalletRead,
    },
    proto::service::{
        self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange, Empty,
        GetSubtreeRootsArg, RawTransaction,
    },
};
use zcash_protocol::consensus::BlockHeight;

use super::block_source::MemoryBlockSource;
use super::{elapsed, SyncError, WalletDatabase};

/// Drop guard keeping the Tor circuit alive for a lightwalletd
/// connection opened via [`open_lwd_channel`]. `None` for the
/// plain-TLS path; `Some(_)` for the Tor path. Callers must bind this
/// alongside the returned client so the guard lives as long as the
/// client does.
pub(crate) type LwdTorGuard = Option<crate::wallet::tor::IsolatedCircuitGuard>;

/// Opens a tonic gRPC channel to the given lightwalletd URL and
/// returns `(client, tor_guard)`. Branches on the `USE_TOR` atomic in
/// `api::sync`: if enabled, the connection is routed through an
/// isolated Tor circuit via `wallet::tor::connect_lightwalletd`, and
/// `tor_guard` carries the `IsolatedCircuitGuard` that must stay
/// alive for as long as the returned client. If disabled, the
/// connection goes through plain tonic TLS and `tor_guard` is `None`.
///
/// Callers bind both results into `let` statements at function scope:
///
/// ```ignore
/// let (mut client, _tor_guard) = open_lwd_channel(url).await?;
/// // use `client` as before; `_tor_guard` just lives alongside it.
/// ```
pub(crate) async fn open_lwd_channel(
    lightwalletd_url: &str,
) -> Result<(CompactTxStreamerClient<Channel>, LwdTorGuard), SyncError> {
    // `SeqCst` pairs with the `SeqCst` store in
    // `api::sync::set_tor_enabled`. A `Relaxed` load here would let a
    // concurrent reader on ARM observe the stale pre-toggle value and
    // legally pick the wrong transport for this connection, which is
    // exactly the privacy-boundary race the Tor toggle is supposed to
    // prevent. Use the same ordering on both ends.
    if crate::api::sync::USE_TOR.load(Ordering::SeqCst) {
        let tor_dir = crate::api::sync::get_tor_dir().map_err(SyncError::net)?;
        let (client, guard) =
            crate::wallet::tor::connect_lightwalletd(tor_dir, lightwalletd_url).await?;
        log::info!("sync: lightwalletd connected via Tor");
        Ok((client, Some(guard)))
    } else {
        let channel = Endpoint::from_shared(lightwalletd_url.to_string())
            .map_err(|e| SyncError::net(format!("invalid URL: {e}")))?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| SyncError::net(format!("TLS error: {e}")))?
            .connect()
            .await
            .map_err(|e| SyncError::net(format!("gRPC connect failed: {e}")))?;
        Ok((CompactTxStreamerClient::new(channel), None))
    }
}

/// Pulls the latest sapling + orchard subtree roots from lightwalletd
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
) -> Result<(), SyncError> {
    let (sap_start, orch_start) = {
        let summary = db
            .get_wallet_summary(ConfirmationsPolicy::default())
            .map_err(|e| SyncError::db(format!("get_wallet_summary: {e}")))?;
        match summary {
            Some(s) => (s.next_sapling_subtree_index(), s.next_orchard_subtree_index()),
            None => (0, 0),
        }
    };
    log::info!(
        "[{}] sync: subtree roots start: sapling={}, orchard={}",
        elapsed(),
        sap_start,
        orch_start
    );

    // Sapling
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: sap_start as u32,
            shielded_protocol: service::ShieldedProtocol::Sapling.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| SyncError::net(format!("sapling subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("sapling subtree roots stream: {e}")))?
    {
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
        db.put_sapling_subtree_roots(sap_start, roots.as_slice())
            .map_err(|e| SyncError::db(format!("put_sapling_subtree_roots: {e}")))?;
    }

    // Orchard
    let mut stream = client
        .get_subtree_roots(GetSubtreeRootsArg {
            start_index: orch_start as u32,
            shielded_protocol: service::ShieldedProtocol::Orchard.into(),
            max_entries: 0,
        })
        .await
        .map_err(|e| SyncError::net(format!("orchard subtree roots: {e}")))?
        .into_inner();

    let mut roots = Vec::new();
    while let Some(root) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("orchard subtree roots stream: {e}")))?
    {
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
        db.put_orchard_subtree_roots(orch_start, roots.as_slice())
            .map_err(|e| SyncError::db(format!("put_orchard_subtree_roots: {e}")))?;
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
    let response = client
        .get_mempool_stream(Empty {})
        .await
        .map_err(|e| SyncError::net(format!("get_mempool_stream: {e}")))?;
    Ok(response.into_inner())
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
) -> Result<MemoryBlockSource, SyncError> {
    let mut stream = client
        .get_block_range(BlockRange {
            start: Some(BlockId {
                height: u32::from(start) as u64,
                hash: vec![],
            }),
            end: Some(BlockId {
                height: u32::from(end) as u64,
                hash: vec![],
            }),
        })
        .await
        .map_err(|e| SyncError::net(format!("get_block_range: {e}")))?
        .into_inner();

    let mut blocks = Vec::new();
    while let Some(block) = stream
        .message()
        .await
        .map_err(|e| SyncError::net(format!("get_block_range stream: {e}")))?
    {
        blocks.push(block);
    }

    Ok(MemoryBlockSource::new(blocks))
}
