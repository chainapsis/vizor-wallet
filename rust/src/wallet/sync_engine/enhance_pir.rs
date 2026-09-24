//! Application policy and transport for shared private recovery.
use super::{
    block_source::MemoryBlockSource, lwd::DirectRouteConnector, SyncError, WalletDatabase,
};
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use bytes::Bytes;
use futures::StreamExt;
use http::{Method, Request, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper::body::{Body, Incoming};
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use std::{
    future::Future,
    time::{Duration, Instant},
};
use tonic::transport::Channel;
use zakura_pir_enhance::transport::{self, BoundedBody, PendingClient};
use zakura_pir_enhance::wallet::{Acceptance, PreparedWork};
use zakura_pir_enhance::{ClientError, ClientResourceLimits, Manifest};
use zcash_client_backend::{
    data_api::enhance_pir::{
        EnhancePirRead, EnhancePirRequest, EnhancePirStoreResult, EnhancePirWrite,
        IronwoodEnhanceDiscoveryRequest, IronwoodEnhanceDiscoveryResult,
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

fn routing_is_current_or_newer(current: &Manifest, candidate: &Manifest) -> bool {
    current_or_newer_routing_revision(
        (current.generation, current.recovery_epoch),
        (candidate.generation, candidate.recovery_epoch),
    )
}

fn current_or_newer_routing_revision(current: (u64, u64), candidate: (u64, u64)) -> bool {
    candidate.0 >= current.0 && candidate.1 >= current.1
}

fn client_transport_error(error: EnhancePirRunError) -> ClientError {
    match error {
        EnhancePirRunError::ExitRequested => ClientError::Cancelled,
        EnhancePirRunError::HttpStatus(status) => ClientError::HttpStatus(status),
        EnhancePirRunError::Failed(error) => ClientError::Transport(error.to_string()),
    }
}

fn is_stale_routing_status(status: u16) -> bool {
    matches!(status, 409 | 410)
}

fn rediscovery_cover_start(height: BlockHeight) -> BlockHeight {
    BlockHeight::from_u32(
        u32::from(height).saturating_sub(REDISCOVERY_COVER_BLOCKS.saturating_sub(1)),
    )
}

/// Storage boundary for recovery scheduling. The production adapter retains
/// wallet anchor validation, record authentication, and serialized writes.
trait RecoveryWallet {
    fn work(&self) -> Result<PreparedWork, EnhancePirRunError>;
    fn accept(
        &self,
        network: WalletNetwork,
        manifest: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError>;
    fn apply(
        &mut self,
        request: EnhancePirRequest,
        record: &zakura_pir_enhance::EnhanceRecord,
    ) -> Result<EnhancePirStoreResult, EnhancePirRunError>;
}

impl RecoveryWallet for WalletDatabase {
    fn work(&self) -> Result<PreparedWork, EnhancePirRunError> {
        Ok(PreparedWork::new(
            self.enhance_pir_work()
                .map_err(|e| SyncError::db(e.to_string()))?,
        ))
    }
    fn accept(
        &self,
        network: WalletNetwork,
        manifest: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError> {
        Ok(zakura_pir_enhance::wallet::acceptance(
            self,
            manifest,
            &network,
            ClientResourceLimits::new(MAX_LOGICAL_ROWS),
        )
        .map_err(|e| SyncError::db(e.to_string()))??)
    }
    fn apply(
        &mut self,
        request: EnhancePirRequest,
        record: &zakura_pir_enhance::EnhanceRecord,
    ) -> Result<EnhancePirStoreResult, EnhancePirRunError> {
        Ok(with_wallet_db_write_lock("enhance_pir.apply", || {
            self.apply_ironwood_enhance_record(request, record)
        })
        .map_err(|e| SyncError::db(e.to_string()))?)
    }
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
    HttpStatus(u16),
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
type DirectHttpsClient = Client<hyper_rustls::HttpsConnector<DirectRouteConnector>, Full<Bytes>>;

/// One transport per `run`, reused by every request it makes.
///
/// The pooled client lives here rather than being built per request: a hyper
/// `Client` owns its connection pool, so a fresh one per call throws the
/// keep-alive connection away and makes a batch of packed rows pay a TCP and
/// TLS handshake for the initialization fetch and again for every query.
///
/// Scoping it to the transport rather than a process-wide cache keeps idle
/// connections from outliving the sync. That is belt and braces only:
/// `routed_request` re-checks the route per request, and `DirectRouteIo` polls
/// the route lease on every read and write, so a pooled connection stays
/// route-policed for its whole life.
struct RoutedTransport<'a, F> {
    should_exit: &'a F,
    direct: DirectHttpsClient,
}

impl<'a, F> RoutedTransport<'a, F> {
    fn new(should_exit: &'a F) -> Self {
        let connector = HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_only()
            .enable_http1()
            .wrap_connector(DirectRouteConnector::new());
        Self {
            should_exit,
            // Cheap: no connection is opened until the first request, and the
            // Tor route simply never uses it.
            direct: Client::builder(TokioExecutor::new()).build(connector),
        }
    }
}

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
            self.should_exit,
            &self.direct,
        )
        .await;
        if (self.should_exit)() {
            return Err(ClientError::Cancelled);
        }
        response.map_err(client_transport_error)
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
        db: &impl RecoveryWallet,
        generation: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError> {
        db.accept(self.network, generation)
    }
    /// Fetch routing without discarding an accepted session on a transient
    /// refresh failure. A rejected row query forces this path past the normal
    /// refresh timer; every candidate is checked against the scanned wallet.
    async fn refresh_routing(
        &mut self,
        db: &impl RecoveryWallet,
        route: &impl transport::Transport,
        uncovered: bool,
        force: bool,
        should_exit: &impl Fn() -> bool,
    ) -> Result<bool, EnhancePirRunError> {
        if force {
            self.pending_session = None;
        }
        let session_refresh_due = self.session.as_ref().is_some_and(|s| s.refresh_due());
        if (force || uncovered || session_refresh_due)
            && self.pending_session.is_none()
            && (force || session_refresh_due || refresh_due(&self.db_path))
        {
            mark_refresh(&self.db_path);
            self.pending_session = Some(
                PendingClient::fetch(route, self.endpoint.as_deref().expect("enabled")).await?,
            );
        }
        let Some(pending) = self.pending_session.as_ref() else {
            return Ok(self.session.is_some());
        };
        match self.acceptance(db, pending.generation())? {
            Acceptance::Accepted(acceptance) => {
                if should_exit() {
                    return Err(EnhancePirRunError::ExitRequested);
                }
                let pending = self.pending_session.take().expect("pending");
                if let Some(session) = self.session.as_mut() {
                    if !routing_is_current_or_newer(session.generation(), pending.generation()) {
                        set_phase(&self.db_path, "retrying_later");
                        return Ok(!force);
                    }
                    session.accept_routing(pending, &acceptance)?;
                } else {
                    self.session = Some(pending.accept(&acceptance)?);
                }
                Ok(true)
            }
            Acceptance::WaitingForScanning => {
                set_phase(&self.db_path, "waiting_for_scanning");
                Ok(false)
            }
            Acceptance::Mismatch => {
                self.pending_session = None;
                Err(SyncError::parse("snapshot anchor mismatch").into())
            }
        }
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
        self.run_queries(db, &RoutedTransport::new(should_exit), should_exit)
            .await
    }

    async fn run_queries(
        &mut self,
        db: &mut impl RecoveryWallet,
        route: &impl transport::Transport,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        if should_exit() {
            return Err(EnhancePirRunError::ExitRequested);
        }
        let work = db.work()?;
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
                .any(|p| p >= session.generation().coverage.records)
        });
        set_phase(
            &self.db_path,
            if uncovered {
                "waiting_for_snapshot"
            } else {
                "recovering"
            },
        );
        // Refresh is opportunistic: it must not suppress already accepted coverage.
        let refresh = self
            .refresh_routing(db, route, uncovered, false, should_exit)
            .await
            .map(|_| ());
        if !retain_coverage_on_refresh_failure(refresh, self.session.is_some())? {
            self.pending_session = None;
            set_phase(&self.db_path, "retrying_later");
        }
        if self.session.is_none() {
            return Ok(());
        }
        for attempt in 0..=1 {
            // Re-read after a partial batch: successfully stored rows are no
            // longer pending, and only the durable remainder is retried.
            let work = db.work()?;
            if work.query_count() == 0 {
                break;
            }
            // Rejected before any network I/O when the batch exceeds the
            // client's input limit.
            let stale_status = {
                let session = self.session.as_mut().expect("checked above");
                match session.query_batch(route, work.positions()) {
                    Err(ClientError::HttpStatus(status)) if is_stale_routing_status(status) => {
                        Some(status)
                    }
                    Err(error) => return Err(error.into()),
                    Ok(results) => {
                        futures::pin_mut!(results);
                        let mut stale = None;
                        while let Some(result) = results.next().await {
                            if should_exit() {
                                return Err(EnhancePirRunError::ExitRequested);
                            }
                            let record = match result.record {
                                Err(ClientError::OutsideCoverage(_)) => continue,
                                Err(ClientError::HttpStatus(status))
                                    if is_stale_routing_status(status) =>
                                {
                                    stale = Some(status);
                                    break;
                                }
                                result => result?,
                            };
                            for (request, record) in work.map_record(result.position, record) {
                                let result = db.apply(request, &record)?;
                                if result == EnhancePirStoreResult::Rejected {
                                    return Err(SyncError::parse(
                                        "PIR record failed wallet authentication",
                                    )
                                    .into());
                                }
                            }
                        }
                        stale
                    }
                }
            };
            let Some(status) = stale_status else {
                break;
            };
            if attempt == 1 {
                return Err(ClientError::HttpStatus(status).into());
            }
            log::info!(
                "sync: Enhance PIR routing became stale (HTTP {status}); refreshing and retrying unfinished work"
            );
            if !self
                .refresh_routing(db, route, true, true, should_exit)
                .await?
            {
                return Ok(());
            }
        }
        let remaining = db.work()?;
        log::info!(
            "sync: private recovery has {} active queries, {} rediscovery jobs, and {} suspended obligations",
            remaining.query_count(),
            remaining.rediscover.len(),
            remaining.suspended
        );
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

/// Validated before route selection, so a plaintext endpoint is rejected on
/// every route rather than only the direct one. Tor conceals the client from
/// the service, but the exit-to-service hop is still the open network.
fn secure_endpoint_uri(url: &str) -> Result<http::Uri, SyncError> {
    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("Enhance PIR transport requires HTTPS"));
    }
    Ok(uri)
}

/// A single deadline covers route acquisition, headers, and body on both routes.
async fn routed_request(
    method: Method,
    url: &str,
    body: Vec<u8>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
    direct: &DirectHttpsClient,
) -> Result<transport::ResponseBody, EnhancePirRunError> {
    receive_response(
        routed_response(method, url, body, should_exit, direct),
        collector,
        should_exit,
    )
    .await
}

async fn routed_response(
    method: Method,
    url: &str,
    body: Vec<u8>,
    should_exit: &impl Fn() -> bool,
    direct: &DirectHttpsClient,
) -> Result<http::Response<Incoming>, EnhancePirRunError> {
    if should_exit() {
        return Err(EnhancePirRunError::ExitRequested);
    }
    let uri = secure_endpoint_uri(url)?;
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
        let request = async {
            match method {
                Method::GET => {
                    client
                        .http_get(
                            uri,
                            |builder| builder,
                            |incoming| async { Ok(incoming) },
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
                            |incoming| async { Ok(incoming) },
                            0,
                            |_| None,
                        )
                        .await
                }
                _ => unreachable!("Enhance PIR uses GET and POST only"),
            }
            .map_err(|error| SyncError::net(format!("Enhance PIR Tor request failed: {error}")))
        };
        // Returning Incoming from the Tor parser exposes headers without
        // polling the body. A malformed error body cannot erase its status.
        return Ok(request.await?);
    }

    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(http::header::CONTENT_TYPE, "application/octet-stream")
        .body(Full::new(Bytes::from(body)))
        .map_err(|error| SyncError::parse(format!("build Enhance PIR request: {error}")))?;
    let response = direct
        .request(request)
        .await
        .map_err(|error| SyncError::net(format!("Enhance PIR HTTPS request failed: {error}")))?;
    Ok(response)
}

