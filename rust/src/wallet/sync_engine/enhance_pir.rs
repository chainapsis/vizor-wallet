//! Application policy and transport for shared private recovery.
use super::{
    block_source::MemoryBlockSource, lwd::DirectRouteConnector, SyncError, WalletDatabase,
};
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use bytes::Bytes;
use futures::StreamExt;
use http::{Method, Request, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use std::{
    future::Future,
    time::{Duration, Instant},
};
use tonic::transport::Channel;
use zakura_pir_enhance::transport::{self, BoundedBody, PendingClient};
use zakura_pir_enhance::wallet::{Acceptance, PreparedWork};
use zakura_pir_enhance::{ClientError, ClientResourceLimits, EnhanceGeneration};
use zcash_client_backend::{
    data_api::enhance_pir::{
        EnhancePirRead, EnhancePirStoreResult, EnhancePirWrite, IronwoodEnhanceDiscoveryRequest,
        IronwoodEnhanceDiscoveryResult,
    },
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_protocol::consensus::BlockHeight;
const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";
const ENDPOINT_ENV: &str = "VIZOR_ENHANCE_PIR_URL";
const LEGACY_ENDPOINT_ENV: &str = "VIZOR_MEMO_PIR_URL";
const HTTP_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_LOGICAL_ROWS: u64 = 65_536;
const REDISCOVERY_COVER_BLOCKS: u32 = 100;

fn rediscovery_cover_start(height: BlockHeight) -> BlockHeight {
    BlockHeight::from_u32(
        u32::from(height).saturating_sub(REDISCOVERY_COVER_BLOCKS.saturating_sub(1)),
    )
}

pub(super) struct EnhancePirSync {
    network: WalletNetwork,
    db_path: String,
    endpoint: Option<String>,
    pending_session: Option<PendingClient>,
    session: Option<transport::Client>,
    deferred: bool,
    attempted_discovery: Vec<IronwoodEnhanceDiscoveryRequest>,
}
#[derive(Debug)]
pub(super) enum EnhancePirRunError {
    ExitRequested,
    Failed(SyncError),
}
impl From<SyncError> for EnhancePirRunError {
    fn from(e: SyncError) -> Self {
        Self::Failed(e)
    }
}
impl From<ClientError> for EnhancePirRunError {
    fn from(e: ClientError) -> Self {
        match e {
            ClientError::Cancelled => Self::ExitRequested,
            e => Self::Failed(client_protocol_error(e)),
        }
    }
}
struct RoutedTransport<'a, F>(&'a F);
impl<F: Fn() -> bool> transport::Transport for RoutedTransport<'_, F> {
    async fn execute(
        &self,
        request: transport::Request,
    ) -> Result<transport::ResponseBody, ClientError> {
        let collector = request.response_body();
        let response = routed_request(
            match request.method {
                transport::Method::Get => Method::GET,
                transport::Method::Post => Method::POST,
            },
            &request.url,
            request.body,
            collector,
            self.0,
        )
        .await;
        if (self.0)() {
            return Err(ClientError::Cancelled);
        }
        response.map_err(|e| match e {
            EnhancePirRunError::ExitRequested => ClientError::Cancelled,
            EnhancePirRunError::Failed(e) => ClientError::Transport(e.to_string()),
        })
    }
}
impl EnhancePirSync {
    pub(super) fn new(network: WalletNetwork, enabled: bool, db_path: &str) -> Self {
        Self {
            network,
            db_path: db_path.into(),
            endpoint: (enabled && network == WalletNetwork::Main).then(|| {
                std::env::var(ENDPOINT_ENV)
                    .or_else(|_| std::env::var(LEGACY_ENDPOINT_ENV))
                    .unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.into())
            }),
            pending_session: None,
            session: None,
            deferred: false,
            attempted_discovery: Vec::new(),
        }
    }
    pub(super) fn enabled(&self) -> bool {
        self.endpoint.is_some()
    }
    pub(super) fn defer(&mut self) {
        self.deferred = true;
        set_phase(&self.db_path, "retrying_later");
    }
    fn acceptance(
        &self,
        db: &WalletDatabase,
        generation: &EnhanceGeneration,
    ) -> Result<Acceptance, EnhancePirRunError> {
        Ok(zakura_pir_enhance::wallet::acceptance(
            db,
            generation,
            &self.network,
            ClientResourceLimits::new(MAX_LOGICAL_ROWS),
        )
        .map_err(|e| SyncError::db(e.to_string()))??)
    }
    pub(super) async fn run(
        &mut self,
        db: &mut WalletDatabase,
        lwd: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        if should_exit() {
            return Err(EnhancePirRunError::ExitRequested);
        }
        if !self.enabled() || self.deferred {
            return Ok(());
        }
        let work = PreparedWork::new(
            db.enhance_pir_work()
                .map_err(|e| SyncError::db(e.to_string()))?,
        );
        for request in work.rediscover {
            // Partial reconstruction can leave active jobs at the same height.
            // Retry those on the next foreground poll, not every scan batch.
            if self.attempted_discovery.contains(&request) {
                continue;
            }
            self.attempted_discovery.push(request);
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            let downloaded;
            let block =
                if let Some(block) = cached.and_then(|source| source.block_at(request.height)) {
                    block
                } else {
                    // Fetch a trailing cover range rather than one isolated block.
                    // Accepted limitation: the requested height remains the range endpoint,
                    // so an informed lightwalletd can still infer the height of interest.
                    downloaded = await_request_with_cancel(
                        super::lwd::download_blocks(
                            lwd,
                            rediscovery_cover_start(request.height),
                            request.height,
                            self.network,
                        ),
                        should_exit,
                        "rediscovery download timed out",
                    )
                    .await?;
                    downloaded
                        .block_at(request.height)
                        .ok_or_else(|| SyncError::parse("rediscovery block missing"))?
                };
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            let result = with_wallet_db_write_lock("enhance_pir.rediscover", || {
                db.rebuild_ironwood_enhancement(request, block)
            })
            .map_err(|e| SyncError::db(e.to_string()))?;
            if matches!(result, IronwoodEnhanceDiscoveryResult::Rejected) {
                return Err(SyncError::parse("rediscovery block rejected").into());
            }
        }
        let work = PreparedWork::new(
            db.enhance_pir_work()
                .map_err(|e| SyncError::db(e.to_string()))?,
        );
        if work.query_count() == 0 {
            return Ok(());
        }
        // Always revalidate after scans and rewinds, including cached coverage.
        if let Some(session) = &self.session {
            match self.acceptance(db, session.generation())? {
                Acceptance::Accepted(_) => {}
                Acceptance::WaitingForScanning => {
                    set_phase(&self.db_path, "waiting_for_scanning");
                    return Ok(());
                }
                Acceptance::Mismatch => {
                    self.session = None;
                    self.pending_session = None;
                    return Err(SyncError::parse("snapshot anchor mismatch").into());
                }
            }
        }
        let uncovered = self.session.as_ref().is_none_or(|session| {
            work.positions()
                .any(|p| p >= session.generation().ironwood_tree_size)
        });
        set_phase(
            &self.db_path,
            if uncovered {
                "waiting_for_snapshot"
            } else {
                "recovering"
            },
        );
        let route = RoutedTransport(should_exit);
        // Refresh is opportunistic: it must not suppress already accepted coverage.
        let refresh = async {
            if uncovered && self.pending_session.is_none() && refresh_due(&self.db_path) {
                mark_refresh(&self.db_path);
                self.pending_session = Some(
                    PendingClient::fetch(&route, self.endpoint.as_deref().expect("enabled"))
                        .await?,
                );
            }
            if let Some(pending) = &self.pending_session {
                match self.acceptance(db, pending.generation())? {
                    Acceptance::Accepted(acceptance) => {
                        if should_exit() {
                            return Err(EnhancePirRunError::ExitRequested);
                        }
                        let pending = self.pending_session.take().expect("pending");
                        // A stale service replica must not replace usable coverage
                        // with an older, smaller snapshot of the accepted chain.
                        if self.session.as_ref().is_none_or(|current| {
                            pending.generation().ironwood_tree_size
                                > current.generation().ironwood_tree_size
                        }) {
                            self.session = Some(pending.accept(&acceptance)?);
                        }
                    }
                    Acceptance::WaitingForScanning => {
                        set_phase(&self.db_path, "waiting_for_scanning");
                    }
                    Acceptance::Mismatch => {
                        self.pending_session = None;
                        return Err(SyncError::parse("snapshot anchor mismatch").into());
                    }
                }
            }
            Ok(())
        }
        .await;
        if !retain_coverage_on_refresh_failure(refresh, self.session.is_some())? {
            self.pending_session = None;
            set_phase(&self.db_path, "retrying_later");
        }
        let Some(session) = &self.session else {
            return Ok(());
        };
        let results = session.query_batch(&route, work.positions());
        futures::pin_mut!(results);
        while let Some(result) = results.next().await {
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            let record = match result.record {
                Err(ClientError::OutsideCoverage(_)) => continue,
                result => result?,
            };
            for (request, record) in work.map_record(result.position, record) {
                let result = with_wallet_db_write_lock("enhance_pir.apply", || {
                    db.apply_ironwood_enhance_record(request, &record)
                })
                .map_err(|e| SyncError::db(e.to_string()))?;
                if result == EnhancePirStoreResult::Rejected {
                    return Err(SyncError::parse("PIR record failed wallet authentication").into());
                }
            }
        }
        let remaining = PreparedWork::new(
            db.enhance_pir_work()
                .map_err(|e| SyncError::db(e.to_string()))?,
        );
        log::info!("sync: private recovery has {} active queries, {} rediscovery jobs, and {} suspended obligations", remaining.query_count(), remaining.rediscover.len(), remaining.suspended);
        Ok(())
    }
}
/// A bad candidate cannot invalidate a separately revalidated current session.
/// Cancellation always wins, even when old coverage remains usable.
fn retain_coverage_on_refresh_failure(
    refresh: Result<(), EnhancePirRunError>,
    has_coverage: bool,
) -> Result<bool, EnhancePirRunError> {
    match refresh {
        Ok(()) => Ok(true),
        Err(EnhancePirRunError::Failed(error)) if has_coverage => {
            log::warn!("sync: snapshot refresh failed; retaining accepted coverage: {error}");
            Ok(false)
        }
        Err(error) => Err(error),
    }
}

