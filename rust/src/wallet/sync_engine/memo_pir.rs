//! Private completion of Ironwood memos discovered by compact scanning.
//!
//! The server sees randomized iPIR queries, never a transaction ID or note
//! position. Snapshot metadata is accepted only after its block hash and
//! Ironwood tree size agree with the wallet's locally scanned chain state.

use std::collections::BTreeMap;
use std::time::Duration;

use bytes::Bytes;
use http::{Method, Request, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use zakura_pir_memo::{
    ClientError, GenerationManifest, PirSession, ACTION_EXPECTATION, RECORDS_PER_ROW,
};
use zcash_client_backend::data_api::memo_pir::{
    decrypt_and_store_ironwood_memo, IronwoodMemoRecord, MemoPirRead, MemoPirSnapshotAnchor,
    MemoPirSnapshotStatus, MemoPirStoreResult,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::{lwd::DirectRouteConnector, SyncError, WalletDatabase};

const DEFAULT_MAINNET_ENDPOINT: &str = "https://memo-pir.167.99.42.60.sslip.io";
const ENDPOINT_ENV: &str = "VIZOR_MEMO_PIR_URL";
const HTTP_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_MANIFEST_BYTES: usize = 1024 * 1024;
const MAX_PARAMS_BYTES: usize = 64 * 1024;
const MAX_PIR_BODY_BYTES: usize = 16 * 1024 * 1024;

/// Per-sync cached PIR state. A validated immutable generation is reused while
/// the wallet scans toward its anchor instead of redownloading parameters for
/// every compact-block batch.
pub(super) struct MemoPirSync {
    endpoint: Option<String>,
    session: Option<PirSession>,
}

impl MemoPirSync {
    pub(super) fn new(network: WalletNetwork) -> Self {
        let endpoint = (network == WalletNetwork::Main).then(|| {
            std::env::var(ENDPOINT_ENV).unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.to_owned())
        });
        Self {
            endpoint,
            session: None,
        }
    }

    /// Mainnet never falls back from memo PIR to transaction-ID enhancement.
    /// Test/regtest retain their existing behavior because the demo service is
    /// intentionally anchored to mainnet.
    pub(super) fn suppresses_tx_enhancement(&self) -> bool {
        self.endpoint.is_some()
    }

    pub(super) async fn run(&mut self, db: &mut WalletDatabase) -> Result<(), SyncError> {
        let requests = db
            .memo_pir_requests()
            .map_err(|error| SyncError::db(format!("memo_pir_requests: {error}")))?;
        if requests.is_empty() || self.endpoint.is_none() {
            return Ok(());
        }

        if self.session.is_none() {
            let endpoint = self.endpoint.as_deref().expect("checked above");
            self.session = Some(connect(endpoint).await?);
        }
        let session = self.session.as_ref().expect("initialized above");
        let snapshot_anchor = session.snapshot_anchor();
        match db
            .memo_pir_snapshot_status(MemoPirSnapshotAnchor {
                height: BlockHeight::from(snapshot_anchor.height),
                block_hash: BlockHash::from_slice(&snapshot_anchor.block_hash),
                ironwood_tree_size: snapshot_anchor.ironwood_tree_size,
            })
            .map_err(|error| SyncError::db(format!("memo_pir_snapshot_status: {error}")))?
        {
            MemoPirSnapshotStatus::NotYetScanned => return Ok(()),
            MemoPirSnapshotStatus::Mismatch => {
                return Err(SyncError::parse(
                    "memo PIR snapshot anchor disagrees with the locally scanned chain",
                ));
            }
            MemoPirSnapshotStatus::Accepted => {}
        }

        // One returned row can satisfy up to RECORDS_PER_ROW pending notes. We
        // group locally so duplicate row queries do not create linkable traffic.
        let mut rows = BTreeMap::<u64, Vec<_>>::new();
        for request in requests {
            let position = u64::from(request.position());
            if position < session.table_manifest().positions {
                rows.entry(position / RECORDS_PER_ROW as u64)
                    .or_default()
                    .push(request);
            }
        }

        let mut stored = 0usize;
        let row_count = rows.len();
        for requests in rows.into_values() {
            let position = u64::from(requests[0].position());
            let query = session
                .prepare_position(position)
                .map_err(client_protocol_error)?;
            let response = routed_request(
                Method::POST,
                &endpoint_path(self.endpoint.as_deref().expect("configured"), "/v1/action/query")?,
                query.request_body().to_vec(),
                MAX_PIR_BODY_BYTES,
            )
            .await?;
            let row = session
                .decode(query, &response)
                .map_err(client_protocol_error)?;

            for request in requests {
                let position = u64::from(request.position());
                let record = row.record(position).ok_or_else(|| {
                    SyncError::parse("memo PIR response did not contain the requested row")
                })?;
                let record =
                    IronwoodMemoRecord::from_parts(*record.ephemeral_key(), *record.ciphertext());
                let result = with_wallet_db_write_lock(
                    "sync_engine.memo_pir.decrypt_and_store_ironwood_memo",
                    || decrypt_and_store_ironwood_memo(db, request, &record),
                )
                .map_err(|error| SyncError::db(format!("store memo PIR result: {error}")))?;
                match result {
                    MemoPirStoreResult::Stored => stored += 1,
                    MemoPirStoreResult::AlreadyResolved => {}
                    MemoPirStoreResult::Rejected => {
                        return Err(SyncError::parse(
                            "memo PIR record failed wallet note authentication",
                        ));
                    }
                }
            }
        }

        if row_count > 0 {
            // Counts are useful demo evidence without recording txids or note positions.
            log::info!(
                "sync: memo PIR privately completed {stored} Ironwood memo(s) in {row_count} row query/queries"
            );
        }
        Ok(())
    }
}

async fn connect(endpoint: &str) -> Result<PirSession, SyncError> {
    if !endpoint.starts_with("https://") {
        return Err(SyncError::parse(
            "memo PIR endpoint must use an https:// URL",
        ));
    }
    let manifest = routed_request(
        Method::GET,
        &endpoint_path(endpoint, "/v1/generation")?,
        Vec::new(),
        MAX_MANIFEST_BYTES,
    )
    .await?;
    let manifest: GenerationManifest = serde_json::from_slice(&manifest)
        .map_err(|error| SyncError::parse(format!("memo PIR manifest JSON: {error}")))?;
    let params = routed_request(
        Method::GET,
        &endpoint_path(endpoint, "/v1/action/params")?,
        Vec::new(),
        MAX_PARAMS_BYTES,
    )
    .await?;
    let public_params = routed_request(
        Method::GET,
        &endpoint_path(endpoint, "/v1/action/public-params")?,
        Vec::new(),
        MAX_PIR_BODY_BYTES,
    )
    .await?;
    PirSession::new(
        "main",
        manifest,
        ACTION_EXPECTATION,
        &params,
        &public_params,
    )
    .map_err(client_protocol_error)
}

fn endpoint_path(endpoint: &str, path: &str) -> Result<String, SyncError> {
    let endpoint = endpoint.trim_end_matches('/');
    if !endpoint.starts_with("https://") {
        return Err(SyncError::parse(
            "memo PIR endpoint must use an https:// URL",
        ));
    }
    Ok(format!("{endpoint}{path}"))
}

fn client_protocol_error(error: ClientError) -> SyncError {
    SyncError::parse(format!("memo PIR protocol validation failed: {error}"))
}

async fn routed_request(
    method: Method,
    url: &str,
    body: Vec<u8>,
    body_limit: usize,
) -> Result<Vec<u8>, SyncError> {
    if crate::network_privacy::is_tor_desired() {
        let client = crate::network_privacy::tor_client_for_route(true)
            .map_err(|error| SyncError::net(format!("network privacy blocked memo PIR: {error}")))?
            .ok_or_else(|| SyncError::net("Tor route changed before memo PIR request"))?;
        let uri = url
            .parse()
            .map_err(|error| SyncError::parse(format!("invalid memo PIR URL: {error}")))?;
        let response = match method {
            Method::GET => {
                tokio::time::timeout(
                    HTTP_TIMEOUT,
                    client.http_get(
                        uri,
                        |builder| builder,
                        |incoming| tor_body_limited(incoming, body_limit),
                        0,
                        |_| None,
                    ),
                )
                .await
            }
            Method::POST => {
                tokio::time::timeout(
                    HTTP_TIMEOUT,
                    client.http_post(
                        uri,
                        |builder| {
                            builder.header(http::header::CONTENT_TYPE, "application/octet-stream")
                        },
                        Full::new(Bytes::from(body)),
                        |incoming| tor_body_limited(incoming, body_limit),
                        0,
                        |_| None,
                    ),
                )
                .await
            }
            _ => unreachable!("memo PIR uses GET and POST only"),
        }
        .map_err(|_| SyncError::net("memo PIR Tor request timed out"))?
        .map_err(|error| SyncError::net(format!("memo PIR Tor request failed: {error}")))?;
        if !response.status().is_success() {
            return Err(SyncError::net(format!(
                "memo PIR server returned HTTP {}",
                response.status()
            )));
        }
        return Ok(response.into_body());
    }

    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid memo PIR URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("memo PIR transport requires HTTPS"));
    }
    let connector = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_only()
        .enable_http1()
        .wrap_connector(DirectRouteConnector::new());
    let client: Client<_, Full<Bytes>> = Client::builder(TokioExecutor::new()).build(connector);
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(http::header::CONTENT_TYPE, "application/octet-stream")
        .body(Full::new(Bytes::from(body)))
        .map_err(|error| SyncError::parse(format!("build memo PIR request: {error}")))?;
    let response = tokio::time::timeout(HTTP_TIMEOUT, client.request(request))
        .await
        .map_err(|_| SyncError::net("memo PIR HTTPS request timed out"))?
        .map_err(|error| SyncError::net(format!("memo PIR HTTPS request failed: {error}")))?;
    if !response.status().is_success() {
        return Err(SyncError::net(format!(
            "memo PIR server returned HTTP {}",
            response.status()
        )));
    }
    read_body_limited(response.status(), response.into_body(), body_limit).await
}