/// Keep the deadline outside both phases; error bodies are never consumed.
async fn receive_response<B, E>(
    headers: impl Future<Output = Result<http::Response<B>, E>>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
) -> Result<transport::ResponseBody, EnhancePirRunError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
    E: Into<EnhancePirRunError>,
{
    await_request_with_cancel(
        async {
            let response = headers.await.map_err(Into::into)?;
            collect_response(response, collector).await
        },
        should_exit,
        "Enhance PIR request timed out",
    )
    .await
}

async fn collect_response<B>(
    response: http::Response<B>,
    collector: BoundedBody,
) -> Result<transport::ResponseBody, EnhancePirRunError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
    if !response.status().is_success() {
        return Err(EnhancePirRunError::HttpStatus(response.status().as_u16()));
    }
    Ok(read_body_limited(response.status(), response.into_body(), collector).await?)
}

async fn await_request_with_cancel<T, E: Into<EnhancePirRunError>>(
    request: impl Future<Output = Result<T, E>>,
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
                .map_err(Into::into)
        }
    }
}

async fn read_body_limited<B>(
    status: StatusCode,
    mut body: B,
    mut bytes: BoundedBody,
) -> Result<transport::ResponseBody, SyncError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
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
    fn routing_refresh_accepts_equal_revision_and_never_downgrades() {
        let current = (37, 0);
        assert!(current_or_newer_routing_revision(current, (38, 0)));
        assert!(current_or_newer_routing_revision(current, (37, 1)));
        assert!(current_or_newer_routing_revision(current, current));
        assert!(!current_or_newer_routing_revision(current, (36, 0)));
        assert!(!current_or_newer_routing_revision((37, 1), (37, 0)));
    }

    #[test]
    fn routed_http_status_is_preserved_for_recovery() {
        for status in [409, 410, 429, 502] {
            assert!(matches!(
                client_transport_error(EnhancePirRunError::HttpStatus(status)),
                ClientError::HttpStatus(actual) if actual == status
            ));
        }
        assert!(is_stale_routing_status(409));
        assert!(is_stale_routing_status(410));
        assert!(!is_stale_routing_status(429));
        assert!(!is_stale_routing_status(502));
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
    fn every_route_requires_an_https_endpoint() {
        assert!(secure_endpoint_uri(DEFAULT_MAINNET_ENDPOINT).is_ok());
        for url in [
            "http://enhance-pir.valargroup.dev",
            "http://127.0.0.1:8080",
            "enhance-pir.valargroup.dev",
            "not a url",
        ] {
            assert!(secure_endpoint_uri(url).is_err(), "accepted {url}");
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

#[cfg(test)]
#[path = "enhance_pir_tests.rs"]
mod recovery_tests;