fn client_protocol_error(error: ClientError) -> SyncError {
    SyncError::parse(format!("Enhance PIR: {error}"))
}

async fn routed_request(
    method: Method,
    url: &str,
    body: Vec<u8>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
) -> Result<transport::ResponseBody, EnhancePirRunError> {
    if should_exit() {
        return Err(EnhancePirRunError::ExitRequested);
    }
    if crate::network_privacy::is_tor_desired() {
        let client = crate::network_privacy::tor_client_for_route(true, || should_exit())
            .await
            .map_err(|error| {
                if should_exit() {
                    EnhancePirRunError::ExitRequested
                } else {
                    EnhancePirRunError::Failed(SyncError::net(format!(
                        "network privacy blocked Enhance PIR: {error}"
                    )))
                }
            })?
            .ok_or_else(|| {
                EnhancePirRunError::Failed(SyncError::net(
                    "Tor route changed before Enhance PIR request",
                ))
            })?;
        let uri = url
            .parse()
            .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
        let request = async {
            match method {
                Method::GET => {
                    client
                        .http_get(
                            uri,
                            |builder| builder,
                            |incoming| tor_body_limited(incoming, collector),
                            0,
                            |_| None,
                        )
                        .await
                }
                Method::POST => {
                    client
                        .http_post(
                            uri,
                            |builder| {
                                builder
                                    .header(http::header::CONTENT_TYPE, "application/octet-stream")
                            },
                            Full::new(Bytes::from(body)),
                            |incoming| tor_body_limited(incoming, collector),
                            0,
                            |_| None,
                        )
                        .await
                }
                _ => unreachable!("Enhance PIR uses GET and POST only"),
            }
            .map_err(|error| SyncError::net(format!("Enhance PIR Tor request failed: {error}")))
        };
        let response =
            await_request_with_cancel(request, should_exit, "Enhance PIR Tor request timed out")
                .await?;
        if !response.status().is_success() {
            return Err(SyncError::net(format!(
                "Enhance PIR server returned HTTP {}",
                response.status()
            ))
            .into());
        }
        return Ok(response.into_body());
    }

    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("Enhance PIR transport requires HTTPS").into());
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
    let request = async {
        let response = client.request(request).await.map_err(|error| {
            SyncError::net(format!("Enhance PIR HTTPS request failed: {error}"))
        })?;
        if !response.status().is_success() {
            return Err(SyncError::net(format!(
                "Enhance PIR server returned HTTP {}",
                response.status()
            )));
        }
        read_body_limited(response.status(), response.into_body(), collector).await
    };
    await_request_with_cancel(request, should_exit, "Enhance PIR HTTPS request timed out").await
}

