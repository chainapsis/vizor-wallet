//! Private completion of Ironwood transactions discovered by compact scanning.
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
use zakura_pir_enhance::client::record_in_row;
use zakura_pir_enhance::{
    apply_record, AcceptedAnchor, ClientError, ClientResourceLimits, EnhanceGeneration,
    EnhanceSession, GenerationAcceptance, QuerySession, RECORDS_PER_ROW,
};
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirRead, EnhancePirSnapshotAnchor, EnhancePirSnapshotStatus, EnhancePirStoreResult,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::{lwd::DirectRouteConnector, SyncError, WalletDatabase};

const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";
const ENDPOINT_ENV: &str = "VIZOR_ENHANCE_PIR_URL";
const LEGACY_ENDPOINT_ENV: &str = "VIZOR_MEMO_PIR_URL";
const HTTP_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_SESSION_BYTES: usize = 1024 * 1024;
const MAX_PIR_BODY_BYTES: usize = 16 * 1024 * 1024;
/// Bounds deterministic PIR setup work on the least-capable supported client.
const MAX_LOGICAL_ROWS: u64 = 65_536;

/// Per-sync cached PIR state. A validated immutable generation is reused while
/// the wallet scans toward its anchor instead of redownloading parameters for
/// every compact-block batch.
pub(super) struct EnhancePirSync {
    endpoint: Option<String>,
    session: Option<QuerySession>,
}

impl EnhancePirSync {
    pub(super) fn new(network: WalletNetwork, enabled: bool) -> Self {
        let endpoint = (enabled && network == WalletNetwork::Main).then(|| {
            std::env::var(ENDPOINT_ENV)
                .or_else(|_| std::env::var(LEGACY_ENDPOINT_ENV))
                .unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.to_owned())
        });
        Self {
            endpoint,
            session: None,
        }
    }

    pub(super) fn enabled(&self) -> bool {
        self.endpoint.is_some()
    }

    pub(super) async fn run(&mut self, db: &mut WalletDatabase) -> Result<(), SyncError> {
        let requests = db
            .enhance_pir_requests()
            .map_err(|error| SyncError::db(format!("enhance_pir_requests: {error}")))?;
        if requests.is_empty() || self.endpoint.is_none() {
            return Ok(());
        }

        if self.session.is_none() {
            let endpoint = self.endpoint.as_deref().expect("checked above");
            let init = fetch_init(endpoint).await?;
            match snapshot_status(db, &init.generation)? {
                EnhancePirSnapshotStatus::NotYetScanned => return Ok(()),
                EnhancePirSnapshotStatus::Mismatch => return Err(snapshot_mismatch()),
                EnhancePirSnapshotStatus::Accepted => {}
            }
            let acceptance = generation_acceptance(&init.generation)?;
            self.session =
                Some(QuerySession::from_session(init, &acceptance).map_err(client_protocol_error)?);
        }
        let session = self.session.as_ref().expect("initialized above");
        let generation = session.generation();
        match snapshot_status(db, generation)? {
            EnhancePirSnapshotStatus::NotYetScanned => return Ok(()),
            EnhancePirSnapshotStatus::Mismatch => return Err(snapshot_mismatch()),
            EnhancePirSnapshotStatus::Accepted => {}
        }

        // One returned row can satisfy up to RECORDS_PER_ROW pending notes. We
        // group locally so duplicate row queries do not create linkable traffic.
        let mut rows = BTreeMap::<u64, Vec<_>>::new();
        for request in requests {
            let position = u64::from(request.position());
            if position < session.generation().ironwood_tree_size {
                rows.entry(position / RECORDS_PER_ROW as u64)
                    .or_default()
                    .push(request);
            }
        }

        let mut stored = 0usize;
        let row_count = rows.len();
        for requests in rows.into_values() {
            let position = u64::from(requests[0].position());
            let (query, _) = session
                .prepare_position(position)
                .map_err(client_protocol_error)?;
            let response = routed_request(
                Method::POST,
                &endpoint_path(
                    self.endpoint.as_deref().expect("configured"),
                    "/v1/enhance/query",
                )?,
                query.body().to_vec(),
                MAX_PIR_BODY_BYTES,
            )
            .await?;
            let row = session
                .decode(query, &response)
                .map_err(client_protocol_error)?;

            for request in requests {
                let position = u64::from(request.position());
                let slot = position as usize % RECORDS_PER_ROW;
                let wire_record = record_in_row(&row, slot).map_err(client_protocol_error)?;
                let result =
                    with_wallet_db_write_lock("sync_engine.enhance_pir.apply_record", || {
                        apply_record(db, request, &wire_record)
                    })
                    .map_err(|error| SyncError::db(format!("apply Enhance PIR record: {error}")))?;
                let incoming = result.incoming;
                let outgoing = result.outgoing;
                stored += [incoming, outgoing]
                    .into_iter()
                    .filter(|result| *result == EnhancePirStoreResult::Stored)
                    .count();
                if incoming == EnhancePirStoreResult::Rejected
                    || outgoing == EnhancePirStoreResult::Rejected
                {
                    return Err(SyncError::parse(
                        "Enhance PIR record failed wallet authentication",
                    ));
                }
            }
        }

        if row_count > 0 {
            // Counts are useful demo evidence without recording txids or note positions.
            log::info!(
                "sync: Enhance PIR privately completed {stored} Ironwood enhancement(s) in {row_count} row query/queries"
            );
        }
        Ok(())
    }
}