async fn tor_body_limited(
    mut body: Incoming,
    limit: usize,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(zcash_client_backend::tor::http::HttpError::from)?;
        if let Some(data) = frame.data_ref() {
            if bytes.len().saturating_add(data.len()) > limit {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "memo PIR HTTP body exceeds limit",
                )
                .into());
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(bytes)
}

async fn read_body_limited(
    status: StatusCode,
    mut body: Incoming,
    limit: usize,
) -> Result<Vec<u8>, SyncError> {
    debug_assert!(status.is_success());
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame
            .map_err(|error| SyncError::net(format!("read memo PIR response body: {error}")))?;
        if let Some(data) = frame.data_ref() {
            if bytes.len().saturating_add(data.len()) > limit {
                return Err(SyncError::parse("memo PIR HTTP body exceeds limit"));
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_mainnet_suppresses_legacy_transaction_enhancement() {
        assert!(MemoPirSync::new(WalletNetwork::Main).suppresses_tx_enhancement());
        assert!(!MemoPirSync::new(WalletNetwork::Test).suppresses_tx_enhancement());
        assert!(!MemoPirSync::new(WalletNetwork::Regtest).suppresses_tx_enhancement());
    }

    #[test]
    fn endpoint_requires_https() {
        assert!(endpoint_path("http://example.test", "/v1/generation").is_err());
        assert_eq!(
            endpoint_path("https://example.test/", "/v1/generation").unwrap(),
            "https://example.test/v1/generation"
        );
    }

    /// Manual smoke test for the deployed demo service. It issues a randomized
    /// cover query, so running it never discloses a wallet position.
    #[tokio::test]
    #[ignore = "requires the deployed memo-PIR demo endpoint"]
    async fn deployed_endpoint_accepts_and_decodes_a_private_query() {
        // Production sync installs this while opening lightwalletd; this test
        // intentionally exercises the PIR transport in isolation.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let session = connect(DEFAULT_MAINNET_ENDPOINT).await.unwrap();
        let query = session.prepare_dummy().unwrap();
        let response = routed_request(
            Method::POST,
            &endpoint_path(DEFAULT_MAINNET_ENDPOINT, "/v1/action/query").unwrap(),
            query.request_body().to_vec(),
            MAX_PIR_BODY_BYTES,
        )
        .await
        .unwrap();

        session.decode(query, &response).unwrap();
    }
}