async fn await_request_with_cancel<T>(
    request: impl Future<Output = Result<T, SyncError>>,
    should_exit: &impl Fn() -> bool,
    timeout_message: &'static str,
) -> Result<T, EnhancePirRunError> {
    if should_exit() {
        return Err(EnhancePirRunError::ExitRequested);
    }
    tokio::pin!(request);
    tokio::select! {
        biased;
        _ = super::watch_for_exit(should_exit) => Err(EnhancePirRunError::ExitRequested),
        result = tokio::time::timeout(HTTP_TIMEOUT, &mut request) => {
            result
                .map_err(|_| EnhancePirRunError::Failed(SyncError::net(timeout_message)))?
                .map_err(EnhancePirRunError::Failed)
        }
    }
}

async fn tor_body_limited(
    mut body: Incoming,
    mut bytes: BoundedBody,
) -> Result<transport::ResponseBody, zcash_client_backend::tor::Error> {
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(zcash_client_backend::tor::http::HttpError::from)?;
        if let Some(data) = frame.data_ref() {
            bytes.extend(data).map_err(|error| {
                std::io::Error::new(std::io::ErrorKind::InvalidData, error.to_string())
            })?;
        }
    }
    Ok(bytes.finish())
}

async fn read_body_limited(
    status: StatusCode,
    mut body: Incoming,
    mut bytes: BoundedBody,
) -> Result<transport::ResponseBody, SyncError> {
    debug_assert!(status.is_success());
    while let Some(frame) = body.frame().await {
        let frame = frame
            .map_err(|error| SyncError::net(format!("read Enhance PIR response body: {error}")))?;
        if let Some(data) = frame.data_ref() {
            bytes.extend(data).map_err(client_protocol_error)?;
        }
    }
    Ok(bytes.finish())
}