async fn fetch_init(endpoint: &str) -> Result<EnhanceSession, SyncError> {
    if !endpoint.starts_with("https://") {
        return Err(SyncError::parse(
            "Enhance PIR endpoint must use an https:// URL",
        ));
    }
    let session = routed_request(
        Method::GET,
        &endpoint_path(endpoint, "/v1/enhance/init")?,
        Vec::new(),
        MAX_SESSION_BYTES,
    )
    .await?;
    let session: EnhanceSession = serde_json::from_slice(&session)
        .map_err(|error| SyncError::parse(format!("Enhance PIR session JSON: {error}")))?;
    Ok(session)
}

fn snapshot_status(
    db: &WalletDatabase,
    generation: &EnhanceGeneration,
) -> Result<EnhancePirSnapshotStatus, SyncError> {
    db.enhance_pir_snapshot_status(EnhancePirSnapshotAnchor {
        height: BlockHeight::from(u32::try_from(generation.anchor_height).map_err(|_| {
            SyncError::parse("Enhance PIR anchor height exceeds the supported range")
        })?),
        block_hash: parse_display_block_hash(&generation.anchor_block_hash)?,
        ironwood_tree_size: generation.ironwood_tree_size,
    })
    .map_err(|error| SyncError::db(format!("enhance_pir_snapshot_status: {error}")))
}

fn generation_acceptance(
    generation: &EnhanceGeneration,
) -> Result<GenerationAcceptance, SyncError> {
    let block_hash: [u8; 32] = hex::decode(&generation.anchor_block_hash)
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR anchor hash: {error}")))?
        .try_into()
        .map_err(|_| SyncError::parse("invalid Enhance PIR anchor hash length"))?;
    Ok(GenerationAcceptance::new(
        AcceptedAnchor::new(
            generation.anchor_height,
            block_hash,
            generation.ironwood_tree_size,
        ),
        ClientResourceLimits::new(MAX_LOGICAL_ROWS),
    ))
}

fn snapshot_mismatch() -> SyncError {
    SyncError::parse("Enhance PIR snapshot anchor disagrees with the locally scanned chain")
}

fn parse_display_block_hash(hash: &str) -> Result<BlockHash, SyncError> {
    let mut bytes = hex::decode(hash)
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR anchor hash: {error}")))?;
    if bytes.len() != 32 {
        return Err(SyncError::parse("invalid Enhance PIR anchor hash length"));
    }
    bytes.reverse();
    Ok(BlockHash::from_slice(&bytes))
}

fn endpoint_path(endpoint: &str, path: &str) -> Result<String, SyncError> {
    let endpoint = endpoint.trim_end_matches('/');
    if !endpoint.starts_with("https://") {
        return Err(SyncError::parse(
            "Enhance PIR endpoint must use an https:// URL",
        ));
    }
    Ok(format!("{endpoint}{path}"))
}

fn client_protocol_error(error: ClientError) -> SyncError {
    SyncError::parse(format!("Enhance PIR protocol validation failed: {error}"))
}

async fn routed_request(
    method: Method,
    url: &str,
    body: Vec<u8>,
    body_limit: usize,
) -> Result<Vec<u8>, SyncError> {
    if crate::network_privacy::is_tor_desired() {
        let client = crate::network_privacy::tor_client_for_route(true, || false)
            .await
            .map_err(|error| {
                SyncError::net(format!("network privacy blocked Enhance PIR: {error}"))
            })?
            .ok_or_else(|| SyncError::net("Tor route changed before Enhance PIR request"))?;
        let uri = url
            .parse()
            .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
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
            _ => unreachable!("Enhance PIR uses GET and POST only"),
        }
        .map_err(|_| SyncError::net("Enhance PIR Tor request timed out"))?
        .map_err(|error| SyncError::net(format!("Enhance PIR Tor request failed: {error}")))?;
        if !response.status().is_success() {
            return Err(SyncError::net(format!(
                "Enhance PIR server returned HTTP {}",
                response.status()
            )));
        }
        return Ok(response.into_body());
    }

    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("Enhance PIR transport requires HTTPS"));
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
        .map_err(|error| SyncError::parse(format!("build Enhance PIR request: {error}")))?;
    let response = tokio::time::timeout(HTTP_TIMEOUT, client.request(request))
        .await
        .map_err(|_| SyncError::net("Enhance PIR HTTPS request timed out"))?
        .map_err(|error| SyncError::net(format!("Enhance PIR HTTPS request failed: {error}")))?;
    if !response.status().is_success() {
        return Err(SyncError::net(format!(
            "Enhance PIR server returned HTTP {}",
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
                    "Enhance PIR HTTP body exceeds limit",
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
            .map_err(|error| SyncError::net(format!("read Enhance PIR response body: {error}")))?;
        if let Some(data) = frame.data_ref() {
            if bytes.len().saturating_add(data.len()) > limit {
                return Err(SyncError::parse("Enhance PIR HTTP body exceeds limit"));
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
    fn only_enabled_mainnet_uses_enhance_pir() {
        assert!(EnhancePirSync::new(WalletNetwork::Main, true).enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Main, false).enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Test, true).enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Regtest, true).enabled());
    }

    #[test]
    fn endpoint_requires_https() {
        assert!(endpoint_path("http://example.test", "/v1/enhance/init").is_err());
        assert_eq!(
            endpoint_path("https://example.test/", "/v1/enhance/init").unwrap(),
            "https://example.test/v1/enhance/init"
        );
    }

    #[test]
    fn display_block_hash_is_converted_to_internal_byte_order() {
        let bytes: [u8; 32] = std::array::from_fn(|index| index as u8);
        let expected = BlockHash::from_slice(&bytes);
        assert_eq!(
            parse_display_block_hash(&expected.to_string()).unwrap(),
            expected,
        );
    }

    /// Manual smoke test for the deployed demo service. It issues a randomized
    /// cover query, so running it never discloses a wallet position.
    #[tokio::test]
    #[ignore = "requires the deployed Enhance-PIR demo endpoint"]
    async fn deployed_endpoint_accepts_and_decodes_a_private_query() {
        // Production sync installs this while opening lightwalletd; this test
        // intentionally exercises the PIR transport in isolation.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let init = fetch_init(DEFAULT_MAINNET_ENDPOINT).await.unwrap();
        let acceptance = generation_acceptance(&init.generation).unwrap();
        let session = QuerySession::from_session(init, &acceptance).unwrap();
        let query = session.prepare_dummy().unwrap();
        let response = routed_request(
            Method::POST,
            &endpoint_path(DEFAULT_MAINNET_ENDPOINT, "/v1/enhance/query").unwrap(),
            query.body().to_vec(),
            MAX_PIR_BODY_BYTES,
        )
        .await
        .unwrap();

        session.decode(query, &response).unwrap();
    }
}