#[derive(Default)]
struct ServiceState {
    path: String,
    phase: String,
    last_refresh: Option<Instant>,
}
static SERVICE: std::sync::Mutex<Option<ServiceState>> = std::sync::Mutex::new(None);
pub(super) fn begin_session(path: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|e| e.into_inner());
    if state.as_ref().is_none_or(|s| s.path != path) {
        *state = Some(ServiceState {
            path: path.into(),
            ..Default::default()
        });
    }
    state.as_mut().unwrap().phase.clear();
}
fn set_phase(path: &str, phase: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(state) = state.as_mut().filter(|s| s.path == path) {
        state.phase = phase.into();
    }
}
fn refresh_due(path: &str) -> bool {
    SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|s| s.path == path)
        .and_then(|s| s.last_refresh)
        .is_none_or(|t| t.elapsed() >= Duration::from_secs(60))
}
fn mark_refresh(path: &str) {
    if let Some(state) = SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_mut()
        .filter(|s| s.path == path)
    {
        state.last_refresh = Some(Instant::now());
    }
}
pub(super) fn phase(path: &str) -> String {
    SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|s| s.path == path)
        .map(|s| s.phase.clone())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };

    struct StaticTransport(Vec<u8>);
    impl transport::Transport for StaticTransport {
        async fn execute(
            &self,
            request: transport::Request,
        ) -> Result<transport::ResponseBody, ClientError> {
            let mut body = request.response_body();
            body.extend(&self.0)?;
            Ok(body.finish())
        }
    }

    #[test]
    fn refresh_failure_preserves_coverage_but_never_swallows_cancellation() {
        for message in [
            "initialization HTTP failure",
            "snapshot anchor mismatch",
            "invalid setup",
        ] {
            let failure = || Err(EnhancePirRunError::Failed(SyncError::parse(message)));
            assert!(!retain_coverage_on_refresh_failure(failure(), true).unwrap());
            assert!(retain_coverage_on_refresh_failure(failure(), false).is_err());
        }
        for covered in [false, true] {
            assert!(matches!(
                retain_coverage_on_refresh_failure(Err(EnhancePirRunError::ExitRequested), covered),
                Err(EnhancePirRunError::ExitRequested)
            ));
            assert!(retain_coverage_on_refresh_failure(Ok(()), covered).unwrap());
        }
    }

    #[test]
    fn only_mainnet_is_enabled() {
        assert!(EnhancePirSync::new(WalletNetwork::Main, true, "test").enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Main, false, "test").enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Test, true, "test").enabled());
        assert!(!EnhancePirSync::new(WalletNetwork::Regtest, true, "test").enabled());
    }

    #[test]
    fn rediscovery_uses_a_trailing_hundred_block_cover_range() {
        assert_eq!(
            rediscovery_cover_start(BlockHeight::from_u32(1_000)),
            BlockHeight::from_u32(901),
        );
        assert_eq!(
            rediscovery_cover_start(BlockHeight::from_u32(50)),
            BlockHeight::from_u32(0),
        );
    }

    #[test]
    fn refresh_is_rate_limited_across_foreground_sessions() {
        begin_session("refresh-test");
        assert!(refresh_due("refresh-test"));
        mark_refresh("refresh-test");
        begin_session("refresh-test");
        assert!(!refresh_due("refresh-test"));
        begin_session("new-wallet");
        assert!(refresh_due("new-wallet"));
        assert_eq!(phase("refresh-test"), "");
    }

    #[tokio::test]
    async fn cancellation_drops_an_in_flight_pir_request() {
        let cancelled = Arc::new(AtomicBool::new(false));
        let flip = cancelled.clone();
        let should_exit = || cancelled.load(Ordering::Acquire);
        let cancelling = tokio::spawn(async move {
            tokio::task::yield_now().await;
            flip.store(true, Ordering::Release);
        });

        let result = await_request_with_cancel(
            std::future::pending::<Result<(), SyncError>>(),
            &should_exit,
            "unused timeout",
        )
        .await;

        assert!(matches!(result, Err(EnhancePirRunError::ExitRequested)));
        cancelling.await.unwrap();
    }

    #[tokio::test]
    async fn malformed_initialization_response_is_rejected() {
        let result = PendingClient::fetch(
            &StaticTransport(b"not a valid initialization document".to_vec()),
            "https://example.test",
        )
        .await;

        assert!(matches!(result, Err(ClientError::Json(_))));
    }
}
